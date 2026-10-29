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

  # Changes and parameter reads that must only ever hit OpenFlows resources (and,
  # for apply roles, only their own environment's).
  protected_change_actions = [
    "ec2:Assign*", "ec2:Unassign*",
    "ec2:Associate*", "ec2:Attach*", "ec2:Authorize*", "ec2:CreateNetworkAclEntry",
    "ec2:CreateRoute", "ec2:Delete*", "ec2:Detach*", "ec2:Disassociate*", "ec2:Modify*",
    "ec2:Reboot*", "ec2:Replace*", "ec2:Revoke*", "ec2:Stop*", "ec2:Terminate*",
    "rds:Delete*", "rds:Modify*", "rds:Stop*", "rds:Reboot*",
    "eks:Delete*", "eks:Update*",
    "elasticache:Delete*", "elasticache:Modify*",
    "elasticloadbalancing:Delete*", "elasticloadbalancing:Modify*",
    "elasticloadbalancing:Register*", "elasticloadbalancing:Deregister*",
    "elasticloadbalancing:Set*", "elasticloadbalancing:CreateListener", "elasticloadbalancing:CreateRule",
    "elasticloadbalancing:AddListenerCertificates", "elasticloadbalancing:RemoveListenerCertificates",
    "autoscaling:Delete*", "autoscaling:Update*",
    "kms:ScheduleKeyDeletion", "kms:DisableKey", "kms:PutKeyPolicy",
    "ssm:GetParameter*", "ssm:PutParameter", "ssm:DeleteParameter*",
  ]

  # Decided by name, not tags: retention is set right after the group is
  # created, before IAM sees its tags. EKS fixes its own name, /aws/eks/<cluster>/.
  log_group_change_actions = ["logs:DeleteLogGroup", "logs:PutRetentionPolicy"]
  log_group_arn            = "arn:aws:logs:*:${var.aws_account_id}:log-group"

  # Secrets are decided by name, not tags: the Manager creates its own, untagged. Verbs by first
  # letter (Cancel/Create, Put, Remove/Replicate/Restore/Rotate, Stop, Tag, Untag/Update) plus the
  # named reads; ListSecrets, GetRandomPassword and Describe* take no secret value and stay open.
  secret_actions = [
    "secretsmanager:C*", "secretsmanager:Delete*", "secretsmanager:GetResourcePolicy",
    "secretsmanager:GetSecretValue", "secretsmanager:P*", "secretsmanager:R*",
    "secretsmanager:S*", "secretsmanager:T*", "secretsmanager:U*",
  ]
  secret_arn = "arn:aws:secretsmanager:*:${var.aws_account_id}:secret:openflows"

  # AWS-owned public parameters (EKS AMI IDs) have no account and no tags.
  aws_public_parameters = "arn:aws:ssm:*::parameter/aws/service/*"

  # Tag writes, which could otherwise relabel another project's resource as ours.
  tag_write_actions = [
    "ec2:CreateTags", "ec2:DeleteTags",
    "rds:AddTagsToResource", "rds:RemoveTagsFromResource",
    "eks:TagResource", "eks:UntagResource",
    "elasticache:AddTagsToResource", "elasticache:RemoveTagsFromResource",
    "elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags",
    "autoscaling:CreateOrUpdateTags", "autoscaling:DeleteTags",
    "kms:TagResource", "kms:UntagResource",
    "ssm:AddTagsToResource", "ssm:RemoveTagsFromResource",
    "logs:TagResource", "logs:UntagResource", "logs:TagLogGroup", "logs:UntagLogGroup",
    "tag:TagResources", "tag:UntagResources",
  ]
}

data "aws_iam_policy_document" "boundary" {
  statement {
    sid       = "Allow"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }

  # Creating a service-linked role (EKS, load balancing) carries
  # iam:AWSServiceName, so it is the one write allowed outside /openflows/.
  statement {
    sid           = "IamOutside"
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
    sid       = "BootstrapIam"
    effect    = "Deny"
    actions   = local.iam_write_actions
    resources = local.bootstrap_iam_resources
  }

  # A role created by an OpenFlows role must carry this same boundary, so no
  # role can mint a less restricted one.
  statement {
    sid       = "NewRoleBoundary"
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
    sid       = "KeepBoundary"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = ["*"]
  }

  statement {
    sid           = "S3Outside"
    effect        = "Deny"
    actions       = ["s3:*"]
    not_resources = ["arn:aws:s3:::openflows-*", "arn:aws:s3:::openflows-*/*"]
  }

  # Untagged resources (other projects' resources) fail the tag check too,
  # because a missing tag never equals "openflows".
  statement {
    sid           = "OtherProjects"
    effect        = "Deny"
    actions       = local.protected_change_actions
    not_resources = [local.aws_public_parameters]
    condition {
      test     = "StringNotEquals"
      variable = "aws:ResourceTag/Project"
      values   = ["openflows"]
    }
  }

  # Environment roles reach only openflows/<their environment>/ secrets. Roles without the
  # tag (the human ones) get the same limit, across environments, in roles.tf.
  statement {
    sid           = "SecretsByName"
    effect        = "Deny"
    actions       = local.secret_actions
    not_resources = ["${local.secret_arn}/$${aws:PrincipalTag/Environment}/*"]
    condition {
      test     = "Null"
      variable = "aws:PrincipalTag/Environment"
      values   = ["false"]
    }
  }

  # Log groups outside /openflows/ (which predate it) still need the project tag.
  statement {
    sid           = "LogGroups"
    effect        = "Deny"
    actions       = local.log_group_change_actions
    not_resources = ["${local.log_group_arn}:/openflows/*", "${local.log_group_arn}:/aws/eks/openflows-*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:ResourceTag/Project"
      values   = ["openflows"]
    }
  }

  # Tagging is allowed while a resource is being created (EC2 sets
  # ec2:CreateAction then) or on a resource that is already OpenFlows'.
  statement {
    sid       = "ProjectRetag"
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

  # Environment roles (tagged Environment by their root) only change their own
  # environment. Untagged roles (platform admin, read-only) span both.
  statement {
    sid           = "OtherEnv"
    effect        = "Deny"
    actions       = local.protected_change_actions
    not_resources = [local.aws_public_parameters]
    condition {
      test     = "StringNotEquals"
      variable = "aws:ResourceTag/Environment"
      values   = ["$${aws:PrincipalTag/Environment}"]
    }
    condition {
      test     = "Null"
      variable = "aws:PrincipalTag/Environment"
      values   = ["false"]
    }
  }

  statement {
    sid       = "EnvRetag"
    effect    = "Deny"
    actions   = local.tag_write_actions
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:ResourceTag/Environment"
      values   = ["$${aws:PrincipalTag/Environment}"]
    }
    condition {
      test     = "Null"
      variable = "aws:PrincipalTag/Environment"
      values   = ["false"]
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
