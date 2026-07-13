# Docker Service Template

Template generico para futuras aplicacoes Docker Compose.

## Uso

1. Copiar este diretorio para `services/<service-name>/` ou usar como base para `compose/<service-name>/`.
2. Revisar os requisitos reais da aplicacao.
3. Criar `.env` apenas na VPS ou no gerenciador de segredos.
4. Validar em ARM64 antes do deploy.

## Padroes

- Nenhuma porta publica por padrao.
- Rede `internal` ativa por padrao.
- Rede `proxy` e labels Traefik somente quando houver endpoint HTTP real.
- Persistencia opcional em `/opt/docker/<service>`.
- Rotacao de logs gerenciada globalmente pelo Docker.
- Sem Docker socket, container privilegiado ou permissoes amplas.

## Quando Usar Traefik

Use Traefik apenas quando o servico expuser um endpoint HTTP que precise ser acessado por hostname e protegido por HTTPS.

Nao use Traefik para bots, workers ou jobs sem interface HTTP.

## Checklist Antes de Produzir

- Repositorio analisado.
- Dockerfile ou imagem validada em ARM64.
- Variaveis reais definidas fora do Git.
- Persistencia e backup avaliados.
- Healthcheck definido quando suportado.
- Rollback documentado.
- Uptime Kuma configurado quando aplicavel.
