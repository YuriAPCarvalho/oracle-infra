# Service Onboarding Checklist

Use este checklist antes de adicionar qualquer novo servico ao inventario operacional.

## Requisitos

- [ ] Requisitos analisados.
- [ ] Repositorio revisado.
- [ ] Linguagem, runtime, build e start identificados.
- [ ] Dependencias externas documentadas.
- [ ] Segredos mapeados e mantidos fora do Git.
- [ ] Consumo esperado avaliado.

## Container e Compose

- [ ] Dockerfile validado em ARM64.
- [ ] Imagem construida e versionada.
- [ ] Compose criado a partir do template.
- [ ] `.env.example` criado sem segredos reais.
- [ ] `.env` real criado somente na VPS ou no gerenciador de segredos.
- [ ] Persistencia definida em `/opt/docker/<service>`, se necessaria.
- [ ] Rede definida.
- [ ] Porta definida somente se necessaria.
- [ ] Traefik habilitado somente com endpoint HTTP real.
- [ ] Healthcheck implementado quando suportado.

## Operacao

- [ ] Logs testados.
- [ ] Uptime Kuma configurado.
- [ ] Backup validado.
- [ ] Restore dry-run validado.
- [ ] Rollback testado.
- [ ] Documentacao atualizada.
- [ ] Pipeline verde.
- [ ] Deploy validado.

## Integracao Com Scripts

- [ ] `scripts/lib/common.sh`: adicionar servico apenas quando houver Compose real.
- [ ] `status.sh`: confirmar exibicao do container.
- [ ] `health.sh`: adicionar diretorios persistentes e checks especificos.
- [ ] `logs.sh`: validar logs por nome do container.
- [ ] `restart.sh`: validar restart por Compose.
- [ ] `shell.sh`: validar shell disponivel no container.
- [ ] `update.sh`: confirmar pull e `up -d`.
- [ ] `backup.sh`: confirmar inclusao de `/opt/docker/<service>`.
- [ ] `restore.sh`: testar dry-run com backup recente.
- [ ] Makefile: adicionar targets especificos somente se agregarem valor.
- [ ] GitHub Actions: validar Compose e checks do servico.
