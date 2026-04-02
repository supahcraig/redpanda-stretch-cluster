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
  public_key = var.public_key_material
}

# ── EC2 Broker Instances ──────────────────────────────────────────────────────
# Brokers are distributed round-robin across the AZ list.
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
  iops = contains(["gp3", "io1", "io2"], var.ebs_volume_type) ? var.ebs_iops : null
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
