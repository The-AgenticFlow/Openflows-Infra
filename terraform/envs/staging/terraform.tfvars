# Non-secret inputs for staging. aws_account_id and zone_name are passed at
# plan time (docs/RUNBOOK-aws.md) until they are decided and committed here.

vpc_cidr = "10.20.0.0/16"

# Staging trades AZ-level egress resilience for cost: one NAT gateway.
single_nat_gateway = true
