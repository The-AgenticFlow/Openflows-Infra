output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Private Kubernetes API endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_admin_security_group_id" {
  description = "Security group a CloudShell VPC environment uses to reach the private API."
  value       = aws_security_group.cluster_admin.id
}

output "admin_tunnel_instance_id" {
  description = "SSM-managed instance that forwards a local port to the private API."
  value       = aws_instance.admin_tunnel.id
}

output "node_security_group_id" {
  description = "Security group on every node; the Load Balancer Controller adds its rules here."
  value       = module.eks.node_security_group_id
}

output "aws_load_balancer_controller_role_arn" {
  description = "Pod Identity role bound to kube-system/aws-load-balancer-controller."
  value       = aws_iam_role.pod["aws-load-balancer-controller"].arn
}

output "workload_role_arns" {
  description = "Workload role ARNs by key."
  value       = { for k, r in aws_iam_role.workload : k => r.arn }
}
