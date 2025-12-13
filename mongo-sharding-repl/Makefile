stack-up:
	docker compose up

stack-down:
	docker compose down

cleanup:
	docker volume ls | grep mongo | awk '{print($$2)}' | xargs docker volume rm
	docker volume prune -f
