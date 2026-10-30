#!/usr/bin/env python3
# Validate every IAM policy we write with IAM Access Analyzer. Fails on ERROR or
# SECURITY_WARNING findings unless policy-findings-allowlist.json accepts them with a reason.
# Usage: validate_policies.py [--live] [--plan <plan.json>] [<policy-file>...]
import json
import os
import subprocess
import sys

BLOCKING = {"ERROR", "SECURITY_WARNING"}
HERE = os.path.dirname(os.path.abspath(__file__))
# Template variables in the policy files, with stand-ins that make them valid documents.
PLACEHOLDERS = {
    "${zone_arn}": "arn:aws:route53:::hostedzone/Z0EXAMPLE",
    "${manager_secret_arn}": "arn:aws:secretsmanager:eu-west-1:123456789012:secret:openflows/staging/manager/*",
}


def validate(name, document, policy_type, resource_type=None):
    cmd = ["aws", "accessanalyzer", "validate-policy", "--policy-type", policy_type,
           "--policy-document", document, "--output", "json"]
    if resource_type:
        cmd += ["--validate-policy-resource-type", resource_type]
    out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"validate-policy failed for {name}: {out.stderr.strip()}")
    doc = json.loads(document)
    statements = doc["Statement"] if isinstance(doc["Statement"], list) else [doc["Statement"]]
    found = []
    for f in json.loads(out.stdout)["findings"]:
        sid = None
        for loc in f["locations"]:
            path = loc["path"]
            if len(path) > 1 and "index" in path[1]:
                sid = statements[path[1]["index"]].get("Sid")
        found.append((f["findingType"], f["issueCode"], sid))
    return found


def aws(*args):
    out = subprocess.run(["aws", *args, "--output", "json"], capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(out.stderr.strip())
    return json.loads(out.stdout)


def live():
    # Everything deployed under /openflows/, including roles the environment roots create.
    for role in aws("iam", "list-roles", "--path-prefix", "/openflows/")["Roles"]:
        name = role["RoleName"]
        yield f"role {name} trust", json.dumps(role["AssumeRolePolicyDocument"]), "RESOURCE_POLICY", "AWS::IAM::AssumeRolePolicyDocument"
        for pol in aws("iam", "list-role-policies", "--role-name", name)["PolicyNames"]:
            doc = aws("iam", "get-role-policy", "--role-name", name, "--policy-name", pol)["PolicyDocument"]
            yield f"role {name} inline {pol}", json.dumps(doc), "IDENTITY_POLICY", None
    for pol in aws("iam", "list-policies", "--scope", "Local", "--path-prefix", "/openflows/")["Policies"]:
        doc = aws("iam", "get-policy-version", "--policy-arn", pol["Arn"], "--version-id", pol["DefaultVersionId"])["PolicyVersion"]["Document"]
        yield f"policy {pol['PolicyName']}", json.dumps(doc), "IDENTITY_POLICY", None


def policies(plan_path, files, include_live):
    if plan_path:
        for rc in json.load(open(plan_path))["resource_changes"]:
            after = rc["change"]["after"] or {}
            # Values unknown until apply are skipped: --live covers deployed IAM roles and
            # policies, not S3 bucket policies.
            if after.get("policy"):
                kind = ("RESOURCE_POLICY", "AWS::S3::Bucket") if rc["type"] == "aws_s3_bucket_policy" else ("IDENTITY_POLICY", None)
                yield (rc["address"], after["policy"], *kind)
            if after.get("assume_role_policy"):
                yield rc["address"] + " trust", after["assume_role_policy"], "RESOURCE_POLICY", "AWS::IAM::AssumeRolePolicyDocument"
    if include_live:
        yield from live()
    for path in files:
        text = open(path).read()
        for placeholder, stand_in in PLACEHOLDERS.items():
            text = text.replace(placeholder, stand_in)
        yield os.path.basename(path), text, "IDENTITY_POLICY", None


def main():
    args = sys.argv[1:]
    include_live = "--live" in args
    args = [a for a in args if a != "--live"]
    plan_path = None
    if "--plan" in args:
        i = args.index("--plan")
        plan_path = args[i + 1]
        del args[i:i + 2]
    allow = json.load(open(os.path.join(HERE, "policy-findings-allowlist.json")))
    # Keyed by finding and statement ID, which is unique across our policies (plan and live names differ).
    accepted = {(a["issueCode"], a["sid"]) for a in allow}
    failed = 0
    for name, document, ptype, rtype in policies(plan_path, args, include_live):
        blocking = [f for f in validate(name, document, ptype, rtype)
                    if f[0] in BLOCKING and (f[1], f[2]) not in accepted]
        print(f"{'FAIL' if blocking else 'ok  '} {name} {blocking if blocking else ''}")
        failed += bool(blocking)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
