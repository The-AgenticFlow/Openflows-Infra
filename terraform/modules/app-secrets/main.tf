# Application secrets in Secrets Manager, read in the cluster by External Secrets.
# Two secrets keep the cost low (about $0.40 each a month): one Terraform generates,
# one a person fills in. Generated values are write-only and never reach state.

ephemeral "random_password" "postgres" {
  length  = 32
  special = false
}

ephemeral "random_password" "chat_hook" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "generated" {
  name                    = "openflows/${var.environment}/generated"
  description             = "Generated OpenFlows secrets: Postgres password, Coder chat hook secret."
  recovery_window_in_days = var.recovery_window_in_days
}

resource "aws_secretsmanager_secret_version" "generated" {
  secret_id = aws_secretsmanager_secret.generated.id
  secret_string_wo = jsonencode({
    postgresPassword = ephemeral.random_password.postgres.result
    chatHookSecret   = ephemeral.random_password.chat_hook.result
  })
  # Bump to rotate: Terraform writes new values only when this changes.
  secret_string_wo_version = var.generated_version
}

# Filled in by a person (docs/RUNBOOK-aws.md, "Setting the provided secrets");
# Terraform never sees the values.
resource "aws_secretsmanager_secret" "provided" {
  name                    = "openflows/${var.environment}/provided"
  description             = "OpenFlows secrets set by hand: githubClientSecret, aiGatewayOpenaiKey."
  recovery_window_in_days = var.recovery_window_in_days
}
