SHELL := /bin/bash
BASE ?= http://localhost:3002
UI_BIND ?= 127.0.0.1
URL ?=
Q ?=
TOKEN ?= $(shell cat .firecrawl/.token 2>/dev/null)
CLI := npx -y firecrawl-cli@latest

export FIRECRAWL_API_URL := $(BASE)
export FIRECRAWL_API_KEY := $(TOKEN)
export FIRECRAWL_NO_TELEMETRY := 1

.PHONY: help start start-auth up up-search up-auth down stop logs ui-up ui-down scrape map search clean

help:
	@echo "server:"
	@echo "  make start         start server + UI (keyless mode)"
	@echo "  make start-auth    start server + UI with the bearer gate"
	@echo "  make up            pull images and start the API on :3002"
	@echo "  make up-search     same, plus SearXNG on 127.0.0.1:8888"
	@echo "  make up-auth       same as up-search, but require a bearer token"
	@echo "  make down          stop everything"
	@echo "  make stop          stop server and UI"
	@echo "ui:"
	@echo "  make ui-up         run obeone/firecrawl-ui on $(UI_BIND):8080"
	@echo "  make ui-down       stop the UI"
	@echo "client:"
	@echo "  make scrape URL=...   official CLI scrape"
	@echo "  make map URL=...      official CLI map"
	@echo "  make search Q=...     official CLI search"

start: up-search ui-up

start-auth: up-auth ui-up

up:
	./scripts/selfhost.sh

up-search:
	./scripts/selfhost.sh --search

up-auth:
	./scripts/selfhost.sh --search --auth

down:
	docker compose -f .firecrawl/docker-compose.yaml down --remove-orphans

stop:
	-$(MAKE) ui-down
	-$(MAKE) down

logs:
	docker compose -f .firecrawl/docker-compose.yaml logs -f api

ui-up:
	docker rm -f firecrawl-ui >/dev/null 2>&1 || true
	docker run -d --name firecrawl-ui --restart unless-stopped \
		-p $(UI_BIND):8080:8080 obeoneorg/firecrawl-ui

ui-down:
	docker rm -f firecrawl-ui

scrape:
	$(CLI) scrape "$(URL)"

map:
	$(CLI) map "$(URL)"

search:
	$(CLI) search "$(Q)"

clean:
	-$(MAKE) down
	rm -rf out .firecrawl
