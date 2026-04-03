#!/usr/bin/env bash
# Day17 — Lab 1: State Migration Walkthrough
# Run each step manually and observe the output.
# This script is annotated — do not run it end-to-end blindly.
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Lab 1: State Migration — Local to S3"

# STEP 1: Deploy with local state
echo ""
echo "STEP 1: Deploy with local state (no backend block)"
echo "Command: terraform init && terraform apply"
echo ""
echo "Expected: terraform.tfstate created in this directory"
echo ""

terraform -chdir="$LAB_DIR" init -input=false
terraform -chdir="$LAB_DIR" apply -auto-approve

echo ""
echo "Local state file contents (resource count):"
# Count resources in local state
python3 -c "
import json, sys
with open('$LAB_DIR/terraform.tfstate') as f:
    state = json.load(f)
resources = state.get('resources', [])
print(f'  Resources in local state: {len(resources)}')
for r in resources:
    print(f'  - {r[\"type\"]}.{r[\"name\"]}')
" 2>/dev/null || echo "  (python3 not available — check terraform.tfstate manually)"

# STEP 2: Verify the resource exists in AWS
echo ""
echo "STEP 2: Verify resource exists in AWS before migration"
echo "Command: aws ssm get-parameter --name /day17/lab1/migration-demo"
echo ""

aws ssm get-parameter \
  --name "/day17/lab1/migration-demo" \
  --query "Parameter.{Name:Name,Value:Value,ARN:ARN}" \
  --output table

echo ""
echo "Result: Resource confirmed in AWS. State is currently local."

# STEP 3: Instruct user to uncomment the backend block
echo ""
echo "STEP 3: Manual action required"
echo ""
echo "1. Open $LAB_DIR/main.tf"
echo "2. Uncomment the backend \"s3\" block"
echo "3. Replace YOUR-STATE-BUCKET-NAME with your actual bucket name"
echo "   (from Day16 bootstrap: terraform output state_bucket_name)"
echo ""
echo "Then run STEP 4 below."
echo ""
echo "Press Enter when you have uncommented the backend block..."
read -r

# STEP 4: Migrate state
echo ""
echo "STEP 4: Migrate state to S3"
echo "Command: terraform init -migrate-state"
echo ""
echo "Terraform will ask: 'Do you want to copy existing state to the new backend?'"
echo "Answer: yes"
echo ""

terraform -chdir="$LAB_DIR" init -migrate-state

# STEP 5: Verify migration
echo ""
echo "STEP 5: Verify migration succeeded"
echo ""

echo "5a. State list should show the same resource:"
echo "Command: terraform state list"
terraform -chdir="$LAB_DIR" state list

echo ""
echo "5b. Local terraform.tfstate should now be empty (state is in S3):"
if [ -f "$LAB_DIR/terraform.tfstate" ]; then
  LOCAL_RESOURCES=$(python3 -c "
import json
with open('$LAB_DIR/terraform.tfstate') as f:
    state = json.load(f)
print(len(state.get('resources', [])))
" 2>/dev/null || echo "unknown")
  echo "  Local state resource count: $LOCAL_RESOURCES (expected: 0)"
else
  echo "  Local terraform.tfstate does not exist (state fully migrated)"
fi

echo ""
echo "5c. Verify S3 contains the state file:"
BUCKET_NAME=$(terraform -chdir="$LAB_DIR" output -raw state_bucket_name 2>/dev/null || echo "")
if [ -n "$BUCKET_NAME" ]; then
  aws s3 ls "s3://$BUCKET_NAME/day17/lab1/" || echo "  (check bucket name in backend block)"
fi

echo ""
echo "5d. Run plan — should show No changes:"
echo "Command: terraform plan"
terraform -chdir="$LAB_DIR" plan

echo ""
echo "Lab 1 Complete: State successfully migrated to S3"
echo ""
echo "CLEANUP: Run terraform destroy to remove the SSM parameter"
echo "Command: terraform -chdir=$LAB_DIR destroy"
