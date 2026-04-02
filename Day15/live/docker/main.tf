terraform {
  required_version = ">= 1.0.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {}

resource "docker_image" "nginx" {
  name         = "nginx:latest"
  keep_locally = false
}

resource "docker_container" "nginx" {
  image = docker_image.nginx.image_id
  name  = "terraform-nginx"

  must_run = true
  restart  = "unless-stopped"

  ports {
    internal = 80
    external = 8080
  }

  labels {
    label = "managed-by"
    value = "terraform"
  }

  labels {
    label = "challenge"
    value = "30DayTerraform-Day15"
  }
}
