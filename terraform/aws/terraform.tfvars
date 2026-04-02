# Active configuration — edit before applying
# Defaults match the design spec; override as needed.

deployment_prefix    = "rp-stretch"
ssh_key_name         = "redpanda-stretch-cluster"
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

# EBS disk settings (used when disk_type = "ebs"; switch broker_instance_type to e.g. m7g.2xlarge)
# ebs_volume_size_gb   = 500
# ebs_volume_type      = "gp3"
# ebs_iops             = 16000
# data_device          = "/dev/nvme1n1"
