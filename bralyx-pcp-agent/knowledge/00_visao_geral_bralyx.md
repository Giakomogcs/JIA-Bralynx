---
titulo: Visão Geral da Bralyx e do Copiloto de PCP
area: contexto
tags: [bralyx, pcp, montagem, ordens-de-producao, copiloto, objetivo]
---

# Visão Geral — Bralyx e o Copiloto de PCP

## O que o copiloto faz
O **Copiloto de PCP da Bralyx** é uma ferramenta de uso interno que apoia o
**Planejamento e Controle da Produção (PCP)** e a **Montagem** a responder, a
qualquer momento, duas perguntas práticas:

1. **Quais Ordens de Produção (OPs) podem ir para a montagem agora?**
2. **O que ainda falta** para liberar as demais — e o que fazer a respeito.

## Como o trabalho é organizado
- Uma **OP (Ordem de Produção)** representa a fabricação de um produto. Tem
  número, código e descrição do produto, quantidade, **mercado**, **cliente**,
  **montador** e a **situação no ERP (Protheus)**.
- Cada OP tem uma lista de **empenhos** = os **componentes** necessários para
  montá-la. Para cada componente o sistema acompanha três quantidades:
  **necessária**, **transferida** (já separada/transferida para a OP) e
  **falta** (= necessária − transferida).
- Quando um componente está em falta, o sistema verifica se há um **pedido de
  compra** em aberto para ele (fornecedor + data prevista) e se está **atrasado**.

## De onde vêm os dados
Tudo vem de **dois relatórios do Protheus em CSV**, reenviados quando atualizam:

| Relatório | Para que serve |
|---|---|
| **OP/Empenhos + Transferência** | Cria as OPs e seus componentes; traz necessária, transferida e falta. |
| **Lista de Prioridades** | Enriquece as OPs com cliente, montador, mercado, situação, painel e datas. |

Cada novo arquivo **substitui** o anterior do mesmo tipo (snapshot do ERP). Não
há planilha-mestre sincronizada — basta reenviar o CSV atualizado.

## Princípio central (humano decide)
O **motor de regras determinístico** calcula o status de cada componente e de
cada OP. O **LLM apenas explica e prioriza** em linguagem clara — **não
recalcula** o status e **não inventa** dados. A recomendação é do copiloto; a
**decisão é da equipe** de PCP/Montagem (human-in-the-loop).
