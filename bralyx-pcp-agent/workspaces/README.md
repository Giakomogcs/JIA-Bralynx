# Workflows n8n — Bralyx PCP

Importe cada `.json` no n8n (**Workflows → Import from File**). Depois ajuste as
credenciais e ative os webhooks.

## Workflows

| Arquivo | Webhook(s) | Função |
|---|---|---|
| `Bralyx-Front.json` | `GET bralyx-app` | Serve o app (SPA) `front-bralyx.html`. Gerado por `.scripts/build-front-workflow.ps1`. |
| `Bralyx-Agent.json` | `POST bralyx-AgentRag` | Agente (AI Agent + memória + RAG + 9 ferramentas HTTP). |
| `Bralyx-Bridge.json` | `POST bralyx-tool-*` | Ponte das ferramentas do agente → RPCs `bx_*` no Postgres. |
| `Bralyx-Relatorio.json` | `POST bralyx-relatorio` | Ingestão dos CSVs (detecta OP/Empenhos × Prioridades). |
| `Bralyx-RAG.json` | `bralyx-rag-upload`, `bralyx-rag-admin-upload`, `bralyx-rag-reindex`, `bralyx-DatabaseSetup` | Indexação de documentos (upload + Google Drive). |
| `Bralyx-RAG-Admin.json` | `bralyx-rag-docs`, `bralyx-rag-doc-delete`, `bralyx-rag-purge-all`, `bralyx-rag-upsert` | Administração da base de conhecimento. |
| `Bralyx-AdminUser.json` | `POST bralyx-admin-create-user` | Criação de usuários (service_role). |
| `Bralyx-Chat-GET-Sessions.json` | `GET bralyx-sessions` | Lista as sessões de chat do usuário. |
| `Bralyx-Chat-GET-History.json` | `GET bralyx-history` | Histórico de mensagens de uma sessão. |
| `Bralyx-Chat-DELETE-Session.json` | `DELETE bralyx-session` | Apaga uma sessão de chat. |

## Ferramentas do Bridge (→ RPC)
| Webhook | RPC |
|---|---|
| `bralyx-tool-stats` | `bx_stats()` |
| `bralyx-tool-dashboard` | `bx_dashboard_ops(status, mercado, search, sort, limit, offset)` |
| `bralyx-tool-op-detalhe` | `bx_op_detalhe(numero)` |
| `bralyx-tool-faltantes` | `bx_componentes_faltantes(sem_pedido, search, limit)` |
| `bralyx-tool-liberar-montagem` | `bx_liberar_montagem(incluir_quase, limit)` |
| `bralyx-tool-compras-atrasadas` | `bx_compras_atrasadas()` |
| `bralyx-tool-importacoes` | `bx_list_importacoes(limit)` |
| `bralyx-tool-learning` | `bx_learning_signals()` |
| `bralyx-tool-decision` | `bx_record_decision(op_numero, acao, NULL, motivo, 'ia')` |

## Credenciais a configurar (placeholders nos JSON)
- `REPLACE_ME_BRALYX_DB` / `Bralyx-DB` → credencial **Postgres** do Supabase.
- `REPLACE_ME_AZURE_OPENAI_CRED` → **Azure OpenAI** (gpt-4o-mini + text-embedding-3-small).
- `REPLACE_ME_SUPABASE_CRED` → conta **Supabase** (Vector Store).
- `REPLACE_ME_SUPABASE_HOST` / `REPLACE_ME_SERVICE_ROLE_KEY` → host/service role (RAG/Admin).

## Ordem sugerida de import
1. Aplicar as migrações (`migrations-clean/`) no Supabase.
2. Importar **Bridge**, **Agent**, **Relatorio**, **RAG**, **RAG-Admin**,
   **AdminUser**, os 3 de **Chat** e o **Front**.
3. Configurar as credenciais acima e ativar os workflows.
4. Ajustar `CONFIG` em `front-bralyx.html` (SUPABASE_URL/ANON, N8N_BASE) e
   regenerar o Front com `.scripts/build-front-workflow.ps1`.

## Notas
- O front é embutido no `Bralyx-Front.json`. Para alterar a interface, edite
  `front-bralyx.html` e rode o build script — **não** edite o JSON à mão.
- Webhooks usam o prefixo `bralyx-*`; tabelas/RPCs usam o prefixo `bx_*`.
