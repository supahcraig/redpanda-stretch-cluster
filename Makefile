TERRAFORM_DIR := terraform/aws
PROFILE_NAME  := stretch-cluster
# Find first executable rpk binary (skips dead Linux binaries that may appear first in PATH)
RPK := $(shell for b in $$(which -a rpk 2>/dev/null); do "$$b" version >/dev/null 2>&1 && echo "$$b" && break; done)

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
	($(RPK) profile delete $(PROFILE_NAME) 2>/dev/null; true) && \
	$(RPK) profile create $(PROFILE_NAME) \
	    --set kafka_api.brokers="$$BROKERS" \
	    --set admin_api.addresses="$$ADMIN" \
	    --set description="Stretch cluster across 3 AWS regions" \
	    --set prompt="hi-red, [%n]" && \
	echo "Profile '$(PROFILE_NAME)' ready" && \
	echo "  Kafka:  $$BROKERS" && \
	echo "  Admin:  $$ADMIN"
