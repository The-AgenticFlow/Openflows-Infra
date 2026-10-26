# Attach this group to a CloudShell VPC environment (or any admin host in the
# VPC) to reach the private API; it allows no inbound traffic.
resource "aws_security_group" "cluster_admin" {
  name        = "${local.name}-cluster-admin"
  description = "Admin sessions that may reach the ${local.name} API"
  vpc_id      = var.vpc_id
  tags        = { Name = "${local.name}-cluster-admin" }
}

# AWS-0104: HTTPS out only, to the cluster API and AWS APIs (SSM) through NAT.
#trivy:ignore:AWS-0104
resource "aws_vpc_security_group_egress_rule" "cluster_admin_https" {
  security_group_id = aws_security_group.cluster_admin.id
  description       = "HTTPS to the cluster API and AWS APIs"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# Laptop access without a public API: an SSM-managed instance forwards a local
# port to the private endpoint (scripts/kube-tunnel.sh). No inbound ports, no SSH.
data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "admin_tunnel" {
  name                 = "${local.name}-admin-tunnel"
  path                 = var.iam_path
  assume_role_policy   = data.aws_iam_policy_document.ec2_trust.json
  permissions_boundary = var.permissions_boundary_arn
}

resource "aws_iam_role_policy_attachment" "admin_tunnel_ssm" {
  role       = aws_iam_role.admin_tunnel.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "admin_tunnel" {
  name = "${local.name}-admin-tunnel"
  path = var.iam_path
  role = aws_iam_role.admin_tunnel.name
}

resource "aws_instance" "admin_tunnel" {
  ami                    = data.aws_ssm_parameter.al2023_arm64.value
  instance_type          = "t4g.nano"
  subnet_id              = var.node_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.cluster_admin.id]
  iam_instance_profile   = aws_iam_instance_profile.admin_tunnel.name

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
  }

  tags        = merge(var.tags, { Name = "${local.name}-admin-tunnel" })
  volume_tags = var.tags

  # Security updates install daily in place, so the AMI is not replaced on every plan.
  user_data = <<-EOT
    #!/bin/bash
    dnf install -y dnf-automatic
    sed -i 's/^upgrade_type.*/upgrade_type = security/; s/^apply_updates.*/apply_updates = yes/' /etc/dnf/automatic.conf
    systemctl enable --now dnf-automatic.timer
  EOT

  lifecycle {
    ignore_changes = [ami]
  }
}
