# INTEGRATIONS — Bralyx PCP Agent

## Externas

| Integração | Uso | Configuração |
|---|---|---|
| **Supabase (Postgres 15 + pgvector + Auth)** | Banco, RPCs, RLS, vetores | Credencial Postgres `Bralyx-DB` / `REPLACE_ME_BRALYX_DB`; host `REPLACE_ME_SUPABASE_HOST`; `REPLACE_ME_SERVICE_ROLE_KEY` (RAG/Admin); `REPLACE_ME_SUPABASE_CRED` (Vector Store). |
| **Azure OpenAI** | `gpt-4o-mini` (chat) + `text-embedding-3-small` (1536) | `REPLACE_ME_AZURE_OPENAI_CRED`. |
| **Google Drive** | Arquivamento/upload de docs do RAG | Pasta única `18enOlOFXT_r4TH5w7cC16fYhfls7PItB`. |
| **n8n** | Orquestração e webhooks `bralyx-*` | Importar JSONs de `workspaces/`, configurar credenciais, ativar. |
| **Protheus (ERP)** | Fonte de dados (somente leitura, via export) | 2 CSVs exportados manualmente; **replace-on-upload**. Sem API/escrita. |

## Webhooks (n8n → fora)

| Webhook | Workflow | Função |
|---|---|---|
| `GET bralyx-app` | Bralyx-Front | serve a SPA |
| `POST bralyx-AgentRag` | Bralyx-Agent | chat/agente |
| `POST bralyx-tool-*` | Bralyx-Bridge | ferramentas → RPCs `bx_` |
| `POST bralyx-relatorio` | Bralyx-Relatorio | ingestão de CSV |
| `bralyx-rag-*`, `bralyx-DatabaseSetup` | Bralyx-RAG / RAG-Admin | indexação/admin de docs |
| `POST bralyx-admin-create-user` | Bralyx-AdminUser | criar usuário |
| `GET bralyx-sessions` / `GET bralyx-history` / `DELETE bralyx-session` | Bralyx-Chat-* | sessões de chat |

## Bridge: ferramenta → RPC

| Webhook | RPC |
|---|---|
| `bralyx-tool-stats` | `bx_stats()` |
| `bralyx-tool-dashboard` | `bx_dashboard_ops(status,mercado,search,sort,limit,offset)` |
| `bralyx-tool-op-detalhe` | `bx_op_detalhe(numero)` |
| `bralyx-tool-faltantes` | `bx_componentes_faltantes(sem_pedido,search,limit)` |
| `bralyx-tool-liberar-montagem` | `bx_liberar_montagem(incluir_quase,limit)` |
| `bralyx-tool-compras-atrasadas` | `bx_compras_atrasadas()` |
| `bralyx-tool-importacoes` | `bx_list_importacoes(limit)` |
| `bralyx-tool-learning` | `bx_learning_signals()` |
| `bralyx-tool-decision` | `bx_record_decision(op_numero,acao,NULL,motivo,'ia')` |

## Fontes de dados (CSV → tabela)

| CSV | RPC de ingestão | Destino |
|---|---|---|
| `OP_Empenhos_Transferencia.csv` | `bx_ingest_ops_empenhos()` | `bx_op` + `bx_empenho` |
| `Prioridades - …(Lista Geral).csv` | `bx_ingest_prioridades()` | enriquece `bx_op` |
