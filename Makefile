SHELL := /usr/bin/env bash

SERVICE ?=
TAIL ?= 100

.PHONY: status health logs restart shell backup update validate validate-compose validate-secrets validate-workflows validate-ci validate-prometheus validate-grafana-dashboards shellcheck

PROMETHEUS_IMAGE ?= prom/prometheus:v3.2.1

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
	shellcheck -x -P scripts bootstrap/*.sh scripts/*.sh scripts/lib/*.sh scripts/metrics/*.sh

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
	gf_env="compose/grafana/.env"; \
	if [[ ! -f "$$gf_env" ]]; then \
		cp compose/grafana/.env.example "$$gf_env"; \
		printf '%s\n' \
			'SERVICE_HOST=grafana.chamaeu.app' \
			'GF_SECURITY_ADMIN_USER=admin' \
			'GF_SECURITY_ADMIN_PASSWORD=placeholder-validate-only' \
			>> "$$gf_env"; \
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

validate-prometheus:
	@set -Eeuo pipefail; \
	echo "promtool check config"; \
	docker run --rm --entrypoint promtool \
		-v "$(CURDIR)/compose/prometheus:/etc/prometheus:ro" \
		"$(PROMETHEUS_IMAGE)" \
		check config /etc/prometheus/prometheus.yml; \
	echo "promtool check rules"; \
	docker run --rm --entrypoint promtool \
		-v "$(CURDIR)/compose/prometheus:/etc/prometheus:ro" \
		"$(PROMETHEUS_IMAGE)" \
		check rules /etc/prometheus/rules/host-alerts.yml /etc/prometheus/rules/container-alerts.yml /etc/prometheus/rules/storage-alerts.yml

validate-grafana-dashboards:
	@set -Eeuo pipefail; \
	for f in compose/grafana/provisioning/dashboards/json/*.json; do \
		echo "Validating JSON $$f"; \
		python -c "import json,sys; json.load(open(sys.argv[1], encoding='utf-8'))" "$$f"; \
	done; \
	echo "grafana dashboards OK"

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
	$(MAKE) validate-prometheus
	$(MAKE) validate-grafana-dashboards
	$(MAKE) validate-secrets
	$(MAKE) validate-ci
