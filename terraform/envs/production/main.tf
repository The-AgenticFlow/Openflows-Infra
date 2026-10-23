locals {
  # Created by terraform/bootstrap; every OpenFlows role must carry it.
  permissions_boundary_arn = "arn:aws:iam::${var.aws_account_id}:policy/openflows/openflows-permissions-boundary"

  environment = "production"
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
