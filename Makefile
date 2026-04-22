DOCKERFILE    ?= Dockerfile
ARTIFACTS     ?= ./artifacts
MANIFEST      := $(ARTIFACTS)/manifest/versions.yml
NODE_TAR      := $(ARTIFACTS)/images/node.tar
COMPOSE       := docker compose --env-file docker-llm-cli.env -f docker-compose.yml

IMAGE_NAME    := docker-llm-cli
BUNDLE_NAME   := docker-llm-cli-bundle
BUNDLE_DIR    := $(BUNDLE_NAME)
BUNDLE_TAR    := $(BUNDLE_NAME).tar.gz

# Versions read from local versions.yml (self-contained)
VERSIONS_FILE := versions.yml
NODE_IMAGE    := $(shell yq '.image.node' $(VERSIONS_FILE) 2>/dev/null || echo node:24-trixie)
YARN_VERSION  := $(shell yq '.yarn' $(VERSIONS_FILE) 2>/dev/null || echo 4.14.1)
CLAUDE_VERSION    := $(shell yq '.scripts.claude.version' $(VERSIONS_FILE) 2>/dev/null || echo 2.1.114)
YARN_SCRIPT_VERSION  := $(shell yq '.scripts.yarn.version' $(VERSIONS_FILE) 2>/dev/null || echo 4.14.1)
COPILOT_VERSION   := $(shell yq '.scripts.copilot.version' $(VERSIONS_FILE) 2>/dev/null || echo 1.0.34)
KIMI_VERSION      := $(shell yq '.scripts.kimi.version' $(VERSIONS_FILE) 2>/dev/null || echo 1.37.0)
MISTRAL_VERSION   := $(shell yq '.scripts.mistral.version' $(VERSIONS_FILE) 2>/dev/null || echo 2.7.6)

export NODE_IMAGE YARN_VERSION \
  CLAUDE_VERSION YARN_SCRIPT_VERSION COPILOT_VERSION KIMI_VERSION MISTRAL_VERSION

.PHONY: build destroy exec run verify-artifacts stage-artifacts backup-home export test clean check-sync

stage-artifacts:
	@if [ "$(ARTIFACTS)" = "./artifacts" ] || [ "$(ARTIFACTS)" = "$(realpath ./artifacts 2>/dev/null || echo ./artifacts)" ]; then \
		echo "ERROR: ARTIFACTS cannot be ./artifacts (would delete itself)."; \
		echo "Usage: make stage-artifacts ARTIFACTS=../artiary/artifacts"; \
		exit 1; \
	fi
	@if [ ! -d "$(ARTIFACTS)" ]; then \
		echo "ERROR: source directory $(ARTIFACTS) does not exist"; \
		echo "Usage: make stage-artifacts ARTIFACTS=../artiary/artifacts"; \
		exit 1; \
	fi
	@rm -rf ./artifacts
	@cp -r "$(ARTIFACTS)" ./artifacts
	@echo "Artifacts staged from $(ARTIFACTS) to ./artifacts"

all:
	docker stop $(IMAGE_NAME) 2>/dev/null || true
	docker rm $(IMAGE_NAME) 2>/dev/null || true
	docker rmi -f $(IMAGE_NAME) 2>/dev/null || true
	$(MAKE) build
	$(MAKE) test
	$(MAKE) export

verify-artifacts:
ifeq ($(DOCKERFILE),Dockerfile.offline)
	@test -f ./artifacts/images/node.tar || \
	    (echo "ERROR: ./artifacts/images/node.tar missing - run 'make stage-artifacts ARTIFACTS=../artiary/artifacts' first" && exit 1)
	@test -f ./artifacts/manifest/versions.yml || \
	    (echo "ERROR: ./artifacts/manifest/versions.yml missing - run 'make stage-artifacts ARTIFACTS=../artiary/artifacts' first" && exit 1)
endif
	@test -f docker-llm-cli.env || \
	    (echo "ERROR: docker-llm-cli.env not found - copy docker-llm-cli.env.example and fill in your values" && exit 1)

build: verify-artifacts
ifeq ($(DOCKERFILE),Dockerfile.offline)
	docker load -i $(NODE_TAR)
	$(COMPOSE) build --pull never
else
	$(COMPOSE) build
endif
	$(COMPOSE) up -d

destroy:
	$(COMPOSE) down --volumes

exec:
	docker exec -it docker-llm-cli bash

backup-home:
	@mkdir -p /workspace/.backups
	@TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	tar czf /workspace/.backups/home-$$TIMESTAMP.tar.gz -C /home/llm .; \
	echo "Backup saved to /workspace/.backups/home-$$TIMESTAMP.tar.gz"

export:
	@./run.sh

test:
	@which dgoss >/dev/null 2>&1 || { echo "ERROR: dgoss not found. Install: https://github.com/goss-org/goss" ; exit 1; }
	@docker image inspect $(IMAGE_NAME) >/dev/null 2>&1 || { echo "ERROR: image '$(IMAGE_NAME)' not found. Run 'make build' first." ; exit 1; }
	dgoss run --user 1000:1000 -e HOME=/home/llm $(IMAGE_NAME) tail -f /dev/null

check-sync:
	@echo "Checking common sections are in sync..."
	@tail -n +$$(grep -n "^USER root$$" Dockerfile | tail -1 | cut -d: -f1) Dockerfile > /tmp/dockerfile.tail
	@tail -n +$$(grep -n "^USER root$$" Dockerfile.offline | tail -1 | cut -d: -f1) Dockerfile.offline > /tmp/dockerfile-offline.tail
	@diff -q /tmp/dockerfile.tail /tmp/dockerfile-offline.tail || \
	    (echo "ERROR: Common tail sections of Dockerfile and Dockerfile.offline have drifted." && exit 1)
	@echo "OK: Common sections are synchronized."

clean:
	docker stop $$(docker ps -aq) 2>/dev/null; \
	docker rm $$(docker ps -aq) 2>/dev/null; \
	docker rmi -f $$(docker images -aq) 2>/dev/null; \
	docker volume rm $$(docker volume ls -q) 2>/dev/null; \
	docker network rm $$(docker network ls -q) 2>/dev/null; \
	docker system prune -a --volumes -f
