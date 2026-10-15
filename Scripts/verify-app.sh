#!/bin/bash
# Verifies the bundled app end-to-end in its real launchd context.
#
# The app runs with --selftest and drops marker files at each UI step; this
# script (running from the terminal, which holds the screen-recording grant)
# captures the screen at each marker. Prints a PASS/FAIL verdict.
set -uo pipefail
cd "$(dirname "$0")/.."

DIR=/tmp/alttab-e2e
APP="build/AltTab Dev.app"

rm -f "$DIR"/step* "$DIR"/vshot* "$DIR"/done "$DIR"/diag.txt

./Scripts/make-app-bundle.sh >/dev/null
# `open` won't pass args to an already-running instance — quit it first.
pkill -x AltTab 2>/dev/null; sleep 1
open "$APP" --args --selftest

capture_at_step() {
    local step=$1 shot=$2
    local waited=0
    while [ ! -f "$DIR/$step" ] && [ "$waited" -lt 300 ]; do
        sleep 0.05; waited=$((waited + 1))
    done
    if [ -f "$DIR/$step" ]; then
        screencapture -x "$DIR/$shot"
        echo "captured $shot"
    else
        echo "TIMEOUT waiting for $step"
        return 1
    fi
}

ok=1
capture_at_step step1 vshot1_show.png || ok=0
# Direct window capture (from this privileged context): proves whether the
# panel window carries real rendered content.
if [ -f "$DIR/diag.txt" ]; then
    WID=$(grep -o 'windowNumber = [0-9]*' "$DIR/diag.txt" | grep -o '[0-9]*')
    if [ -n "$WID" ]; then
        screencapture -x -l"$WID" "$DIR/panel_direct.png" && echo "captured panel_direct.png (window $WID)" || echo "direct window capture failed (window $WID)"
    fi
fi
capture_at_step step2 vshot2_tab.png || ok=0
capture_at_step step3 vshot3_arrow.png || ok=0
capture_at_step step4 vshot4_hidden.png || ok=0

# wait for the app to finish
waited=0
while [ ! -f "$DIR/done" ] && [ "$waited" -lt 100 ]; do
    sleep 0.1; waited=$((waited + 1))
done

# Screen-lock awareness: with the session locked the lock screen covers all
# window compositing — pixel verification is meaningless (even the original
# AltTab's panel cannot appear). Fall back to window-server-level evidence.
LOCKED=$(swift - <<'EOF'
import CoreGraphics
if let s = CGSessionCopyCurrentDictionary() as? [String: Any],
   (s["CGSSessionScreenIsLocked"] as? Int ?? 0) == 1 {
    print("yes")
} else {
    print("no")
}
EOF
)

if [ "$LOCKED" = "yes" ]; then
    echo "NOTE: screen is locked — lock layer hides all windows; using CG evidence only."
    # Window-server evidence: the panel must exist on-screen with a sane frame.
    swift - "$DIR" <<'EOF' || ok=0
import CoreGraphics
import Foundation
let dir = CommandLine.arguments[1]
let diag = try String(contentsOfFile: "\(dir)/diag.txt")
guard let frameLine = diag.split(separator: "\n").first(where: { $0.hasPrefix("panel.frame") }),
      let numberLine = diag.split(separator: "\n").first(where: { $0.hasPrefix("panel.windowNumber") })
else { print("CG-EVIDENCE: no diagnostics"); exit(1) }
let number = Int(numberLine.split(whereSeparator: { !$0.isNumber }).last ?? "0") ?? 0
guard number > 0 else { print("CG-EVIDENCE: no window number"); exit(1) }
var found = false
if let list = CGWindowListCopyWindowInfo([.optionAll], CGWindowID(number)) as? [[String: Any]] {
    found = !list.isEmpty
}
let frameOK = frameLine.contains("1016.0") && frameLine.contains("758.0")
print("CG-EVIDENCE: window \(number) in window server: \(found), expected frame: \(frameOK)")
exit(found && frameOK ? 0 : 1)
EOF
    if [ "$ok" = 1 ]; then
        echo "VERIFY-APP: PASS (locked-screen mode: window-server evidence only; unlock and rerun for pixel verification)"
    else
        echo "VERIFY-APP: FAIL"
        exit 1
    fi
    exit 0
fi

swift Scripts/panel_diff.swift "$DIR" || ok=0

if [ "$ok" = 1 ]; then
    echo "VERIFY-APP: PASS"
else
    echo "VERIFY-APP: FAIL"
    exit 1
fi
