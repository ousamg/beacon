BRANCH ?= $(shell git rev-parse --abbrev-ref HEAD)
PIPELINE_ID ?= beacon-$(BRANCH)
VERSION = 0.1
CONTAINER_NAME ?= $(PIPELINE_ID)
NAME_OF_GENERATED_IMAGE = local/$(PIPELINE_ID)

.PHONY: build test test-all test-beacon test-utils

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

	docker exec $(PIPELINE_ID)-test test/run_tests.sh
	@docker rm -f $(PIPELINE_ID)-test
