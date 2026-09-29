# ADR-0003: Plain HTTP over a `.int` internal hostname, no TLS

Status: accepted

## Context

OpenFlows moved from a dedicated LoadBalancer IP (`coder.accessUrl` pointing
at a raw `http://<ip>:7080`) to routing through the cluster's shared
`ingress-nginx` controller, so multiple internal services can share one IP
via Host-header routing instead of consuming a LoadBalancer IP each.

This is enterprise-internal only, resolved purely via `/etc/hosts` on each
machine that needs it, no public DNS, no ACME/Let's Encrypt path (those
require a publicly resolvable domain), and no internal CA or
`cert-manager` deployed to this cluster yet.

Two more decisions fell out of picking a hostname:

- `.dev` was considered and rejected: it's a real public TLD hardcoded into
  every major browser's HSTS preload list, so browsers force HTTPS on any
  `.dev` hostname, registered or not, with no override. That would have
  broken plain HTTP outright.
- `.home` was used briefly during setup, renamed to `.int` since this is
  enterprise-internal rather than a personal homelab convention.

## Decision

`openflows.int`, plain HTTP, `ingress-nginx`'s default `ssl-redirect` forced
off explicitly (`nginx.ingress.kubernetes.io/ssl-redirect: "false"`) and no
`tls:` block on the Ingress. `.int` is not IETF-reserved the way
`.internal` (RFC 8375) is, it's a real but restricted public TLD (ICANN,
international organizations), chosen here purely for brevity; it is never
expected to resolve publicly for this cluster's use.

## Consequences

- Traffic between a client's `/etc/hosts`-resolved request and
  `ingress-nginx` is unencrypted. Acceptable for an internal-only LAN
  service today, not acceptable if this is ever exposed beyond the trusted
  internal network.
- Every client machine that needs to reach OpenFlows needs a manual
  `/etc/hosts` entry (`192.168.1.200 openflows.int`), there is no internal
  DNS server resolving `.int` automatically.
- If TLS becomes a requirement, the path is either an internal CA (`step-ca`,
  `cert-manager` with a self-signed or internal issuer) or moving to a
  domain with a real ACME path, revisit this ADR at that point.
