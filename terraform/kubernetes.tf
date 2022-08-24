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

  backend "gcs" {
    bucket = "terraform-testing-jaf"
    prefix = "elm-terraform"
  }
}


data "terraform_remote_state" "gke" {
  backend = "gcs"

  config = {
    bucket = "terraform-testing-jaf"
    prefix = "gck"
  }
}

# Retrieve GKE cluster information
provider "google" {
  project =  data.terraform_remote_state.gke.outputs.project_id
  region  =  data.terraform_remote_state.gke.outputs.kubernetes_cluster_name
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
    name = "scalable-elm-example"
    labels = {
      App = "ScalableElmExample"
    }
  }

  spec {
    replicas = 2
    selector {
      match_labels = {
        App = "ScalableElmExample"
      }
    }
    template {
      metadata {
        labels = {
          App = "ScalableElmExample"
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