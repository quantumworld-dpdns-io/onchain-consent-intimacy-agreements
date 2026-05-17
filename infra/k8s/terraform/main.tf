terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "ConsentAgreements"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
    }
  }
}

locals {
  cluster_name = "consent-agreements-${var.environment}"
  qdrant_mode  = var.qdrant_mode
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway   = true
  single_nat_gateway   = var.environment != "production"
  enable_dns_hostnames = true
  enable_dns_support   = true

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = local.cluster_name
  cluster_version = "1.28"

  cluster_endpoint_public_access = var.environment != "production"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    general = {
      desired_size = var.node_desired_size
      min_size     = var.node_min_size
      max_size     = var.node_max_size

      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 100
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      tags = {
        "k8s.io/cluster-autoscaler/enabled"             = "true"
        "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
      }
    }

    spot = {
      desired_size = 0
      min_size     = 0
      max_size     = 10

      instance_types = ["c5a.large", "c5.large", "m5.large"]
      capacity_type  = "SPOT"

      tags = {
        "k8s.io/cluster-autoscaler/enabled"             = "true"
        "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
      }
    }
  }

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    ingress_cluster_all = {
      description = "Cluster to node all ports"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      source_cluster_security_group = true
    }
    egress_all = {
      description = "Node all egress"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }
}

module "qdrant_cloud" {
  source = "./modules/qdrant-cloud"
  count  = local.qdrant_mode == "cloud" ? 1 : 0

  qdrant_api_key = var.qdrant_api_key
  region         = var.aws_region
  cluster_name   = local.cluster_name
}

resource "kubernetes_namespace" "consent" {
  metadata {
    name = "consent-agreements"
    labels = {
      name        = "consent-agreements"
      environment = var.environment
    }
  }
}

resource "helm_release" "qdrant" {
  count = local.qdrant_mode == "self-hosted" ? 1 : 0

  name       = "qdrant"
  repository = "https://qdrant.github.io/qdrant-helm"
  chart      = "qdrant"
  namespace  = kubernetes_namespace.consent.metadata[0].name
  version    = "0.1.0"

  values = [
    file("${path.module}/../helm/qdrant/values.yaml")
  ]

  set {
    name  = "replicaCount"
    value = var.qdrant_replicas
  }

  set {
    name  = "persistence.size"
    value = var.qdrant_storage_size
  }
}

resource "helm_release" "redis" {
  name       = "redis"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "redis"
  namespace  = kubernetes_namespace.consent.metadata[0].name
  version    = "18.0"

  values = [
    file("${path.module}/../helm/redis/values.yaml")
  ]

  set {
    name  = "architecture"
    value = "replication"
  }

  set {
    name  = "auth.enabled"
    value = true
  }
}

resource "helm_release" "postgres" {
  name       = "postgres"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "postgresql"
  namespace  = kubernetes_namespace.consent.metadata[0].name
  version    = "13.0"

  values = [
    file("${path.module}/../helm/postgres/values.yaml")
  ]

  set {
    name  = "auth.database"
    value = "consent_db"
  }

  set {
    name  = "auth.username"
    value = "consent"
  }

  set {
    name  = "auth.password"
    value = var.postgres_password
  }
}

resource "helm_release" "go_api" {
  name       = "go-api"
  chart      = "${path.module}/../helm/go-api"
  namespace  = kubernetes_namespace.consent.metadata[0].name

  values = [
    file("${path.module}/../helm/go-api/values.yaml")
  ]

  set {
    name  = "image.tag"
    value = var.image_tag
  }

  set {
    name  = "replicaCount"
    value = var.api_replicas
  }

  set {
    name  = "config.qdrantUrl"
    value = local.qdrant_mode == "cloud" ? var.qdrant_cloud_url : "http://qdrant:6333"
  }

  set {
    name  = "config.redisUrl"
    value = "redis://:${var.redis_password}@redis-master:6379"
  }

  set {
    name  = "config.databaseUrl"
    value = "postgres://consent:${var.postgres_password}@postgres:5432/consent_db?sslmode=disable"
  }

  set {
    name  = "ingress.host"
    value = var.api_hostname
  }
}

resource "helm_release" "rust_zk" {
  name       = "rust-zk-service"
  chart      = "${path.module}/../helm/rust-zk"
  namespace  = kubernetes_namespace.consent.metadata[0].name

  values = [
    file("${path.module}/../helm/rust-zk/values.yaml")
  ]

  set {
    name  = "image.tag"
    value = var.image_tag
  }

  set {
    name  = "replicaCount"
    value = var.zk_replicas
  }
}

resource "helm_release" "event_indexer" {
  name       = "event-indexer"
  chart      = "${path.module}/../helm/event-indexer"
  namespace  = kubernetes_namespace.consent.metadata[0].name

  values = [
    file("${path.module}/../helm/event-indexer/values.yaml")
  ]

  set {
    name  = "image.tag"
    value = var.image_tag
  }

  set {
    name  = "config.anvilRpc"
    value = var.anvil_rpc_endpoint
  }
}

resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"
  namespace  = "monitoring"
  version    = "25.0"

  create_namespace = true

  set {
    name  = "server.persistentVolume.size"
    value = var.prometheus_storage_size
  }
}

resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  namespace  = "monitoring"
  version    = "7.0"

  create_namespace = false

  set {
    name  = "adminPassword"
    value = var.grafana_admin_password
  }

  set {
    name  = "persistence.size"
    value = var.grafana_storage_size
  }
}

resource "random_password" "postgres" {
  length  = 24
  special = false
}

resource "random_password" "redis" {
  length  = 24
  special = false
}

resource "random_password" "grafana" {
  length  = 24
  special = false
}

resource "aws_iam_role" "eks" {
  name = "${local.cluster_name}-eks-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks.name
}

resource "aws_iam_role_policy_attachment" "eks_service_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks.name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_security_group_id" {
  description = "Security group ID for the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "region" {
  description = "AWS region"
  value       = var.aws_region
}

output "api_hostname" {
  description = "API ingress hostname"
  value       = var.api_hostname
}
