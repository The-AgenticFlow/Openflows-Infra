# Private EKS cluster for one environment: a managed x86 node group, add-ons
# through the EKS API, and Pod Identity roles for the add-ons that call AWS.

locals {
  name = "openflows-${var.environment}"

  # Pinned to each add-on's default version for this Kubernetes version:
  # aws eks describe-addon-versions --kubernetes-version <v> --addon-name <name>
  addon_versions = {
    vpc-cni                = "v1.22.4-eksbuild.3"
    coredns                = "v1.14.7-eksbuild.11"
    kube-proxy             = "v1.37.0-eksbuild.22"
    eks-pod-identity-agent = "v1.3.10-eksbuild.3"
    aws-ebs-csi-driver     = "v1.67.1-eksbuild.1"
    metrics-server         = "v0.9.0-eksbuild.13"
    external-dns           = "v0.23.0-eksbuild.2"
  }

  external_dns = var.zone_id != ""
}

# AWS-0039: EKS envelope-encrypts all API data by default (AWS-owned key, 1.28+).
# AWS-0104: nodes need egress through NAT for images and AWS APIs.
#trivy:ignore:AWS-0039
#trivy:ignore:AWS-0104
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.29.0"

  name               = local.name
  kubernetes_version = var.kubernetes_version
  vpc_id             = var.vpc_id
  subnet_ids         = var.control_plane_subnet_ids

  # Private only: Terraform uses EKS APIs, people use CloudShell's VPC environment.
  endpoint_public_access  = false
  endpoint_private_access = true

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = false
  access_entries = merge(
    { for i, arn in var.admin_role_arns : "admin-${i}" => {
      principal_arn = arn
      policy_associations = { admin = {
        policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
        access_scope = { type = "cluster" }
      } }
    } },
    { for i, arn in var.viewer_role_arns : "viewer-${i}" => {
      principal_arn = arn
      policy_associations = { view = {
        policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
        access_scope = { type = "cluster" }
      } }
    } },
  )

  # STANDARD stops a silent move to extended support pricing; upgrades are planned.
  upgrade_policy = { support_type = "STANDARD" }

  # EKS envelope-encrypts all API data with an AWS-owned key on 1.28+.
  create_kms_key    = false
  encryption_config = null

  # Pod Identity replaces IRSA, so no OIDC provider.
  enable_irsa = false

  # The EKS-created primary security group is untagged; the boundary forbids re-tagging it.
  create_primary_security_group_tags = false

  iam_role_path                 = var.iam_path
  iam_role_permissions_boundary = var.permissions_boundary_arn

  enabled_log_types                      = var.control_plane_log_types
  cloudwatch_log_group_retention_in_days = var.log_retention_days

  addons = merge(
    {
      vpc-cni = {
        addon_version  = local.addon_versions["vpc-cni"]
        most_recent    = false
        before_compute = true
        # Tags the ENIs it creates in the create call, so the boundary allows attaching them.
        configuration_values = jsonencode({ env = { ADDITIONAL_ENI_TAGS = jsonencode(var.tags) } })
      }
      eks-pod-identity-agent = {
        addon_version  = local.addon_versions["eks-pod-identity-agent"]
        most_recent    = false
        before_compute = true
      }
      kube-proxy = {
        addon_version = local.addon_versions["kube-proxy"]
        most_recent   = false
      }
      coredns = {
        addon_version = local.addon_versions["coredns"]
        most_recent   = false
      }
      aws-ebs-csi-driver = {
        addon_version = local.addon_versions["aws-ebs-csi-driver"]
        most_recent   = false
        configuration_values = jsonencode({
          controller          = { extraVolumeTags = var.tags }
          defaultStorageClass = { enabled = true }
        })
        pod_identity_association = [{ role_arn = aws_iam_role.pod["ebs-csi"].arn, service_account = "ebs-csi-controller-sa" }]
      }
      metrics-server = {
        addon_version = local.addon_versions["metrics-server"]
        most_recent   = false
      }
    },
    local.external_dns ? {
      external-dns = {
        addon_version = local.addon_versions["external-dns"]
        most_recent   = false
        configuration_values = jsonencode({
          domainFilters = [var.zone_name]
          txtOwnerId    = local.name
          policy        = "sync"
        })
        pod_identity_association = [{ role_arn = aws_iam_role.pod["external-dns"].arn, service_account = "external-dns" }]
      }
    } : {},
  )

  eks_managed_node_groups = {
    default = {
      name                     = "${local.name}-node"
      iam_role_name            = "${local.name}-node"
      iam_role_use_name_prefix = false
      ami_type                 = "AL2023_x86_64_STANDARD"
      instance_types           = var.node_instance_types
      capacity_type            = var.node_capacity_type
      subnet_ids               = var.node_subnet_ids

      min_size     = var.node_min_size
      desired_size = var.node_desired_size
      max_size     = var.node_max_size

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = var.node_disk_size_gb
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      iam_role_path                 = var.iam_path
      iam_role_permissions_boundary = var.permissions_boundary_arn
    }
  }

  # Default tags do not reach launch template tag specifications; these do.
  tags = var.tags
}
