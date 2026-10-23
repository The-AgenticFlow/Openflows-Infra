data "aws_partition" "current" {}

data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

locals {
  # Load Balancer Controller policy from its release tag, matching the chart Argo CD installs.
  pod_roles = merge(
    {
      ebs-csi                      = { managed_policy = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy", inline = null }
      aws-load-balancer-controller = { managed_policy = null, inline = file("${path.module}/policies/aws-load-balancer-controller.json") }
    },
    local.external_dns ? { external-dns = { managed_policy = null, inline = templatefile("${path.module}/policies/external-dns.json.tftpl", { zone_arn = "arn:${data.aws_partition.current.partition}:route53:::hostedzone/${var.zone_id}" }) } } : {},
  )
}

resource "aws_iam_role" "pod" {
  for_each = local.pod_roles

  name                 = "${local.name}-${each.key}"
  path                 = var.iam_path
  assume_role_policy   = data.aws_iam_policy_document.pod_identity_trust.json
  permissions_boundary = var.permissions_boundary_arn
}

resource "aws_iam_role_policy_attachment" "pod" {
  for_each = { for k, v in local.pod_roles : k => v.managed_policy if v.managed_policy != null }

  role       = aws_iam_role.pod[each.key].name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "pod" {
  for_each = { for k, v in local.pod_roles : k => v.inline if v.inline != null }

  name   = each.key
  role   = aws_iam_role.pod[each.key].id
  policy = each.value
}

# The Load Balancer Controller is installed later by Argo CD; its role is bound now.
resource "aws_eks_pod_identity_association" "aws_load_balancer_controller" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.pod["aws-load-balancer-controller"].arn
}
