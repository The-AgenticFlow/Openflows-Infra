output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Private Kubernetes API endpoint."
  value       = module.eks.cluster_endpoint
}

output "node_security_group_id" {
  description = "Security group on every node; the Load Balancer Controller adds its rules here."
  value       = module.eks.node_security_group_id
}

output "aws_load_balancer_controller_role_arn" {
  description = "Pod Identity role bound to kube-system/aws-load-balancer-controller."
  value       = aws_iam_role.pod["aws-load-balancer-controller"].arn
}
