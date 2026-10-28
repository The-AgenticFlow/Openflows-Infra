# Off-hours node schedule: EventBridge Scheduler calls EKS UpdateNodegroupConfig
# directly (no Lambda). Not ASG scheduled actions: EKS leaves the node group's ASG
# untagged, so the boundary would deny deleting them later.
locals {
  node_schedules = var.node_schedule == null ? {} : {
    stop  = { cron = var.node_schedule.stop_cron, desired = 0 }
    start = { cron = var.node_schedule.start_cron, desired = var.node_desired_size }
  }
  node_group_name = split(":", module.eks.eks_managed_node_groups["default"].node_group_id)[1]
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "node_schedule_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "node_schedule" {
  count                = var.node_schedule == null ? 0 : 1
  name                 = "${local.name}-node-schedule"
  path                 = var.iam_path
  assume_role_policy   = data.aws_iam_policy_document.node_schedule_trust.json
  permissions_boundary = var.permissions_boundary_arn
  tags                 = var.tags
}

data "aws_iam_policy_document" "node_schedule" {
  statement {
    actions   = ["eks:UpdateNodegroupConfig"]
    resources = [module.eks.eks_managed_node_groups["default"].node_group_arn]
  }
}

resource "aws_iam_role_policy" "node_schedule" {
  count  = var.node_schedule == null ? 0 : 1
  name   = "scale-node-group"
  role   = aws_iam_role.node_schedule[0].id
  policy = data.aws_iam_policy_document.node_schedule.json
}

resource "aws_scheduler_schedule" "node" {
  for_each = local.node_schedules

  name                         = "${local.name}-nodes-${each.key}"
  schedule_expression          = each.value.cron
  schedule_expression_timezone = var.node_schedule.timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:${data.aws_partition.current.partition}:scheduler:::aws-sdk:eks:updateNodegroupConfig"
    role_arn = aws_iam_role.node_schedule[0].arn
    input = jsonencode({
      clusterName   = module.eks.cluster_name
      nodegroupName = local.node_group_name
      scalingConfig = { desiredSize = each.value.desired }
    })

    retry_policy {
      maximum_retry_attempts = 3
    }
  }
}
