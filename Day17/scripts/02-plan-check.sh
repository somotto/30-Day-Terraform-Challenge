#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; }
info() { echo -e "${YELLOW}[INFO]${NC} $*"; }

ENV="${1:-dev}"
RESULTS_FILE="$ROOT_DIR/results/plan-check-${ENV}-results.txt"
mkdir -p "$ROOT_DIR/results"
> "$RESULTS_FILE"

log() { echo "$*" | tee -a "$RESULTS_FILE"; }

case "$ENV" in
  dev)
    DIR="$ROOT_DIR/../Day16/live/dev/services/webserver-cluster"
    PLAN_FILE="/tmp/day17-plan-dev.tfplan"
    ;;
  production)
    DIR="$ROOT_DIR/../Day16/live/production/services/webserver-cluster"
    PLAN_FILE="/tmp/day17-plan-prod.tfplan"
    ;;
  *)
    echo "Usage: $0 [dev|production]"
    exit 1
    ;;
esac

log "Plan Check — Environment: $ENV"
log "Directory:  $DIR"
log "Timestamp:  $(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# Ensure init has been run
log ""
log "--- Ensuring init is current ---"
terraform -chdir="$DIR" init -input=false >> "$RESULTS_FILE" 2>&1

# Run plan and capture output
log ""
log "--- TEST: terraform plan (fresh deploy) ---"
log "Command: terraform -chdir=$DIR plan -out=$PLAN_FILE"

PLAN_OUTPUT=$(terraform -chdir="$DIR" plan \
  -out="$PLAN_FILE" \
  -var="db_password=placeholder-for-plan" \
  2>&1)

echo "$PLAN_OUTPUT" >> "$RESULTS_FILE"

# Check plan completed without error
if echo "$PLAN_OUTPUT" | grep -q "Error:"; then
  log "Result: FAIL — plan produced errors"
  fail "[$ENV] terraform plan"
else
  log "Result: PASS — plan completed without errors"
  pass "[$ENV] terraform plan"
fi

# Count resources to add
RESOURCES_TO_ADD=$(echo "$PLAN_OUTPUT" | grep -oP '\d+(?= to add)' || echo "0")
RESOURCES_TO_CHANGE=$(echo "$PLAN_OUTPUT" | grep -oP '\d+(?= to change)' || echo "0")
RESOURCES_TO_DESTROY=$(echo "$PLAN_OUTPUT" | grep -oP '\d+(?= to destroy)' || echo "0")

log ""
log "--- Plan Summary ---"
log "Resources to add:     $RESOURCES_TO_ADD"
log "Resources to change:  $RESOURCES_TO_CHANGE"
log "Resources to destroy: $RESOURCES_TO_DESTROY"

# For a fresh deploy, we expect >0 resources to add and 0 to destroy
if [ "$RESOURCES_TO_DESTROY" -eq 0 ]; then
  log "Result: PASS — no unexpected destroys in plan"
  pass "[$ENV] No unexpected destroys"
else
  log "Result: FAIL — plan shows $RESOURCES_TO_DESTROY resources to destroy"
  fail "[$ENV] Unexpected destroys in plan"
fi

log ""
log "Plan file saved to: $PLAN_FILE"
log "Results written to: $RESULTS_FILE"
