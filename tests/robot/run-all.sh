#!/bin/bash
# Run all Robot Framework tests for the on-chain consent framework
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_DIR="$PROJECT_ROOT/tests/results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "============================================"
echo "  On-Chain Consent Framework Test Suite"
echo "============================================"
echo ""

# Ensure output dirs exist
mkdir -p "$RESULTS_DIR"/{owasp,api,contracts,combined}

# Check for required tools
command -v robot >/dev/null 2>&1 || {
    echo >&2 "ERROR: robot (Robot Framework) not found. Install with: pip install robotframework"
    exit 1
}
command -v pabot >/dev/null 2>&1 || {
    echo "WARNING: pabot not found, falling back to sequential robot execution"
    PABOT_AVAILABLE=false
}
command -v rebot >/dev/null 2>&1 || {
    echo "WARNING: rebot not found, skipping combined report generation"
    REBOT_AVAILABLE=false
}

export PROJECT_ROOT
export PYTHONPATH="$PROJECT_ROOT/tests/robot/resources:$PYTHONPATH"

# ==============================================
# OWASP Top 10 Security Tests
# ==============================================
echo ""
echo "--- Running OWASP Top 10 security tests ---"
if [ "${PABOT_AVAILABLE:-true}" = true ]; then
    pabot --processes 4 \
        --outputdir "$RESULTS_DIR/owasp/$TIMESTAMP" \
        --variable PROJECT_ROOT:"$PROJECT_ROOT" \
        "$SCRIPT_DIR/owasp/"
else
    for test_file in "$SCRIPT_DIR"/owasp/A*.robot; do
        test_name=$(basename "$test_file" .robot)
        echo "  Running $test_name..."
        robot --outputdir "$RESULTS_DIR/owasp/$TIMESTAMP/$test_name" \
            --variable PROJECT_ROOT:"$PROJECT_ROOT" \
            "$test_file"
    done
fi
echo "OWASP tests complete."

# ==============================================
# API Integration Tests
# ==============================================
echo ""
echo "--- Running API integration tests ---"
robot --outputdir "$RESULTS_DIR/api/$TIMESTAMP" \
    --variable PROJECT_ROOT:"$PROJECT_ROOT" \
    "$SCRIPT_DIR/api/"
echo "API tests complete."

# ==============================================
# Contract Interaction Tests
# ==============================================
echo ""
echo "--- Running contract interaction tests ---"
if [ -d "$SCRIPT_DIR/contracts" ] && [ "$(ls -A "$SCRIPT_DIR/contracts/")" ]; then
    robot --outputdir "$RESULTS_DIR/contracts/$TIMESTAMP" \
        --variable PROJECT_ROOT:"$PROJECT_ROOT" \
        "$SCRIPT_DIR/contracts/"
    echo "Contract tests complete."
else
    echo "No contract tests found, skipping."
fi

# ==============================================
# Combined Report
# ==============================================
echo ""
echo "--- Generating combined report ---"
OWASP_OUTPUT="$RESULTS_DIR/owasp/$TIMESTAMP/output.xml"
API_OUTPUT="$RESULTS_DIR/api/$TIMESTAMP/output.xml"
CONTRACTS_OUTPUT="$RESULTS_DIR/contracts/$TIMESTAMP/output.xml"

ALL_OUTPUTS=()
[ -f "$OWASP_OUTPUT" ] && ALL_OUTPUTS+=("$OWASP_OUTPUT")
[ -f "$API_OUTPUT" ] && ALL_OUTPUTS+=("$API_OUTPUT")
[ -f "$CONTRACTS_OUTPUT" ] && ALL_OUTPUTS+=("$CONTRACTS_OUTPUT")

if [ "${#ALL_OUTPUTS[@]}" -gt 0 ] && [ "${REBOT_AVAILABLE:-true}" = true ]; then
    rebot --outputdir "$RESULTS_DIR/combined/$TIMESTAMP" \
        --name "Consent Framework Tests" \
        "${ALL_OUTPUTS[@]}"
    echo "Combined report: $RESULTS_DIR/combined/$TIMESTAMP/report.html"
elif [ "${#ALL_OUTPUTS[@]}" -gt 0 ]; then
    echo "Individual output files available at:"
    for f in "${ALL_OUTPUTS[@]}"; do
        echo "  $f"
    done
else
    echo "No test output files found to combine."
fi

# ==============================================
# Summary
# ==============================================
echo ""
echo "============================================"
echo "  Test Suite Complete"
echo "============================================"
echo ""
echo "Results:"
echo "  OWASP:    $RESULTS_DIR/owasp/$TIMESTAMP/"
echo "  API:      $RESULTS_DIR/api/$TIMESTAMP/"
echo "  Combined: $RESULTS_DIR/combined/$TIMESTAMP/"
echo ""
echo "To view the report:"
echo "  open $RESULTS_DIR/combined/$TIMESTAMP/report.html"
