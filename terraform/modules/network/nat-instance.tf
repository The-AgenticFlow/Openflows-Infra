# nat_mode = "instance": one t4g.nano forwards the private subnets' egress
# instead of a managed NAT gateway. No failover; EC2 auto-recovery restarts it on
# host failure. Routes and the Elastic IP sit on a separate ENI that outlives it.
# No instance role: it patches itself, and if it breaks, replace it.
locals {
  nat_instance = var.nat_mode == "instance" ? 1 : 0
}

data "aws_ssm_parameter" "al2023_arm64" {
  count = local.nat_instance
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

# AWS-0104: a NAT forwards anything the VPC sends to the internet; inbound is
# limited to the VPC itself. Inline rules: separate rule resources are tagged
# objects the boundary denies at creation.
#trivy:ignore:AWS-0104
resource "aws_security_group" "nat" {
  count       = local.nat_instance
  name        = "openflows-${var.environment}-nat"
  description = "NAT instance: forwards VPC traffic to the internet"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Everything from inside the VPC"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Forwarded traffic and package updates"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "openflows-${var.environment}-nat", Environment = var.environment }
}

resource "aws_network_interface" "nat" {
  count             = local.nat_instance
  subnet_id         = module.vpc.public_subnets[0]
  security_groups   = [aws_security_group.nat[0].id]
  source_dest_check = false
  tags              = { Name = "openflows-${var.environment}-nat", Environment = var.environment }
}

# Attached to the ENI before the instance boots, so user_data has internet.
resource "aws_eip" "nat" {
  count             = local.nat_instance
  domain            = "vpc"
  network_interface = aws_network_interface.nat[0].id
  tags              = { Name = "openflows-${var.environment}-nat", Environment = var.environment }
}

resource "aws_instance" "nat" {
  count         = local.nat_instance
  ami           = data.aws_ssm_parameter.al2023_arm64[0].value
  instance_type = "t4g.nano"

  primary_network_interface {
    network_interface_id = aws_network_interface.nat[0].id
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
  }

  tags = { Name = "openflows-${var.environment}-nat", Environment = var.environment }
  # Provider default_tags do not reach the root volume.
  volume_tags = { Name = "openflows-${var.environment}-nat", Project = "openflows", Environment = var.environment }

  # Forwarding plus masquerade for VPC sources; security updates install daily in place.
  user_data = <<-EOT
    #!/bin/bash
    set -euo pipefail
    echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/90-nat.conf
    sysctl --system
    dnf install -y nftables dnf-automatic
    cat > /etc/sysconfig/nftables.conf <<'NFT'
    table ip nat {
      chain postrouting {
        type nat hook postrouting priority srcnat;
        ip saddr ${var.vpc_cidr} ip daddr != ${var.vpc_cidr} masquerade
      }
    }
    NFT
    systemctl enable --now nftables
    sed -i 's/^upgrade_type.*/upgrade_type = security/; s/^apply_updates.*/apply_updates = yes/' /etc/dnf/automatic.conf
    systemctl enable --now dnf-automatic.timer
  EOT

  # A changed boot script means a new instance; the ENI, EIP and routes stay.
  user_data_replace_on_change = true

  lifecycle {
    ignore_changes = [ami]
  }

  depends_on = [aws_eip.nat]
}

resource "aws_route" "private_nat_instance" {
  count                  = local.nat_instance * length(module.vpc.private_route_table_ids)
  route_table_id         = module.vpc.private_route_table_ids[count.index]
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_network_interface.nat[0].id

  # Switching from a gateway: the VPC module's 0.0.0.0/0 route must be gone first,
  # or AWS rejects this one with RouteAlreadyExists.
  depends_on = [module.vpc]
}
