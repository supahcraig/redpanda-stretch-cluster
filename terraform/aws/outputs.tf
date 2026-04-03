output "broker_public_ips" {
  description = "All broker public IPs by name"
  value = {
    for b in local.all_brokers :
    b.name => b.public_ip
  }
}

output "broker_private_ips" {
  description = "All broker private IPs by name"
  value = {
    for b in local.all_brokers :
    b.name => b.private_ip
  }
}

output "bootstrap_brokers" {
  description = "Kafka bootstrap string using public IPs"
  value = join(",", [
    for b in local.all_brokers :
    "${b.public_ip}:9092"
  ])
}

output "leader_rack_order" {
  description = "Ordered AZ list used for default_leaders_preference"
  value = local.leader_rack_order
}

output "ssh_private_key_path" {
  description = "Path where Terraform wrote the generated private key"
  value       = local.ssh_private_key_path
}

output "console_url" {
  description = "Redpanda Console URL"
  value       = "http://${aws_instance.console.public_ip}:8080"
}
