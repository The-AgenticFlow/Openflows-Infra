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

# The Manager's database password. Its own secret: a new key in "generated" would need a version
# bump that rewrites, and so rotates, the Coder database password too.
ephemeral "random_password" "manager_postgres" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "manager_db" {
  name                    = "openflows/${var.environment}/manager-db"
  description             = "Password of the OpenFlows Manager's PostgreSQL role."
  recovery_window_in_days = var.recovery_window_in_days
}

resource "aws_secretsmanager_secret_version" "manager_db" {
  secret_id                = aws_secretsmanager_secret.manager_db.id
  secret_string_wo         = jsonencode({ password = ephemeral.random_password.manager_postgres.result })
  secret_string_wo_version = var.manager_db_version
}

# Filled in by a person (docs/RUNBOOK-aws.md, "Setting the provided secrets");
# Terraform never sees the values.
resource "aws_secretsmanager_secret" "provided" {
  name                    = "openflows/${var.environment}/provided"
  description             = "OpenFlows secrets set by hand: githubClientSecret."
  recovery_window_in_days = var.recovery_window_in_days
}
