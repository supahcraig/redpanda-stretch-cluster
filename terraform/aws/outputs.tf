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
