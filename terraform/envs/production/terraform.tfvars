# Non-secret inputs for production. aws_account_id and zone_name are passed at
# plan time (docs/RUNBOOK-aws.md) until they are decided and committed here.

vpc_cidr = "10.30.0.0/16"

# One NAT gateway per AZ, so losing an AZ does not cut egress for the others.
single_nat_gateway = false
