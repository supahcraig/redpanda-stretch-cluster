# Redpanda Stretch Cluster

Terraform + Ansible automation for deploying a 5-broker [Redpanda](https://redpanda.com) stretch cluster across 3 AWS regions. Designed for fault-domain testing and OMB (OpenMessaging Benchmark) performance testing with partition leaders pinned to a preferred region.

**Default layout:** 2 brokers in us-east-1, 2 brokers in us-east-2, 1 tiebreaker broker in us-west-2 — one broker per AZ, rack awareness at the AZ level, RF=5.

---

## Architecture

- **Terraform** (`terraform/aws/`) generates an SSH key pair, provisions VPCs, security groups, EC2 instances, full-mesh VPC peering across all 3 regions, and a Redpanda Console host in the primary region, then writes `ansible/hosts.ini`.
- **Ansible** (`ansible/provision-cluster.yml`) bootstraps Redpanda on the broker inventory and installs Redpanda Console using the `redpanda.cluster` collection.
- Brokers advertise their **public IPs** so external clients and producers can connect directly.
- Inter-broker RPC flows over **private IPs** via VPC peering.
- Console connects to brokers via private IPs and is publicly accessible on port 8080.
- No TLS.

---

## Prerequisites

### Local tools

| Tool | Version |
|------|---------|
| Terraform | ≥ 1.3 |
| Ansible | ≥ 2.13 |
| AWS CLI | ≥ 2.x, configured with credentials |
| make | any (pre-installed on macOS/Linux) |

### AWS permissions

Your AWS credentials must have permission to create/destroy: VPCs, subnets, internet gateways, route tables, security groups, EC2 instances, EBS volumes, key pairs, and VPC peering connections — in all 3 target regions.

### Ansible Galaxy dependencies

From the repo root:

```bash
make install-deps
```

This installs Ansible Galaxy collections and applies a small patch to the `redpanda_broker` role that fixes a bug where `no_log: true` causes a false failure on cluster config tasks (the underlying `rpk` commands succeed but Ansible marks them failed due to an unsafe variable evaluation error).

---

## Quick Start

### 1. Configure

Edit `terraform/aws/terraform.tfvars` to review defaults. The committed values deploy the standard 5-broker layout; change `ssh_key_name`, instance type, or regions as needed.

### 2. Provision infrastructure

From the repo root:

```bash
make init
make apply
```

Terraform generates a 4096-bit RSA key pair, writes the private key to `~/.ssh/<ssh_key_name>` (mode 0600), registers the public key in every AWS region, creates all cloud resources, and writes `ansible/hosts.ini`.

### 3. Bootstrap Redpanda

```bash
make provision
```

The SSH key path is embedded in `ansible/hosts.ini` by Terraform, so no `--private-key` flag is needed.

To provision infrastructure and bootstrap Redpanda in one step:

```bash
make deploy
```

### 4. Verify

```bash
make output
```

This prints the Kafka bootstrap string, the Console URL (`http://<ip>:8080`), and the SSH key path.

---

## Configuration Reference

All variables are defined in `terraform/aws/variables.tf` with defaults. Override in `terraform/aws/terraform.tfvars`.

### Key variables

| Variable | Default | Description |
|----------|---------|-------------|
| `regions` | us-east-1 (2), us-east-2 (2), us-west-2 (1) | Ordered list of region configs. Each entry sets `name`, `broker_count`, `azs`, and `vpc_cidr`. Exactly 3 regions required. |
| `leader_preference` | `["us-east-1", "us-east-2", "us-west-2"]` | Regions ordered most → least preferred for partition leadership. Must match region names in `regions`. |
| `ssh_key_name` | `redpanda-stretch-cluster` | Name for the generated key pair (registered in all regions). Private key is written to `~/.ssh/<ssh_key_name>`. |
| `broker_instance_type` | `m7gd.2xlarge` | Graviton3 + local NVMe. |
| `machine_architecture` | `arm64` | Must match instance type (`arm64` for Graviton, `x86_64` for Intel/AMD). |
| `disk_type` | `instance_store` | `instance_store` or `ebs`. |
| `redpanda_version` | `latest` | Redpanda version to install. |
| `console_instance_type` | `t4g.small` | EC2 instance type for Redpanda Console (arm64, primary region only). |
| `deployment_prefix` | `rp-stretch` | Prefix applied to all AWS resource Name tags. |

### EBS disk mode

If `m7gd` instances are unavailable in your target region, switch to EBS:

```hcl
broker_instance_type = "m7g.2xlarge"   # no 'd' = no local NVMe
disk_type            = "ebs"
ebs_volume_size_gb   = 500
ebs_volume_type      = "gp3"           # gp3, io1, or io2
ebs_iops             = 16000
```

### Changing regions

To use different regions, update `terraform/aws/terraform.tfvars`. The module supports exactly 3 regions (fixed provider aliases `region0`, `region1`, `region2`). Each region must have as many AZs listed as `broker_count`:

```hcl
regions = [
  {
    name         = "eu-west-1"
    broker_count = 2
    azs          = ["eu-west-1a", "eu-west-1b"]
    vpc_cidr     = "10.0.0.0/16"
  },
  {
    name         = "eu-central-1"
    broker_count = 2
    azs          = ["eu-central-1a", "eu-central-1b"]
    vpc_cidr     = "10.1.0.0/16"
  },
  {
    name         = "eu-west-2"
    broker_count = 1
    azs          = ["eu-west-2a"]
    vpc_cidr     = "10.2.0.0/16"
  },
]
leader_preference = ["eu-west-1", "eu-central-1", "eu-west-2"]
```

---

## Rack Awareness & Leader Preference

Rack awareness is enabled with **rack = AZ name**. This ensures Redpanda places replicas across AZs (and therefore across regions) for maximum fault tolerance.

`leader_preference` maps to Redpanda's `default_leaders_preference.racks` setting. The module expands each region in the list to its configured AZs, producing an ordered AZ list. With the default config, partition leaders will prefer us-east-1 AZs, fall back to us-east-2 AZs, then us-west-2.

RF=5 is set for all topics including internal topics and schema registry.

---

## Teardown

```bash
make destroy
```

This destroys all AWS resources. The generated `ansible/hosts.ini` is gitignored and can be safely deleted. The generated private key at `~/.ssh/<ssh_key_name>` is not deleted automatically — remove it manually if desired.

---

## Dual-NVMe Instances (e.g. i3en)

For instances with multiple NVMe drives, create a RAID-0 array before running the playbook and set `data_device` in `terraform.tfvars` to the resulting md device path (e.g. `/dev/md0`). The playbook will format and mount that device.

---

## Repository Layout

```
stretch_cluster/
  Makefile                       # Task runner — all commands run from repo root
  ansible.cfg                    # Ansible config (inventory path, host key checking)
  requirements.yml               # Ansible Galaxy deps
  ansible/
    provision-cluster.yml        # Main playbook
  terraform/
    aws/
      main.tf                    # Providers, key generation, module calls, VPC peering, hosts.ini
      variables.tf
      outputs.tf
      terraform.tfvars           # Active configuration (edit before applying)
      hosts.ini.tpl              # Inventory template
    modules/
      aws/
        regional/                # Reusable per-region module (VPC, SG, EC2, EBS)
          main.tf
          variables.tf
          outputs.tf
  docs/
    superpowers/
      specs/                     # Design documents
      plans/                     # Implementation plans
```
