# STACK — Bralyx PCP Agent

> Copiloto de PCP, Estoque e Compras da Bralyx (fabricante de equipamentos para
> alimentação). Transforma os exports do Protheus em uma visão por Ordem de
> Produção (OP). **As regras calculam, o LLM justifica.**

## Camadas

| Camada | Tecnologia | Detalhes |
|---|---|---|
| **Orquestração** | n8n | Workflows `bralyx-*` (webhooks). Importados via JSON em `workspaces/`. |
| **Banco / Backend** | Supabase (Postgres 15) | `pgvector` (HNSW), Auth (RLS), RPCs `SECURITY DEFINER`. Prefixo de objetos `bx_`. |
| **LLM (chat)** | Azure OpenAI `gpt-4o-mini` | Apenas redige justificativas executivas. |
| **Embeddings (RAG)** | Azure OpenAI `text-embedding-3-small` | 1536 dimensões → `bx_documents`. |
| **Front** | SPA HTML única (`front-bralyx.html`) | Servida embutida pelo workflow `Bralyx-Front.json`. Sem build de framework. |
| **Scripts** | PowerShell (`.scripts/`) | `build-front-workflow.ps1`, `scaffold-infra-workflows.ps1`. |

## Identidade / convenções de plataforma

- Prefixo de tabelas/RPCs: **`bx_`**.
- Prefixo de webhooks n8n: **`bralyx-*`**.
- Papel do usuário em `raw_user_meta_data.role ∈ {admin, visualizacao}`,
  `company_name = 'bralyx'`.
- Admin inicial: `admin@bralyx.com.br` / `@Admin123` (trocar no 1º login).

## Integrações externas

- **Google Drive** (RAG): pasta única `18enOlOFXT_r4TH5w7cC16fYhfls7PItB`.
- **Azure OpenAI**: chat + embeddings.
- **Supabase Vector Store / service_role**: usados pelos workflows de RAG/Admin.

## Origem

Derivado do projeto **Welmy** (`../welmy-pcp-agent/`, mantido como referência —
não modificar). Domínio refeito: objeto central = **OP** e o cruzamento
`necessidade × transferido × falta × pedido de compra`.
