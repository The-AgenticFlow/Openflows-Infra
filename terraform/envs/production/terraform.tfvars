# Non-secret inputs for production. zone_name is passed at
# plan time (docs/RUNBOOK-aws.md) until the domain is decided and committed here.

aws_account_id = "686255958454"

vpc_cidr = "10.30.0.0/16"

# One NAT gateway per AZ, so losing an AZ does not cut egress for the others.
single_nat_gateway = false
