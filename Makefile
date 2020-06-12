# SHELL := /bin/bash
DB_PORT = $(shell docker inspect --format='{{(index (index .NetworkSettings.Ports "5432/tcp") 0).HostPort}}' metis_db_1)

help: ## Display help text
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) /dev/null | \
		sed 's/^[^:]*://' | sort | \
		awk -F':.*?## ' '{printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.PHONY: lint help
.DEFAULT_GOAL := help

vendor/bundle: Gemfile Gemfile.lock docker/app/Dockerfile
				@ $(MAKE) bundle
				@ touch vendor/bundle

.docker-build-mark: $(wildcard docker/**/*) docker-compose.yml
				docker-compose rm -f metis_db
				docker-compose pull metis_db
				docker-compose build
				@ touch .docker-build-mark

config.yml:
				cp config.yml.template config.yml

.PHONY: up
up: config.yml .docker-build-mark ## Starts up the database, worker, and webservers of metis in the background.
				@ docker-compose up -d

.PHONY: down
down: ## Ends background metis processes
				@ docker-compose down --remove-orphans

.PHONY: ps
ps: ## Lists status of running metis processes
				@ docker-compose ps

.PHONY: bundle
bundle: ## Executes a bundle install inside of the metis app context.
				docker-compose run --rm metis_app bundle install

.PHONY: build
build: ## Rebuilds the metis docker environment.  Does not clear volumes or databases, just rebuilds code components.
				@ docker-compose build

.PHONY: console
console: ## Starts an irb console inside of the metis app context.
				docker exec -ti "$$(docker ps --format '{{.Names}}' | grep metis_app)" bundle exec irb

.PHONY: migrate
migrate: ## Executes dev and test migrations inside of the metis app context.
				@ docker exec "$$(docker ps --format '{{.Names}}' | grep metis_app)" ./bin/metis migrate
				@ docker exec -e METIS_ENV=test "$$(docker ps --format '{{.Names}}' | grep metis_app)" ./bin/metis migrate

.PHONY: test
test: ## Execute (all) rspec tests inside of the metis app context.
				@ docker-compose run -e METIS_ENV=test --rm metis_app bundle exec rspec

.PHONY: bash
bash: ## Start a bash shell inside of the app context.
				@docker exec -ti "$$(docker ps --format '{{.Names}}' | grep metis_app)" bash

.PHONY: db-port
db-port: ## Print the db port associated with the app.
				@ echo $(DB_PORT)

.PHONY: psql
psql: ## Start a psql shell conntected to the metis development db
				@ docker exec -ti -e PGPASSWORD=password "$$(docker ps --format '{{.Names}}' | grep metis_app)" psql -h metis_db -U developer -d metis_development

.PHONY: logs
logs: ## Follow logs of running containers
				docker-compose logs -f