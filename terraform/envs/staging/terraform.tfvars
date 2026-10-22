# Non-secret inputs for staging. zone_name is passed at
# plan time (docs/RUNBOOK-aws.md) until the domain is decided and committed here.

aws_account_id = "686255958454"

vpc_cidr = "10.20.0.0/16"

# Staging trades AZ-level egress resilience for cost: one NAT gateway.
single_nat_gateway = true
