#!/usr/bin/env python3
# Run expected allow/deny cases through `aws iam simulate-custom-policy` (evaluation only,
# changes nothing). Usage: iam_policy_tests.py cases.json ; exits 1 on any mismatch.
import json
import os
import subprocess
import sys

USAGE = "usage: iam_policy_tests.py cases.json"


def load(path, base):
    with open(os.path.join(base, path)) as f:
        return json.dumps(json.load(f))


def simulate(identity, boundary, case):
    request = {
        "PolicyInputList": identity,
        "ActionNames": [case["action"]],
        "ResourceArns": [case.get("resource", "*")],
        "ContextEntries": [
            {"ContextKeyName": k, "ContextKeyValues": v if isinstance(v, list) else [v], "ContextKeyType": "string"}
            for k, v in case.get("context", {}).items()
        ],
    }
    if boundary:
        request["PermissionsBoundaryPolicyInputList"] = boundary
    out = subprocess.run(
        ["aws", "iam", "simulate-custom-policy", "--cli-input-json", json.dumps(request), "--output", "json"],
        capture_output=True, text=True, env={**os.environ, "AWS_PAGER": ""},
    )
    if out.returncode != 0:
        sys.exit(f"simulation failed for {case['name']}: {out.stderr.strip()}")
    decision = json.loads(out.stdout)["EvaluationResults"][0]["EvalDecision"]
    return "allow" if decision == "allowed" else "deny", decision


def main():
    if len(sys.argv) != 2:
        sys.exit(USAGE)
    path = sys.argv[1]
    base = os.path.dirname(os.path.abspath(path))
    with open(path) as f:
        spec = json.load(f)
    identity = [load(p, base) for p in spec["identity_policies"]]
    boundary = [load(p, base) for p in spec.get("boundary_policies", [])]

    failures = 0
    for case in spec["cases"]:
        got, raw = simulate(identity, boundary, case)
        ok = got == case["expect"]
        failures += not ok
        print(f"{'PASS' if ok else 'FAIL'}  expect={case['expect']:<5} got={raw:<12} {case['name']}")
    print(f"\n{len(spec['cases']) - failures}/{len(spec['cases'])} cases passed")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
