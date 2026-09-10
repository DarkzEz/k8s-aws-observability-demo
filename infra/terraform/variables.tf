variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Prefix for all resource names."
  type        = string
  default     = "status-api"
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "cluster_version" {
  description = "Kubernetes version of the EKS control plane."
  type        = string
  default     = "1.33"
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2

  validation {
    condition     = var.node_desired_size >= 1 && var.node_desired_size <= 3
    error_message = "node_desired_size must be between 1 and 3 for this demo."
  }
}

variable "github_repository" {
  description = "GitHub repository allowed to deploy via OIDC, in the form owner/name."
  type        = string
}
