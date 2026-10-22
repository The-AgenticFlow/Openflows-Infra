output "zone_id" {
  description = "Route 53 hosted zone ID."
  value       = aws_route53_zone.this.zone_id
}

output "zone_name" {
  description = "Domain the zone serves."
  value       = aws_route53_zone.this.name
}

output "name_servers" {
  description = "Name servers to delegate to from the parent domain."
  value       = aws_route53_zone.this.name_servers
}

output "certificate_arn" {
  description = "Wildcard ACM certificate for the environment's HTTPS ingress."
  value       = aws_acm_certificate.this.arn
}
