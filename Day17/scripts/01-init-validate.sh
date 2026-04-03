#!/usr/bin/env bash
# Day17 — Manual Test Script 1: Init and Validate
# Runs terraform init and terraform validate against both environments.
# Usage: bash scripts/01-init-validate.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colours
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; }
info() { echo -e "${YELLOW}[INFO]${NC} $*"; }

RESULTS_FILE="$ROOT_DIR/results/init-validate-results.txt"
mkdir -p "$ROOT_DIR/results"
> "$RESULTS_FILE"

log() {
  echo "$*" | tee -a "$RESULTS_FILE"
}

run_init_validate() {
  local env_name="$1"
  local dir="$2"

  log "Environment: $env_name"
  log "Directory:   $dir"
  log "Timestamp:   $(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  if [ ! -d "$dir" ]; then
    log "[SKIP] Directory does not exist: $dir"
    return
  fi

  log "--- TEST: terraform init ---"
  log "Command: terraform -chdir=$dir init -input=false"
  if terraform -chdir="$dir" init -input=false >> "$RESULTS_FILE" 2>&1; then
    log "Result: PASS"
    pass "[$env_name] terraform init"
  else
    log "Result: FAIL"
    fail "[$env_name] terraform init"
  fi

  log "--- TEST: terraform validate ---"
  log "Command: terraform -chdir=$dir validate"
  if terraform -chdir="$dir" validate >> "$RESULTS_FILE" 2>&1; then
    log "Result: PASS"
    pass "[$env_name] terraform validate"
  else
    log "Result: FAIL"
    fail "[$env_name] terraform validate"
  fi
}

# Module itself
run_init_validate "module/webserver-cluster" \
  "$ROOT_DIR/../Day16/modules/services/webserver-cluster"

# Dev live environment
run_init_validate "live/dev" \
  "$ROOT_DIR/../Day16/live/dev/services/webserver-cluster"

# Production live environment
run_init_validate "live/production" \
  "$ROOT_DIR/../Day16/live/production/services/webserver-cluster"

log ""
log "Results written to: $RESULTS_FILE"
