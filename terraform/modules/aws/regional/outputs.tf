output "vpc_id" {
  value = aws_vpc.this.id
}

output "first_subnet_id" {
  description = "ID of the first public subnet (AZ index 0) — used for console placement"
  value       = aws_subnet.public[0].id
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
