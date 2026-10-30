output "secret_arn_pattern" {
  description = "ARN pattern covering this environment's application secrets, for the External Secrets role."
  value       = "${replace(aws_secretsmanager_secret.generated.arn, "/:secret:.*/", "")}:secret:openflows/${var.environment}/*"
}

output "generated_secret_name" {
  description = "Name of the generated secret."
  value       = aws_secretsmanager_secret.generated.name
}

output "provided_secret_name" {
  description = "Name of the secret a person fills in."
  value       = aws_secretsmanager_secret.provided.name
}

output "manager_db_secret_name" {
  description = "Name of the secret holding the Manager's database password."
  value       = aws_secretsmanager_secret.manager_db.name
}

output "manager_policy_json" {
  description = "IAM policy for the Manager's pod role: only secrets named openflows/<environment>/manager/."
  value = templatefile("${path.module}/policies/manager.json.tftpl", {
    manager_secret_arn = "${replace(aws_secretsmanager_secret.generated.arn, "/:secret:.*/", "")}:secret:openflows/${var.environment}/manager/*"
  })
}
