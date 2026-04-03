#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass()  { echo -e "${GREEN}[PASS]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; }
info()  { echo -e "${YELLOW}[INFO]${NC} $*"; }
step()  { echo -e "${BLUE}[STEP]${NC} $*"; }

ENV="${1:-dev}"
RESULTS_FILE="$ROOT_DIR/results/functional-verify-${ENV}-results.txt"
mkdir -p "$ROOT_DIR/results"
> "$RESULTS_FILE"

log() { echo "$*" | tee -a "$RESULTS_FILE"; }

case "$ENV" in
  dev)
    DIR="$ROOT_DIR/../Day16/live/dev/services/webserver-cluster"
    CLUSTER_NAME="webservers-dev"
    EXPECTED_BODY="Hello World"
    ;;
  production)
    DIR="$ROOT_DIR/../Day16/live/production/services/webserver-cluster"
    CLUSTER_NAME="webservers-prod"
    EXPECTED_BODY="Hello World"
    ;;
  *)
    echo "Usage: $0 [dev|production]"
    exit 1
    ;;
esac

log "Functional Verification — Environment: $ENV"
log "Cluster:    $CLUSTER_NAME"
log "Timestamp:  $(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# 1. Get ALB DNS from Terraform output
log ""
log "--- TEST 1: Get ALB DNS name from Terraform output ---"
log "Command: terraform -chdir=$DIR output -raw alb_dns_name"

ALB_DNS=$(terraform -chdir="$DIR" output -raw alb_dns_name 2>&1)
if [ -z "$ALB_DNS" ] || echo "$ALB_DNS" | grep -q "Error"; then
  log "Result: FAIL — could not retrieve ALB DNS name"
  log "Output: $ALB_DNS"
  fail "[TEST 1] ALB DNS name retrieval"
  exit 1
fi

log "ALB DNS: $ALB_DNS"
log "Result: PASS"
pass "[TEST 1] ALB DNS name retrieved: $ALB_DNS"

# 2. DNS resolution check
log ""
log "--- TEST 2: ALB DNS resolves ---"
log "Command: host $ALB_DNS"

if host "$ALB_DNS" >> "$RESULTS_FILE" 2>&1; then
  log "Result: PASS"
  pass "[TEST 2] DNS resolves for $ALB_DNS"
else
  log "Result: FAIL — DNS did not resolve"
  fail "[TEST 2] DNS resolution"
fi

# 3. HTTP status code check
log ""
log "--- TEST 3: ALB returns HTTP 200 ---"
log "Command: curl -s -o /dev/null -w \"%{http_code}\" http://$ALB_DNS"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://$ALB_DNS" 2>&1 || echo "000")
log "HTTP status code: $HTTP_CODE"

if [ "$HTTP_CODE" = "200" ]; then
  log "Result: PASS"
  pass "[TEST 3] HTTP 200 from ALB"
else
  log "Result: FAIL — expected 200, got $HTTP_CODE"
  fail "[TEST 3] HTTP status code (expected 200, got $HTTP_CODE)"
fi

# 4. Response body check
log ""
log "--- TEST 4: Response body contains '$EXPECTED_BODY' ---"
log "Command: curl -s http://$ALB_DNS | grep '$EXPECTED_BODY'"

BODY=$(curl -s --max-time 10 "http://$ALB_DNS" 2>&1 || echo "")
log "Response body (first 500 chars):"
log "${BODY:0:500}"

if echo "$BODY" | grep -q "$EXPECTED_BODY"; then
  log "Result: PASS"
  pass "[TEST 4] Response body contains '$EXPECTED_BODY'"
else
  log "Result: FAIL — '$EXPECTED_BODY' not found in response"
  fail "[TEST 4] Response body check"
fi

# 5. Target group health check
log ""
log "--- TEST 5: All targets in target group are healthy ---"
log "Command: aws elbv2 describe-target-groups --query ..."

TG_ARN=$(aws elbv2 describe-target-groups \
  --query "TargetGroups[?contains(TargetGroupName, '${CLUSTER_NAME}')].TargetGroupArn" \
  --output text 2>&1)

if [ -z "$TG_ARN" ] || [ "$TG_ARN" = "None" ]; then
  log "Result: FAIL — target group not found for cluster $CLUSTER_NAME"
  fail "[TEST 5] Target group lookup"
else
  log "Target Group ARN: $TG_ARN"

  HEALTH_OUTPUT=$(aws elbv2 describe-target-health \
    --target-group-arn "$TG_ARN" \
    --query "TargetHealthDescriptions[*].{ID:Target.Id,Port:Target.Port,State:TargetHealth.State}" \
    --output table 2>&1)

  log "$HEALTH_OUTPUT"

  UNHEALTHY_COUNT=$(aws elbv2 describe-target-health \
    --target-group-arn "$TG_ARN" \
    --query "length(TargetHealthDescriptions[?TargetHealth.State!='healthy'])" \
    --output text 2>&1)

  if [ "$UNHEALTHY_COUNT" = "0" ]; then
    log "Result: PASS — all targets healthy"
    pass "[TEST 5] All targets healthy"
  else
    log "Result: FAIL — $UNHEALTHY_COUNT unhealthy target(s)"
    fail "[TEST 5] Target health ($UNHEALTHY_COUNT unhealthy)"
  fi
fi

# 6. ASG instance count check
log ""
log "--- TEST 6: ASG running instance count matches desired ---"
log "Command: terraform -chdir=$DIR output -raw asg_name"

ASG_NAME=$(terraform -chdir="$DIR" output -raw asg_name 2>&1)
log "ASG Name: $ASG_NAME"

ASG_INFO=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query "AutoScalingGroups[0].{Min:MinSize,Max:MaxSize,Desired:DesiredCapacity,InService:Instances[?LifecycleState=='InService']|length(@)}" \
  --output table 2>&1)

log "$ASG_INFO"

DESIRED=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query "AutoScalingGroups[0].DesiredCapacity" \
  --output text 2>&1)

IN_SERVICE=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query "length(AutoScalingGroups[0].Instances[?LifecycleState=='InService'])" \
  --output text 2>&1)

if [ "$IN_SERVICE" = "$DESIRED" ]; then
  log "Result: PASS — $IN_SERVICE/$DESIRED instances InService"
  pass "[TEST 6] ASG instance count ($IN_SERVICE/$DESIRED InService)"
else
  log "Result: FAIL — $IN_SERVICE InService, expected $DESIRED"
  fail "[TEST 6] ASG instance count ($IN_SERVICE InService, expected $DESIRED)"
fi

# 7. CloudWatch alarms in OK state
log ""
log "--- TEST 7: CloudWatch alarms exist and are in OK state ---"
log "Command: aws cloudwatch describe-alarms --alarm-name-prefix $CLUSTER_NAME"

ALARM_OUTPUT=$(aws cloudwatch describe-alarms \
  --alarm-name-prefix "$CLUSTER_NAME" \
  --query "MetricAlarms[*].{Name:AlarmName,State:StateValue}" \
  --output table 2>&1)

log "$ALARM_OUTPUT"

ALARM_COUNT=$(aws cloudwatch describe-alarms \
  --alarm-name-prefix "$CLUSTER_NAME" \
  --query "length(MetricAlarms)" \
  --output text 2>&1)

if [ "$ALARM_COUNT" -ge 3 ]; then
  log "Result: PASS — $ALARM_COUNT alarms found"
  pass "[TEST 7] CloudWatch alarms exist ($ALARM_COUNT found)"
else
  log "Result: FAIL — expected at least 3 alarms, found $ALARM_COUNT"
  fail "[TEST 7] CloudWatch alarm count (expected >=3, got $ALARM_COUNT)"
fi

# 8. Resource tagging spot-check
log ""
log "--- TEST 8: ALB has required tags ---"
log "Command: aws elbv2 describe-load-balancers ..."

ALB_ARN=$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName, '${CLUSTER_NAME}')].LoadBalancerArn" \
  --output text 2>&1)

if [ -n "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ]; then
  TAG_OUTPUT=$(aws elbv2 describe-tags \
    --resource-arns "$ALB_ARN" \
    --query "TagDescriptions[0].Tags" \
    --output table 2>&1)

  log "$TAG_OUTPUT"

  MANAGED_BY=$(aws elbv2 describe-tags \
    --resource-arns "$ALB_ARN" \
    --query "TagDescriptions[0].Tags[?Key=='ManagedBy'].Value" \
    --output text 2>&1)

  if [ "$MANAGED_BY" = "terraform" ]; then
    log "Result: PASS — ManagedBy=terraform tag present"
    pass "[TEST 8] ALB has ManagedBy=terraform tag"
  else
    log "Result: FAIL — ManagedBy tag missing or incorrect (got: $MANAGED_BY)"
    fail "[TEST 8] ALB tagging"
  fi
else
  log "Result: FAIL — ALB not found for cluster $CLUSTER_NAME"
  fail "[TEST 8] ALB lookup for tagging check"
fi

log ""
log "Functional verification complete for: $ENV"
log "Results written to: $RESULTS_FILE"
