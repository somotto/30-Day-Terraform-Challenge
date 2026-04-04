package test

import (
	"fmt"
	"strings"
	"testing"
	"time"

	http_helper "github.com/gruntwork-io/terratest/modules/http-helper"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestWebserverClusterIntegration deploys the webserver-cluster module with a
// unique cluster name, waits for the ALB to return HTTP 200, then destroys
// everything — even if assertions fail.
func TestWebserverClusterIntegration(t *testing.T) {
	t.Parallel()

	// Generate a unique suffix so parallel test runs never collide on resource names.
	uniqueID := strings.ToLower(random.UniqueId())
	clusterName := fmt.Sprintf("test-%s", uniqueID)

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../modules/services/webserver-cluster",
		Vars: map[string]interface{}{
			"cluster_name":        clusterName,
			"instance_type":       "t3.micro",
			"min_size":            1,
			"max_size":            2,
			"environment":         "dev",
			"app_version":         "v1-integration-test",
			"cpu_alarm_threshold": 90,
			"log_retention_days":  7,
		},
		// Increase default Terraform operation timeout for slow ASG operations
		MaxRetries:         3,
		TimeBetweenRetries: 10 * time.Second,
	})

	defer terraform.Destroy(t, terraformOptions)

	terraform.InitAndApply(t, terraformOptions)

	albDnsName := terraform.Output(t, terraformOptions, "alb_dns_name")
	asgName := terraform.Output(t, terraformOptions, "asg_name")
	logGroupName := terraform.Output(t, terraformOptions, "log_group_name")

	assert.NotEmpty(t, albDnsName, "alb_dns_name output must not be empty")
	assert.Contains(t, asgName, clusterName, "ASG name must contain the cluster name")
	assert.Equal(t, fmt.Sprintf("/aws/ec2/%s", clusterName), logGroupName,
		"log_group_name must follow the /aws/ec2/<cluster_name> convention")

	// ALBs take time to register targets and pass health checks.
	// The ASG health_check_grace_period is 120s, plus instance boot time.
	// We retry for up to 15 minutes (60 × 15s) to be safe.
	url := fmt.Sprintf("http://%s", albDnsName)
	http_helper.HttpGetWithRetryWithCustomValidation(
		t,
		url,
		nil,
		60,
		15*time.Second,
		func(statusCode int, body string) bool {
			return statusCode == 200 && strings.Contains(body, "Hello World")
		},
	)
}

// TestWebserverClusterOutputs verifies that all expected outputs are present
// and non-empty after a real deployment. This catches regressions where an
// output is accidentally removed or renamed in outputs.tf.
func TestWebserverClusterOutputs(t *testing.T) {
	t.Parallel()

	uniqueID := strings.ToLower(random.UniqueId())
	clusterName := fmt.Sprintf("out-%s", uniqueID)

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../modules/services/webserver-cluster",
		Vars: map[string]interface{}{
			"cluster_name":  clusterName,
			"instance_type": "t3.micro",
			"min_size":      1,
			"max_size":      1,
			"environment":   "dev",
		},
	})

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	outputs := []string{
		"alb_dns_name",
		"alb_arn",
		"asg_name",
		"instance_role_name",
		"instance_profile_name",
		"sns_topic_arn",
		"log_group_name",
		"web_sg_id",
		"alb_sg_id",
	}

	for _, outputName := range outputs {
		value := terraform.Output(t, terraformOptions, outputName)
		require.NotEmpty(t, value, "output '%s' must not be empty after apply", outputName)
	}
}
