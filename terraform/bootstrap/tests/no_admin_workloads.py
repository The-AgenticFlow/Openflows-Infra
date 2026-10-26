#!/usr/bin/env python3
# Fail if any OpenFlows role that an AWS service assumes (pods, nodes, EKS, flow logs)
# holds administrator rights. Only GitHub deployers and MFA-gated humans may be admins.
# --plan <plan.json>: environment roots never grant admin, so any admin grant there fails.
import json
import subprocess
import sys

ADMIN_POLICIES = {"arn:aws:iam::aws:policy/AdministratorAccess", "arn:aws:iam::aws:policy/PowerUserAccess"}


def aws(*args):
    out = subprocess.run(["aws", *args, "--output", "json"], capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(out.stderr.strip())
    return json.loads(out.stdout)


def service_principals(trust):
    found = []
    for st in trust["Statement"]:
        services = st.get("Principal", {}).get("Service", [])
        found += [services] if isinstance(services, str) else services
    return found


def grants_everything(doc):
    for st in doc["Statement"] if isinstance(doc["Statement"], list) else [doc["Statement"]]:
        actions = st.get("Action", [])
        actions = [actions] if isinstance(actions, str) else actions
        if st.get("Effect") == "Allow" and "*" in actions:
            return True
    return False


def check_plan(path):
    failed = 0
    for rc in json.load(open(path))["resource_changes"]:
        after = rc["change"]["after"] or {}
        bad = (rc["type"] == "aws_iam_role_policy_attachment" and after.get("policy_arn") in ADMIN_POLICIES) or \
              (rc["type"] in ("aws_iam_role_policy", "aws_iam_policy") and after.get("policy") and grants_everything(json.loads(after["policy"])))
        if bad:
            print(f"FAIL {rc['address']} grants administrator rights")
            failed += 1
    print(f"plan: {failed} administrator grants")
    return failed


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--plan":
        sys.exit(1 if check_plan(sys.argv[2]) else 0)
    failed = 0
    for role in aws("iam", "list-roles", "--path-prefix", "/openflows/")["Roles"]:
        name = role["RoleName"]
        services = service_principals(role["AssumeRolePolicyDocument"])
        if not services:
            continue
        attached = {p["PolicyArn"] for p in aws("iam", "list-attached-role-policies", "--role-name", name)["AttachedPolicies"]}
        docs = [aws("iam", "get-role-policy", "--role-name", name, "--policy-name", p)["PolicyDocument"]
                for p in aws("iam", "list-role-policies", "--role-name", name)["PolicyNames"]]
        for arn in attached:
            version = aws("iam", "get-policy", "--policy-arn", arn)["Policy"]["DefaultVersionId"]
            docs.append(aws("iam", "get-policy-version", "--policy-arn", arn, "--version-id", version)["PolicyVersion"]["Document"])
        admin = bool(attached & ADMIN_POLICIES) or any(grants_everything(d) for d in docs)
        print(f"{'FAIL' if admin else 'ok  '} {name} ({', '.join(services)})")
        failed += admin
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
