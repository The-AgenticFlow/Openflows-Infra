# Non-secret inputs for staging. zone_name comes from the ZONE_NAME_STAGING
# repository variable (docs/RUNBOOK-aws.md, "Change control").

aws_account_id = "686255958454"

vpc_cidr = "10.20.0.0/16"

# Staging trades AZ-level egress resilience for cost: one NAT gateway.
single_nat_gateway = true

# trial.openflows.dev is delegated from the parent zone, so the certificate validates.
wait_for_certificate_validation = true

kubernetes_version       = "1.37"
node_ami_release_version = "1.37.1-20261023"

# Staging trades availability for cost: Spot, one AZ, one node. Several types
# improve Spot availability; burstable t3a is avoided (unlimited CPU credits bill extra).
node_instance_types    = ["m6a.xlarge", "m5a.xlarge", "m7a.xlarge", "m6i.xlarge"]
node_capacity_type     = "SPOT"
node_az_count          = 1
node_min_size          = 1
node_desired_size      = 1
node_max_size          = 2
eks_log_retention_days = 30
