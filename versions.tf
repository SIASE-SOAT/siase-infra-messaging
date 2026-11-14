terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Ajuste para o backend usado na Fase 3 (siase-infra-k8s / siase-infra-database).
  # backend "s3" {
  #   bucket = "siase-terraform-state"
  #   key    = "fase4/messaging/terraform.tfstate"
  #   region = "us-east-1"
  # }
}
