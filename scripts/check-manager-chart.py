#!/usr/bin/env python3
# Render charts/openflows-manager with the staging app's values; fail on anything that would stop the Manager starting.
import os
import subprocess
import sys
import tempfile

import yaml

APP = "gitops/staging/apps/openflows-manager.yaml"
CHART = "charts/openflows-manager"

# From the Manager's config.rs (hosted mode) and what its setup and doctor commands read.
REQUIRED_ENV = [
    "OPENFLOWS_MODE", "OPENFLOWS_SECRET_PROVIDER", "OPENFLOWS_AWS_SECRETS_PREFIX", "OPENFLOWS_DATABASE_URL",
    "OPENFLOWS_PUBLIC_URL", "OPENFLOWS_GITHUB_APP_ID", "OPENFLOWS_GITHUB_APP_SLUG", "OPENFLOWS_GITHUB_CLIENT_ID",
    "OPENFLOWS_GITHUB_CLIENT_SECRET_REF", "OPENFLOWS_GITHUB_PRIVATE_KEY_REF", "OPENFLOWS_GITHUB_WEBHOOK_SECRET_REF",
    "OPENFLOWS_CRYPTO_MASTER_KEY_REF", "CODER_URL", "OPENFLOWS_CODER_OPERATOR_TOKEN_REF",
    "OPENFLOWS_CODER_HOOK_SECRET_REF", "OPENFLOWS_CODER_OAUTH_CLIENT_SECRET_REF", "OPENFLOWS_CODER_VERSION_BASELINE",
    "REDIS_URL", "OPENFLOWS_REDIS_ADMIN_URL", "OPENFLOWS_RUNTIME_REDIS_URL", "OPENFLOWS_PROVISIONER_BACKEND",
    "OPENFLOWS_RUNTIME_MANAGER_URL", "OPENFLOWS_RUNTIME_RELAY_BASE_URL", "AWS_REGION",
]


def fail(message):
    print(f"FAIL {message}")
    sys.exit(1)


def main():
    values = yaml.safe_load(open(APP))["spec"]["source"]["helm"]["valuesObject"]
    with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False) as f:
        yaml.safe_dump(values, f)
    subprocess.run(["helm", "lint", CHART, "-f", f.name], check=True)
    out = subprocess.run(["helm", "template", "openflows-manager", CHART, "-n", "openflows", "-f", f.name],
                         check=True, capture_output=True, text=True).stdout
    os.unlink(f.name)
    docs = [d for d in yaml.safe_load_all(out) if d]
    workloads = [d for d in docs if d["kind"] in ("Job", "Deployment")]

    dep = next(d for d in workloads if d["kind"] == "Deployment")["spec"]["template"]["spec"]["containers"][0]
    missing = [n for n in REQUIRED_ENV if n not in {e["name"] for e in dep["env"]}]
    if missing:
        fail(f"Deployment is missing settings: {', '.join(missing)}")
    if "@sha256:" not in dep["image"]:
        fail(f"image is not pinned by digest: {dep['image']}")
    waves = {d["metadata"]["name"]: int(d["metadata"]["annotations"]["argocd.argoproj.io/sync-wave"]) for d in workloads}
    if not waves["openflows-manager-db"] < waves["openflows-manager-setup"] < waves["openflows-manager"]:
        fail(f"database job, setup job and Deployment are out of order: {waves}")
    for d in workloads:
        ctx = d["spec"]["template"]["spec"]["containers"][0].get("securityContext") or {}
        if not ctx.get("runAsNonRoot") or ctx.get("allowPrivilegeEscalation") is not False:
            fail(f"{d['metadata']['name']} must run as non-root without privilege escalation")
    print(f"ok   {len(dep['env'])} settings, image pinned, hooks ordered {waves}")


if __name__ == "__main__":
    main()
