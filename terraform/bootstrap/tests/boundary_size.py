#!/usr/bin/env python3
# Fail if the rendered permissions boundary exceeds IAM's managed-policy limit (6,144 characters,
# whitespace excluded). Caught here, not during the manual bootstrap apply.
import json
import sys

LIMIT = 6144


def main():
    path = sys.argv[1] if len(sys.argv) == 2 else "tests/rendered/boundary.json"
    size = len(json.dumps(json.load(open(path)), separators=(",", ":")))
    print(f"boundary is {size} of {LIMIT} characters, {LIMIT - size} free")
    sys.exit(1 if size > LIMIT else 0)


if __name__ == "__main__":
    main()
