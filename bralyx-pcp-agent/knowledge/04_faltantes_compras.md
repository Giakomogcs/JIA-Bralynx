---
titulo: Faltantes, Pedidos e Compras Atrasadas
area: regras
tags: [faltantes, compras, pedido, fornecedor, atraso]
---

# Faltantes, Pedidos e Compras Atrasadas

## Componentes faltantes (visão de compras)
A tela **Faltantes** (e a ferramenta `componentes_faltantes`) agrupa por código
de componente, somando entre todas as OPs:

- **OPs afetadas** — quantas OPs aquele item trava (distintas).
- **Falta total** — soma das quantidades faltantes.
- **Tem pedido / sem pedido** — se existe pedido de compra em aberto.
- **Previsão** — data prevista mais próxima (e se está atrasada).
- **Fornecedor** e **estoque atual** do item.

Use o filtro **"só sem pedido"** para ver o que **ainda precisa virar compra** —
é a fila de trabalho do setor de Compras. Resolver um item no topo (muitas OPs
afetadas, sem pedido) costuma destravar o maior número de OPs.

## Compras atrasadas (cobrança de fornecedor)
A tela **Compras atrasadas** (e a ferramenta `compras_atrasadas`) lista os
**pedidos de compra cuja data prevista já venceu** (`aberto`/`parcial`/
`atrasado` e `data_prevista < hoje`):

- fornecedor, quantidade, data do pedido e data prevista;
- **dias de atraso**;
- **OPs dependentes** — quantas OPs estão esperando aquele pedido.

É a base para **priorizar as cobranças**: comece pelos pedidos mais atrasados
que travam mais OPs.

## Como isso vira ação
| Situação | Ação sugerida |
|---|---|
| Faltante **sem pedido**, muitas OPs | `priorizar_compra` (abrir/priorizar pedido). |
| Faltante **com pedido atrasado** | `cobrar_fornecedor`. |
| Componente disponível em estoque | `transferir` para a OP. |
| OP `completa` | `liberar_montagem`. |
| Sem informação suficiente | `aguardar` e reimportar o relatório. |

O copiloto **recomenda**; a equipe **decide** e pode registrar a decisão
(ver `06_decisoes_e_acoes`).
