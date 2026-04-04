// End-to-End Tests using Terratest

// The key difference from integration tests:
//   Integration tests verify a single module in isolation.
//   E2E tests verify that multiple modules work together as a system —
//   they catch interface mismatches (wrong output name, wrong variable type)
//   that unit and integration tests cannot see because each module is tested
//   alone.
//
// Why run E2E tests less frequently than unit tests?
//   E2E tests take 15–30 minutes and cost more because they deploy more
//   resources. Running them on every PR would slow down developer feedback
//   loops and increase costs. The right cadence is: unit tests on every PR,
//   integration tests on merge to main, E2E tests nightly or before releases.


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

// TestFullStackEndToEnd deploys the webserver cluster and verifies the full
// application path: DNS → ALB → target group → EC2 instance → HTTP 200.

func TestFullStackEndToEnd(t *testing.T) {
	t.Parallel()

	uniqueID := strings.ToLower(random.UniqueId())
	clusterName := fmt.Sprintf("e2e-%s", uniqueID)

	// Deploy the application tier (uses default VPC via data sources)
	appOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../modules/services/webserver-cluster",
		Vars: map[string]interface{}{
			"cluster_name":        clusterName,
			"instance_type":       "t3.micro",
			"min_size":            1,
			"max_size":            2,
			"environment":         "dev",
			"app_version":         "v1-e2e-test",
			"cpu_alarm_threshold": 90,
			"log_retention_days":  7,
		},
	})

	defer terraform.Destroy(t, appOptions)
	terraform.InitAndApply(t, appOptions)

	// Capture cross-module outputs (the "integration seam")
	albDnsName := terraform.Output(t, appOptions, "alb_dns_name")
	asgName := terraform.Output(t, appOptions, "asg_name")
	snsTopicArn := terraform.Output(t, appOptions, "sns_topic_arn")

	// Structural checks — verify the full naming convention is honoured end-to-end.
	assert.Contains(t, asgName, clusterName,
		"E2E: ASG name must contain the cluster name across the full stack")
	assert.Contains(t, snsTopicArn, clusterName,
		"E2E: SNS topic ARN must contain the cluster name")

	//  Full application path verification

	url := fmt.Sprintf("http://%s", albDnsName)

	// Retry for up to 15 minutes — ALB + ASG health checks take time.
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

	statusCode, body := http_helper.HttpGet(t, url, nil)
	assert.Equal(t, 200, statusCode, "E2E: final HTTP GET must return 200")
	assert.Contains(t, body, clusterName,
		"E2E: response body must contain the cluster name (proves user-data.sh ran)")
	assert.Contains(t, body, "Hello World",
		"E2E: response body must contain 'Hello World'")
}

// Pattern reference: multi-module E2E with explicit VPC wiring
//
// Uncomment and adapt this when you have a separate vpc module:
//
// func TestFullStackWithVPC(t *testing.T) {
//     t.Parallel()
//     uniqueID := random.UniqueId()
//
//     vpcOptions := &terraform.Options{
//         TerraformDir: "../modules/networking/vpc",
//         Vars: map[string]interface{}{
//             "vpc_name": fmt.Sprintf("test-vpc-%s", uniqueID),
//         },
//     }
//     defer terraform.Destroy(t, vpcOptions)
//     terraform.InitAndApply(t, vpcOptions)
//
//     vpcID     := terraform.Output(t, vpcOptions, "vpc_id")
//     subnetIDs := terraform.OutputList(t, vpcOptions, "public_subnet_ids")
//
//     appOptions := &terraform.Options{
//         TerraformDir: "../modules/services/webserver-cluster",
//         Vars: map[string]interface{}{
//             "cluster_name": fmt.Sprintf("app-%s", uniqueID),
//             "vpc_id":       vpcID,
//             "subnet_ids":   subnetIDs,
//             "environment":  "dev",
//         },
//     }
//     defer terraform.Destroy(t, appOptions)
//     terraform.InitAndApply(t, appOptions)
//
//     albDnsName := terraform.Output(t, appOptions, "alb_dns_name")
//     http_helper.HttpGetWithRetry(t,
//         fmt.Sprintf("http://%s", albDnsName), nil, 200, "Hello World", 30, 10*time.Second)
// }