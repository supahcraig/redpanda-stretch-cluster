TERRAFORM_DIR := terraform/aws
PROFILE_NAME  := stretch-cluster

.PHONY: install-deps init apply plan provision deploy destroy output profile

install-deps:
	ansible-galaxy install -r requirements.yml
	python3 scripts/patch-ansible-roles.py

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

profile:
	@BROKERS=$$(terraform -chdir=$(TERRAFORM_DIR) output -raw bootstrap_brokers) && \
	ADMIN=$$(terraform -chdir=$(TERRAFORM_DIR) output -raw admin_api_addresses) && \
	(rpk profile create $(PROFILE_NAME) 2>/dev/null; true) && \
	rpk profile use $(PROFILE_NAME) && \
	rpk profile set kafka.brokers $$BROKERS && \
	rpk profile set admin_api.addresses $$ADMIN && \
	echo "Profile '$(PROFILE_NAME)' ready" && \
	echo "  Kafka:  $$BROKERS" && \
	echo "  Admin:  $$ADMIN"
