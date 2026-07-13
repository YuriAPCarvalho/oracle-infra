SHELL := /usr/bin/env bash

SERVICE ?=
TAIL ?= 100

.PHONY: status health logs restart shell backup update

status:
	bash scripts/status.sh

health:
	bash scripts/health.sh

logs:
	@test -n "$(SERVICE)" || (echo "Use: make logs SERVICE=traefik"; exit 1)
	bash scripts/logs.sh "$(SERVICE)" --tail "$(TAIL)"

restart:
	@test -n "$(SERVICE)" || (echo "Use: make restart SERVICE=traefik"; exit 1)
	bash scripts/restart.sh "$(SERVICE)"

shell:
	@test -n "$(SERVICE)" || (echo "Use: make shell SERVICE=traefik"; exit 1)
	bash scripts/shell.sh "$(SERVICE)"

backup:
	bash scripts/backup.sh

update:
	bash scripts/update.sh
