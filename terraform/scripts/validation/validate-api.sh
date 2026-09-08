#!/usr/bin/env bash

set -euo pipefail

VALIDATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "$VALIDATION_DIR/../.." && pwd)"
OUTPUT_DIR="$TERRAFORM_DIR/validation-results"

mkdir -p "$OUTPUT_DIR"

cd "$TERRAFORM_DIR"

RESULT_FILE="$OUTPUT_DIR/api-validation.txt"

DOMAIN="$(terraform output -raw distribution_domain_name)"
ENDPOINT="https://${DOMAIN}/api/health"

{
    echo "RetailEdge API Validation"
    echo "=========================="
    echo
    echo "CloudFront Domain: $DOMAIN"
    echo "API Endpoint:      $ENDPOINT"
    echo

    echo "Test: CloudFront API Health Check"
    echo "---------------------------------"

    RESPONSE_FILE="$(mktemp)"

    HTTP_CODE=$(curl -sk \
        --max-time 30 \
        -o "$RESPONSE_FILE" \
        -w "%{http_code}" \
        "$ENDPOINT")

    echo "HTTP Status: $HTTP_CODE"
    echo "Response:"
    cat "$RESPONSE_FILE"
    echo
    echo

    if [[ "$HTTP_CODE" != "200" ]]; then
        echo "Result: FAILED"
        rm -f "$RESPONSE_FILE"
        exit 1
    fi

    echo "Application Health:"
    if grep -q '"status":"ok"' "$RESPONSE_FILE"; then
        echo "  status: OK"
    else
        echo "  status: FAILED"
        rm -f "$RESPONSE_FILE"
        exit 1
    fi

    echo
    echo "MySQL:"
    if grep -q '"mysql":"connected"' "$RESPONSE_FILE"; then
        echo "  connected: YES"
    else
        echo "  connected: NO"
        rm -f "$RESPONSE_FILE"
        exit 1
    fi

    echo
    echo "Redis:"
    if grep -q '"redis":"connected"' "$RESPONSE_FILE"; then
        echo "  connected: YES"
    else
        echo "  connected: NO"
        rm -f "$RESPONSE_FILE"
        exit 1
    fi

    echo
    echo "End-to-End Flow:"
    echo "  Client"
    echo "    -> CloudFront"
    echo "    -> CloudFront /api/* behavior"
    echo "    -> CloudFront Function (/api/health -> /health)"
    echo "    -> VPC Origin"
    echo "    -> Internal ALB"
    echo "    -> EC2"
    echo "    -> Docker Application"
    echo "    -> MySQL"
    echo "    -> Redis"

    echo
    echo "Result: PASSED"

    rm -f "$RESPONSE_FILE"

} | tee "$RESULT_FILE"