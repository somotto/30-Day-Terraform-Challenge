output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks_cluster.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks_cluster.cluster_endpoint
}

output "configure_kubectl" {
  description = "Run this command to configure kubectl for the cluster"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks_cluster.cluster_name}"
}

output "nginx_deployment_name" {
  description = "Name of the nginx Kubernetes deployment"
  value       = kubernetes_deployment.nginx.metadata[0].name
}

output "nginx_service_name" {
  description = "Name of the nginx Kubernetes service"
  value       = kubernetes_service.nginx.metadata[0].name
}
