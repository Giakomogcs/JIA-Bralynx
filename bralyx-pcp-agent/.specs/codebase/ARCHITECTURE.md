# ARCHITECTURE — Bralyx PCP Agent

## Visão geral

```
front (SPA)  ──HTTP──►  n8n (webhooks bralyx-*)  ──►  Supabase (Postgres + pgvector + Auth)
                                 │
                                 ├─ AI Agent (Azure OpenAI gpt-4o-mini)
                                 ├─ RAG (text-embedding-3-small → bx_documents)
                                 └─ RPCs SECURITY DEFINER (motor de regras determinístico)
```

**Princípio central:** todo status de OP/componente e a priorização são
calculados por **RPCs determinísticas** no Postgres. O LLM apenas redige a
explicação. Human-in-the-loop: o agente recomenda, o PCP decide, o ERP **não** é
alterado.

## Fluxos principais

### 1. Ingestão de dados (replace-on-upload)
2 CSVs do Protheus → `Bralyx-Relatorio.json` (Code node detecta o tipo pelo
header) → `bx_ingest_ops_empenhos()` ou `bx_ingest_prioridades()` → cada upload
**substitui** o snapshot anterior → `bx_recompute_all()` recalcula status +
prioridade.

- `OP_Empenhos_Transferencia.csv` → `bx_op` (cabeçalho SC2) + `bx_empenho` (SD4).
- `Prioridades - …(Lista Geral).csv` → enriquece `bx_op` (cliente, montador,
  mercado, situação, painel, datas, atraso).

### 2. Chat / Agente
front → `POST bralyx-AgentRag` (`Bralyx-Agent.json`) → AI Agent com memória +
RAG (`bx_match_documents`) + 9 ferramentas HTTP → `Bralyx-Bridge.json`
(`bralyx-tool-*`) → RPCs `bx_*`. Mensagens persistidas em `bx_chat_message`.

### 3. RAG / Conhecimento
Uploads e Google Drive → `Bralyx-RAG.json` / `Bralyx-RAG-Admin.json` →
embeddings (`text-embedding-3-small`) → `bx_documents` (vector 1536, HNSW).
`knowledge/` (9 docs) é a base curada.

### 4. Front (SPA)
`front-bralyx.html` é embutida no `Bralyx-Front.json` (`GET bralyx-app`).
Views: painel (landing), ops, op-detalhe, montagem, faltantes, compras, dados,
documentos, importações, usuários. Charts em SVG/CSS puro (sem libs).

## Motor de regras (determinístico)

### Status do componente — `bx_classificar_componente`
| Status | Regra |
|---|---|
| `transferido` | `qtd_falta ≤ 0` **e** `qtd_transferida ≥ qtd_necessaria` |
| `ok` | `qtd_falta ≤ 0` |
| `falta_parcial` | `0 < qtd_falta < qtd_necessaria` |
| `falta_total` | `qtd_falta ≥ qtd_necessaria` |

### Status da OP — `bx_classificar_op`
| Status | Regra | Significado |
|---|---|---|
| `completa` | 0 componentes faltando | pode ir para montagem |
| `quase_completa` | faltam ≤ 3 **ou** ≤ 10% do total | falta pouco |
| `travada` | mais que isso | bloqueada por material |
| `sem_dados` | nenhum empenho cadastrado | OP sem componentes |

`pode_montar = (status = 'completa')`. Prioridade ordena `quase_completa` no
topo, depois `travada`, pesando faltantes sem pedido e dias de atraso.

## RPCs / ferramentas do agente

| RPC | Responde a… |
|---|---|
| `bx_stats()` | visão geral (completas/quase/travadas, faltantes, atrasos) |
| `bx_dashboard_ops(status,mercado,search,sort,limit,offset)` | listar OPs priorizadas |
| `bx_liberar_montagem(incluir_quase,limit)` | quais máquinas liberar p/ montagem |
| `bx_op_detalhe(numero)` | o que falta p/ concluir a OP X |
| `bx_componentes_faltantes(sem_pedido,search,limit)` | itens faltantes sem pedido/estoque |
| `bx_compras_atrasadas()` | compras atrasadas que travam produção |
| `bx_record_decision()` / `bx_learning_signals()` | registra/observa decisões |
| `bx_list_importacoes(limit)` | último relatório carregado |

Vocabulário de ação (front + agente):
`liberar_montagem | priorizar_compra | cobrar_fornecedor | transferir | aguardar`.
