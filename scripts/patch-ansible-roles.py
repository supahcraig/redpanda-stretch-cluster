#!/usr/bin/env python3
"""
Patches the installed redpanda.cluster redpanda_broker role to fix a bug
in the 'Set cluster config' task where no_log: true on the config version
registration taints the variable as unsafe, causing changed_when to fail
with "Conditional is marked as unsafe" even when the underlying rpk commands
succeed. Also fixes the {{ }} in changed_when which Ansible refuses to evaluate.
"""
import os
import sys

path = os.path.expanduser(
    "~/.ansible/collections/ansible_collections/redpanda/cluster"
    "/roles/redpanda_broker/tasks/start-redpanda.yml"
)

if not os.path.exists(path):
    print(f"Role not found at {path} — run 'ansible-galaxy install -r requirements.yml' first")
    sys.exit(1)

with open(path) as f:
    content = f.read()

original = content

# Fix 1: remove no_log from the config_version registration task so the
# variable is not tainted as unsafe when used in changed_when below.
content = content.replace(
    "  register: config_version\n  changed_when: false\n  run_once: true\n  no_log: true",
    "  register: config_version\n  changed_when: false\n  run_once: true",
)

# Fix 2: replace {{ }} in changed_when with ~ concatenation so Ansible
# can evaluate it without "Conditional is marked as unsafe" error.
content = content.replace(
    '  changed_when: \'"New configuration version is {{ config_version.stdout|int() }}." not in result.stdout\'',
    '  changed_when: \'"New configuration version is " ~ (config_version.stdout | int) ~ "." not in result.stdout\'',
)

# Fix 3: remove no_log from the Set cluster config task so failures are visible.
content = content.replace(
    '  changed_when: \'"New configuration version is " ~ (config_version.stdout | int) ~ "." not in result.stdout\'\n  run_once: true\n  no_log: true',
    '  changed_when: \'"New configuration version is " ~ (config_version.stdout | int) ~ "." not in result.stdout\'\n  run_once: true',
)

if content == original:
    print("Role already patched or pattern not found — no changes made")
else:
    with open(path, "w") as f:
        f.write(content)
    print("Patched redpanda_broker role successfully")
