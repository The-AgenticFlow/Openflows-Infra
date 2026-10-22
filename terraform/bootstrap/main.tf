locals {
  # Each environment has its own state bucket, and so does the bootstrap root,
  # so no environment deployer can reach the state that manages its own roles.
  state_scopes = setunion(var.environments, ["bootstrap"])

  # Bucket names are global across AWS, so the account ID keeps them unique.
  state_bucket_names = {
    for scope in local.state_scopes : scope => "openflows-tfstate-${scope}-${var.aws_account_id}"
  }

  # Built from the name (known at plan time) so policies render in the plan.
  state_bucket_arns = { for scope, name in local.state_bucket_names : scope => "arn:aws:s3:::${name}" }

  # Principals allowed into each state bucket besides break-glass.
  state_bucket_principals = merge(
    {
      for env in var.environments : env => [
        aws_iam_role.terraform_plan[env].arn,
        aws_iam_role.terraform_apply[env].arn,
        aws_iam_role.platform_admin.arn,
      ]
    },
    { bootstrap = [aws_iam_role.platform_admin.arn] },
  )
}

# One customer-managed key per state scope, so access to one scope's state can
# be revoked without touching the others.
resource "aws_kms_key" "state" {
  for_each = local.state_scopes

  description             = "Encrypts OpenFlows ${each.key} Terraform state"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = { Environment = each.key }
}

resource "aws_kms_alias" "state" {
  for_each = local.state_scopes

  name          = "alias/openflows-tfstate-${each.key}"
  target_key_id = aws_kms_key.state[each.key].key_id
}

resource "aws_s3_bucket" "state" {
  for_each = local.state_scopes

  bucket = local.state_bucket_names[each.key]
  tags   = { Environment = each.key }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "state" {
  for_each = local.state_scopes

  bucket = aws_s3_bucket.state[each.key].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  for_each = local.state_scopes

  bucket                  = aws_s3_bucket.state[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "state" {
  for_each = local.state_scopes

  bucket = aws_s3_bucket.state[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  for_each = local.state_scopes

  bucket = aws_s3_bucket.state[each.key].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state[each.key].arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  for_each = local.state_scopes

  bucket = aws_s3_bucket.state[each.key].id
  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

data "aws_iam_policy_document" "state" {
  for_each = local.state_scopes

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state[each.key].arn,
      "${aws_s3_bucket.state[each.key].arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Uploads that ask for anything but KMS would bypass the scope's key.
  statement {
    sid       = "DenyNonKmsEncryption"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.state[each.key].arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
    condition {
      test     = "Null"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["false"]
    }
  }

  # Everyone outside this scope's roles and break-glass is denied, which keeps
  # each environment's pipeline out of the other's state and the bootstrap's.
  statement {
    sid     = "DenyPrincipalsOutsideEnvironment"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state[each.key].arn,
      "${aws_s3_bucket.state[each.key].arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = concat(local.state_bucket_principals[each.key], var.state_break_glass_principal_arns)
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  for_each = local.state_scopes

  bucket = aws_s3_bucket.state[each.key].id
  policy = data.aws_iam_policy_document.state[each.key].json

  depends_on = [aws_s3_bucket_public_access_block.state]
}
