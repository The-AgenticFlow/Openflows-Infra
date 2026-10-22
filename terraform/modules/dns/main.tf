# Environment DNS: a public hosted zone for the environment's domain and a
# DNS-validated wildcard certificate that the HTTPS ingress uses.

resource "aws_route53_zone" "this" {
  name    = var.zone_name
  comment = "OpenFlows ${var.environment}"
  tags    = { Environment = var.environment }
}

resource "aws_acm_certificate" "this" {
  domain_name               = var.zone_name
  subject_alternative_names = ["*.${var.zone_name}"]
  validation_method         = "DNS"
  tags                      = { Environment = var.environment }

  lifecycle {
    create_before_destroy = true
  }
}

# Keyed by domain (known at plan time). The apex and the wildcard resolve to the
# same record, which allow_overwrite lets both entries write without conflict.
resource "aws_route53_record" "validation" {
  for_each = {
    for o in aws_acm_certificate.this.domain_validation_options : o.domain_name => o
  }

  zone_id         = aws_route53_zone.this.zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 300
  allow_overwrite = true
}

# Validation only completes once the parent domain delegates to this zone.
resource "aws_acm_certificate_validation" "this" {
  count = var.wait_for_certificate_validation ? 1 : 0

  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}
