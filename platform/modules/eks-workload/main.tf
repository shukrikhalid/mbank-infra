# Task 10 — EKS Workload Terraform module
# Provisions namespace-level resources: IRSA, service account, network policies, HPA

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

locals {
  tags = merge(
    var.tags,
    {
      Application = var.app_name
      Environment = var.environment
      Team        = var.team
      CostCentre  = var.cost_centre
      Module      = "eks-workload"
    }
  )
}

# Data source for EKS cluster
data "aws_eks_cluster" "cluster" {
  name = var.eks_cluster_name
}

# Data source for EKS cluster auth token
data "aws_eks_cluster_auth" "cluster" {
  name = var.eks_cluster_name
}

# Configure Kubernetes provider
provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# Get EKS OIDC provider thumbprint
data "tls_certificate" "cluster" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

# Data source for OIDC provider
data "aws_iam_openid_connect_provider" "oidc" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

# IAM Role for IRSA (IAM Roles for Service Accounts)
resource "aws_iam_role" "irsa_role" {
  name = "${var.app_name}-irsa-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.oidc.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
            "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.tags
}

# Attach IAM policies to IRSA role
resource "aws_iam_role_policy_attachment" "irsa_policies" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.irsa_role.name
  policy_arn = each.value
}

# Kubernetes Namespace
resource "kubernetes_namespace" "workload" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"       = var.app_name
      "app.kubernetes.io/environment" = var.environment
      "managed-by"                    = "terraform"
    }
  }
}

# Resource Quota for the namespace
resource "kubernetes_resource_quota" "workload" {
  metadata {
    name      = "${var.app_name}-quota"
    namespace = kubernetes_namespace.workload.metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = "${var.hpa_max_replicas * 1}"  # max pods × 1 CPU
      "requests.memory" = "${var.hpa_max_replicas * 1}Gi"
      "limits.cpu"      = "${var.hpa_max_replicas * 2}"  # burst capacity
      "limits.memory"   = "${var.hpa_max_replicas * 2}Gi"
    }
  }
}

# Limit Range for the namespace
resource "kubernetes_limit_range" "workload" {
  metadata {
    name      = "${var.app_name}-limits"
    namespace = kubernetes_namespace.workload.metadata[0].name
  }

  spec {
    limit {
      type = "Pod"
      max = {
        cpu    = var.resource_limits_cpu
        memory = var.resource_limits_memory
      }
      min = {
        cpu    = "100m"
        memory = "128Mi"
      }
    }
    limit {
      type = "Container"
      max = {
        cpu    = var.resource_limits_cpu
        memory = var.resource_limits_memory
      }
      min = {
        cpu    = "100m"
        memory = "128Mi"
      }
      default = {
        cpu    = var.resource_limits_cpu
        memory = var.resource_limits_memory
      }
      default_request = {
        cpu    = "100m"
        memory = "128Mi"
      }
    }
  }
}

# Kubernetes Service Account
resource "kubernetes_service_account" "workload" {
  metadata {
    name      = var.service_account_name
    namespace = kubernetes_namespace.workload.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.irsa_role.arn
    }
  }
}

# Network Policy — Deny all ingress by default
resource "kubernetes_network_policy" "default_deny" {
  metadata {
    name      = "${var.app_name}-default-deny"
    namespace = kubernetes_namespace.workload.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }
}

# Network Policy — Allow ingress from same namespace
resource "kubernetes_network_policy" "allow_same_namespace" {
  metadata {
    name      = "${var.app_name}-allow-same-ns"
    namespace = kubernetes_namespace.workload.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]
    ingress {
      from {
        pod_selector {}
      }
    }
  }
}

# Network Policy — Allow ingress from kube-system (metrics, logging)
resource "kubernetes_network_policy" "allow_kube_system" {
  metadata {
    name      = "${var.app_name}-allow-kube-system"
    namespace = kubernetes_namespace.workload.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "name" = "kube-system"
          }
        }
      }
    }
  }
}

# Horizontal Pod Autoscaler (HPA v2)
resource "kubernetes_manifest" "hpa" {
  manifest = {
    apiVersion = "autoscaling/v2"
    kind       = "HorizontalPodAutoscaler"
    metadata = {
      name      = "${var.app_name}-hpa"
      namespace = kubernetes_namespace.workload.metadata[0].name
      labels = {
        "app.kubernetes.io/name"       = var.app_name
        "app.kubernetes.io/environment" = var.environment
        "managed-by"                    = "terraform"
      }
    }
    spec = {
      scaleTargetRef = {
        apiVersion = "apps/v1"
        kind       = "Deployment"
        name       = var.app_name
      }
      minReplicas = var.hpa_min_replicas
      maxReplicas = var.hpa_max_replicas
      metrics = [
        {
          type = "Resource"
          resource = {
            name   = "cpu"
            target = {
              type               = "Utilization"
              averageUtilization = var.hpa_cpu_target
            }
          }
        },
        {
          type = "Resource"
          resource = {
            name   = "memory"
            target = {
              type               = "Utilization"
              averageUtilization = 75
            }
          }
        }
      ]
      behavior = {
        scaleDown = {
          stabilizationWindowSeconds = 300
          policies = [
            {
              type                = "PercentChangePercentage"
              value               = 50
              periodSeconds       = 60
            }
          ]
        }
        scaleUp = {
          stabilizationWindowSeconds = 0
          policies = [
            {
              type          = "Percent"
              value         = 100
              periodSeconds = 30
            },
            {
              type          = "Pods"
              value         = 4
              periodSeconds = 60
            }
          ]
          selectPolicy = "Max"
        }
      }
    }
  }
}

# SSM Parameter — Export IRSA role ARN
resource "aws_ssm_parameter" "irsa_role_arn" {
  name        = "/eks/${var.eks_cluster_name}/${var.app_name}/irsa-role-arn"
  description = "IRSA role ARN for ${var.app_name} in namespace ${var.namespace}"
  type        = "String"
  value       = aws_iam_role.irsa_role.arn

  tags = local.tags
}

# SSM Parameter — Export namespace
resource "aws_ssm_parameter" "namespace" {
  name        = "/eks/${var.eks_cluster_name}/${var.app_name}/namespace"
  description = "Kubernetes namespace for ${var.app_name}"
  type        = "String"
  value       = var.namespace

  tags = local.tags
}

# SSM Parameter — Export service account name
resource "aws_ssm_parameter" "service_account_name" {
  name        = "/eks/${var.eks_cluster_name}/${var.app_name}/service-account-name"
  description = "Kubernetes service account name for ${var.app_name}"
  type        = "String"
  value       = var.service_account_name

  tags = local.tags
}
