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
