output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR."
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "Private subnets for EKS nodes and data services."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnets for internet-facing load balancers and NAT gateways."
  value       = module.vpc.public_subnets
}

output "azs" {
  description = "Availability zones the subnets span."
  value       = local.azs
}

output "nat_public_ips" {
  description = "Egress IPs of the NAT gateways, for allow-lists on external services."
  value       = var.nat_mode == "gateway" ? module.vpc.nat_public_ips : aws_eip.nat[*].public_ip
}
