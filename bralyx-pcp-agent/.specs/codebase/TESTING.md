# TESTING — Bralyx PCP Agent

> **Estado atual:** o projeto **não possui** suíte de testes automatizada. A
> validação hoje é manual (aplicar migrations, importar workflows, enviar CSVs,
> conferir no front). Esta lacuna está registrada em `CONCERNS.md`.

## Como validar hoje (manual)

### 1. Banco (migrations)
- Aplicar `migrations-clean/*.sql` **em ordem** no Supabase SQL Editor.
- Pré-requisito: extensão `vector` habilitada + Supabase Auth ativo.
- Verificação rápida: rodar `SELECT bx_stats();` (deve retornar zeros antes da
  ingestão, sem erro).

### 2. Ingestão / motor de regras
- Enviar os 2 CSVs via `bralyx-relatorio` (ou rodar `bx_ingest_*` direto).
- Conferir `bx_list_importacoes()` (1 log por tipo) e `bx_stats()`.
- Conferir status calculado: `bx_dashboard_ops()`, `bx_op_detalhe(<numero>)`.

### 3. Workflows n8n
- Validação atual = **JSON válido** + import no n8n sem erro de schema.
- Testar webhooks com chamadas reais após configurar credenciais.

### 4. Front
- Após editar `front-bralyx.html`, **sempre** rodar
  `.scripts/build-front-workflow.ps1` e reimportar `Bralyx-Front.json`.
- Validar visualmente login → painel → views (ops/faltantes/compras/chat).

## Gate checks recomendados (a definir)

Como não há runner configurado, ao adicionar testes preferir:
- **SQL**: testes de regras com `pgTAP` ou asserts em script SQL para
  `bx_classificar_componente` / `bx_classificar_op` / parsers BR.
- **Front**: smoke test de carregamento (Playwright) — login + render do painel.
- **Ingestão**: fixtures CSV pequenas → asserts em `bx_stats()`.

> Até existir gate automatizado, considere "verde" = migrations aplicam sem erro
> + JSON dos workflows válidos + smoke manual do front OK.
