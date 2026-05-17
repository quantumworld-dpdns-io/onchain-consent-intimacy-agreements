terraform {
  required_providers {
    qdrant-cloud = {
      source  = "qdrant/qdrant-cloud"
      version = "~> 1.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

variable "qdrant_api_key" {
  type        = string
  description = "Qdrant Cloud API key"
  sensitive   = true
}

variable "region" {
  type        = string
  description = "Cloud provider region"
  default     = "us-east-1"
}

variable "cluster_name" {
  type        = string
  description = "Parent cluster name for resource naming"
}

locals {
  supported_regions = {
    "us-east-1" : "aws"
    "us-west-2" : "aws"
    "eu-west-1" : "aws"
    "eu-central-1" : "aws"
    "ap-southeast-1" : "aws"
    "ap-northeast-1" : "aws"
  }

  cloud_provider = lookup(local.supported_regions, var.region, "aws")

  cluster_config = {
    vector_size         = 384
    replication_factor  = 2
    shard_number        = 3
    on_disk_payload     = true
    hnsw_config = {
      m              = 16
      ef_construct   = 100
      full_scan_threshold = 10000
    }
    optimizers_config = {
      default_segment_number = 2
      memmap_threshold_kb    = 20000
      indexing_threshold     = 50000
    }
  }
}

resource "random_string" "cluster_suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "qdrant_cloud_cluster" "main" {
  name           = "${var.cluster_name}-qdrant-${random_string.cluster_suffix.result}"
  cloud_provider = local.cloud_provider
  region         = var.region

  configuration {
    vector_size        = local.cluster_config.vector_size
    replication_factor = local.cluster_config.replication_factor
    shard_number       = local.cluster_config.shard_number
    on_disk_payload    = local.cluster_config.on_disk_payload

    hnsw_config {
      m                    = local.cluster_config.hnsw_config.m
      ef_construct         = local.cluster_config.hnsw_config.ef_construct
      full_scan_threshold  = local.cluster_config.hnsw_config.full_scan_threshold
    }

    optimizers_config {
      default_segment_number = local.cluster_config.optimizers_config.default_segment_number
      memmap_threshold_kb    = local.cluster_config.optimizers_config.memmap_threshold_kb
      indexing_threshold     = local.cluster_config.optimizers_config.indexing_threshold
    }
  }
}

resource "qdrant_cloud_api_key" "cluster_key" {
  cluster_id = qdrant_cloud_cluster.main.id
  name       = "${var.cluster_name}-api-key"
}

resource "qdrant_cloud_collection" "consent" {
  cluster_id = qdrant_cloud_cluster.main.id
  name       = "consent_agreements"

  configuration {
    vector_size        = local.cluster_config.vector_size
    replication_factor = local.cluster_config.replication_factor
    shard_number       = local.cluster_config.shard_number
    on_disk_payload    = local.cluster_config.on_disk_payload

    hnsw_config {
      m                    = local.cluster_config.hnsw_config.m
      ef_construct         = local.cluster_config.hnsw_config.ef_construct
      full_scan_threshold  = local.cluster_config.hnsw_config.full_scan_threshold
    }

    optimizers_config {
      default_segment_number = local.cluster_config.optimizers_config.default_segment_number
      memmap_threshold_kb    = local.cluster_config.optimizers_config.memmap_threshold_kb
      indexing_threshold     = local.cluster_config.optimizers_config.indexing_threshold
    }
  }
}

resource "null_resource" "collection_payload_schema" {
  depends_on = [qdrant_cloud_collection.consent]

  provisioner "local-exec" {
    command = <<-EOT
      curl -s -X PUT "https://${qdrant_cloud_cluster.main.url}/collections/consent_agreements/index" \
        -H "api-key: ${qdrant_cloud_api_key.cluster_key.key}" \
        -H "Content-Type: application/json" \
        -d '{
          "field_name": "consent_id",
          "field_type": "keyword"
        }'

      curl -s -X PUT "https://${qdrant_cloud_cluster.main.url}/collections/consent_agreements/index" \
        -H "api-key: ${qdrant_cloud_api_key.cluster_key.key}" \
        -H "Content-Type: application/json" \
        -d '{
          "field_name": "chain",
          "field_type": "keyword"
        }'

      curl -s -X PUT "https://${qdrant_cloud_cluster.main.url}/collections/consent_agreements/index" \
        -H "api-key: ${qdrant_cloud_api_key.cluster_key.key}" \
        -H "Content-Type: application/json" \
        -d '{
          "field_name": "party_address",
          "field_type": "keyword"
        }'

      curl -s -X PUT "https://${qdrant_cloud_cluster.main.url}/collections/consent_agreements/index" \
        -H "api-key: ${qdrant_cloud_api_key.cluster_key.key}" \
        -H "Content-Type: application/json" \
        -d '{
          "field_name": "status",
          "field_type": "keyword"
        }'
    EOT
  }
}

output "cluster_url" {
  value       = qdrant_cloud_cluster.main.url
  description = "Qdrant Cloud cluster URL"
}

output "api_key" {
  value       = qdrant_cloud_api_key.cluster_key.key
  description = "Qdrant Cloud API key"
  sensitive   = true
}

output "collection_name" {
  value       = qdrant_cloud_collection.consent.name
  description = "Qdrant collection name"
}
