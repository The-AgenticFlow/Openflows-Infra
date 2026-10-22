locals {
  # Bucket names are global across AWS, so the account ID keeps them unique.
  state_bucket_names = {
    for env in var.environments : env => "openflows-tfstate-${env}-${var.aws_account_id}"
  }
}

# One customer-managed key per environment, so access to one environment's
# state can be revoked without touching the other.
resource "aws_kms_key" "state" {
  for_each = var.environments

  description             = "Encrypts OpenFlows ${each.key} Terraform state"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = { Environment = each.key }
}

resource "aws_kms_alias" "state" {
  for_each = var.environments

  name          = "alias/openflows-tfstate-${each.key}"
  target_key_id = aws_kms_key.state[each.key].key_id
}

resource "aws_s3_bucket" "state" {
  for_each = var.environments

  bucket = local.state_bucket_names[each.key]
  tags   = { Environment = each.key }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "state" {
  for_each = var.environments

  bucket = aws_s3_bucket.state[each.key].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  for_each = var.environments

  bucket                  = aws_s3_bucket.state[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "state" {
  for_each = var.environments

  bucket = aws_s3_bucket.state[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  for_each = var.environments

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
  for_each = var.environments

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
  for_each = var.environments

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

  # Only when an allow-list is set for the environment: every principal outside
  # it is denied, which keeps one environment's deployer out of the other's state.
  dynamic "statement" {
    for_each = length(lookup(var.state_admin_principal_arns, each.key, [])) > 0 ? [1] : []
    content {
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
        values   = var.state_admin_principal_arns[each.key]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  for_each = var.environments

  bucket = aws_s3_bucket.state[each.key].id
  policy = data.aws_iam_policy_document.state[each.key].json

  depends_on = [aws_s3_bucket_public_access_block.state]
}
