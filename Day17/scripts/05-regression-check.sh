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
RESULTS_FILE="$ROOT_DIR/results/regression-check-${ENV}-results.txt"
mkdir -p "$ROOT_DIR/results"
> "$RESULTS_FILE"

log() { echo "$*" | tee -a "$RESULTS_FILE"; }

case "$ENV" in
  dev)
    DIR="$ROOT_DIR/../Day16/live/dev/services/webserver-cluster"
    MAIN_TF="$DIR/main.tf"
    ;;
  production)
    DIR="$ROOT_DIR/../Day16/live/production/services/webserver-cluster"
    MAIN_TF="$DIR/main.tf"
    ;;
  *)
    echo "Usage: $0 [dev|production]"
    exit 1
    ;;
esac

BACKUP_FILE="${MAIN_TF}.regression-backup"

log "Regression Check — Environment: $ENV"
log "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# 1. Baseline: plan should be clean before we start
log ""
log "--- TEST 1: Baseline plan is clean before change ---"
log "Command: terraform -chdir=$DIR plan -detailed-exitcode"

BASELINE_OUTPUT=$(terraform -chdir="$DIR" plan \
  -detailed-exitcode \
  -var="db_password=placeholder-for-plan" \
  2>&1) || BASELINE_EXIT=$?

BASELINE_EXIT="${BASELINE_EXIT:-0}"
log "Exit code: $BASELINE_EXIT"

if [ "$BASELINE_EXIT" -eq 0 ]; then
  log "Result: PASS — baseline is clean"
  pass "[TEST 1] Baseline plan clean"
else
  log "Result: FAIL — baseline plan is not clean (exit $BASELINE_EXIT)"
  log "Fix drift before running regression check."
  fail "[TEST 1] Baseline not clean — aborting regression check"
  exit 1
fi

# 2. Introduce a small, safe change: add a regression-test tag
log ""
log "--- Introducing regression test change ---"
log "Adding custom_tags = { RegressionTest = \"day17\" } to $MAIN_TF"

cp "$MAIN_TF" "$BACKUP_FILE"

# Inject the regression tag into the custom_tags block
# We look for the existing custom_tags block and add our key
sed -i 's/custom_tags = {/custom_tags = {\n    RegressionTest = "day17"/' "$MAIN_TF"

log "Modified $MAIN_TF"

# 3. Plan should show ONLY the tag change
log ""
log "--- TEST 2: Plan shows only the tag change ---"
log "Command: terraform -chdir=$DIR plan -detailed-exitcode"

CHANGE_PLAN=$(terraform -chdir="$DIR" plan \
  -detailed-exitcode \
  -var="db_password=placeholder-for-plan" \
  2>&1) || CHANGE_EXIT=$?

CHANGE_EXIT="${CHANGE_EXIT:-0}"
log "$CHANGE_PLAN"
log "Exit code: $CHANGE_EXIT"

# Exit code 2 = changes present (expected)
if [ "$CHANGE_EXIT" -eq 2 ]; then
  log "Result: PASS — plan shows changes (as expected after tag addition)"
  pass "[TEST 2] Plan detects tag change"

  # Verify only tag-related changes appear — no resource replacements
  if echo "$CHANGE_PLAN" | grep -q "must be replaced"; then
    log "Result: FAIL — plan shows resource replacement (unexpected)"
    fail "[TEST 2] Unexpected resource replacement in plan"
  else
    log "Result: PASS — no resource replacements (only tag updates)"
    pass "[TEST 2] No unexpected resource replacements"
  fi
else
  log "Result: FAIL — expected exit code 2 (changes), got $CHANGE_EXIT"
  fail "[TEST 2] Plan did not detect change"
fi

# 4. Apply the change
log ""
log "--- Applying regression test change ---"
log "Command: terraform -chdir=$DIR apply -auto-approve"

APPLY_OUTPUT=$(terraform -chdir="$DIR" apply \
  -auto-approve \
  -var="db_password=placeholder-for-plan" \
  2>&1)

log "$APPLY_OUTPUT"

if echo "$APPLY_OUTPUT" | grep -q "Apply complete"; then
  log "Result: PASS — apply succeeded"
  pass "[TEST 3] Apply with regression tag succeeded"
else
  log "Result: FAIL — apply did not complete"
  fail "[TEST 3] Apply failed"
fi

# 5. Post-apply plan should be clean again
log ""
log "--- TEST 4: Plan is clean after applying the change ---"
log "Command: terraform -chdir=$DIR plan -detailed-exitcode"

POST_PLAN=$(terraform -chdir="$DIR" plan \
  -detailed-exitcode \
  -var="db_password=placeholder-for-plan" \
  2>&1) || POST_EXIT=$?

POST_EXIT="${POST_EXIT:-0}"
log "Exit code: $POST_EXIT"

if [ "$POST_EXIT" -eq 0 ]; then
  log "Result: PASS — plan clean after apply"
  pass "[TEST 4] Plan clean after regression change applied"
else
  log "Result: FAIL — plan not clean after apply (exit $POST_EXIT)"
  log "$POST_PLAN"
  fail "[TEST 4] Plan not clean after apply"
fi

# 6. Restore original file
log ""
log "--- Restoring original main.tf ---"
cp "$BACKUP_FILE" "$MAIN_TF"
rm "$BACKUP_FILE"
log "Restored $MAIN_TF from backup"

log ""
log "Regression check complete for: $ENV"
log "Results written to: $RESULTS_FILE"
