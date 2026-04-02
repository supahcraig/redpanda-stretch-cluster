# Stretch Redpanda Cluster — AWS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Terraform + Ansible automation that provisions a 5-broker stretch Redpanda cluster across 3 AWS regions with VPC peering, rack-aware replica placement, and region-level leader affinity, outputting a `hosts.ini` that the included Ansible playbook uses to bootstrap the cluster.

**Architecture:** A single Terraform root (`terraform/aws/`) with three fixed provider aliases drives a reusable regional module (`modules/aws/regional/`) that creates one VPC, security group, key pair, and N EC2 brokers per region. The root wires a full-mesh VPC peering and renders `ansible/hosts.ini` via `templatefile()`. An Ansible playbook adapted from `deployment-automation` bootstraps Redpanda using the generated inventory.

**Tech Stack:** Terraform ≥ 1.3, AWS provider ~5.0, Ansible, `redpanda.cluster` Ansible collection, Ubuntu 22.04 arm64 (default), `m7gd.2xlarge` (Graviton3 + local NVMe).

---

## File Map

```
stretch_cluster/
  .gitignore
  requirements.yml                          # Ansible galaxy deps (same as deployment-automation)
  terraform/
    aws/
      main.tf                               # providers, module calls, peering, hosts.ini
      variables.tf                          # all root variables with defaults
      outputs.tf                            # useful post-apply outputs
      terraform.tfvars                      # active values (committed, safe defaults)
      hosts.ini.tpl                         # templatefile() template
    modules/
      aws/
        regional/
          main.tf                           # VPC, subnets, IGW, SG, key pair, EC2, EBS
          variables.tf
          outputs.tf
  ansible/
    provision-cluster.yml                   # multi-region adapted playbook
    .gitignore                              # ignores hosts.ini
```

---

## Task 1: Repository Scaffolding

**Files:**
- Create: `.gitignore`
- Create: `requirements.yml`
- Create: `ansible/.gitignore`
- Create: `terraform/aws/` (empty dir placeholder)
- Create: `terraform/modules/aws/regional/` (empty dir placeholder)

- [ ] **Step 1: Create root .gitignore**

```
# Terraform
**/.terraform/
*.tfstate
*.tfstate.backup
*.tfplan
.terraform.lock.hcl

# Ansible generated inventory
ansible/hosts.ini

# OS
.DS_Store
```

File: `.gitignore`

- [ ] **Step 2: Create requirements.yml**

Same dependencies as `deployment-automation` — copy exactly:

```yaml
collections:
  - name: community.general
  - name: redpanda.cluster
    type: galaxy
  - name: ansible.posix
  - name: grafana.grafana
    version: 5.6.0
  - name: prometheus.prometheus

roles:
  - src: mrlesmithjr.mdadm
  - src: mrlesmithjr.squid
  - src: geerlingguy.node_exporter
```

File: `requirements.yml`

- [ ] **Step 3: Create ansible/.gitignore**

```
hosts.ini
```

File: `ansible/.gitignore`

- [ ] **Step 4: Create directory placeholders**

```bash
mkdir -p terraform/aws
mkdir -p terraform/modules/aws/regional
mkdir -p artifacts/collections
mkdir -p artifacts/roles
```

- [ ] **Step 5: Commit scaffolding**

```bash
git add .gitignore requirements.yml ansible/.gitignore terraform/ artifacts/
git commit -m "chore: initial repo scaffolding for stretch cluster"
```

---

## Task 2: Regional Module — Variables & Outputs

**Files:**
- Create: `terraform/modules/aws/regional/variables.tf`
- Create: `terraform/modules/aws/regional/outputs.tf`

Define the module's interface before any implementation. This locks in the contract between root and module.

- [ ] **Step 1: Write variables.tf**

```hcl
variable "region_name" {
  type        = string
  description = "AWS region name, e.g. us-east-1"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for this region's VPC, e.g. 10.0.0.0/16"
}

variable "azs" {
  type        = list(string)
  description = "Availability zones to use; one subnet and one broker per AZ"
}

variable "broker_count" {
  type        = number
  description = "Number of Redpanda brokers in this region"
}

variable "peer_cidrs" {
  type        = list(string)
  description = "VPC CIDRs from all other regions, used to open port 33145"
}

variable "deployment_prefix" {
  type        = string
  description = "Short prefix applied to all resource Name tags"
}

variable "ssh_key_name" {
  type        = string
  description = "AWS key pair name to register and attach to instances"
}

variable "public_key_path" {
  type        = string
  description = "Local path to the SSH public key file"
}

variable "broker_instance_type" {
  type        = string
  description = "EC2 instance type for brokers, must have local NVMe if disk_type=instance_store"
}

variable "machine_architecture" {
  type        = string
  description = "arm64 for Graviton (m7gd etc.), x86_64 for Intel/AMD"
  validation {
    condition     = contains(["arm64", "x86_64"], var.machine_architecture)
    error_message = "machine_architecture must be arm64 or x86_64"
  }
}

variable "disk_type" {
  type        = string
  description = "instance_store (local NVMe) or ebs (provisioned EBS volume)"
  default     = "instance_store"
  validation {
    condition     = contains(["instance_store", "ebs"], var.disk_type)
    error_message = "disk_type must be instance_store or ebs"
  }
}

variable "ebs_volume_size_gb" {
  type    = number
  default = 500
}

variable "ebs_volume_type" {
  type    = string
  default = "gp3"
}

variable "ebs_iops" {
  type    = number
  default = 16000
}

variable "data_device" {
  type        = string
  default     = "/dev/nvme1n1"
  description = "OS device path for the Redpanda data volume. /dev/nvme1n1 is correct for single-NVMe Nitro instances (m7gd, i4i). Dual-NVMe instances (i3en) require RAID-0 setup first."
}
```

File: `terraform/modules/aws/regional/variables.tf`

- [ ] **Step 2: Write outputs.tf**

```hcl
output "vpc_id" {
  value = aws_vpc.this.id
}

output "route_table_id" {
  value = aws_route_table.public.id
}

output "brokers" {
  description = "Per-broker info used to build hosts.ini and peering routes"
  value = [for i, inst in aws_instance.broker : {
    name       = "broker-${i}-${var.region_name}"
    public_ip  = inst.public_ip
    private_ip = inst.private_ip
    az         = inst.availability_zone
    region     = var.region_name
  }]
}
```

File: `terraform/modules/aws/regional/outputs.tf`

- [ ] **Step 3: Validate module structure**

Create a minimal stub `main.tf` so Terraform can parse the module:

```hcl
# Placeholder — implementation added in Tasks 3–6
```

File: `terraform/modules/aws/regional/main.tf`

```bash
cd terraform/modules/aws/regional
terraform init
terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 4: Commit module interface**

```bash
cd ../../../../
git add terraform/modules/aws/regional/
git commit -m "feat: regional module interface (variables + outputs)"
```

---

## Task 3: Regional Module — VPC, Subnets, IGW, Route Table

**Files:**
- Modify: `terraform/modules/aws/regional/main.tf`

- [ ] **Step 1: Write VPC + networking resources**

Replace the stub `main.tf` with:

```hcl
# ── AMI lookup ────────────────────────────────────────────────────────────────
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-*-22.04-${var.machine_architecture == "arm64" ? "arm64" : "amd64"}-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = [var.machine_architecture]
  }
}

# ── VPC ───────────────────────────────────────────────────────────────────────
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "${var.deployment_prefix}-${var.region_name}" }
}

# ── Subnets (one per AZ) ──────────────────────────────────────────────────────
resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "${var.deployment_prefix}-${var.azs[count.index]}" }
}

# ── Internet Gateway + Route Table ────────────────────────────────────────────
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.deployment_prefix}-${var.region_name}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "${var.deployment_prefix}-${var.region_name}" }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
```

File: `terraform/modules/aws/regional/main.tf`

- [ ] **Step 2: Validate**

```bash
cd terraform/modules/aws/regional
terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
cd ../../../../
git add terraform/modules/aws/regional/main.tf
git commit -m "feat: regional module VPC, subnets, IGW, route table"
```

---

## Task 4: Regional Module — Security Group & Key Pair

**Files:**
- Modify: `terraform/modules/aws/regional/main.tf`

- [ ] **Step 1: Append security group + key pair to main.tf**

Add the following to the bottom of `terraform/modules/aws/regional/main.tf`:

```hcl
# ── Security Group ────────────────────────────────────────────────────────────
resource "aws_security_group" "redpanda" {
  name        = "${var.deployment_prefix}-${var.region_name}-rp"
  description = "Redpanda stretch cluster broker"
  vpc_id      = aws_vpc.this.id

  # SSH — Ansible access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Kafka — client access
  ingress {
    description = "Kafka"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Admin API
  ingress {
    description = "Admin API"
    from_port   = 9644
    to_port     = 9644
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP Proxy (Pandaproxy)
  ingress {
    description = "HTTP Proxy"
    from_port   = 8082
    to_port     = 8082
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Internal RPC — inter-broker only, restricted to all VPC CIDRs
  ingress {
    description = "Internal RPC"
    from_port   = 33145
    to_port     = 33145
    protocol    = "tcp"
    cidr_blocks = concat([var.vpc_cidr], var.peer_cidrs)
  }

  # All traffic within own VPC
  ingress {
    description = "Intra-VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.deployment_prefix}-${var.region_name}-rp" }
}

# ── SSH Key Pair ──────────────────────────────────────────────────────────────
# Same name and key material registered in every region so one ~/.ssh entry works.
resource "aws_key_pair" "redpanda" {
  key_name   = var.ssh_key_name
  public_key = file(var.public_key_path)
}
```

- [ ] **Step 2: Validate**

```bash
cd terraform/modules/aws/regional
terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
cd ../../../../
git add terraform/modules/aws/regional/main.tf
git commit -m "feat: regional module security group and key pair"
```

---

## Task 5: Regional Module — EC2 Instances

**Files:**
- Modify: `terraform/modules/aws/regional/main.tf`

- [ ] **Step 1: Append EC2 instance resources to main.tf**

Add the following to the bottom of `terraform/modules/aws/regional/main.tf`:

```hcl
# ── EC2 Broker Instances ──────────────────────────────────────────────────────
# Brokers are distributed round-robin across the AZ list.
# element() wraps safely when broker_count > len(azs).
resource "aws_instance" "broker" {
  count         = var.broker_count
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.broker_instance_type
  subnet_id     = aws_subnet.public[count.index % length(aws_subnet.public)].id
  key_name      = aws_key_pair.redpanda.key_name

  vpc_security_group_ids      = [aws_security_group.redpanda.id]
  associate_public_ip_address = true

  # Surface local NVMe instance store to the OS (no-op for EBS path)
  dynamic "ephemeral_block_device" {
    for_each = var.disk_type == "instance_store" ? [1] : []
    content {
      device_name  = "/dev/sdb"
      virtual_name = "ephemeral0"
    }
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 50
    delete_on_termination = true
  }

  tags = {
    Name = "${var.deployment_prefix}-broker-${count.index}-${var.region_name}"
  }
}

# ── EBS Data Volumes (only when disk_type = "ebs") ────────────────────────────
resource "aws_ebs_volume" "broker_data" {
  count             = var.disk_type == "ebs" ? var.broker_count : 0
  availability_zone = aws_instance.broker[count.index].availability_zone
  type              = var.ebs_volume_type
  size              = var.ebs_volume_size_gb
  # gp3 and io2 accept explicit IOPS; gp2 does not
  iops = contains(["gp3", "io2"], var.ebs_volume_type) ? var.ebs_iops : null
  tags = {
    Name = "${var.deployment_prefix}-broker-${count.index}-${var.region_name}-data"
  }
}

resource "aws_volume_attachment" "broker_data" {
  count       = var.disk_type == "ebs" ? var.broker_count : 0
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.broker_data[count.index].id
  instance_id = aws_instance.broker[count.index].id
}
```

- [ ] **Step 2: Validate the complete regional module**

```bash
cd terraform/modules/aws/regional
terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
cd ../../../../
git add terraform/modules/aws/regional/main.tf
git commit -m "feat: regional module EC2 instances with instance_store and EBS paths"
```

---

## Task 6: Root Module — variables.tf

**Files:**
- Create: `terraform/aws/variables.tf`

- [ ] **Step 1: Write variables.tf**

```hcl
variable "regions" {
  description = "Ordered list of region configs. Index 0-2 map to provider aliases region0/region1/region2."
  type = list(object({
    name         = string
    broker_count = number
    azs          = list(string)
    vpc_cidr     = string
  }))
  default = [
    {
      name         = "us-east-1"
      broker_count = 2
      azs          = ["us-east-1a", "us-east-1b"]
      vpc_cidr     = "10.0.0.0/16"
    },
    {
      name         = "us-east-2"
      broker_count = 2
      azs          = ["us-east-2a", "us-east-2b"]
      vpc_cidr     = "10.1.0.0/16"
    },
    {
      name         = "us-west-2"
      broker_count = 1
      azs          = ["us-west-2a"]
      vpc_cidr     = "10.2.0.0/16"
    },
  ]
}

variable "deployment_prefix" {
  type        = string
  default     = "rp-stretch"
  description = "Short prefix applied to all resource Name tags"
}

variable "ssh_key_name" {
  type        = string
  default     = "redpanda-stretch-cluster"
  description = "Key pair name registered in all 3 regions with the same public key material"
}

variable "public_key_path" {
  type        = string
  default     = "~/.ssh/id_rsa.pub"
  description = "Local path to SSH public key"
}

variable "ssh_private_key_path" {
  type        = string
  default     = "~/.ssh/id_rsa"
  description = "Local path to SSH private key — written into hosts.ini for Ansible"
}

variable "broker_instance_type" {
  type        = string
  default     = "m7gd.2xlarge"
  description = "m7gd.2xlarge = Graviton3 + local NVMe. Use m7g.2xlarge + disk_type=ebs in regions where m7gd unavailable."
}

variable "machine_architecture" {
  type        = string
  default     = "arm64"
  description = "arm64 for Graviton (m7gd). Must match broker_instance_type."
}

variable "disk_type" {
  type        = string
  default     = "instance_store"
  description = "instance_store or ebs"
}

variable "ebs_volume_size_gb" {
  type    = number
  default = 500
}

variable "ebs_volume_type" {
  type    = string
  default = "gp3"
}

variable "ebs_iops" {
  type    = number
  default = 16000
}

variable "data_device" {
  type        = string
  default     = "/dev/nvme1n1"
  description = "OS device path for the data volume. Correct for single-NVMe Nitro instances (m7gd, i4i). Dual-NVMe (i3en) requires RAID-0 first."
}

variable "leader_preference" {
  type        = list(string)
  default     = ["us-east-1", "us-east-2", "us-west-2"]
  description = "Regions ordered from most to least preferred for partition leadership. Must match names in var.regions."
}

variable "redpanda_version" {
  type    = string
  default = "latest"
}
```

File: `terraform/aws/variables.tf`

- [ ] **Step 2: Commit**

```bash
git add terraform/aws/variables.tf
git commit -m "feat: root module variables"
```

---

## Task 7: Root Module — Providers, Module Instantiations, and Locals

**Files:**
- Create: `terraform/aws/main.tf`
- Create: `terraform/aws/outputs.tf`

- [ ] **Step 1: Write main.tf — terraform block, providers, locals, module calls**

```hcl
terraform {
  required_version = ">=1.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.1"
    }
  }
}

# ── Providers (fixed aliases, variable-driven regions) ────────────────────────
provider "aws" { alias = "region0"; region = var.regions[0].name }
provider "aws" { alias = "region1"; region = var.regions[1].name }
provider "aws" { alias = "region2"; region = var.regions[2].name }

# ── Locals ────────────────────────────────────────────────────────────────────
locals {
  all_cidrs = [for r in var.regions : r.vpc_cidr]

  # Expand leader_preference regions into ordered AZ list for Redpanda rack config.
  # E.g. ["us-east-1","us-east-2"] → ["us-east-1a","us-east-1b","us-east-2a","us-east-2b"]
  leader_rack_order = flatten([
    for region_name in var.leader_preference : [
      for r in var.regions : r.azs
      if r.name == region_name
    ]
  ])
}

# ── Regional Modules ──────────────────────────────────────────────────────────
module "region0" {
  source               = "../modules/aws/regional"
  region_name          = var.regions[0].name
  vpc_cidr             = var.regions[0].vpc_cidr
  azs                  = var.regions[0].azs
  broker_count         = var.regions[0].broker_count
  peer_cidrs           = [var.regions[1].vpc_cidr, var.regions[2].vpc_cidr]
  deployment_prefix    = var.deployment_prefix
  ssh_key_name         = var.ssh_key_name
  public_key_path      = var.public_key_path
  broker_instance_type = var.broker_instance_type
  machine_architecture = var.machine_architecture
  disk_type            = var.disk_type
  ebs_volume_size_gb   = var.ebs_volume_size_gb
  ebs_volume_type      = var.ebs_volume_type
  ebs_iops             = var.ebs_iops
  data_device          = var.data_device
  providers            = { aws = aws.region0 }
}

module "region1" {
  source               = "../modules/aws/regional"
  region_name          = var.regions[1].name
  vpc_cidr             = var.regions[1].vpc_cidr
  azs                  = var.regions[1].azs
  broker_count         = var.regions[1].broker_count
  peer_cidrs           = [var.regions[0].vpc_cidr, var.regions[2].vpc_cidr]
  deployment_prefix    = var.deployment_prefix
  ssh_key_name         = var.ssh_key_name
  public_key_path      = var.public_key_path
  broker_instance_type = var.broker_instance_type
  machine_architecture = var.machine_architecture
  disk_type            = var.disk_type
  ebs_volume_size_gb   = var.ebs_volume_size_gb
  ebs_volume_type      = var.ebs_volume_type
  ebs_iops             = var.ebs_iops
  data_device          = var.data_device
  providers            = { aws = aws.region1 }
}

module "region2" {
  source               = "../modules/aws/regional"
  region_name          = var.regions[2].name
  vpc_cidr             = var.regions[2].vpc_cidr
  azs                  = var.regions[2].azs
  broker_count         = var.regions[2].broker_count
  peer_cidrs           = [var.regions[0].vpc_cidr, var.regions[1].vpc_cidr]
  deployment_prefix    = var.deployment_prefix
  ssh_key_name         = var.ssh_key_name
  public_key_path      = var.public_key_path
  broker_instance_type = var.broker_instance_type
  machine_architecture = var.machine_architecture
  disk_type            = var.disk_type
  ebs_volume_size_gb   = var.ebs_volume_size_gb
  ebs_volume_type      = var.ebs_volume_type
  ebs_iops             = var.ebs_iops
  data_device          = var.data_device
  providers            = { aws = aws.region2 }
}
```

File: `terraform/aws/main.tf`

- [ ] **Step 2: Write outputs.tf**

```hcl
output "broker_public_ips" {
  description = "All broker public IPs by name"
  value = {
    for b in concat(module.region0.brokers, module.region1.brokers, module.region2.brokers) :
    b.name => b.public_ip
  }
}

output "broker_private_ips" {
  description = "All broker private IPs by name"
  value = {
    for b in concat(module.region0.brokers, module.region1.brokers, module.region2.brokers) :
    b.name => b.private_ip
  }
}

output "bootstrap_brokers" {
  description = "Kafka bootstrap string using public IPs"
  value = join(",", [
    for b in concat(module.region0.brokers, module.region1.brokers, module.region2.brokers) :
    "${b.public_ip}:9092"
  ])
}

output "leader_rack_order" {
  description = "Ordered AZ list used for default_leaders_preference"
  value = local.leader_rack_order
}
```

File: `terraform/aws/outputs.tf`

- [ ] **Step 3: Run terraform init and validate**

```bash
cd terraform/aws
terraform init
terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 4: Commit**

```bash
cd ../../
git add terraform/aws/main.tf terraform/aws/outputs.tf
git commit -m "feat: root module providers, regional module instantiations, outputs"
```

---

## Task 8: Root Module — VPC Peering Full Mesh

**Files:**
- Modify: `terraform/aws/main.tf`

Three connections: r0↔r1, r0↔r2, r1↔r2. Each needs a connection resource (requester), an accepter resource (different provider), and route table entries in both VPCs.

- [ ] **Step 1: Append peering to terraform/aws/main.tf**

Add the following after the module blocks:

```hcl
# ── VPC Peering: region0 ↔ region1 ───────────────────────────────────────────
resource "aws_vpc_peering_connection" "r0_r1" {
  provider    = aws.region0
  vpc_id      = module.region0.vpc_id
  peer_vpc_id = module.region1.vpc_id
  peer_region = var.regions[1].name
  auto_accept = false
  tags        = { Name = "${var.deployment_prefix}-r0-r1" }
}

resource "aws_vpc_peering_connection_accepter" "r0_r1" {
  provider                  = aws.region1
  vpc_peering_connection_id = aws_vpc_peering_connection.r0_r1.id
  auto_accept               = true
  tags                      = { Name = "${var.deployment_prefix}-r0-r1" }
}

resource "aws_route" "r0_to_r1" {
  provider                  = aws.region0
  route_table_id            = module.region0.route_table_id
  destination_cidr_block    = var.regions[1].vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.r0_r1.id
}

resource "aws_route" "r1_to_r0" {
  provider                  = aws.region1
  route_table_id            = module.region1.route_table_id
  destination_cidr_block    = var.regions[0].vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.r0_r1.id
}

# ── VPC Peering: region0 ↔ region2 ───────────────────────────────────────────
resource "aws_vpc_peering_connection" "r0_r2" {
  provider    = aws.region0
  vpc_id      = module.region0.vpc_id
  peer_vpc_id = module.region2.vpc_id
  peer_region = var.regions[2].name
  auto_accept = false
  tags        = { Name = "${var.deployment_prefix}-r0-r2" }
}

resource "aws_vpc_peering_connection_accepter" "r0_r2" {
  provider                  = aws.region2
  vpc_peering_connection_id = aws_vpc_peering_connection.r0_r2.id
  auto_accept               = true
  tags                      = { Name = "${var.deployment_prefix}-r0-r2" }
}

resource "aws_route" "r0_to_r2" {
  provider                  = aws.region0
  route_table_id            = module.region0.route_table_id
  destination_cidr_block    = var.regions[2].vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.r0_r2.id
}

resource "aws_route" "r2_to_r0" {
  provider                  = aws.region2
  route_table_id            = module.region2.route_table_id
  destination_cidr_block    = var.regions[0].vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.r0_r2.id
}

# ── VPC Peering: region1 ↔ region2 ───────────────────────────────────────────
resource "aws_vpc_peering_connection" "r1_r2" {
  provider    = aws.region1
  vpc_id      = module.region1.vpc_id
  peer_vpc_id = module.region2.vpc_id
  peer_region = var.regions[2].name
  auto_accept = false
  tags        = { Name = "${var.deployment_prefix}-r1-r2" }
}

resource "aws_vpc_peering_connection_accepter" "r1_r2" {
  provider                  = aws.region2
  vpc_peering_connection_id = aws_vpc_peering_connection.r1_r2.id
  auto_accept               = true
  tags                      = { Name = "${var.deployment_prefix}-r1-r2" }
}

resource "aws_route" "r1_to_r2" {
  provider                  = aws.region1
  route_table_id            = module.region1.route_table_id
  destination_cidr_block    = var.regions[2].vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.r1_r2.id
}

resource "aws_route" "r2_to_r1" {
  provider                  = aws.region2
  route_table_id            = module.region2.route_table_id
  destination_cidr_block    = var.regions[1].vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.r1_r2.id
}
```

- [ ] **Step 2: Validate**

```bash
cd terraform/aws
terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
cd ../../
git add terraform/aws/main.tf
git commit -m "feat: VPC peering full mesh (r0↔r1, r0↔r2, r1↔r2)"
```

---

## Task 9: Root Module — hosts.ini Template and local_file

**Files:**
- Create: `terraform/aws/hosts.ini.tpl`
- Modify: `terraform/aws/main.tf`

- [ ] **Step 1: Write hosts.ini.tpl**

```
[redpanda]
%{ for b in brokers ~}
${b.name} ansible_host=${b.public_ip} private_ip=${b.private_ip} rack=${b.az} data_device=${data_device} ansible_user=ubuntu
%{ endfor ~}

[all:vars]
ansible_ssh_private_key_file=${ssh_private_key_path}
redpanda_version=${redpanda_version}
seeds=${join(",", [for b in brokers : b.private_ip])}
redpanda_leader_rack_preference=${join(",", leader_rack_order)}
```

File: `terraform/aws/hosts.ini.tpl`

- [ ] **Step 2: Append local_file resource to terraform/aws/main.tf**

Add after the peering blocks:

```hcl
# ── hosts.ini Generation ──────────────────────────────────────────────────────
locals {
  all_brokers = concat(module.region0.brokers, module.region1.brokers, module.region2.brokers)
}

resource "local_file" "hosts_ini" {
  content = templatefile("${path.module}/hosts.ini.tpl", {
    brokers                  = local.all_brokers
    data_device              = var.data_device
    ssh_private_key_path     = var.ssh_private_key_path
    redpanda_version         = var.redpanda_version
    leader_rack_order        = local.leader_rack_order
  })
  filename        = "${path.module}/../../ansible/hosts.ini"
  file_permission = "0644"
}
```

- [ ] **Step 3: Create terraform.tfvars with active defaults**

```hcl
# Active configuration — edit before applying
# Defaults match the design spec; override as needed.

deployment_prefix    = "rp-stretch"
ssh_key_name         = "redpanda-stretch-cluster"
public_key_path      = "~/.ssh/id_rsa.pub"
ssh_private_key_path = "~/.ssh/id_rsa"
broker_instance_type = "m7gd.2xlarge"
machine_architecture = "arm64"
disk_type            = "instance_store"
redpanda_version     = "latest"

leader_preference = ["us-east-1", "us-east-2", "us-west-2"]

regions = [
  {
    name         = "us-east-1"
    broker_count = 2
    azs          = ["us-east-1a", "us-east-1b"]
    vpc_cidr     = "10.0.0.0/16"
  },
  {
    name         = "us-east-2"
    broker_count = 2
    azs          = ["us-east-2a", "us-east-2b"]
    vpc_cidr     = "10.1.0.0/16"
  },
  {
    name         = "us-west-2"
    broker_count = 1
    azs          = ["us-west-2a"]
    vpc_cidr     = "10.2.0.0/16"
  },
]
```

File: `terraform/aws/terraform.tfvars`

- [ ] **Step 4: Final validate of complete root module**

```bash
cd terraform/aws
terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 5: Commit**

```bash
cd ../../
git add terraform/aws/hosts.ini.tpl terraform/aws/main.tf terraform/aws/terraform.tfvars
git commit -m "feat: hosts.ini template and local_file generation"
```

---

## Task 10: Ansible Playbook

**Files:**
- Create: `ansible/provision-cluster.yml`

Adapted from `../deployment-automation/ansible/provision-cluster.yml`. Key additions:
- All brokers' private IPs used as seeds (dynamically built from inventory)
- Rack set per-broker from the `rack` host variable in hosts.ini
- Cluster-wide properties: RF=5, rack awareness, leader preference
- Explicit disk format + mount before Redpanda install

- [ ] **Step 1: Write ansible/provision-cluster.yml**

```yaml
---
# Provisions a stretch Redpanda cluster across multiple regions.
# Run after `terraform apply` has generated ansible/hosts.ini.
#
# Usage:
#   ansible-playbook ansible/provision-cluster.yml --private-key ~/.ssh/id_rsa
#
- name: Provision stretch Redpanda cluster
  hosts: redpanda
  become: true
  vars:
    advertise_public_ips: true

  tasks:
    # ── System prereqs & sysctl ───────────────────────────────────────────────
    - name: Install system prerequisites
      ansible.builtin.include_role:
        name: redpanda.cluster.system_setup

    - name: Apply sysctl settings
      ansible.builtin.include_role:
        name: redpanda.cluster.sysctl_setup

    # ── Disk setup ────────────────────────────────────────────────────────────
    # Format the data volume as XFS and mount at /var/lib/redpanda/data.
    # data_device is set per-host in hosts.ini (default: /dev/nvme1n1).
    # For dual-NVMe instances (i3en), create a RAID-0 array first and set
    # data_device to the md device path before running this playbook.
    - name: Create Redpanda data directory
      ansible.builtin.file:
        path: /var/lib/redpanda/data
        state: directory
        mode: "0755"
        owner: redpanda
        group: redpanda
      ignore_errors: true   # user may not exist yet; broker role creates it

    - name: Format data volume as XFS
      community.general.filesystem:
        fstype: xfs
        dev: "{{ data_device | default('/dev/nvme1n1') }}"
        force: false   # never reformat if already formatted

    - name: Mount data volume
      ansible.posix.mount:
        path: /var/lib/redpanda/data
        src: "{{ data_device | default('/dev/nvme1n1') }}"
        fstype: xfs
        opts: defaults,noatime
        state: mounted

    - name: Ensure Redpanda data directory ownership
      ansible.builtin.file:
        path: /var/lib/redpanda/data
        state: directory
        mode: "0755"
        owner: redpanda
        group: redpanda

    # ── Build seed list from inventory ───────────────────────────────────────
    # All brokers' private IPs as seeds. Private IPs are reachable cross-region
    # via VPC peering. Using set_fact avoids complex Jinja2 filter chains.
    - name: Collect broker private IPs for seeds
      ansible.builtin.set_fact:
        _broker_seeds: >-
          {{
            groups['redpanda']
            | map('extract', hostvars, 'private_ip')
            | list
          }}

    # ── Redpanda broker install ───────────────────────────────────────────────
    - name: Install and start Redpanda
      ansible.builtin.include_role:
        name: redpanda.cluster.redpanda_broker
      vars:
        redpanda_version: "{{ redpanda_version | default('latest') }}"
        seeds: "{{ _broker_seeds }}"
        # Per-broker rack = AZ name, set via hosts.ini host variable
        redpanda_rack: "{{ rack }}"
        # Cluster-wide settings applied on first broker bootstrap
        redpanda_cluster_properties:
          enable_rack_awareness: true
          default_topic_replications: 5
          internal_topic_replication_factor: 5
          default_leaders_preference:
            # Ordered AZ list derived from leader_preference in Terraform.
            # Passed through hosts.ini as comma-separated string.
            racks: "{{ redpanda_leader_rack_preference.split(',') }}"
      when: not skip_node | default(false) | bool
```

File: `ansible/provision-cluster.yml`

- [ ] **Step 2: Syntax check the playbook**

```bash
export ANSIBLE_COLLECTIONS_PATHS=$PWD/artifacts/collections
export ANSIBLE_ROLES_PATH=$PWD/artifacts/roles
# Install deps if not already done
ansible-galaxy collection install -r requirements.yml --force -p $ANSIBLE_COLLECTIONS_PATHS
ansible-galaxy role install -r requirements.yml --force -p $ANSIBLE_ROLES_PATH
# Syntax check against a dummy inventory
ansible-playbook ansible/provision-cluster.yml --syntax-check -i /dev/null
```

Expected: `playbook: ansible/provision-cluster.yml` with no errors.

- [ ] **Step 3: Commit**

```bash
git add ansible/provision-cluster.yml
git commit -m "feat: stretch cluster Ansible playbook with rack awareness and RF=5"
```

---

## Task 11: End-to-End Deploy and Verify

This task provisions real infrastructure. Estimated cost: ~$2–4/hour for 5 `m7gd.2xlarge` instances across 3 regions. **Destroy immediately after testing.**

- [ ] **Step 1: Initialize Terraform**

```bash
cd terraform/aws
terraform init
```

Expected: `Terraform has been successfully initialized!`

- [ ] **Step 2: Review the plan**

```bash
terraform plan
```

Review the output. You should see:
- 3 VPCs (one per region)
- 5 EC2 instances total (2 in us-east-1, 2 in us-east-2, 1 in us-west-2)
- 3 key pairs (same name, all 3 regions)
- 3 security groups
- 3 peering connections + 6 accepters/routes
- 1 local_file (hosts.ini)

- [ ] **Step 3: Apply**

```bash
terraform apply
```

Type `yes` when prompted. Takes ~5–7 minutes.

- [ ] **Step 4: Verify hosts.ini was generated**

```bash
cat ../../ansible/hosts.ini
```

Expected output shape:
```
[redpanda]
broker-0-us_east_1 ansible_host=1.2.3.4 private_ip=10.0.0.x rack=us-east-1a data_device=/dev/nvme1n1 ansible_user=ubuntu
broker-1-us_east_1 ansible_host=1.2.3.5 private_ip=10.0.0.y rack=us-east-1b data_device=/dev/nvme1n1 ansible_user=ubuntu
broker-0-us_east_2 ansible_host=...
broker-1-us_east_2 ansible_host=...
broker-0-us_west_2 ansible_host=...

[all:vars]
ansible_ssh_private_key_file=~/.ssh/id_rsa
redpanda_version=latest
seeds=10.0.0.x,10.0.0.y,...
redpanda_leader_rack_preference=us-east-1a,us-east-1b,us-east-2a,us-east-2b,us-west-2a
```

- [ ] **Step 5: Wait for instances to be SSH-ready**

```bash
# Spot check one broker — grab its IP from hosts.ini
ssh -i ~/.ssh/id_rsa ubuntu@<any_public_ip> "echo OK"
```

Expected: `OK`

- [ ] **Step 6: Install Ansible dependencies (one-time)**

```bash
cd ../../
export ANSIBLE_COLLECTIONS_PATHS=$PWD/artifacts/collections
export ANSIBLE_ROLES_PATH=$PWD/artifacts/roles
ansible-galaxy collection install -r requirements.yml --force -p $ANSIBLE_COLLECTIONS_PATHS
ansible-galaxy role install -r requirements.yml --force -p $ANSIBLE_ROLES_PATH
```

- [ ] **Step 7: Run the Ansible playbook**

```bash
export ANSIBLE_INVENTORY=$PWD/ansible/hosts.ini
ansible-playbook ansible/provision-cluster.yml --private-key ~/.ssh/id_rsa
```

Expected: All tasks complete with no `failed` or `unreachable` counts.

- [ ] **Step 8: Verify cluster health**

SSH into any broker and check cluster status:

```bash
ssh -i ~/.ssh/id_rsa ubuntu@<any_public_ip>
rpk cluster info
```

Expected: All 5 brokers listed with status `alive`.

```bash
rpk cluster health
```

Expected: `Healthy: true`

- [ ] **Step 9: Verify rack awareness and RF**

```bash
rpk cluster config get enable_rack_awareness
# Expected: true

rpk cluster config get default_topic_replications
# Expected: 5

rpk topic create test-topic --partitions 5 --replicas 5
rpk topic describe test-topic
# Confirm replicas spread across all 5 AZ racks

rpk topic delete test-topic
```

- [ ] **Step 10: Verify leader preference**

```bash
rpk cluster config get default_leaders_preference
# Expected: racks: [us-east-1a, us-east-1b, us-east-2a, us-east-2b, us-west-2a]
```

- [ ] **Step 11: Destroy infrastructure**

```bash
cd terraform/aws
terraform destroy
```

Type `yes`. Verify all resources are destroyed.

- [ ] **Step 12: Final commit**

```bash
cd ../../
git add -A
git commit -m "feat: complete stretch cluster AWS implementation — tested end-to-end"
```

---

## Notes

**Changing regions:** Update `var.regions` list in `terraform.tfvars`. Provider aliases `region0/1/2` always map to `var.regions[0/1/2].name` — the alias names don't change, only the region values.

**Switching to EBS:** Set `disk_type = "ebs"` and `broker_instance_type = "m7g.2xlarge"` (drop the `d`). The regional module provisions `aws_ebs_volume` + `aws_volume_attachment` automatically.

**Adding monitoring/clients:** Follow the same pattern as `deployment-automation` — add a `[monitor]` group to `hosts.ini.tpl` pointing at a designated broker (or new instance) and run `deploy-monitor.yml`.

**Azure/GCP:** Create `terraform/azure/` and `terraform/gcp/` roots using this spec as reference. The `ansible/` directory is shared — no changes needed there.
