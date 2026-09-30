#!/bin/bash
# Everything about the Audit app that can be checked on a Mac without an iOS SDK and without building the core:
#   - the catalogue against its schema and against the guest program it drives
#   - the probe protocol constants (guest header vs Swift)
#   - the frame-statistics code the core hooks use (C++), and the app's pure Swift logic (frame analysis, anomaly
#     detection, verdicts, planner, report writer), with the real catalogue loaded
#   - a sample report written by the real writer, validated against the report schema and run through the diff tool
# Used by the audit workflow's "checks" job and runnable by hand:  tools/audit-app/run-host-checks.sh
set -eo pipefail
cd "$(dirname "$0")"
OUT="${1:-$(mktemp -d)}"
mkdir -p "$OUT"
BRIDGE="../../src/ios/Bridge"

echo "== catalogue"
python3 validate_catalogue.py
echo "== protocol"
python3 check_protocol.py

echo "== frame statistics (C++)"
clang++ -std=c++17 -Wall -Wextra -I "$BRIDGE" Tests/frame_stats_test.cpp -o "$OUT/frame_stats_test"
"$OUT/frame_stats_test"

echo "== app logic (Swift)"
swiftc -swift-version 5 -Onone -o "$OUT/logic_tests" Sources/Model/*.swift Sources/Analysis/*.swift Tests/main.swift
AUDIT_CATALOGUE_DIR="$PWD/Catalogue" AUDIT_SAMPLE_OUT="$OUT/sample-report.json" "$OUT/logic_tests"

echo "== report schema"
if python3 -c "import jsonschema" 2>/dev/null; then
  python3 validate_report.py "$OUT/sample-report.json"
else
  echo "jsonschema is not installed; skipping (pip install jsonschema)"
fi

echo "== diff tool"
python3 Tests/test_audit_diff.py "$OUT/sample-report.json"

echo "all host checks passed"
