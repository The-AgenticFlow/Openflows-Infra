locals {
  # Created by terraform/bootstrap; every OpenFlows role must carry it.
  permissions_boundary_arn = "arn:aws:iam::${var.aws_account_id}:policy/openflows/openflows-permissions-boundary"

  environment = "staging"
}

module "network" {
  source = "../../modules/network"

  environment        = local.environment
  vpc_cidr           = var.vpc_cidr
  single_nat_gateway = var.single_nat_gateway

  iam_path                 = "/openflows/${local.environment}/"
  permissions_boundary_arn = local.permissions_boundary_arn
}

# Only once the environment's domain is decided; until then the network stands alone.
module "dns" {
  source = "../../modules/dns"
  count  = var.zone_name == "" ? 0 : 1

  environment                     = local.environment
  zone_name                       = var.zone_name
  wait_for_certificate_validation = var.wait_for_certificate_validation
}

module "eks" {
  source = "../../modules/eks"

  environment        = local.environment
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.network.vpc_id

  control_plane_subnet_ids = module.network.private_subnet_ids
  node_subnet_ids          = slice(module.network.private_subnet_ids, 0, var.node_az_count)

  iam_path                 = "/openflows/${local.environment}/"
  permissions_boundary_arn = local.permissions_boundary_arn
  tags                     = { Project = "openflows", Environment = local.environment }

  admin_role_arns  = ["arn:aws:iam::${var.aws_account_id}:role/openflows/openflows-platform-admin"]
  viewer_role_arns = ["arn:aws:iam::${var.aws_account_id}:role/openflows/openflows-readonly"]

  node_instance_types      = var.node_instance_types
  node_ami_release_version = var.node_ami_release_version
  node_capacity_type       = var.node_capacity_type
  node_min_size            = var.node_min_size
  node_desired_size        = var.node_desired_size
  node_max_size            = var.node_max_size

  log_retention_days = var.eks_log_retention_days

  zone_id   = one(module.dns[*].zone_id) == null ? "" : one(module.dns[*].zone_id)
  zone_name = var.zone_name
}
