# STRUCTURE — Bralyx PCP Agent

```
Bralynx/                                  # raiz do workspace
├── OP_Empenhos_Transferencia.csv         # export Protheus (amostra) — OPs/empenhos
├── Prioridades - Abril 2026(...).csv     # export Protheus (amostra) — enriquecimento
└── bralyx-pcp-agent/                      # PROJETO
    ├── README.md                          # visão geral, arquitetura, stack
    ├── front-bralyx.html                  # SPA (login, painel, dashboards, chat)
    ├── .scripts/
    │   ├── build-front-workflow.ps1       # embute o front no Bralyx-Front.json
    │   └── scaffold-infra-workflows.ps1   # gera workflows de infra (swap de tokens)
    ├── migrations-clean/                   # esquema Supabase (aplicar em ordem)
    │   ├── 001_users_and_admin.sql         # helpers auth, bx_is_admin/member, CRUD users
    │   ├── 002_rag_schema.sql              # bx_document_metadata/rows/documents (HNSW)
    │   ├── 003_match_documents.sql         # bx_match_documents (busca vetorial)
    │   ├── 004_chat_messages.sql           # bx_chat_message + trigger user_id
    │   ├── 005_pcp_schema.sql              # bx_fornecedor/item/pedido_compra/op/empenho/
    │   │                                   #   importacao/decision_log + parsers BR + RLS
    │   ├── 006_pcp_rpc.sql                 # MOTOR DE REGRAS + dashboards + ferramentas
    │   ├── 007_seeds.sql                   # admin inicial (sem dados de exemplo)
    │   ├── 008_ingest.sql                  # bx_ingest_ops_empenhos / bx_ingest_prioridades
    │   └── README.md                       # modelo de domínio + regras detalhadas
    ├── workspaces/                          # workflows n8n (importar via JSON)
    │   ├── Bralyx-Front.json                # GET bralyx-app (serve a SPA)
    │   ├── Bralyx-Agent.json                # POST bralyx-AgentRag (AI Agent + RAG + 9 tools)
    │   ├── Bralyx-Bridge.json               # POST bralyx-tool-* → RPCs bx_*
    │   ├── Bralyx-Relatorio.json            # POST bralyx-relatorio (ingestão CSV)
    │   ├── Bralyx-RAG.json                  # upload + Google Drive + reindex
    │   ├── Bralyx-RAG-Admin.json            # admin da base de conhecimento
    │   ├── Bralyx-AdminUser.json            # criação de usuários (service_role)
    │   ├── Bralyx-Chat-GET-Sessions.json    # GET bralyx-sessions
    │   ├── Bralyx-Chat-GET-History.json     # GET bralyx-history
    │   ├── Bralyx-Chat-DELETE-Session.json  # DELETE bralyx-session
    │   └── README.md                        # mapa workflow → webhook → RPC + credenciais
    ├── knowledge/                           # base de conhecimento (RAG)
    │   ├── 00_visao_geral_bralyx.md
    │   ├── 01_glossario_pcp.md
    │   ├── 02_status_op_regras.md
    │   ├── 03_cruzamento_necessidade_transferido_falta.md
    │   ├── 04_faltantes_compras.md
    │   ├── 05_como_ler_relatorios_protheus.md
    │   ├── 06_decisoes_e_acoes.md
    │   ├── 07_playbook_agente.md
    │   ├── 08_faq_pcp.md
    │   └── README.md
    └── .specs/                              # SDD (este diretório)
        ├── codebase/                        # mapeamento brownfield (7 docs)
        └── project/                         # PROJECT / ROADMAP / STATE
```

## Pontos de entrada por tarefa

| Quero mexer em… | Vá para… |
|---|---|
| Regras de status / priorização | `migrations-clean/006_pcp_rpc.sql` |
| Esquema de dados / parsers | `migrations-clean/005_pcp_schema.sql` |
| Ingestão de CSV | `migrations-clean/008_ingest.sql` + `Bralyx-Relatorio.json` |
| Interface / dashboards / chat | `front-bralyx.html` (depois rodar build script) |
| Comportamento do agente / tools | `Bralyx-Agent.json` + `Bralyx-Bridge.json` |
| Conhecimento do RAG | `knowledge/*.md` + `Bralyx-RAG*.json` |
