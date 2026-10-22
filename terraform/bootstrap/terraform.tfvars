# Shared organization member account that hosts OpenFlows alongside other projects.
aws_account_id = "686255958454"

# The bootstrap operator. It assumes the admin and read-only roles with MFA and
# keeps break-glass access to the state buckets.
human_principal_arns             = ["arn:aws:iam::686255958454:user/openflows-user"]
state_break_glass_principal_arns = ["arn:aws:iam::686255958454:user/openflows-user"]
