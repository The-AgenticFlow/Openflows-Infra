# Workload roles from var.workload_roles: one role per service account, bound through
# Pod Identity. Add a role by adding an entry; nothing here changes per workload.
resource "aws_iam_role" "workload" {
  for_each = var.workload_roles

  name                 = "${local.name}-${each.key}"
  path                 = var.iam_path
  assume_role_policy   = data.aws_iam_policy_document.pod_identity_trust.json
  permissions_boundary = var.permissions_boundary_arn
}

resource "aws_iam_role_policy_attachment" "workload" {
  for_each = { for pair in flatten([
    for k, v in var.workload_roles : [for arn in v.managed_policy_arns : { key = k, arn = arn }]
  ]) : "${pair.key}/${pair.arn}" => pair }

  role       = aws_iam_role.workload[each.value.key].name
  policy_arn = each.value.arn
}

resource "aws_iam_role_policy" "workload" {
  for_each = { for k, v in var.workload_roles : k => v.policy_json if v.policy_json != null }

  name   = each.key
  role   = aws_iam_role.workload[each.key].id
  policy = each.value
}

resource "aws_eks_pod_identity_association" "workload" {
  for_each = var.workload_roles

  cluster_name    = module.eks.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = aws_iam_role.workload[each.key].arn
}
