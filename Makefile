DOCKERFILE    ?= Dockerfile
ARTIFACTS     ?= ./artifacts
MANIFEST      := $(ARTIFACTS)/manifest/versions.yml
COMPOSE       := docker compose --env-file docker-llm-cli.env -f docker-compose.yml

IMAGE_NAME    := docker-llm-cli
BUNDLE_NAME   := docker-llm-cli-bundle
BUNDLE_DIR    := $(BUNDLE_NAME)
BUNDLE_TAR    := $(BUNDLE_NAME).tar.gz

# Versions read from local versions.yml (self-contained)
VERSIONS_FILE := versions.yml
_BASE_SLUG    := $(shell yq '.image.base' $(VERSIONS_FILE) 2>/dev/null | tr -d '"' | tr ':' '-')
_VER_SLUG     := $(shell yq '.image.version // ""' $(VERSIONS_FILE) 2>/dev/null | tr -d '"' | sed 's/^sha256://')
NODE_TAR      := $(ARTIFACTS)/images/$(_BASE_SLUG)$(if $(_VER_SLUG),-$(_VER_SLUG),).tar
NODE_BASE     := $(or $(shell yq '.image.base' $(VERSIONS_FILE) 2>/dev/null | tr -d '"'),node:24-trixie)
NODE_DIGEST   := $(shell yq '.image.version // ""' $(VERSIONS_FILE) 2>/dev/null | tr -d '"')
NODE_IMAGE    := $(if $(NODE_DIGEST),$(NODE_BASE)@$(NODE_DIGEST),$(NODE_BASE))
YARN_VERSION  := $(or $(shell yq '.yarn' $(VERSIONS_FILE) 2>/dev/null | tr -d '"'),4.14.1)
CLAUDE_VERSION    := $(or $(shell yq '.scripts.claude.version' $(VERSIONS_FILE) 2>/dev/null | tr -d '"'),2.1.114)
YARN_SCRIPT_VERSION  := $(or $(shell yq '.scripts.yarn.version' $(VERSIONS_FILE) 2>/dev/null | tr -d '"'),4.14.1)
COPILOT_VERSION   := $(or $(shell yq '.scripts.copilot.version' $(VERSIONS_FILE) 2>/dev/null | tr -d '"'),1.0.34)
GH_VERSION        := $(or $(shell yq '.scripts.gh.version' $(VERSIONS_FILE) 2>/dev/null | tr -d '"'),2.91.0)
KIMI_VERSION      := $(or $(shell yq '.scripts.kimi.version' $(VERSIONS_FILE) 2>/dev/null | tr -d '"'),1.37.0)
MISTRAL_VERSION   := $(or $(shell yq '.scripts.mistral.version' $(VERSIONS_FILE) 2>/dev/null | tr -d '"'),2.7.6)

export NODE_IMAGE YARN_VERSION \
  CLAUDE_VERSION YARN_SCRIPT_VERSION COPILOT_VERSION GH_VERSION KIMI_VERSION MISTRAL_VERSION

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

clean:
	docker stop $(IMAGE_NAME) 2>/dev/null || true
	docker rm $(IMAGE_NAME) 2>/dev/null || true
	docker rmi -f $(IMAGE_NAME) 2>/dev/null || true
	docker system prune -af || true

all:
	docker stop $(IMAGE_NAME) 2>/dev/null || true
	docker rm $(IMAGE_NAME) 2>/dev/null || true
	docker rmi -f $(IMAGE_NAME) 2>/dev/null || true
	docker system prune -af || true
	$(MAKE) build DOCKERFILE=Dockerfile.offline
	$(MAKE) test

verify-artifacts:
ifeq ($(DOCKERFILE),Dockerfile.offline)
	@test -f $(NODE_TAR) || \
	    (echo "ERROR: $(NODE_TAR) missing - run 'make stage-artifacts ARTIFACTS=../artiary/artifacts' first" && exit 1)
	@test -f ./artifacts/manifest/versions.yml || \
	    (echo "ERROR: ./artifacts/manifest/versions.yml missing - run 'make stage-artifacts ARTIFACTS=../artiary/artifacts' first" && exit 1)
	@for entry in $$(yq -r '.apt[]' ./artifacts/manifest/versions.yml 2>/dev/null | grep '='); do \
	    name=$$(echo "$$entry" | cut -d= -f1 | cut -d: -f1); \
	    ver=$$(echo "$$entry" | cut -d= -f2-); \
	    deb_ver=$$(echo "$$ver" | sed 's/:/%3a/g'); \
	    ls "./artifacts/apt/$${name}_$${deb_ver}_"*.deb >/dev/null 2>&1 || \
	        { echo "ERROR: missing apt artifact: $$entry" >&2; exit 1; }; \
	done
endif
	@test -f docker-llm-cli.env || \
	    (echo "ERROR: docker-llm-cli.env not found - copy docker-llm-cli.env.example and fill in your values" && exit 1)

build: verify-artifacts
ifeq ($(DOCKERFILE),Dockerfile.offline)
	@set -e; \
	  LOAD_OUT=$$(docker load -i $(NODE_TAR)); \
	  echo "$$LOAD_OUT"; \
	  IMAGE_REF=$$(echo "$$LOAD_OUT" | awk '/Loaded image/{print $$NF}'); \
	  [ -n "$$IMAGE_REF" ] || { echo "ERROR: docker load produced no output for $(NODE_TAR)" >&2; exit 1; }; \
	  docker tag "$$IMAGE_REF" "$(NODE_BASE)"
	NODE_IMAGE=$(NODE_BASE) $(COMPOSE) build
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
