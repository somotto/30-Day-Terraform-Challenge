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
RESULTS_FILE="$ROOT_DIR/results/asg-self-healing-${ENV}-results.txt"
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

log "ASG Self-Healing Test — Environment: $ENV"
log "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"

ASG_NAME=$(terraform -chdir="$DIR" output -raw asg_name 2>&1)
log "ASG Name: $ASG_NAME"

# 1. Record initial instance count
log ""
log "--- TEST 1: Record initial InService instance count ---"

INITIAL_COUNT=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query "length(AutoScalingGroups[0].Instances[?LifecycleState=='InService'])" \
  --output text 2>&1)

DESIRED=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query "AutoScalingGroups[0].DesiredCapacity" \
  --output text 2>&1)

log "Initial InService count: $INITIAL_COUNT"
log "Desired capacity:        $DESIRED"

if [ "$INITIAL_COUNT" -ge 2 ]; then
  log "Result: PASS — enough instances to safely terminate one"
  pass "[TEST 1] Initial count sufficient ($INITIAL_COUNT instances)"
else
  log "Result: SKIP — only $INITIAL_COUNT instance(s), need at least 2 to safely test"
  info "Increase min_size to 2 and re-apply before running this test"
  exit 0
fi

# 2. Pick one instance to terminate
log ""
log "--- Selecting one instance to terminate ---"

INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query "AutoScalingGroups[0].Instances[?LifecycleState=='InService'][0].InstanceId" \
  --output text 2>&1)

log "Terminating instance: $INSTANCE_ID"
log "Command: aws ec2 terminate-instances --instance-ids $INSTANCE_ID"

aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" >> "$RESULTS_FILE" 2>&1
log "Termination initiated."

# 3. Wait and verify ASG replaces the instance
log ""
log "--- TEST 2: ASG replaces terminated instance within 5 minutes ---"
log "Polling every 30 seconds for up to 5 minutes..."

MAX_WAIT=300
INTERVAL=30
ELAPSED=0
REPLACED=false

while [ $ELAPSED -lt $MAX_WAIT ]; do
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))

  CURRENT_COUNT=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --query "length(AutoScalingGroups[0].Instances[?LifecycleState=='InService'])" \
    --output text 2>&1)

  log "  [${ELAPSED}s] InService instances: $CURRENT_COUNT / $DESIRED"

  if [ "$CURRENT_COUNT" -ge "$DESIRED" ]; then
    REPLACED=true
    break
  fi
done

if $REPLACED; then
  log "Result: PASS — ASG replaced terminated instance within ${ELAPSED}s"
  pass "[TEST 2] ASG self-healing: instance replaced in ${ELAPSED}s"
else
  log "Result: FAIL — ASG did not restore desired count within ${MAX_WAIT}s"
  fail "[TEST 2] ASG self-healing: instance not replaced within ${MAX_WAIT}s"
fi

# 4. Verify ALB still serves traffic after replacement
log ""
log "--- TEST 3: ALB still serves traffic after instance replacement ---"

ALB_DNS=$(terraform -chdir="$DIR" output -raw alb_dns_name 2>&1)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://$ALB_DNS" 2>&1 || echo "000")

log "ALB DNS: $ALB_DNS"
log "HTTP status: $HTTP_CODE"

if [ "$HTTP_CODE" = "200" ]; then
  log "Result: PASS — ALB still serving HTTP 200 after instance replacement"
  pass "[TEST 3] ALB serving traffic after self-healing"
else
  log "Result: FAIL — ALB returned $HTTP_CODE after instance replacement"
  fail "[TEST 3] ALB not serving traffic after self-healing"
fi

log ""
log "ASG self-healing test complete for: $ENV"
log "Results written to: $RESULTS_FILE"
