#!/bin/bash
# End-to-end UI verification without any TCC grants:
# concatenates core + app sources with the e2e main and runs the result
# under the swift JIT, which inherits the terminal's permissions.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=/tmp/alttab-e2e
mkdir -p "$OUT"

{
    cat Sources/AltTabCore/*.swift
    cat Sources/AltTabApp/*.swift
    # strip module imports; everything is one file now
} | sed -e 's/^import AltTabCore$//' -e 's/^import AltTabApp$//' > "$OUT/_sources.swift"

cat "$OUT/_sources.swift" Scripts/e2e/main.swift \
    | sed -e 's/^import AltTabCore$//' -e 's/^import AltTabApp$//' > "$OUT/e2e_combined.swift"

echo "combined: $(wc -l < "$OUT/e2e_combined.swift") lines"
exec swift "$OUT/e2e_combined.swift"
