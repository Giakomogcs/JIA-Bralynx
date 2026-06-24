# CONVENTIONS — Bralyx PCP Agent

## Nomenclatura

- **Tabelas / RPCs / funções**: prefixo `bx_` (ex.: `bx_op`, `bx_recompute_all`).
- **Webhooks n8n**: prefixo `bralyx-*` (ex.: `bralyx-AgentRag`, `bralyx-tool-stats`).
- **Workflows n8n**: PascalCase com prefixo `Bralyx-` (ex.: `Bralyx-Bridge.json`).
- **Migrations**: `NNN_snake_case.sql`, numeradas e aplicadas **em ordem**.
- **Documentos de conhecimento**: `NN_snake_case.md` em `knowledge/`.

## SQL / Banco

- Cada migration tem seção `UP` (aplicar) e comentários `DOWN` (reverter).
- RPCs expostas ao cliente são `SECURITY DEFINER SET search_path = public`.
- Autorização dentro da RPC: checar `bx_is_member()` / `bx_is_admin()` /
  `bx_is_backend()`; negar com `RAISE EXCEPTION ... USING ERRCODE = '42501'`.
- `bx_is_backend()` libera chamadas do n8n (service_role / user `postgres`)
  sem JWT de usuário.
- Volatilidade correta: funções que dependem de `CURRENT_DATE` são `STABLE`
  (ex.: `bx_parse_ts`); parsers puros são `IMMUTABLE` (ex.: `bx_parse_num`).
- Parse tolerante a formato BR: datas (`DD/MM`, `DD-mmm` pt, `DD-mmm-YY`) e
  números (`1.234,56`). Ano ausente ⇒ **ano atual** (decisão de negócio).
- Ingestão é **replace-on-upload**: `DELETE` + recriar a partir do snapshot;
  OPs são **upsertadas** por `numero` (preserva enriquecimento da Prioridades).

## n8n / Workflows

- Não editar os `.json` à mão para mudar o front: editar `front-bralyx.html` e
  rodar `.scripts/build-front-workflow.ps1` (o front é embutido no JSON).
- Workflows de infra são gerados por `.scripts/scaffold-infra-workflows.ps1`
  (swap 1:1 de tokens `welmy→bralyx`, `wl_→bx_`, driveID).
- Bridge: cada ferramenta = 3 nós; mapeia 1 webhook `bralyx-tool-*` → 1 RPC `bx_`.
- Credenciais como placeholders nos JSON: `REPLACE_ME_BRALYX_DB` / `Bralyx-DB`,
  `REPLACE_ME_AZURE_OPENAI_CRED`, `REPLACE_ME_SUPABASE_CRED`,
  `REPLACE_ME_SUPABASE_HOST`, `REPLACE_ME_SERVICE_ROLE_KEY`.

## Front (SPA)

- Arquivo único `front-bralyx.html` (CSS/JS inline; sem framework/build).
- `storageKey = 'bralyx-auth'`, `COMPANY = 'bralyx'`.
- Charts em SVG/CSS puro (donut, gauge, hbars) — **sem bibliotecas**.
- `CONFIG` (SUPABASE_URL/ANON, N8N_BASE) ajustado pelo usuário para a infra Bralyx.

## Idioma

- Domínio, documentação, comentários e mensagens de UI em **português (BR)**.
- Identificadores de código em `snake_case` (SQL) seguem o domínio em português.
