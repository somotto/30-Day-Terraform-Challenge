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
RESULTS_FILE="$ROOT_DIR/results/state-consistency-${ENV}-results.txt"
mkdir -p "$ROOT_DIR/results"
> "$RESULTS_FILE"

log() { echo "$*" | tee -a "$RESULTS_FILE"; }

case "$ENV" in
  dev)
    DIR="$ROOT_DIR/../Day16/live/dev/services/webserver-cluster"
    CLUSTER_NAME="webservers-dev"
    ;;
  production)
    DIR="$ROOT_DIR/../Day16/live/production/services/webserver-cluster"
    CLUSTER_NAME="webservers-prod"
    ;;
  *)
    echo "Usage: $0 [dev|production]"
    exit 1
    ;;
esac

log "State Consistency Check — Environment: $ENV"
log "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# 1. terraform plan should return "No changes" after apply
log ""
log "--- TEST 1: terraform plan returns No changes after apply ---"
log "Command: terraform -chdir=$DIR plan -detailed-exitcode"
log "Expected: Exit code 0 (no changes)"

PLAN_OUTPUT=$(terraform -chdir="$DIR" plan \
  -detailed-exitcode \
  -var="db_password=placeholder-for-plan" \
  2>&1) || PLAN_EXIT=$?

PLAN_EXIT="${PLAN_EXIT:-0}"
log "Plan output:"
log "$PLAN_OUTPUT"
log "Exit code: $PLAN_EXIT"

# Exit codes: 0=no changes, 1=error, 2=changes present
case "$PLAN_EXIT" in
  0)
    log "Result: PASS — no changes (infrastructure matches configuration)"
    pass "[TEST 1] No changes after apply (exit code 0)"
    ;;
  2)
    log "Result: FAIL — plan shows changes (exit code 2)"
    log "This means the state file does not match what is in AWS."
    log "Investigate the diff above and re-apply to reconcile."
    fail "[TEST 1] State drift detected (exit code 2 — changes present)"
    ;;
  *)
    log "Result: FAIL — plan errored (exit code $PLAN_EXIT)"
    fail "[TEST 1] Plan error (exit code $PLAN_EXIT)"
    ;;
esac

# 2. terraform state list — verify expected resources exist
log ""
log "--- TEST 2: State file contains expected resources ---"
log "Command: terraform -chdir=$DIR state list"

STATE_LIST=$(terraform -chdir="$DIR" state list 2>&1)
log "$STATE_LIST"

EXPECTED_RESOURCES=(
  "module.webserver_cluster.aws_lb.example"
  "module.webserver_cluster.aws_autoscaling_group.example"
  "module.webserver_cluster.aws_lb_target_group.asg"
  "module.webserver_cluster.aws_security_group.alb_sg"
  "module.webserver_cluster.aws_security_group.web_sg"
  "module.webserver_cluster.aws_launch_template.example"
  "module.webserver_cluster.aws_cloudwatch_metric_alarm.high_cpu"
  "module.webserver_cluster.aws_cloudwatch_metric_alarm.unhealthy_hosts"
  "module.webserver_cluster.aws_cloudwatch_metric_alarm.alb_5xx"
)

ALL_PRESENT=true
for resource in "${EXPECTED_RESOURCES[@]}"; do
  if echo "$STATE_LIST" | grep -q "$resource"; then
    log "  [PRESENT] $resource"
  else
    log "  [MISSING] $resource"
    ALL_PRESENT=false
  fi
done

if $ALL_PRESENT; then
  log "Result: PASS — all expected resources in state"
  pass "[TEST 2] All expected resources present in state"
else
  log "Result: FAIL — one or more expected resources missing from state"
  fail "[TEST 2] Missing resources in state"
fi

# 3. Cross-check: state resource count vs AWS resource count
log ""
log "--- TEST 3: EC2 instances in AWS match ASG desired count ---"
log "Command: aws ec2 describe-instances --filters ..."

ASG_NAME=$(terraform -chdir="$DIR" output -raw asg_name 2>&1)

AWS_INSTANCE_COUNT=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:aws:autoscaling:groupName,Values=$ASG_NAME" \
    "Name=instance-state-name,Values=running" \
  --query "length(Reservations[*].Instances[*])" \
  --output text 2>&1)

DESIRED=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query "AutoScalingGroups[0].DesiredCapacity" \
  --output text 2>&1)

log "ASG desired: $DESIRED"
log "Running instances in AWS: $AWS_INSTANCE_COUNT"

if [ "$AWS_INSTANCE_COUNT" = "$DESIRED" ]; then
  log "Result: PASS — AWS instance count matches ASG desired"
  pass "[TEST 3] Instance count matches ($AWS_INSTANCE_COUNT running, $DESIRED desired)"
else
  log "Result: FAIL — AWS instance count ($AWS_INSTANCE_COUNT) != ASG desired ($DESIRED)"
  fail "[TEST 3] Instance count mismatch"
fi

log ""
log "State consistency check complete for: $ENV"
log "Results written to: $RESULTS_FILE"
