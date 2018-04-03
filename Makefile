BRANCH ?= $(shell git rev-parse --abbrev-ref HEAD)
PIPELINE_ID ?= beacon-$(BRANCH)
VERSION = 0.1
CONTAINER_NAME ?= $(PIPELINE_ID)
NAME_OF_GENERATED_IMAGE = local/$(PIPELINE_ID)

ASSEMBLY_ID ?= GRCh37
BEACON_DB ?= beaconData.$(ASSEMBLY_ID).sqlite
BEACON_EXE := ./query
FILTER_EXE := utils/filter_vcf.py
DB_TABLE ?= ousamg
THRESHOLD ?= 5
BED_FILTER ?= ""
AF ?= ""

.PHONY: help

help :
	@echo
	@echo "  * Data operations"
	@echo " make import VCF_FILE=someData.vcf[.gz] [ DB_TABLE=table_name ] [ ASSEMBLY_ID=GRCh## ]"
	@echo "      - Loads the specified VCF file into $(BEACON_DB)"
	@echo "      VCF_FILE: VCF file to be imported, can be gzipped. Required."
	@echo "      DB_TABLE: the name of the table / dataset. Default: $(DB_TABLE)"
	@echo "      ASSEMBLY_ID: Genome assembly ID of the dataset. Default: $(ASSEMBLY_ID)"
	@echo
	@echo " make filter VCF_FILE=someData.vcf[.gz] [ THRESHOLD=N ] [ BED_FILTER=something.bed ] [ AF=allele_frequency ]"
	@echo "      - Filters VCF_FILE to have a minimum number of indications, be within certain"
	@echo "        regions, and/or be under a maximum observed allele frequency"
	@echo "      VCF_FILE: VCF file(s) to be imported, can be gzipped. Required."
	@echo "      THRESHOLD: minimum number of indications. Default: $(THRESHOLD)"
	@echo "      BED_FILTER: restrict variants to regions in bed file. Default: $(BED_FILTER)"
	@echo "      AF: maximum allele frequency of variants. Default: $(AF)"
	@echo
	@echo
	@echo "  * Testing"
	@echo " make test-beacon                   - Test beacon query responses"
	@echo " make test-utils                    - Test beacon utility functions"
	@echo " make test | make test-all          - Run all tests"
	@echo
	@echo
	@echo "  * Production"
	@echo " make build                         - Build the docker image"
	@echo " make deploy                        - Build and run the docker image locally"
	@echo " make digitalocean DO_CONFIG=config.json DO_SSHKEY=/path/to/some_key"
	@echo "      - Creates a droplet in your DigitalOcean account, deploys and starts the beacon"
	@echo "      DO_CONFIG: json file containing droplet options"
	@echo "      DO_SSHKEY: Path to private key to connect to droplet"
	@echo

# Check that given variables are set and all have non-empty values,
# die with an error otherwise.
#
# From: https://stackoverflow.com/questions/10858261/abort-makefile-if-variable-not-set
#
# Params:
#   1. Variable name(s) to test.
#   2. (optional) Error message to print.
check_defined = \
    $(strip $(foreach 1,$1, \
        $(call __check_defined,$1,$(strip $(value 2)))))
__check_defined = \
    $(if $(value $1),, \
      $(error Undefined $1$(if $2, ($2))))

#---------------------------------------------
# Data operations
#---------------------------------------------

BACKUP_DB ?= $(BEACON_DB).$(shell date +%Y%m%d-%H%M%S)
FILT_OPTS := -t $(THRESHOLD)
ifdef AF
FILT_OPTS += -af $(AF)
endif
ifdef BED_FILTER
FILT_OPTS += -b $(BED_FILTER)
endif
ifdef VERBOSE
FILT_OPTS += --verbose
endif
ifdef DEBUG
FILT_OPTS += --debug
endif

.PHONY: import filter

import:
	cp $(BEACON_DB) $(BACKUP_DB)
	$(BEACON_EXE) $(ASSEMBLY_ID) $(DB_TABLE) $(VCF_FILE)
	@echo "Updated db, previous data saved in $(BACKUP_DB)"

filter:
	@$(call check_defined, VCF_FILE, 'Missing VCF_FILE. Please provide a value on the command line')
	$(FILTER_EXE) -f $(VCF_FILE) $(FILTER_OPTS)

#---------------------------------------------
# Testing
#---------------------------------------------

.PHONY: build test test-all test-beacon test-utils docker-clean

build:
	docker build -t $(NAME_OF_GENERATED_IMAGE) .

test: test-all
test-all: test-beacon test-utils

test-beacon: build
	docker run -dit \
	  --label io.ousamg.gitversion=$(BRANCH) \
	  --name $(PIPELINE_ID)-test $(NAME_OF_GENERATED_IMAGE)

	docker exec $(PIPELINE_ID)-test ./testBeacon
	@docker rm -f $(PIPELINE_ID)-test

test-utils: build
	docker run -dit \
	  --label io.ousamg.gitversion=$(BRANCH) \
	  --name $(PIPELINE_ID)-test $(NAME_OF_GENERATED_IMAGE)

	docker exec $(PIPELINE_ID)-test test/test_utils.sh
	@docker rm -f $(PIPELINE_ID)-test

#---------------------------------------------
# Production
#---------------------------------------------

LOCAL_PORT ?= 80
IMAGE_PORT ?= 80
IP_FILE := droplet.ipaddr

.PHONY: deploy digitalocean clean create-droplet

deploy: build
	docker run -dit \
		-p $(LOCAL_PORT):$(IMAGE_PORT) \
		--name $(PIPELINE_ID) $(NAME_OF_GENERATED_IMAGE)

redeploy: build docker-clean deploy

digitalocean: create-droplet
	@echo "sshd takes a bit to warm sometimes, sleeping to give it a chance"
	@sleep 30
	rsync -avz . -e "ssh -i $(DO_SSHKEY) -o StrictHostKeyChecking=no" root@$(shell cat $(IP_FILE)):beacon/ \
		 --exclude='beaconData.*.sqlite.*' --exclude=test_data --exclude='*.pyc' --exclude=venv
	ssh -i $(DO_SSHKEY) root@$(shell cat $(IP_FILE)) 'bash beacon/utils/init_do.sh'

create-droplet:
	@$(call check_defined, DO_CONFIG, 'Missing digitalocean config. Please provide a value for DO_CONFIG on the command line')
	@$(call check_defined, DO_SSHKEY, 'Missing ssh key. Set DO_SSHKEY to the location of the desired SSH key from the digitalocean config')
	utils/create-droplet.py -c $(DO_CONFIG) > $(IP_FILE)

clean:
	-rm droplet.ipaddr
