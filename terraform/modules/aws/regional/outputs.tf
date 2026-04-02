output "vpc_id" {
  value = aws_vpc.this.id
}

output "route_table_id" {
  value = aws_route_table.public.id
}

output "brokers" {
  description = "Per-broker info used to build hosts.ini and peering routes"
  value       = [] # updated in Task 5 when aws_instance.broker is declared
}
