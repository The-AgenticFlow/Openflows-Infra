# GitHub Actions authenticates through OIDC, so no AWS key is stored in GitHub.
# Trust is pinned to this repository (by its OIDC subject prefix) and to a ref,
# not to a GitHub environment: a job that sets `environment:` is refused.

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

locals {
  github_sub = var.github_oidc_subject_prefix

  # Who may apply each environment: staging from main, production from release tags.
  apply_subjects = {
    staging    = ["${local.github_sub}:ref:refs/heads/main"]
    production = ["${local.github_sub}:ref:refs/tags/v*"]
  }

  # Plans run on pull requests and on main (scheduled drift checks).
  plan_subjects = [
    "${local.github_sub}:pull_request",
    "${local.github_sub}:ref:refs/heads/main",
  ]
}

data "aws_iam_policy_document" "github_trust" {
  for_each = {
    for pair in setproduct(tolist(var.environments), ["plan", "apply"]) :
    "${pair[0]}-${pair[1]}" => pair[1] == "plan" ? local.plan_subjects : local.apply_subjects[pair[0]]
  }

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = each.value
    }
  }
}

resource "aws_iam_role" "terraform_plan" {
  for_each = var.environments

  name                 = "openflows-${each.key}-terraform-plan"
  path                 = local.iam_path
  description          = "Read-only Terraform plans for ${each.key} from GitHub Actions"
  assume_role_policy   = data.aws_iam_policy_document.github_trust["${each.key}-plan"].json
  permissions_boundary = aws_iam_policy.boundary.arn
  max_session_duration = 3600
  tags                 = { Environment = each.key }
}

resource "aws_iam_role_policy_attachment" "terraform_plan_readonly" {
  for_each = var.environments

  role       = aws_iam_role.terraform_plan[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# A plan reads state and takes the lock, which writes a .tflock object.
data "aws_iam_policy_document" "terraform_plan_state" {
  for_each = var.environments

  statement {
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket_arns[each.key]]
  }
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${local.state_bucket_arns[each.key]}/*"]
  }
  statement {
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_bucket_arns[each.key]}/*.tflock"]
  }
  statement {
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.state[each.key].arn]
  }
}

resource "aws_iam_role_policy" "terraform_plan_state" {
  for_each = var.environments

  name   = "terraform-state"
  role   = aws_iam_role.terraform_plan[each.key].id
  policy = data.aws_iam_policy_document.terraform_plan_state[each.key].json
}

# Administrator within the boundary: the boundary, not this attachment, decides
# what the apply role can really do.
resource "aws_iam_role" "terraform_apply" {
  for_each = var.environments

  name                 = "openflows-${each.key}-terraform-apply"
  path                 = local.iam_path
  description          = "Terraform applies for ${each.key} from GitHub Actions"
  assume_role_policy   = data.aws_iam_policy_document.github_trust["${each.key}-apply"].json
  permissions_boundary = aws_iam_policy.boundary.arn
  max_session_duration = 3600
  tags                 = { Environment = each.key }
}

resource "aws_iam_role_policy_attachment" "terraform_apply_admin" {
  for_each = var.environments

  role       = aws_iam_role.terraform_apply[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# The boundary separates OpenFlows from other projects; this separates the two
# OpenFlows environments, so one environment's apply cannot touch the other's.
data "aws_iam_policy_document" "terraform_apply_environment" {
  for_each = var.environments

  statement {
    sid     = "DenyIamOutsideEnvironmentPath"
    effect  = "Deny"
    actions = local.iam_write_actions
    not_resources = [
      "arn:aws:iam::${var.aws_account_id}:role/openflows/${each.key}/*",
      "arn:aws:iam::${var.aws_account_id}:policy/openflows/${each.key}/*",
      "arn:aws:iam::${var.aws_account_id}:instance-profile/openflows/${each.key}/*",
      "arn:aws:iam::${var.aws_account_id}:oidc-provider/oidc.eks.*",
    ]
    condition {
      test     = "Null"
      variable = "iam:AWSServiceName"
      values   = ["true"]
    }
  }

  statement {
    sid     = "DenyS3OutsideEnvironment"
    effect  = "Deny"
    actions = ["s3:*"]
    not_resources = [
      "arn:aws:s3:::openflows-${each.key}-*",
      "arn:aws:s3:::openflows-${each.key}-*/*",
      local.state_bucket_arns[each.key],
      "${local.state_bucket_arns[each.key]}/*",
    ]
  }

  statement {
    sid       = "DenyChangesToOtherEnvironment"
    effect    = "Deny"
    actions   = local.protected_change_actions
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [each.key]
    }
  }

  statement {
    sid           = "DenyLogGroupChangesOutsideEnvironment"
    effect        = "Deny"
    actions       = local.log_group_change_actions
    not_resources = ["${local.log_group_arn}:/openflows/${each.key}/*", "${local.log_group_arn}:/aws/eks/openflows-${each.key}/*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [each.key]
    }
  }

  # New resources must carry this environment's tag, never the other one.
  statement {
    sid       = "DenyTaggingAsOtherEnvironment"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestTag/Environment"
      values   = [each.key]
    }
    condition {
      test     = "Null"
      variable = "aws:RequestTag/Environment"
      values   = ["false"]
    }
  }
}

resource "aws_iam_role_policy" "terraform_apply_environment" {
  for_each = var.environments

  name   = "environment-isolation"
  role   = aws_iam_role.terraform_apply[each.key].id
  policy = data.aws_iam_policy_document.terraform_apply_environment[each.key].json
}

# Human access: assumed from an IAM user only with MFA.
data "aws_iam_policy_document" "human_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = var.human_principal_arns
    }
    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role" "platform_admin" {
  name                 = "openflows-platform-admin"
  path                 = local.iam_path
  description          = "Break-glass administrator for OpenFlows, MFA required"
  assume_role_policy   = data.aws_iam_policy_document.human_trust.json
  permissions_boundary = aws_iam_policy.boundary.arn
  max_session_duration = 14400
}

resource "aws_iam_role_policy_attachment" "platform_admin" {
  role       = aws_iam_role.platform_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role" "readonly" {
  name                 = "openflows-readonly"
  path                 = local.iam_path
  description          = "Day-to-day read-only access for OpenFlows operators, MFA required"
  assume_role_policy   = data.aws_iam_policy_document.human_trust.json
  permissions_boundary = aws_iam_policy.boundary.arn
  max_session_duration = 43200
}

resource "aws_iam_role_policy_attachment" "readonly" {
  role       = aws_iam_role.readonly.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
