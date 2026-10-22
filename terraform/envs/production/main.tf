locals {
  environment = "production"
}

module "network" {
  source = "../../modules/network"

  environment        = local.environment
  vpc_cidr           = var.vpc_cidr
  single_nat_gateway = var.single_nat_gateway
}

module "dns" {
  source = "../../modules/dns"

  environment                     = local.environment
  zone_name                       = var.zone_name
  wait_for_certificate_validation = var.wait_for_certificate_validation
}
