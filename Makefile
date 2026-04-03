TERRAFORM_DIR := terraform/aws

.PHONY: init apply provision deploy destroy

init:
	terraform -chdir=$(TERRAFORM_DIR) init

apply:
	terraform -chdir=$(TERRAFORM_DIR) apply

plan:
	terraform -chdir=$(TERRAFORM_DIR) plan

destroy:
	terraform -chdir=$(TERRAFORM_DIR) destroy

provision:
	ansible-playbook ansible/provision-cluster.yml

deploy: apply provision

output:
	terraform -chdir=$(TERRAFORM_DIR) output
