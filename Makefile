ARTIFACTS := ../artiary/artifacts
MANIFEST := $(ARTIFACTS)/manifest/versions.yml
NODE_TAR := $(ARTIFACTS)/images/node.tar
COMPOSE := docker compose -f docker-compose.yml

.PHONY: build destroy exec verify-artifacts

verify-artifacts:
	@test -f $(NODE_TAR) || \
	    (echo "ERROR: artifact image missing - run 'make artifacts' from repo root first" && exit 1)
	@test -f $(MANIFEST) || \
	    (echo "ERROR: artifact manifest missing - run 'make artifacts' from repo root first" && exit 1)

build: verify-artifacts
	docker load -i $(NODE_TAR)
	NODE_IMAGE=$$(yq '.image.node' $(MANIFEST)) \
	YARN_VERSION=$$(yq '.yarn' $(MANIFEST)) \
	$(COMPOSE) up -d --build --pull never

destroy:
	$(COMPOSE) down --volumes

exec:
	docker exec -it kev-labs bash

clean:
	docker stop $(docker ps -aq) 2>/dev/null; \
	docker rm $(docker ps -aq) 2>/dev/null; \
	docker rmi -f $(docker images -aq) 2>/dev/null; \
	docker volume rm $(docker volume ls -q) 2>/dev/null; \
	docker network rm $(docker network ls -q) 2>/dev/null; \
	docker system prune -a --volumes -f
