# Permissions boundary for every OpenFlows role. The account is shared with
# other projects, so this caps what any OpenFlows role can do, whatever its
# own policies say. Per-environment limits live on the apply roles (roles.tf).

locals {
  iam_path     = "/openflows/"
  boundary_arn = "arn:aws:iam::${var.aws_account_id}:policy/openflows/openflows-permissions-boundary"

  # Every IAM write verb. Matching by verb keeps new IAM actions covered.
  iam_write_actions = [
    "iam:Add*", "iam:Attach*", "iam:Change*", "iam:Create*", "iam:Deactivate*",
    "iam:Delete*", "iam:Detach*", "iam:Enable*", "iam:PassRole", "iam:Put*",
    "iam:Remove*", "iam:Reset*", "iam:Resync*", "iam:Set*", "iam:Tag*",
    "iam:Untag*", "iam:Update*", "iam:Upload*",
  ]

  # IAM resources OpenFlows may manage. Everything else in IAM is off limits.
  openflows_iam_resources = [
    "arn:aws:iam::${var.aws_account_id}:role/openflows/*",
    "arn:aws:iam::${var.aws_account_id}:policy/openflows/*",
    "arn:aws:iam::${var.aws_account_id}:instance-profile/openflows/*",
    "arn:aws:iam::${var.aws_account_id}:oidc-provider/oidc.eks.*",
  ]

  # Managed only by the bootstrap root, which runs without this boundary.
  bootstrap_iam_resources = [
    "arn:aws:iam::${var.aws_account_id}:role/openflows/openflows-*",
    "arn:aws:iam::${var.aws_account_id}:oidc-provider/token.actions.githubusercontent.com",
    local.boundary_arn,
  ]

  # Changes and secret reads that must only ever hit OpenFlows resources (and,
  # for apply roles, only their own environment's).
  protected_change_actions = [
    "ec2:Associate*", "ec2:Attach*", "ec2:Authorize*", "ec2:CreateNetworkAclEntry",
    "ec2:CreateRoute", "ec2:Delete*", "ec2:Detach*", "ec2:Disassociate*", "ec2:Modify*",
    "ec2:Reboot*", "ec2:Replace*", "ec2:Revoke*", "ec2:Stop*", "ec2:Terminate*",
    "rds:Delete*", "rds:Modify*", "rds:Stop*", "rds:Reboot*",
    "eks:Delete*", "eks:Update*",
    "elasticache:Delete*", "elasticache:Modify*",
    "elasticloadbalancing:Delete*", "elasticloadbalancing:Modify*",
    "autoscaling:Delete*", "autoscaling:Update*",
    "kms:ScheduleKeyDeletion", "kms:DisableKey", "kms:PutKeyPolicy",
    "secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue",
    "secretsmanager:UpdateSecret", "secretsmanager:DeleteSecret",
    "ssm:GetParameter*", "ssm:PutParameter", "ssm:DeleteParameter*",
  ]

  # Decided by name, not tags: retention is set right after the group is
  # created, before IAM sees its tags. OpenFlows log groups live under /openflows/.
  log_group_change_actions = ["logs:DeleteLogGroup", "logs:PutRetentionPolicy"]
  log_group_arn_prefix     = "arn:aws:logs:*:${var.aws_account_id}:log-group:/openflows"

  # Tag writes, which could otherwise relabel another project's resource as ours.
  tag_write_actions = [
    "ec2:CreateTags", "ec2:DeleteTags",
    "rds:AddTagsToResource", "rds:RemoveTagsFromResource",
    "eks:TagResource", "eks:UntagResource",
    "elasticache:AddTagsToResource", "elasticache:RemoveTagsFromResource",
    "elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags",
    "autoscaling:CreateOrUpdateTags", "autoscaling:DeleteTags",
    "kms:TagResource", "kms:UntagResource",
    "secretsmanager:TagResource", "secretsmanager:UntagResource",
    "ssm:AddTagsToResource", "ssm:RemoveTagsFromResource",
    "logs:TagResource", "logs:UntagResource", "logs:TagLogGroup", "logs:UntagLogGroup",
    "tag:TagResources", "tag:UntagResources",
  ]
}

data "aws_iam_policy_document" "boundary" {
  statement {
    sid       = "AllowWithinBoundary"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }

  # Creating a service-linked role (EKS, load balancing) carries
  # iam:AWSServiceName, so it is the one write allowed outside /openflows/.
  statement {
    sid           = "DenyIamWritesOutsideOpenflows"
    effect        = "Deny"
    actions       = local.iam_write_actions
    not_resources = local.openflows_iam_resources
    condition {
      test     = "Null"
      variable = "iam:AWSServiceName"
      values   = ["true"]
    }
  }

  statement {
    sid       = "ProtectBootstrapIam"
    effect    = "Deny"
    actions   = local.iam_write_actions
    resources = local.bootstrap_iam_resources
  }

  # A role created by an OpenFlows role must carry this same boundary, so no
  # role can mint a less restricted one.
  statement {
    sid       = "RequireBoundaryOnNewRoles"
    effect    = "Deny"
    actions   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.boundary_arn]
    }
  }

  statement {
    sid       = "KeepBoundaryOnRoles"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = ["*"]
  }

  statement {
    sid           = "DenyS3OutsideOpenflows"
    effect        = "Deny"
    actions       = ["s3:*"]
    not_resources = ["arn:aws:s3:::openflows-*", "arn:aws:s3:::openflows-*/*"]
  }

  # Untagged resources (other projects' resources) fail the tag check too,
  # because a missing tag never equals "openflows".
  statement {
    sid       = "DenyChangesToOtherProjectsResources"
    effect    = "Deny"
    actions   = local.protected_change_actions
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:ResourceTag/Project"
      values   = ["openflows"]
    }
  }

  # Log groups outside /openflows/ (which predate it) still need the project tag.
  statement {
    sid           = "DenyLogGroupChangesOutsideOpenflows"
    effect        = "Deny"
    actions       = local.log_group_change_actions
    not_resources = ["${local.log_group_arn_prefix}/*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:ResourceTag/Project"
      values   = ["openflows"]
    }
  }

  # Tagging is allowed while a resource is being created (EC2 sets
  # ec2:CreateAction then) or on a resource that is already OpenFlows'.
  statement {
    sid       = "DenyRetaggingOtherProjectsResources"
    effect    = "Deny"
    actions   = local.tag_write_actions
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:ResourceTag/Project"
      values   = ["openflows"]
    }
    condition {
      test     = "Null"
      variable = "ec2:CreateAction"
      values   = ["true"]
    }
  }
}

resource "aws_iam_policy" "boundary" {
  name        = "openflows-permissions-boundary"
  path        = local.iam_path
  description = "Ceiling for every OpenFlows role in this shared account"
  policy      = data.aws_iam_policy_document.boundary.json
}
