[redpanda]
%{ for b in brokers ~}
${b.name} ansible_host=${b.public_ip} private_ip=${b.private_ip} rack=${b.az} data_device=${data_device} ansible_user=ubuntu
%{ endfor ~}

[all:vars]
ansible_ssh_private_key_file=${ssh_private_key_path}
redpanda_version=${redpanda_version}
seeds=${join(",", [for b in brokers : b.private_ip])}
redpanda_leader_rack_preference=${join(",", leader_rack_order)}
