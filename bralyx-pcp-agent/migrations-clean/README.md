# Migrations — Bralyx (Copiloto de PCP, Estoque e Compras)

SQL para o Supabase (Postgres 15 + pgvector). Rode **na ordem** no SQL Editor.
Cada arquivo tem seções `UP` (aplicar) e comentários `DOWN` (reverter).
Prefixo de objetos: `bx_` · papel guardado em `raw_user_meta_data`
(`role` ∈ `admin` | `visualizacao`, `company_name='bralyx'`).

> Derivado do agente **Welmy** (`../../welmy-pcp-agent/`), mantido como
> referência. O domínio foi **refeito** para o PCP da Bralyx: o objeto central
> é a **Ordem de Produção (OP)** e o cruzamento `necessidade × transferido ×
> falta × pedido de compra`, e **não** o relatório de necessidades/lead-time da
> Welmy.

| Ordem | Arquivo | Objetos principais |
|---|---|---|
| 1 | `001_users_and_admin.sql` | `bx_set_updated_at()`, `bx_is_admin()`, `bx_is_member()`, CRUD de usuários |
| 2 | `002_rag_schema.sql` | `bx_document_metadata`, `bx_document_rows`, `bx_documents` (vector 1536, HNSW) + RPCs do RAG |
| 3 | `003_match_documents.sql` | `bx_match_documents()` — busca vetorial global; isola anexos de conversa por `session_id` |
| 4 | `004_chat_messages.sql` | `bx_chat_message` + trigger que extrai `user_id` do bloco `ID="<uuid>"` |
| 5 | `005_pcp_schema.sql` | `bx_fornecedor`, `bx_item`, `bx_pedido_compra`, **`bx_op`**, **`bx_empenho`**, `bx_importacao`, `bx_decision_log` + RLS + helpers de parse |
| 6 | `006_pcp_rpc.sql` | **Motor de regras** (`bx_classificar_componente`, `bx_classificar_op`), `bx_recompute_op/all`, dashboard, detalhe da OP, faltantes, compras atrasadas, liberar montagem, decisões, stats |
| 7 | `007_seeds.sql` | Apenas **admin inicial** (sem dados de exemplo — tudo vem dos relatórios) |
| 8 | `008_ingest.sql` | Ingestão dos 2 CSVs do ERP: `bx_ingest_ops_empenhos()` e `bx_ingest_prioridades()` (replace-on-upload) |

## Pré-requisitos
- Extensão `vector` habilitada (Database → Extensions → `vector`).
- Supabase Auth ativo.

## Modelo de domínio (escopo Bralyx)

A Bralyx já tem os dados no Protheus, mas entender a situação real de cada OP
exige cruzamento manual entre produção, estoque, compras e faltantes. Este
schema guarda o **resultado do cruzamento**, calculado por um motor de regras
determinístico (o LLM apenas explica).

### Fontes de dados — **somente 2 CSVs** (sem PDF, sem planilha-mestre)

| Relatório | Arquivo de exemplo | Vira… | RPC de ingestão |
|---|---|---|---|
| **OP / Empenhos + Transferência** | `OP_Empenhos_Transferencia.csv` | `bx_op` (cabeçalho SC2) + `bx_empenho` (componentes SD4) | `bx_ingest_ops_empenhos()` |
| **Lista de Prioridades** | `Prioridades - …(Lista Geral).csv` | enriquece `bx_op` (cliente, montador, mercado, situação, painel, datas, atraso) | `bx_ingest_prioridades()` |

Mapeamento das colunas do Protheus em `bx_empenho`:

| Coluna CSV | Campo | Significado |
|---|---|---|
| `D4_COD` | `codigo` | código do componente |
| `D4_QTDEORI` | `qtd_original` | quantidade originalmente empenhada |
| `Soma de D4_QUANT` / `D4_QUANT` | `qtd_necessaria` | quantidade necessária para a OP |
| `D4_XQTRANS` | `qtd_transferida` | já transferido para a produção |
| `D4_XQFALFI` | `qtd_falta` | **ainda falta** (já considera o estoque alocado) |

> A coluna `Chave` / `C2_PRODUTO` / datas (`C2_DATPRI`/`C2_DATPRF`) carregam o
> **cabeçalho da OP**. O export real traz a OP preenchida em **cada linha de
> componente** (confirmado), o que permite o cruzamento OP↔componente.

### Replace-on-upload (sobre a pergunta "precisa do esquema de trocar conteúdo?")

**Não** é preciso o esquema de planilha-mestre sincronizada da Welmy (ler do
Google Sheets e substituir o arquivo no Drive). Aqui os dois relatórios são
**snapshots do ERP**: cada novo CSV **substitui** o anterior.

- `bx_ingest_ops_empenhos()` faz `DELETE FROM bx_empenho` e recria tudo a partir
  do arquivo (a falta/transferência vem 100% do novo snapshot); as OPs são
  **upsertadas** por `numero` (preservando o enriquecimento da Prioridades).
- `bx_ingest_prioridades()` reescreve os campos de enriquecimento das OPs.
- Cada importação registra **um único** log por tipo em `bx_importacao`
  (histórico único, igual ao "inventário único" da Welmy).
- Ao final, `bx_recompute_all()` recalcula status e prioridade de todas as OPs.

> Não há IDs fixos de planilha a configurar. O **único ID** do projeto é a pasta
> do Google Drive do RAG (arquivamento de uploads de conhecimento):
> **`18enOlOFXT_r4TH5w7cC16fYhfls7PItB`** — usado nos workflows de RAG (n8n).

## Regras (motor determinístico)

### Status do componente (`bx_classificar_componente`)
| Status | Regra |
|---|---|
| `transferido` | `qtd_falta ≤ 0` e `qtd_transferida ≥ qtd_necessaria` (já em produção) |
| `ok` | `qtd_falta ≤ 0` (disponível/empenhado, sem falta) |
| `falta_parcial` | `0 < qtd_falta < qtd_necessaria` |
| `falta_total` | `qtd_falta ≥ qtd_necessaria` |

### Status da OP (`bx_classificar_op`)
| Status | Regra | Significado |
|---|---|---|
| `completa` | 0 componentes faltando | **pode ir para montagem** |
| `quase_completa` | faltam ≤ 3 componentes **ou** ≤ 10% do total | falta pouco para liberar |
| `travada` | mais que isso faltando | bloqueada por material |
| `sem_dados` | nenhum empenho cadastrado | OP sem componentes importados |

`pode_montar = (status = 'completa')`. A **prioridade** de atenção do PCP
ordena `quase_completa` no topo (pequeno esforço destrava a montagem), depois
`travada`, e pesa **faltantes sem pedido** e **dias de atraso**.

## Ferramentas/consultas (usadas pelo agente n8n)

| RPC | Responde a… |
|---|---|
| `bx_stats()` | "visão geral: quantas OPs completas/quase/travadas, faltantes, compras atrasadas" |
| `bx_dashboard_ops(status,mercado,search,sort,limit,offset)` | "liste as OPs priorizadas / por status" |
| `bx_liberar_montagem(incluir_quase,limit)` | **"quais máquinas posso liberar para montagem esta semana?"** |
| `bx_op_detalhe(numero)` | **"o que falta para concluir a OP da máquina X?"** (faltantes + pedido + previsão + fornecedor) |
| `bx_componentes_faltantes(sem_pedido,search,limit)` | "quais itens faltam? quais não têm pedido nem estoque?" |
| `bx_compras_atrasadas()` | "quais compras estão atrasadas e travam produção?" |
| `bx_record_decision()` / `bx_learning_signals()` | registra/observa decisões do PCP |
| `bx_list_importacoes()` | "qual o último relatório carregado?" |

> O agente **não** decide nem altera o ERP: organiza, cruza e interpreta para o
> PCP/compras/produção decidirem mais rápido (human-in-the-loop).

## Admin inicial
`007` cria `admin@bralyx.com.br` / `@Admin123`. **Troque a senha** após o
primeiro login.

## Backend (n8n)
O Postgres usa o usuário `postgres`, reconhecido por `bx_is_backend()` — assim
as RPCs `SECURITY DEFINER` aceitam as chamadas do n8n sem JWT de usuário.

## Próximos passos (fora desta entrega)
Workflows n8n (`bralyx-*`), base de conhecimento (RAG) e front SPA serão
derivados do projeto Welmy em etapas seguintes, reaproveitando estas RPCs.
