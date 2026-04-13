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
)

// TestWebserverClusterIntegration deploys the module, verifies all outputs, waits
// for HTTP 200, then destroys. Outputs verification is folded in here to avoid
// running a second parallel deploy (free-tier account limit).
func TestWebserverClusterIntegration(t *testing.T) {
	t.Parallel()

	uniqueID    := strings.ToLower(random.UniqueId())
	clusterName := fmt.Sprintf("test-%s", uniqueID)

	opts := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../modules/services/webserver-cluster",
		Vars: map[string]interface{}{
			"cluster_name":        clusterName,
			"environment":         "dev",
			"instance_type":       "t3.micro",
			"min_size":            1,
			"max_size":            2,
			"app_version":         "v3-integration-test",
			"cpu_alarm_threshold": 90,
			"log_retention_days":  7,
		},
	})

	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	for _, name := range []string{
		"alb_dns_name", "alb_arn", "asg_name",
		"instance_role_name", "instance_profile_name",
		"sns_topic_arn", "log_group_name",
		"web_sg_id", "alb_sg_id",
	} {
		assert.NotEmpty(t, terraform.Output(t, opts, name),
			"output '%s' must not be empty", name)
	}

	albDnsName   := terraform.Output(t, opts, "alb_dns_name")
	asgName      := terraform.Output(t, opts, "asg_name")
	logGroupName := terraform.Output(t, opts, "log_group_name")

	assert.Contains(t, asgName, clusterName, "ASG name must contain cluster name")
	assert.Equal(t, fmt.Sprintf("/aws/ec2/%s", clusterName), logGroupName,
		"log_group_name must follow /aws/ec2/<cluster_name> convention")

	url := fmt.Sprintf("http://%s", albDnsName)
	http_helper.HttpGetWithRetryWithCustomValidation(
		t, url, nil, 80, 15*time.Second,
		func(statusCode int, body string) bool {
			return statusCode == 200 && strings.Contains(body, "Hello World")
		},
	)

	statusCode, body := http_helper.HttpGet(t, url, nil)
	assert.Equal(t, 200, statusCode)
	assert.Contains(t, body, "Hello World")
	assert.Contains(t, body, "v3", "response must include app_version v3")
}

// TestWebserverClusterValidation ensures invalid variable values are rejected at
// plan time. Plan-only — no real AWS resources are created.
func TestWebserverClusterValidation(t *testing.T) {
	t.Parallel()

	base := map[string]interface{}{
		"cluster_name":  "test-cluster",
		"environment":   "dev",
		"instance_type": "t3.micro",
	}

	cases := []struct {
		name   string
		mutate func(map[string]interface{})
	}{
		{"invalid_environment", func(v map[string]interface{}) { v["environment"] = "qa" }},
		{"invalid_instance_type", func(v map[string]interface{}) { v["instance_type"] = "m5.large" }},
		{"invalid_cluster_name", func(v map[string]interface{}) { v["cluster_name"] = "UPPER_CASE" }},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			vars := make(map[string]interface{})
			for k, v := range base {
				vars[k] = v
			}
			tc.mutate(vars)
			_, err := terraform.InitAndPlanE(t, &terraform.Options{
				TerraformDir: "../modules/services/webserver-cluster",
				Vars:         vars,
			})
			assert.Error(t, err, "plan should fail for case: %s", tc.name)
		})
	}
}
