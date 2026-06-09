---
titulo: Decisões e Ações
area: regras
tags: [decisao, acao, learning, human-in-the-loop]
---

# Decisões e Ações

A equipe pode **registrar a decisão** tomada para uma OP. Isso cria um histórico
que alimenta o aprendizado do padrão do time (sinais de concordância).

## Vocabulário de ações
| Ação | Quando usar |
|---|---|
| **liberar_montagem** | OP `completa` — todos os componentes transferidos. |
| **priorizar_compra** | Faltante sem pedido — abrir/priorizar a compra. |
| **cobrar_fornecedor** | Pedido em aberto **atrasado**. |
| **transferir** | Componente disponível em estoque — transferir para a OP. |
| **aguardar** | Sem informação suficiente ou aguardando etapa anterior. |

## Como é registrado
- Cada decisão guarda: OP, **status calculado** no momento, **ação**, **motivo**
  (opcional), **origem** (`humano` ou `ia`) e um **snapshot** da OP.
- Quando o copiloto registra automaticamente (a pedido do usuário), a origem é
  `ia`. Quando a equipe registra na tela, é `humano`.

## Aprendizado (learning signals)
A ferramenta `learning_signals` resume, por **status × ação**, a **taxa de
concordância** das decisões passadas. O copiloto consulta esse sinal antes de
recomendar, para **seguir o padrão do time** em vez de impor um critério fixo.

## Human-in-the-loop
O copiloto **só registra** uma decisão quando o usuário **pede ou confirma**. Por
padrão ele **apenas recomenda** — a decisão final é sempre da equipe de PCP/
Montagem.
