SHELL := /usr/bin/env bash

SERVICE ?=
TAIL ?= 100

.PHONY: status health logs restart shell backup update validate validate-compose validate-secrets validate-workflows validate-ci shellcheck

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

shellcheck:
	shellcheck -x -P scripts bootstrap/*.sh scripts/*.sh scripts/lib/*.sh

validate-compose:
	@set -Eeuo pipefail; \
	pg_env="compose/postgres/.env"; \
	if [[ ! -f "$$pg_env" ]]; then \
		cp compose/postgres/.env.example "$$pg_env"; \
		printf '%s\n' 'POSTGRES_PASSWORD=placeholder-validate-only' >> "$$pg_env"; \
	fi; \
	minio_env="compose/minio/.env"; \
	if [[ ! -f "$$minio_env" ]]; then \
		cp compose/minio/.env.example "$$minio_env"; \
		printf '%s\n' 'MINIO_ROOT_PASSWORD=placeholder-validate-only' >> "$$minio_env"; \
	fi; \
	m7api_env="compose/marca7-api/.env"; \
	if [[ ! -f "$$m7api_env" ]]; then \
		cp compose/marca7-api/.env.example "$$m7api_env"; \
		sed -i.bak 's/CHANGE_ME/placeholder-validate-only/g' "$$m7api_env" 2>/dev/null || \
			sed -i '' 's/CHANGE_ME/placeholder-validate-only/g' "$$m7api_env"; \
		rm -f "$$m7api_env.bak"; \
	fi; \
	m7app_env="compose/marca7-app/.env"; \
	if [[ ! -f "$$m7app_env" ]]; then \
		cp compose/marca7-app/.env.example "$$m7app_env"; \
	fi; \
	for file in compose/*/compose.yml; do \
		echo "Validating $$file"; \
		docker compose -f "$$file" config -q; \
	done; \
	template_env="templates/docker-service/.env"; \
	trap 'rm -f "$$template_env"' EXIT; \
	printf '%s\n' \
		'SERVICE_NAME=template-service' \
		'SERVICE_IMAGE=busybox:latest' \
		'SERVICE_HOST=template.local' \
		'SERVICE_PORT=8080' > "$$template_env"; \
	echo "Validating templates/docker-service/compose.yml"; \
	docker compose -f templates/docker-service/compose.yml config -q

validate-secrets:
	@set -Eeuo pipefail; \
	tracked_env_files="$$(git ls-files | grep -E '(^|/)\.env($|\.)' | grep -v -E '(^|/)\.env\.example$$' || true)"; \
	if [[ -n "$$tracked_env_files" ]]; then \
		echo "Tracked real .env files are not allowed:"; \
		printf '%s\n' "$$tracked_env_files"; \
		exit 1; \
	fi; \
	if git grep -nIE -- '-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9_]{30,}|mfa\.[A-Za-z0-9_-]{20,}' ':!backups' ':!logs'; then \
		echo "Potential secret detected."; \
		exit 1; \
	fi; \
	if git grep -nIE -- '^[[:space:]]*[A-Za-z0-9_]*(TOKEN|SECRET|PASSWORD|PRIVATE_KEY)[A-Za-z0-9_]*[[:space:]]*=[^#[:space:]]+' -- '*.env' '*.env.example' 'services/**' 'templates/**'; then \
		echo "Potential uncommented secret assignment detected."; \
		exit 1; \
	fi

validate-workflows:
	bash scripts/validate-workflows.sh

validate-ci: validate-workflows
	@set -Eeuo pipefail; \
	echo "Discord notify dry-run (no network)"; \
	bash scripts/discord-notify.sh --dry-run \
		--title "CI dry-run" \
		--service "oracle-infra" \
		--environment "local" \
		--status started \
		--commit "dry-run" \
		--author "make validate-ci" \
		--branch "local" \
		--message "payload only"; \
	test -f templates/github-actions/build-and-publish.yml; \
	test -f templates/github-actions/deploy-to-vps.yml; \
	test -f templates/github-actions/README.md; \
	test -f .github/workflows/reusable-docker-build.yml; \
	test -f .github/workflows/reusable-vps-deploy.yml; \
	test -f .github/actions/discord-notify/action.yml; \
	test -f scripts/ci-deploy-service.sh; \
	echo "validate-ci OK"

validate:
	bash -n bootstrap/*.sh scripts/*.sh scripts/lib/*.sh
	$(MAKE) shellcheck
	git diff --check
	$(MAKE) validate-compose
	$(MAKE) validate-secrets
	$(MAKE) validate-ci
