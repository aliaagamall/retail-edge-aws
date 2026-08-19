#!/usr/bin/env bash

set -euo pipefail

# Directory containing this script
VALIDATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Terraform root directory
TERRAFORM_DIR="$(cd "$VALIDATION_DIR/../.." && pwd)"

# Validation results directory
OUTPUT_DIR="$TERRAFORM_DIR/validation-results"

mkdir -p "$OUTPUT_DIR"

# Always run Terraform commands from Terraform root
cd "$TERRAFORM_DIR"