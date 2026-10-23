output "vpc_id" {
  description = "VPC ID."
  value       = module.network.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnets for EKS nodes and data services."
  value       = module.network.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnets for internet-facing load balancers."
  value       = module.network.public_subnet_ids
}

output "nat_public_ips" {
  description = "Egress IPs of the NAT gateways."
  value       = module.network.nat_public_ips
}

output "zone_id" {
  description = "Route 53 hosted zone ID."
  value       = one(module.dns[*].zone_id)
}

output "name_servers" {
  description = "Name servers the parent domain must delegate to."
  value       = one(module.dns[*].name_servers)
}

output "certificate_arn" {
  description = "Wildcard ACM certificate for the HTTPS ingress."
  value       = one(module.dns[*].certificate_arn)
}

output "eks_cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "aws_load_balancer_controller_role_arn" {
  description = "Pod Identity role for the Load Balancer Controller."
  value       = module.eks.aws_load_balancer_controller_role_arn
}
