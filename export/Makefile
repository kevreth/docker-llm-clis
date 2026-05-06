IMAGE_NAME := docker-llm-cli

.PHONY: init start stop exec clean

init: clean
	./run.sh

start:
	docker start $(IMAGE_NAME)
	$(make) exec

stop:
	docker stop $(IMAGE_NAME)

exec:
	docker exec -it $(IMAGE_NAME) bash

clean:
	docker stop $(IMAGE_NAME) 2>/dev/null || true
	docker rm $(IMAGE_NAME) 2>/dev/null || true
	docker rmi -f $(IMAGE_NAME) 2>/dev/null || true
	docker system prune -af || true
	
status:
	docker container ls -f name=$(IMAGE_NAME)