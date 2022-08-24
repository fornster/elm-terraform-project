variable "bucket" {
  default     = ""
  description = "gcs bucket used to store terraform state"
}

variable "gckStatePrefix" {
  default     = ""
  description = "prefix of terraform gck state is. needed if using remote state to get variables"
}

variable "thisStatePrefix" {
  default     = ""
  description = "prefix for where to store this files terraform state"
}

variable "applicationName" {
  default     = ""
  description = "name of the application being managed"
}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "3.52.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.1"
    }
  }
  #tells terraform where to store the state file
  #if commented out will default to local
  backend "gcs" {
    bucket = var.bucket
    prefix = var.thisStatePrefix
  }
}

#Use remote state from gke deployment to get things like project_id and cluster name.
#not necessary but speeds things up and makes it more modular
data "terraform_remote_state" "gke" {
  backend = "gcs"

  config = {
    bucket = var.bucket
    prefix = var.gckStatePrefix
  }
}

# Retrieve GKE cluster information
provider "google" {
  project = data.terraform_remote_state.gke.outputs.project_id
  region  = data.terraform_remote_state.gke.outputs.kubernetes_cluster_name
}

data "google_client_config" "default" {}

data "google_container_cluster" "my_cluster" {
  name     = data.terraform_remote_state.gke.outputs.kubernetes_cluster_name
  location = data.terraform_remote_state.gke.outputs.region
}


provider "kubernetes" {
  host = data.terraform_remote_state.gke.outputs.kubernetes_cluster_host

  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.my_cluster.master_auth[0].cluster_ca_certificate)
}

resource "kubernetes_deployment" "elm" {
  metadata {
    name   = "scalable-elm-example"
    labels = {
      App = var.applicationName
    }
  }

  spec {
    replicas = 2
    selector {
      match_labels = {
        App = var.applicationName
      }
    }
    template {
      metadata {
        labels = {
          App = var.applicationName
        }
      }
      spec {
        container {
          image = "us-central1-docker.pkg.dev/spartan-vertex-360314/testing/elm-nginx-image:0.0.2"
          name  = "example"

          port {
            container_port = 80
          }

          resources {
            limits = {
              cpu    = "0.5"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "50Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "elm" {
  metadata {
    name = "elm-example"
  }
  spec {
    selector = {
      App = kubernetes_deployment.elm.spec.0.template.0.metadata[0].labels.App
    }
    port {
      port        = 80
      target_port = 80
    }

    type = "LoadBalancer"
  }
}

output "lb_ip" {
  value = kubernetes_service.elm.status.0.load_balancer.0.ingress.0.ip
}