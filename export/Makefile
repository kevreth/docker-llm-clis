.PHONY: init start stop exec

init:
	./run.sh

start:
	docker start docker-llm-cli
	docker exec -it docker-llm-cli bash

stop:
	docker stop docker-llm-cli

exec:
	docker exec -it docker-llm-cli bash
