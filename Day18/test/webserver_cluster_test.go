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

	// ALB health checks pass before apply returns (min_elb_capacity=1),
	// but the python HTTP server may still be starting. Retry for 20 minutes.
	url := fmt.Sprintf("http://%s", albDnsName)
	http_helper.HttpGetWithRetryWithCustomValidation(
		t,
		url,
		nil,
		80,             // 80 retries
		15*time.Second, // 15s apart = 20 minutes total
		func(statusCode int, body string) bool {
			return statusCode == 200 && strings.Contains(body, "Hello World")
		},
	)

	// Final check — log the actual response so failures are easy to diagnose
	statusCode, body := http_helper.HttpGet(t, url, nil)
	assert.Equal(t, 200, statusCode, "final HTTP GET must return 200")
	assert.Contains(t, body, "Hello World", "response body must contain 'Hello World'")
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
