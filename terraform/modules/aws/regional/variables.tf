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
