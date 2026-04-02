output "container_id" {
  description = "Docker container ID"
  value       = docker_container.nginx.id
}

output "container_name" {
  description = "Docker container name"
  value       = docker_container.nginx.name
}

output "container_url" {
  description = "URL to reach the nginx container"
  value       = "http://localhost:8080"
}

output "image_id" {
  description = "Pulled nginx image ID"
  value       = docker_image.nginx.image_id
}
