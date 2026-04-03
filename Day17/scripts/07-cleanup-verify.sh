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
RESULTS_FILE="$ROOT_DIR/results/cleanup-verify-${ENV}-results.txt"
mkdir -p "$ROOT_DIR/results"
> "$RESULTS_FILE"

log() { echo "$*" | tee -a "$RESULTS_FILE"; }

case "$ENV" in
  dev)
    DIR="$ROOT_DIR/../Day16/live/dev/services/webserver-cluster"
    CLUSTER_NAME="webservers-dev"
    ;;
  production)
    log "ERROR: Refusing to destroy production environment automatically."
    log "Run terraform destroy manually in $ROOT_DIR/../Day16/live/production/services/webserver-cluster"
    exit 1
    ;;
  *)
    echo "Usage: $0 [dev|production]"
    exit 1
    ;;
esac

log "Cleanup and Verification — Environment: $ENV"
log "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
# 1. Preview what will be destroyed
log ""
log "--- Step 1: Preview destroy plan ---"
log "Command: terraform -chdir=$DIR plan -destroy"

DESTROY_PLAN=$(terraform -chdir="$DIR" plan \
  -destroy \
  -var="db_password=placeholder-for-plan" \
  2>&1)

log "$DESTROY_PLAN"

RESOURCES_TO_DESTROY=$(echo "$DESTROY_PLAN" | grep -oP '\d+(?= to destroy)' || echo "0")
log "Resources to destroy: $RESOURCES_TO_DESTROY"

if [ "$RESOURCES_TO_DESTROY" -eq 0 ]; then
  log "Nothing to destroy — environment may already be clean."
  pass "[Step 1] Nothing to destroy"
  exit 0
fi

# 2. Confirm before destroying
log ""
info "About to destroy $RESOURCES_TO_DESTROY resources in $ENV."
info "This is irreversible. Press Ctrl+C within 10 seconds to abort."
sleep 10

# 3. Run destroy
log ""
log "--- Step 2: terraform destroy ---"
log "Command: terraform -chdir=$DIR destroy -auto-approve"

DESTROY_OUTPUT=$(terraform -chdir="$DIR" destroy \
  -auto-approve \
  -var="db_password=placeholder-for-plan" \
  2>&1)

log "$DESTROY_OUTPUT"

if echo "$DESTROY_OUTPUT" | grep -q "Destroy complete"; then
  log "Result: PASS — terraform destroy completed"
  pass "[Step 2] terraform destroy completed"
else
  log "Result: FAIL — terraform destroy did not complete cleanly"
  fail "[Step 2] terraform destroy"
fi

# 4. Post-destroy verification: EC2 instances
log ""
log "--- Step 3: Verify no EC2 instances remain ---"
log "Command: aws ec2 describe-instances --filters Name=tag:ManagedBy,Values=terraform Name=tag:Cluster,Values=$CLUSTER_NAME"

REMAINING_INSTANCES=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:ManagedBy,Values=terraform" \
    "Name=tag:Cluster,Values=$CLUSTER_NAME" \
    "Name=instance-state-name,Values=running,pending,stopping,stopped" \
  --query "Reservations[*].Instances[*].InstanceId" \
  --output text 2>&1)

log "Remaining instances: ${REMAINING_INSTANCES:-none}"

if [ -z "$REMAINING_INSTANCES" ] || [ "$REMAINING_INSTANCES" = "None" ]; then
  log "Result: PASS — no EC2 instances remain"
  pass "[Step 3] No EC2 instances remain"
else
  log "Result: FAIL — orphaned instances found: $REMAINING_INSTANCES"
  fail "[Step 3] Orphaned EC2 instances: $REMAINING_INSTANCES"
fi

# 5. Post-destroy verification: Load Balancers
log ""
log "--- Step 4: Verify no load balancers remain ---"
log "Command: aws elbv2 describe-load-balancers --query ..."

REMAINING_ALBS=$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName, '${CLUSTER_NAME}')].LoadBalancerArn" \
  --output text 2>&1)

log "Remaining ALBs: ${REMAINING_ALBS:-none}"

if [ -z "$REMAINING_ALBS" ] || [ "$REMAINING_ALBS" = "None" ]; then
  log "Result: PASS — no load balancers remain"
  pass "[Step 4] No load balancers remain"
else
  log "Result: FAIL — orphaned ALBs found: $REMAINING_ALBS"
  fail "[Step 4] Orphaned ALBs: $REMAINING_ALBS"
fi

# 6. Post-destroy verification: Security Groups
log ""
log "--- Step 5: Verify no security groups remain ---"
log "Command: aws ec2 describe-security-groups --filters ..."

REMAINING_SGS=$(aws ec2 describe-security-groups \
  --filters \
    "Name=tag:ManagedBy,Values=terraform" \
    "Name=tag:Cluster,Values=$CLUSTER_NAME" \
  --query "SecurityGroups[*].GroupId" \
  --output text 2>&1)

log "Remaining security groups: ${REMAINING_SGS:-none}"

if [ -z "$REMAINING_SGS" ] || [ "$REMAINING_SGS" = "None" ]; then
  log "Result: PASS — no security groups remain"
  pass "[Step 5] No security groups remain"
else
  log "Result: FAIL — orphaned security groups: $REMAINING_SGS"
  fail "[Step 5] Orphaned security groups: $REMAINING_SGS"
fi

# 7. Post-destroy verification: Target Groups
log ""
log "--- Step 6: Verify no target groups remain ---"
log "Command: aws elbv2 describe-target-groups --query ..."

REMAINING_TGS=$(aws elbv2 describe-target-groups \
  --query "TargetGroups[?contains(TargetGroupName, '${CLUSTER_NAME}')].TargetGroupArn" \
  --output text 2>&1)

log "Remaining target groups: ${REMAINING_TGS:-none}"

if [ -z "$REMAINING_TGS" ] || [ "$REMAINING_TGS" = "None" ]; then
  log "Result: PASS — no target groups remain"
  pass "[Step 6] No target groups remain"
else
  log "Result: FAIL — orphaned target groups: $REMAINING_TGS"
  fail "[Step 6] Orphaned target groups: $REMAINING_TGS"
fi

# 8. Post-destroy verification: CloudWatch alarms
log ""
log "--- Step 7: Verify no CloudWatch alarms remain ---"
log "Command: aws cloudwatch describe-alarms --alarm-name-prefix $CLUSTER_NAME"

REMAINING_ALARMS=$(aws cloudwatch describe-alarms \
  --alarm-name-prefix "$CLUSTER_NAME" \
  --query "length(MetricAlarms)" \
  --output text 2>&1)

log "Remaining alarms: $REMAINING_ALARMS"

if [ "$REMAINING_ALARMS" = "0" ]; then
  log "Result: PASS — no CloudWatch alarms remain"
  pass "[Step 7] No CloudWatch alarms remain"
else
  log "Result: FAIL — $REMAINING_ALARMS alarm(s) still exist"
  fail "[Step 7] Orphaned CloudWatch alarms: $REMAINING_ALARMS"
fi

log ""
log "Cleanup verification complete for: $ENV"
log "Results written to: $RESULTS_FILE"
