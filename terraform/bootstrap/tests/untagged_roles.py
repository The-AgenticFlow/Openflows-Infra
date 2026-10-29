#!/usr/bin/env python3
# Fail if an OpenFlows role has no Environment tag and is not a human role. The boundary limits
# secrets by the caller's Environment tag; the human roles carry their own policy instead (roles.tf).
# --plan <plan.json>: judge the roles a bootstrap change would create. Default: the live roles.
import json
import subprocess
import sys

HUMAN_ROLES = {"openflows-platform-admin", "openflows-readonly"}


def aws(*args):
    out = subprocess.run(["aws", *args, "--output", "json"], capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(out.stderr.strip())
    return json.loads(out.stdout)


def roles_from_plan(path):
    for rc in json.load(open(path))["resource_changes"]:
        if rc["type"] == "aws_iam_role":
            after = rc["change"]["after"] or {}
            yield after["name"], after.get("tags") or {}


def roles_from_account():
    for role in aws("iam", "list-roles", "--path-prefix", "/openflows/")["Roles"]:
        tags = aws("iam", "list-role-tags", "--role-name", role["RoleName"])["Tags"]
        yield role["RoleName"], {t["Key"]: t["Value"] for t in tags}


def main():
    roles = roles_from_plan(sys.argv[2]) if len(sys.argv) == 3 and sys.argv[1] == "--plan" else roles_from_account()
    failed = 0
    for name, tags in roles:
        bad = "Environment" not in tags and name not in HUMAN_ROLES
        print(f"{'FAIL' if bad else 'ok  '} {name}" + (" has no Environment tag and no secrets policy" if bad else ""))
        failed += bad
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
