#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================================"
echo "          RetailEdge Full Infrastructure Validation"
echo "============================================================"
echo "Date: $(date)"
echo

FAILED=0

for SCRIPT in "$SCRIPT_DIR"/validate-*.sh; do

    NAME=$(basename "$SCRIPT")

    if [[ "$NAME" == "validate-all.sh" ]]; then
        continue
    fi

    echo
    echo "============================================================"
    echo "Running: $NAME"
    echo "============================================================"

    if bash "$SCRIPT"; then
        echo "✓ $NAME PASSED"
    else
        echo "✗ $NAME FAILED"
        FAILED=1
    fi

done

echo
echo "============================================================"
echo "              FULL VALIDATION SUMMARY"
echo "============================================================"

if [[ "$FAILED" -eq 0 ]]; then
    echo "✓ All validation scripts passed"
    exit 0
else
    echo "✗ One or more validation scripts failed"
    exit 1
fi