# NOTE: These outputs use placeholder null values while main.tf is a stub.
# They will be replaced with real resource references in Tasks 3–5 when
# aws_vpc.this, aws_route_table.public, and aws_instance.broker are declared.

output "vpc_id" {
  description = "ID of the VPC created in this region"
  value       = null # replaced in Task 3: aws_vpc.this.id
}

output "route_table_id" {
  description = "ID of the public route table (used for VPC peering routes)"
  value       = null # replaced in Task 3: aws_route_table.public.id
}

output "brokers" {
  description = "Per-broker info used to build hosts.ini and peering routes"
  value       = [] # replaced in Task 5: [for i, inst in aws_instance.broker : { ... }]
}
