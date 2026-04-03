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
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# ── SSH Key Generation ────────────────────────────────────────────────────────
# Generates a 4096-bit RSA key pair. Private key is written to ~/.ssh/<ssh_key_name>.
# Public key material is registered in every AWS region under the same key name.
resource "tls_private_key" "redpanda" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.redpanda.private_key_pem
  filename        = pathexpand("~/.ssh/${var.ssh_key_name}")
  file_permission = "0600"
}

locals {
  ssh_private_key_path = pathexpand("~/.ssh/${var.ssh_key_name}")
}

# ── Providers (fixed aliases, variable-driven regions) ────────────────────────
provider "aws" {
  alias  = "region0"
  region = var.regions[0].name
}

provider "aws" {
  alias  = "region1"
  region = var.regions[1].name
}

provider "aws" {
  alias  = "region2"
  region = var.regions[2].name
}

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
  public_key_material  = tls_private_key.redpanda.public_key_openssh
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
  public_key_material  = tls_private_key.redpanda.public_key_openssh
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
  public_key_material  = tls_private_key.redpanda.public_key_openssh
  broker_instance_type = var.broker_instance_type
  machine_architecture = var.machine_architecture
  disk_type            = var.disk_type
  ebs_volume_size_gb   = var.ebs_volume_size_gb
  ebs_volume_type      = var.ebs_volume_type
  ebs_iops             = var.ebs_iops
  data_device          = var.data_device
  providers            = { aws = aws.region2 }
}

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
  depends_on                = [aws_vpc_peering_connection_accepter.r0_r1]
}

resource "aws_route" "r1_to_r0" {
  provider                  = aws.region1
  route_table_id            = module.region1.route_table_id
  destination_cidr_block    = var.regions[0].vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.r0_r1.id
  depends_on                = [aws_vpc_peering_connection_accepter.r0_r1]
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
  depends_on                = [aws_vpc_peering_connection_accepter.r0_r2]
}

resource "aws_route" "r2_to_r0" {
  provider                  = aws.region2
  route_table_id            = module.region2.route_table_id
  destination_cidr_block    = var.regions[0].vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.r0_r2.id
  depends_on                = [aws_vpc_peering_connection_accepter.r0_r2]
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
  depends_on                = [aws_vpc_peering_connection_accepter.r1_r2]
}

resource "aws_route" "r2_to_r1" {
  provider                  = aws.region2
  route_table_id            = module.region2.route_table_id
  destination_cidr_block    = var.regions[1].vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.r1_r2.id
  depends_on                = [aws_vpc_peering_connection_accepter.r1_r2]
}

# ── Redpanda Console ─────────────────────────────────────────────────────────
# Single instance in the primary region (region0). Public HTTP on port 8080.
data "aws_ami" "console_ubuntu" {
  provider    = aws.region0
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-*-22.04-arm64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

resource "aws_security_group" "console" {
  provider    = aws.region0
  name        = "${var.deployment_prefix}-console"
  description = "Redpanda Console — HTTP and SSH"
  vpc_id      = module.region0.vpc_id

  ingress {
    description = "Console UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.deployment_prefix}-console" }
}

resource "aws_instance" "console" {
  provider               = aws.region0
  ami                    = data.aws_ami.console_ubuntu.id
  instance_type          = var.console_instance_type
  subnet_id              = module.region0.first_subnet_id
  key_name               = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.console.id]

  associate_public_ip_address = true

  tags = { Name = "${var.deployment_prefix}-console" }
}

# ── hosts.ini Generation ──────────────────────────────────────────────────────
locals {
  all_brokers = concat(module.region0.brokers, module.region1.brokers, module.region2.brokers)
}

resource "local_file" "hosts_ini" {
  content = templatefile("${path.module}/hosts.ini.tpl", {
    brokers              = local.all_brokers
    data_device          = var.data_device
    ssh_private_key_path = local.ssh_private_key_path
    redpanda_version     = var.redpanda_version
    leader_rack_order    = local.leader_rack_order
    console_public_ip    = aws_instance.console.public_ip
  })
  filename        = "${path.module}/../../ansible/hosts.ini"
  file_permission = "0644"
}
