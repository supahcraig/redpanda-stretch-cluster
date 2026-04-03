#!/usr/bin/env python3
"""
Creates or updates an rpk profile for the stretch cluster by writing
directly to ~/.config/rpk/rpk.yaml. Uses only stdlib — no pyyaml needed.

Usage:
    python3 scripts/create-rpk-profile.py <profile-name> <kafka-brokers> <admin-addresses>

Example:
    python3 scripts/create-rpk-profile.py stretch-cluster \
        "1.2.3.4:9092,5.6.7.8:9092" \
        "1.2.3.4:9644,5.6.7.8:9644"
"""
import sys
import os
import re

def main():
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(1)

    profile_name, brokers_str, admin_str = sys.argv[1], sys.argv[2], sys.argv[3]
    brokers = [b.strip() for b in brokers_str.split(",") if b.strip()]
    admin   = [a.strip() for a in admin_str.split(",") if a.strip()]

    config_dir  = os.path.expanduser("~/.config/rpk")
    config_path = os.path.join(config_dir, "rpk.yaml")
    os.makedirs(config_dir, exist_ok=True)

    # Read existing file so we can preserve other profiles
    existing_content = ""
    if os.path.exists(config_path):
        with open(config_path) as f:
            existing_content = f.read()

    # Build the profile YAML block
    broker_lines = "\n".join(f"        - {b}" for b in brokers)
    admin_lines  = "\n".join(f"        - {a}" for a in admin)
    profile_block = (
        f"    - name: {profile_name}\n"
        f"      kafka_api:\n"
        f"        brokers:\n"
        f"{broker_lines}\n"
        f"      admin_api:\n"
        f"        addresses:\n"
        f"{admin_lines}\n"
    )

    # If the profile already exists, replace its block; otherwise append
    profile_pattern = re.compile(
        rf"(    - name: {re.escape(profile_name)}\n(?:      .*\n|        .*\n)*)",
        re.MULTILINE,
    )

    if profile_pattern.search(existing_content):
        new_content = profile_pattern.sub(profile_block, existing_content)
        # Update current-profile line
        new_content = re.sub(
            r"^current-profile:.*$", f"current-profile: {profile_name}", new_content, flags=re.MULTILINE
        )
    else:
        # Build from scratch or append to existing profiles section
        if "profiles:" in existing_content:
            new_content = existing_content.rstrip() + "\n" + profile_block
            new_content = re.sub(
                r"^current-profile:.*$", f"current-profile: {profile_name}", new_content, flags=re.MULTILINE
            )
        else:
            new_content = (
                f"current-profile: {profile_name}\n"
                f"profiles:\n"
                f"{profile_block}"
            )

    with open(config_path, "w") as f:
        f.write(new_content)

    print(f"Profile '{profile_name}' written to {config_path}")
    print(f"  Kafka:  {brokers_str}")
    print(f"  Admin:  {admin_str}")

if __name__ == "__main__":
    main()
