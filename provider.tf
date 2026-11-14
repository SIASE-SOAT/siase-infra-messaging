provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "siase"
      Phase       = "fase4"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
