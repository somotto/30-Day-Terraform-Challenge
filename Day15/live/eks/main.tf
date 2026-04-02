terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.region
}

provider "kubernetes" {
  host                   = module.eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name", module.eks_cluster.cluster_name,
      "--region", var.region,
    ]
  }
}

module "eks_cluster" {
  source = "../../modules/eks-cluster"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  availability_zones   = ["${var.region}a", "${var.region}b"]
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24"]

  node_min_size       = 1
  node_max_size       = 3
  node_desired_size   = 2
  node_instance_types = ["t3.small"]

  tags = {
    Environment = "dev"
    Challenge   = "30DayTerraform"
    Day         = "15"
  }
}

resource "kubernetes_deployment" "nginx" {
  # Explicit dependency ensures the cluster is fully provisioned before
  # Terraform attempts to connect to the Kubernetes API.
  depends_on = [module.eks_cluster]

  metadata {
    name      = "nginx-deployment"
    namespace = "default"
    labels = {
      app       = "nginx"
      challenge = "30DayTerraform"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "nginx"
      }
    }

    template {
      metadata {
        labels = {
          app = "nginx"
        }
      }

      spec {
        container {
          name  = "nginx"
          image = "nginx:latest"

          port {
            container_port = 80
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "nginx" {
  depends_on = [module.eks_cluster]

  metadata {
    name      = "nginx-service"
    namespace = "default"
  }

  spec {
    selector = {
      app = "nginx"
    }

    port {
      port        = 80
      target_port = 80
    }

    type = "ClusterIP"
  }
}
