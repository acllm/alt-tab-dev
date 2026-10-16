#!/bin/bash
# One-command verification ladder for local development:
#   L0 preflight → L1 build → L2 unit tests → L3 enumeration smoke
#   (+ thumbnail pipeline) → L4 in-process UI e2e → L5 real .app e2e.
# Default runs everything; --quick skips the thumbnail pass and L5 (no
# screen disturbance). Artifacts land in build/e2e/<timestamp>/.
set -uo pipefail
cd "$(dirname "$0")/.."

QUICK=0
for arg in "$@"; do
    case "$arg" in
        --quick) QUICK=1 ;;
        *) echo "usage: $(basename "$0") [--quick]" >&2; exit 2 ;;
    esac
done

TS=$(date +%Y%m%d-%H%M%S)
OUT="build/e2e/$TS"
mkdir -p "$OUT"

declare -a NAMES STATUSES
FAILED=0

record() { # record <name> <PASS|FAIL|SKIP[:reason]>
    NAMES+=("$1"); STATUSES+=("$2")
    if [ "$2" != PASS ] && [ "${2%%:*}" != SKIP ]; then FAILED=1; fi
}

echo "verify: artifacts → $OUT"

# ── L0 preflight: environment facts; gates L5 ──────────────────────────
echo; echo "── L0 preflight"
WS_OK=0
pgrep -x WindowServer >/dev/null && WS_OK=1

LOCKED=$(swift - <<'EOF'
import CoreGraphics
if let s = CGSessionCopyCurrentDictionary() as? [String: Any],
   (s["CGSSessionScreenIsLocked"] as? Int ?? 0) == 1 { print("yes") } else { print("no") }
EOF
)

SR_OK=0
PX=$(screencapture -x "$OUT/preflight.png" 2>/dev/null \
    && sips -g pixelWidth "$OUT/preflight.png" 2>/dev/null | awk '/pixelWidth/{print $2}')
[ -n "$PX" ] && [ "$PX" -gt 0 ] 2>/dev/null && SR_OK=1

{
    echo "macOS $(sw_vers -productVersion) ($(uname -m)), $(swift --version 2>&1 | head -1)"
    if [ "$WS_OK" = 1 ]; then
        echo "window server: running (GUI session)"
    else
        echo "window server: NOT running (headless session — L5 impossible)"
    fi
    if [ "$SR_OK" = 1 ]; then
        echo "screen capture: ${PX}px wide (screen-recording grant present)"
    else
        echo "screen capture: produced no image (missing screen-recording grant?)"
    fi
    echo "screen locked: $LOCKED"
} | tee "$OUT/l0-preflight.log"

L5_GATE=1
L5_SKIP_REASON=""
if [ "$WS_OK" != 1 ]; then L5_GATE=0; L5_SKIP_REASON="no GUI session"; fi
if [ "$LOCKED" = "yes" ]; then L5_GATE=0; L5_SKIP_REASON="screen locked"; fi
if [ "$SR_OK" != 1 ]; then L5_GATE=0; L5_SKIP_REASON="terminal lacks screen-recording grant"; fi
record "L0 preflight" PASS

# ── L1 build ────────────────────────────────────────────────────────────
echo; echo "── L1 swift build"
if swift build 2>&1 | tee "$OUT/l1-build.log"; then
    record "L1 build" PASS
else
    record "L1 build" FAIL
    echo "verify: build failed — later layers are meaningless, stopping."
    exit 1
fi

# ── L2 unit tests ───────────────────────────────────────────────────────
echo; echo "── L2 unit tests (swift run AltTabTests)"
swift run AltTabTests 2>&1 | tee "$OUT/l2-unit.log"
SUMMARY=$(grep -E '^Passed: ' "$OUT/l2-unit.log" | tail -1)
PASSED_N=${SUMMARY#Passed: }; PASSED_N=${PASSED_N%% *}
if [ -n "$PASSED_N" ] && [ "$PASSED_N" -gt 0 ] 2>/dev/null && [[ "$SUMMARY" == *"Failed: 0"* ]]; then
    record "L2 unit tests ($PASSED_N cases)" PASS
else
    record "L2 unit tests" FAIL
fi

# ── L3 enumeration smoke (+ thumbnails) ─────────────────────────────────
echo; echo "── L3 window enumeration smoke (AltTab --dump)"
.build/debug/AltTab --dump 2>&1 | tee "$OUT/l3-dump.log"
WINDOWS=$(grep -o 'living windows: [0-9]*' "$OUT/l3-dump.log" | grep -o '[0-9]*$')
if [ -n "$WINDOWS" ] && [ "$WINDOWS" -ge 2 ] 2>/dev/null; then
    record "L3 enumeration ($WINDOWS windows)" PASS
else
    record "L3 enumeration" FAIL
fi

if [ "$QUICK" -ne 1 ]; then
    echo; echo "── L3b thumbnail pipeline (AltTab --dump --thumbnails)"
    .build/debug/AltTab --dump --thumbnails "$OUT/thumbnails" 2>&1 | tee "$OUT/l3b-thumbs.log"
    THUMBS=$(ls "$OUT/thumbnails"/*.png 2>/dev/null | wc -l | tr -d ' ')
    if [ "$THUMBS" -ge 1 ] 2>/dev/null; then
        record "L3b thumbnails ($THUMBS pngs)" PASS
    else
        record "L3b thumbnails" FAIL
    fi
fi

# ── L4 in-process UI e2e (JIT, inherits terminal grants) ────────────────
echo; echo "── L4 in-process UI e2e (Scripts/run-e2e.sh)"
./Scripts/run-e2e.sh 2>&1 | tee "$OUT/l4-jit-e2e.log"
if grep -q "E2E-UI: PASS" "$OUT/l4-jit-e2e.log"; then
    record "L4 in-process UI e2e" PASS
else
    record "L4 in-process UI e2e" FAIL
fi

# ── L5 real .app e2e (launchd context + pixel verdict) ──────────────────
if [ "$QUICK" -eq 1 ]; then
    record "L5 real-app e2e" "SKIP:--quick"
elif [ "$L5_GATE" != 1 ]; then
    echo "⚠️  L5 skipped: $L5_SKIP_REASON"
    record "L5 real-app e2e" "SKIP:$L5_SKIP_REASON"
else
    echo; echo "── L5 real-app e2e (Scripts/verify-app.sh)"
    echo "⚠️  the switcher panel will flash on screen for ~7 s and any running AltTab Dev is restarted"
    ./Scripts/verify-app.sh 2>&1 | tee "$OUT/l5-app-e2e.log"
    if grep -q "VERIFY-APP: PASS" "$OUT/l5-app-e2e.log"; then
        record "L5 real-app e2e" PASS
    else
        record "L5 real-app e2e" FAIL
    fi
    mkdir -p "$OUT/app"
    cp /tmp/alttab-e2e/vshot*.png /tmp/alttab-e2e/panel_direct.png /tmp/alttab-e2e/diag.txt "$OUT/app/" 2>/dev/null
fi

# ── summary ─────────────────────────────────────────────────────────────
echo; echo "═══ verify summary ═══"
for i in "${!NAMES[@]}"; do
    status=${STATUSES[$i]}
    case "$status" in
        PASS) mark="✅" ;;
        SKIP*) mark="⏭️ " ;;
        *) mark="❌" ;;
    esac
    printf "  %s %-34s %s\n" "$mark" "${NAMES[$i]}" "$status"
done
echo "artifacts: $OUT"
if [ "$FAILED" -ne 0 ]; then
    echo "verify: FAIL"
    exit 1
fi
echo "verify: PASS"
