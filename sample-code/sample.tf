# ==============================================================================
# Solarized Dark Terraform / HCL Syntax Highlighting Showcase
# Demonstrates providers, variables, validation, locals, resources, and outputs.
# ==============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.25"
    }
  }
}

variable "environment" {
  type        = string
  default     = "production"
  description = "Target deployment tier"

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be either 'staging' or 'production'."
  }
}

variable "cluster_size" {
  type        = number
  default     = 3
  description = "Number of worker nodes to provision"
}

locals {
  is_production = var.environment == "production"
  vpc_cidr      = local.is_production ? "10.100.0.0/16" : "10.200.0.0/16"

  standard_tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Workspace   = terraform.workspace
  }

  subnet_mapping = {
    for idx in range(var.cluster_size) :
    "subnet-${idx}" => cidrsubnet(local.vpc_cidr, 8, idx + 1)
  }
}

resource "aws_s3_bucket" "telemetry_lake" {
  bucket        = "company-${var.environment}-telemetry-lake"
  force_destroy = !local.is_production

  tags = merge(local.standard_tags, {
    Name        = "TelemetryStorage"
    CostCenter  = 4200
  })

  lifecycle {
    prevent_destroy = false
  }
}

output "bucket_arn" {
  value       = aws_s3_bucket.telemetry_lake.arn
  description = "Amazon Resource Name for the provisioned data bucket"
}

output "subnet_cidr_blocks" {
  value       = local.subnet_mapping
  description = "Generated subnet CIDR allocations"
}
