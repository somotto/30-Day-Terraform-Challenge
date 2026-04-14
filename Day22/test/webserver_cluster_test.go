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

// TestWebserverCluster deploys the module, verifies all outputs and HTTP response,
// then destroys everything. This is the integration test run by the CI pipeline.
func TestWebserverCluster(t *testing.T) {
	t.Parallel()

	uniqueID    := strings.ToLower(random.UniqueId())
	clusterName := fmt.Sprintf("test-%s", uniqueID)

	opts := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../modules/services/webserver-cluster",
		Vars: map[string]interface{}{
			"cluster_name":                   clusterName,
			"environment":                    "dev",
			"instance_type":                  "t3.micro",
			"min_size":                       1,
			"max_size":                       2,
			"app_version":                    "v5-integration-test",
			"cpu_alarm_threshold":            90,
			"request_count_alarm_threshold":  500,
			"log_retention_days":             7,
		},
	})

	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	// Verify all expected outputs are present
	for _, name := range []string{
		"alb_dns_name", "alb_arn", "asg_name",
		"instance_role_name", "instance_profile_name",
		"sns_topic_arn", "log_group_name",
		"web_sg_id", "alb_sg_id",
		"high_cpu_alarm_arn", "unhealthy_hosts_alarm_arn",
		"alb_5xx_alarm_arn", "request_count_alarm_arn",
	} {
		assert.NotEmpty(t, terraform.Output(t, opts, name),
			"output '%s' must not be empty", name)
	}

	asgName      := terraform.Output(t, opts, "asg_name")
	logGroupName := terraform.Output(t, opts, "log_group_name")
	albDnsName   := terraform.Output(t, opts, "alb_dns_name")

	assert.Contains(t, asgName, clusterName, "ASG name must contain cluster name")
	assert.Equal(t, fmt.Sprintf("/aws/ec2/%s", clusterName), logGroupName,
		"log_group_name must follow /aws/ec2/<cluster_name> convention")

	requestCountAlarmArn := terraform.Output(t, opts, "request_count_alarm_arn")
	assert.Contains(t, requestCountAlarmArn, clusterName,
		"request_count_alarm_arn must reference the cluster")

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
	assert.Contains(t, body, "v5", "response must include app_version v5")
	// Sentinel compliance marker rendered by user-data.sh
	assert.Contains(t, body, "Sentinel: compliant", "response must include Sentinel compliance marker")
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
		// Sentinel: allowed-instance-types would also block this, but the variable
		// validation catches it first at plan time.
		{"invalid_instance_type", func(v map[string]interface{}) { v["instance_type"] = "m5.large" }},
		{"invalid_cluster_name", func(v map[string]interface{}) { v["cluster_name"] = "UPPER_CASE" }},
		{"invalid_server_port_low", func(v map[string]interface{}) { v["server_port"] = 80 }},
		{"invalid_cpu_threshold", func(v map[string]interface{}) { v["cpu_alarm_threshold"] = 0 }},
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
