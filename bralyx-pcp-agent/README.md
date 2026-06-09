# Bralyx — Copiloto de PCP, Estoque e Compras

Agente de IA para a **Bralyx** (fabricante de equipamentos para alimentação —
formadoras, empanadeiras, fritadeiras, etc.). É um **assistente de PCP** que
transforma os dados que já existem no ERP (Protheus) em uma visão clara da
situação de cada **Ordem de Produção (OP)**.

A dor central: os dados existem, mas entender cada OP exige cruzar manualmente
produção, estoque, compras e componentes faltantes. O agente automatiza esse
cruzamento e responde, em linguagem natural:

- **"Quais máquinas posso liberar para montagem esta semana?"**
- **"O que falta para concluir a OP da máquina X?"**
- "Quais OPs estão travadas por falta de material?"
- "Quais faltantes já têm pedido de compra? Quais não têm estoque nem pedido?"
- "Quais compras estão atrasadas?" · "O que devo priorizar?"

O agente **não decide nem altera o ERP** — ele organiza, cruza e interpreta para
o PCP/compras/produção decidirem mais rápido (human-in-the-loop).

## Arquitetura

```
front (SPA)  ──HTTP──►  n8n (webhooks bralyx-*)  ──►  Supabase (Postgres + pgvector + Auth)
                                 │
                                 ├─ AI Agent (Azure OpenAI gpt-4o-mini)
                                 ├─ RAG (text-embedding-3-small → bx_documents)
                                 └─ RPCs SECURITY DEFINER (motor de regras determinístico)
```

Princípio: **as regras calculam, o LLM justifica**. Todo o status de OP/componente
e a priorização são feitos por RPCs no banco; o modelo apenas redige a explicação.

## Fontes de dados (somente 2 CSVs do Protheus — sem PDF, sem planilha-mestre)

| Relatório | Vira… |
|---|---|
| `OP_Empenhos_Transferencia.csv` | OPs (`bx_op`) + componentes/empenhos (`bx_empenho`) |
| `Prioridades - …(Lista Geral).csv` | enriquece as OPs (cliente, montador, status, painel, datas) |

**Replace-on-upload:** cada CSV é um snapshot e **substitui** o anterior — não há
sincronização de planilha nem IDs de planilha a configurar. O **único ID** do
projeto é a pasta do Google Drive do RAG:
`18enOlOFXT_r4TH5w7cC16fYhfls7PItB`.

## Estrutura

| Pasta | Conteúdo | Status |
|---|---|---|
| `migrations-clean/` | Esquema Supabase (auth/RAG, OPs/empenhos, motor de regras, ingestão). Ver `migrations-clean/README.md`. | ✅ pronto |
| `workspaces/` | Workflows n8n (`bralyx-*`). | ⏳ próxima etapa |
| `knowledge/` | Base de conhecimento (RAG). | ⏳ próxima etapa |
| `front-bralyx.html` | SPA (login, dashboards de OPs, chat). | ⏳ próxima etapa |

> Derivado do agente **Welmy** (`../welmy-pcp-agent/`), mantido como referência.
> O domínio foi refeito para o PCP por **Ordem de Produção** da Bralyx.

## Como subir o banco

Aplicar `migrations-clean/*.sql` no Supabase **na ordem numérica** (SQL Editor).
Ver detalhes, modelo de domínio e regras em `migrations-clean/README.md`.

## Stack

- **n8n** — orquestração e webhooks (`bralyx-*`).
- **Supabase** — Postgres 15 + `pgvector` + Auth (RLS). Papel em
  `raw_user_meta_data.role ∈ {admin, visualizacao}`, `company_name='bralyx'`.
- **Azure OpenAI** — `gpt-4o-mini` (chat) e `text-embedding-3-small` (1536 dims).
