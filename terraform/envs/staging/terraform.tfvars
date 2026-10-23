# Non-secret inputs for staging. zone_name comes from the ZONE_NAME_STAGING
# repository variable (docs/RUNBOOK-aws.md, "Change control").

aws_account_id = "686255958454"

vpc_cidr = "10.20.0.0/16"

# Staging trades AZ-level egress resilience for cost: one NAT gateway.
single_nat_gateway = true

# trial.openflows.dev is delegated from the parent zone, so the certificate validates.
wait_for_certificate_validation = true
