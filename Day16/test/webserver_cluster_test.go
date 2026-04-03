package test

import (
	"fmt"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/http-helper"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// TestWebserverClusterDev deploys the webserver cluster module in dev mode,
// verifies the ALB returns HTTP 200 with "Hello World", then destroys everything.
func TestWebserverClusterDev(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		// Path to the module under test
		TerraformDir: "../modules/services/webserver-cluster",

		Vars: map[string]interface{}{
			"cluster_name":        "test-cluster",
			"environment":         "dev",
			"project_name":        "terratest",
			"team_name":           "test-team",
			"instance_type":       "t3.micro",
			"min_size":            1,
			"max_size":            2,
			"app_version":         "v1-test",
			"cpu_alarm_threshold": 90,
			"log_retention_days":  7,
		},
	})

	// defer runs even if the test panics — ensures we never leave resources running
	defer terraform.Destroy(t, terraformOptions)

	// Init and apply — Terratest retries on known transient AWS errors
	terraform.InitAndApply(t, terraformOptions)

	// Read the ALB DNS name from outputs
	albDnsName := terraform.Output(t, terraformOptions, "alb_dns_name")
	url := fmt.Sprintf("http://%s", albDnsName)

	// Poll the ALB every 10 seconds for up to 5 minutes waiting for HTTP 200
	// ALBs take time to register targets and pass health checks
	http_helper.HttpGetWithRetry(
		t,
		url,
		nil,
		200,
		"Hello World",
		30,
		10*time.Second,
	)
}

// TestWebserverClusterValidation verifies that invalid variable values are rejected
// before any AWS resources are created.
func TestWebserverClusterValidation(t *testing.T) {
	t.Parallel()

	// Invalid environment should fail at plan time
	invalidEnvOptions := &terraform.Options{
		TerraformDir: "../modules/services/webserver-cluster",
		Vars: map[string]interface{}{
			"cluster_name":  "test-cluster",
			"environment":   "invalid-env", // not in ["dev","staging","production"]
			"instance_type": "t3.micro",
		},
	}

	_, err := terraform.InitAndPlanE(t, invalidEnvOptions)
	assert.Error(t, err, "Expected plan to fail with invalid environment")

	// Invalid instance type should fail at plan time
	invalidInstanceOptions := &terraform.Options{
		TerraformDir: "../modules/services/webserver-cluster",
		Vars: map[string]interface{}{
			"cluster_name":  "test-cluster",
			"environment":   "dev",
			"instance_type": "m5.large", // not a t3 type
		},
	}

	_, err = terraform.InitAndPlanE(t, invalidInstanceOptions)
	assert.Error(t, err, "Expected plan to fail with invalid instance type")
}

// TestWebserverClusterOutputs verifies all expected outputs are present after apply.
func TestWebserverClusterOutputs(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../modules/services/webserver-cluster",
		Vars: map[string]interface{}{
			"cluster_name":        "test-outputs",
			"environment":         "dev",
			"project_name":        "terratest",
			"team_name":           "test-team",
			"instance_type":       "t3.micro",
			"min_size":            1,
			"max_size":            2,
			"log_retention_days":  7,
		},
	})

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Assert all outputs are non-empty
	outputs := []string{
		"alb_dns_name",
		"asg_name",
		"instance_role_name",
		"sns_topic_arn",
		"log_group_name",
		"web_sg_id",
		"alb_sg_id",
	}

	for _, output := range outputs {
		value := terraform.Output(t, terraformOptions, output)
		assert.NotEmpty(t, value, "Expected output %s to be non-empty", output)
	}
}
