#!/usr/bin/env python3
# Run expected allow/deny cases through the IAM policy simulator (evaluation only, changes
# nothing). --principal tests a live role's real policies instead of the files. Exits 1 on mismatch.
import json
import os
import subprocess
import sys

USAGE = "usage: iam_policy_tests.py cases.json [--principal <role-or-user-arn>]"


def load(path, base):
    with open(os.path.join(base, path)) as f:
        return json.dumps(json.load(f))


def simulate(identity, boundary, case, principal=None):
    request = {
        "ActionNames": [case["action"]],
        "ResourceArns": [case.get("resource", "*")],
        "ContextEntries": [
            {"ContextKeyName": k, "ContextKeyValues": v if isinstance(v, list) else [v], "ContextKeyType": "string"}
            for k, v in case.get("context", {}).items()
        ],
    }
    if principal:
        request["PolicySourceArn"] = principal
        command = "simulate-principal-policy"
    else:
        request["PolicyInputList"] = identity
        if boundary:
            request["PermissionsBoundaryPolicyInputList"] = boundary
        command = "simulate-custom-policy"
    out = subprocess.run(
        ["aws", "iam", command, "--cli-input-json", json.dumps(request), "--output", "json"],
        capture_output=True, text=True, env={**os.environ, "AWS_PAGER": ""},
    )
    if out.returncode != 0:
        sys.exit(f"simulation failed for {case['name']}: {out.stderr.strip()}")
    decision = json.loads(out.stdout)["EvaluationResults"][0]["EvalDecision"]
    return "allow" if decision == "allowed" else "deny", decision


def main():
    args = sys.argv[1:]
    principal = None
    if "--principal" in args:
        i = args.index("--principal")
        principal = args[i + 1] if i + 1 < len(args) else sys.exit(USAGE)
        del args[i:i + 2]
    if len(args) != 1:
        sys.exit(USAGE)
    path = args[0]
    base = os.path.dirname(os.path.abspath(path))
    with open(path) as f:
        spec = json.load(f)
    identity = [] if principal else [load(p, base) for p in spec["identity_policies"]]
    boundary = [] if principal else [load(p, base) for p in spec.get("boundary_policies", [])]

    failures = 0
    for case in spec["cases"]:
        got, raw = simulate(identity, boundary, case, principal)
        ok = got == case["expect"]
        failures += not ok
        print(f"{'PASS' if ok else 'FAIL'}  expect={case['expect']:<5} got={raw:<12} {case['name']}")
    print(f"\n{len(spec['cases']) - failures}/{len(spec['cases'])} cases passed")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
