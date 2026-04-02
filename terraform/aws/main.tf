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
