ARTIFACTS := ../artiary/artifacts
MANIFEST := $(ARTIFACTS)/manifest/versions.yml
NODE_TAR := $(ARTIFACTS)/images/node.tar
COMPOSE := docker compose --env-file docker-llm-cli.env -f docker-compose.yml

IMAGE_NAME  := docker-llm-cli
BUNDLE_NAME := docker-llm-cli-bundle
BUNDLE_DIR  := $(BUNDLE_NAME)
BUNDLE_TAR  := $(BUNDLE_NAME).tar.gz

.PHONY: build destroy exec run verify-artifacts backup-home export

verify-artifacts:
	@test -f $(NODE_TAR) || \
	    (echo "ERROR: artifact image missing - run 'make artifacts' from repo root first" && exit 1)
	@test -f $(MANIFEST) || \
	    (echo "ERROR: artifact manifest missing - run 'make artifacts' from repo root first" && exit 1)
	@test -f docker-llm-cli.env || \
	    (echo "ERROR: docker-llm-cli.env not found - copy docker-llm-cli.env.example and fill in your values" && exit 1)

build: verify-artifacts
	docker load -i $(NODE_TAR)
	NODE_IMAGE=$$(yq '.image.node' $(MANIFEST)) \
	YARN_VERSION=$$(yq '.yarn' $(MANIFEST)) \
	$(COMPOSE) up -d --build --pull never

destroy:
	$(COMPOSE) down --volumes

exec:
	docker exec -it docker-llm-cli bash

run:
	./export/run.sh

backup-home:
	@mkdir -p /workspace/.backups
	@TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	tar czf /workspace/.backups/home-$$TIMESTAMP.tar.gz -C /home/llm .; \
	echo "Backup saved to /workspace/.backups/home-$$TIMESTAMP.tar.gz"

export:
	@./run.sh

clean:
	docker stop $(docker ps -aq) 2>/dev/null; \
	docker rm $(docker ps -aq) 2>/dev/null; \
	docker rmi -f $(docker images -aq) 2>/dev/null; \
	docker volume rm $(docker volume ls -q) 2>/dev/null; \
	docker network rm $(docker network ls -q) 2>/dev/null; \
	docker system prune -a --volumes -f
