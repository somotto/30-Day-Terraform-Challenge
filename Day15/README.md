# Day 15: Working with Multiple Providers — Part 2
---

## Directory Structure

```
Day15/
├── modules/
│   ├── multi-region-app/        # Module that accepts two AWS provider aliases
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── eks-cluster/             # EKS + VPC module wrapper
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── live/
│   ├── multi-region/            # Lab: multi-region S3 via configuration_aliases
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── docker/                  # Lab: Docker provider — nginx container
│   │   ├── main.tf
│   │   └── outputs.tf
│   └── eks/                     # Lab: EKS cluster + Kubernetes nginx deployment
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── README.md
```

---

## Labs

### Lab 1 — Multi-Region Module with `configuration_aliases`

```bash
cd Day15/live/multi-region
terraform init
terraform apply
terraform destroy
```

### Lab 2 — Docker Provider

> Requires Docker daemon running locally.

```bash
cd Day15/live/docker
terraform init
terraform apply
# verify: curl http://localhost:8080
terraform destroy
```

### Lab 3 — EKS Cluster + Kubernetes Deployment

> ⚠️ Takes 10–15 minutes to provision. Will incur AWS charges. Destroy immediately after verification.

```bash
cd Day15/live/eks
terraform init
terraform apply
# verify: kubectl get pods -n default
terraform destroy
```

---

## Key Concepts

### Kubernetes provider authentication via `exec`

After EKS is provisioned, the Kubernetes provider uses the `exec` block to call `aws eks get-token`, which returns a short-lived bearer token. This avoids storing credentials in state and works with IAM roles and instance profiles automatically.

---
