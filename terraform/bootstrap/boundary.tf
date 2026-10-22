# Permissions boundary for every OpenFlows role. The account is shared with
# other projects, so this caps what any OpenFlows role can do, whatever its
# own policies say: IAM only under /openflows/, S3 only on openflows-* buckets,
# and no changes to resources not tagged Project=openflows.

locals {
  iam_path     = "/openflows/"
  boundary_arn = "arn:aws:iam::${var.aws_account_id}:policy/openflows/openflows-permissions-boundary"

  # IAM resources OpenFlows may manage. Everything else in IAM is off limits.
  openflows_iam_resources = [
    "arn:aws:iam::${var.aws_account_id}:role/openflows/*",
    "arn:aws:iam::${var.aws_account_id}:policy/openflows/*",
    "arn:aws:iam::${var.aws_account_id}:instance-profile/openflows/*",
    "arn:aws:iam::${var.aws_account_id}:oidc-provider/token.actions.githubusercontent.com",
    "arn:aws:iam::${var.aws_account_id}:oidc-provider/oidc.eks.*",
  ]
}

data "aws_iam_policy_document" "boundary" {
  statement {
    sid       = "AllowWithinBoundary"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }

  statement {
    sid    = "DenyIamOutsideOpenflows"
    effect = "Deny"
    actions = [
      "iam:AddClientIDToOpenIDConnectProvider", "iam:AddRoleToInstanceProfile", "iam:AddUserToGroup",
      "iam:AttachGroupPolicy", "iam:AttachRolePolicy", "iam:AttachUserPolicy",
      "iam:CreateAccessKey", "iam:CreateGroup", "iam:CreateInstanceProfile", "iam:CreateLoginProfile",
      "iam:CreateOpenIDConnectProvider", "iam:CreatePolicy", "iam:CreatePolicyVersion", "iam:CreateRole",
      "iam:CreateUser", "iam:DeleteGroup", "iam:DeleteInstanceProfile", "iam:DeleteOpenIDConnectProvider",
      "iam:DeletePolicy", "iam:DeletePolicyVersion", "iam:DeleteRole", "iam:DeleteRolePolicy",
      "iam:DeleteUser", "iam:DetachGroupPolicy", "iam:DetachRolePolicy", "iam:DetachUserPolicy",
      "iam:PassRole", "iam:PutGroupPolicy", "iam:PutRolePolicy", "iam:PutUserPolicy",
      "iam:RemoveRoleFromInstanceProfile", "iam:SetDefaultPolicyVersion", "iam:TagOpenIDConnectProvider",
      "iam:TagPolicy", "iam:TagRole", "iam:UntagRole", "iam:UpdateAssumeRolePolicy",
      "iam:UpdateOpenIDConnectProviderThumbprint", "iam:UpdateRole", "iam:UpdateRoleDescription",
    ]
    not_resources = local.openflows_iam_resources
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
    sid    = "ProtectBoundary"
    effect = "Deny"
    actions = [
      "iam:DeleteRolePermissionsBoundary", "iam:CreatePolicyVersion", "iam:DeletePolicy",
      "iam:DeletePolicyVersion", "iam:SetDefaultPolicyVersion",
    ]
    resources = [local.boundary_arn, "arn:aws:iam::${var.aws_account_id}:role/*"]
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
    sid    = "DenyChangesToOtherProjectsResources"
    effect = "Deny"
    actions = [
      "ec2:Delete*", "ec2:Modify*", "ec2:Terminate*", "ec2:Stop*", "ec2:Reboot*",
      "ec2:Disassociate*", "ec2:Detach*", "ec2:Replace*",
      "rds:Delete*", "rds:Modify*", "rds:Stop*", "rds:Reboot*",
      "eks:Delete*", "eks:Update*",
      "elasticache:Delete*", "elasticache:Modify*",
      "elasticloadbalancing:Delete*", "elasticloadbalancing:Modify*",
      "autoscaling:Delete*", "autoscaling:Update*",
      "kms:ScheduleKeyDeletion", "kms:DisableKey", "kms:PutKeyPolicy",
      "secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecret", "secretsmanager:DeleteSecret",
      "ssm:GetParameter*", "ssm:PutParameter", "ssm:DeleteParameter*",
      "logs:DeleteLogGroup", "logs:PutRetentionPolicy",
    ]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:ResourceTag/Project"
      values   = ["openflows"]
    }
  }
}

resource "aws_iam_policy" "boundary" {
  name        = "openflows-permissions-boundary"
  path        = local.iam_path
  description = "Ceiling for every OpenFlows role in this shared account"
  policy      = data.aws_iam_policy_document.boundary.json
}
