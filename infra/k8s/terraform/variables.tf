variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (development, staging, production)"
  type        = string
  default     = "development"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 3
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 10
}

variable "node_instance_types" {
  description = "EC2 instance types for node group"
  type        = list(string)
  default     = ["m5.xlarge", "m5a.xlarge"]
}

variable "image_tag" {
  description = "Container image tag to deploy"
  type        = string
  default     = "latest"
}

variable "api_hostname" {
  description = "Hostname for the API ingress"
  type        = string
  default     = "api.consent-agreements.local"
}

variable "api_replicas" {
  description = "Number of Go API replicas"
  type        = number
  default     = 3
}

variable "zk_replicas" {
  description = "Number of Rust ZK service replicas"
  type        = number
  default     = 2
}

variable "qdrant_mode" {
  description = "Qdrant deployment mode: self-hosted or cloud"
  type        = string
  default     = "self-hosted"
}

variable "qdrant_api_key" {
  description = "Qdrant Cloud API key (required when qdrant_mode=cloud)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "qdrant_cloud_url" {
  description = "Qdrant Cloud cluster URL"
  type        = string
  default     = ""
}

variable "qdrant_replicas" {
  description = "Number of Qdrant replicas (self-hosted mode)"
  type        = number
  default     = 3
}

variable "qdrant_storage_size" {
  description = "Qdrant persistent storage size"
  type        = string
  default     = "100Gi"
}

variable "postgres_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
}

variable "redis_password" {
  description = "Redis password"
  type        = string
  sensitive   = true
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
}

variable "prometheus_storage_size" {
  description = "Prometheus persistent storage size"
  type        = string
  default     = "50Gi"
}

variable "grafana_storage_size" {
  description = "Grafana persistent storage size"
  type        = string
  default     = "10Gi"
}

variable "anvil_rpc_endpoint" {
  description = "Anvil RPC endpoint for event indexer"
  type        = string
  default     = "http://anvil:8545"
}
