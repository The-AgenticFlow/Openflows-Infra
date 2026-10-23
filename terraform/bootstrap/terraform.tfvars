# Shared organization member account that hosts OpenFlows alongside other projects.
aws_account_id = "686255958454"

# The bootstrap operator. It assumes the admin and read-only roles with MFA and
# keeps break-glass access to the state buckets.
human_principal_arns             = ["arn:aws:iam::686255958454:user/openflows-user"]
state_break_glass_principal_arns = ["arn:aws:iam::686255958454:user/openflows-user"]

# From `gh api repos/The-AgenticFlow/Openflows-Infra/actions/oidc/customization/sub`:
# the repository issues immutable subjects that carry the owner and repository IDs.
github_oidc_subject_prefix = "repo:The-AgenticFlow@270928091/Openflows-Infra@1385687794"
