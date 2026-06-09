---
titulo: Regras de Status de Componente e de OP
area: regras
tags: [status, regras, completa, quase_completa, travada, falta]
---

# Regras de Status (determinísticas)

O status é **calculado pelo banco** (motor de regras), nunca pelo LLM. As regras
abaixo refletem exatamente o que está implementado.

## Status do componente
Para cada componente de uma OP, com `falta = necessária − transferida`:

| Status | Condição | Leitura |
|---|---|---|
| **ok** | `falta ≤ 0` | Não falta nada. |
| **transferido** | `transferida ≥ necessária` | Já transferido o suficiente. |
| **falta_parcial** | `0 < falta < necessária` | Falta uma parte. |
| **falta_total** | `falta ≥ necessária` | Nada foi transferido. |

> Componentes `ok` e `transferido` não bloqueiam a OP. `falta_parcial` e
> `falta_total` são os que contam como **faltantes**.

## Status da OP
A partir da contagem de componentes faltantes da OP:

| Status | Condição | Ação típica |
|---|---|---|
| **completa** | **0** componentes em falta | `pode_montar = true` → liberar montagem. |
| **quase_completa** | faltam **≤ 3** componentes **OU** **≤ 10%** do total | Falta pouco; priorizar o que falta. |
| **travada** | faltam **mais** que o limite acima | Depende de compra/transferência. |
| **sem_dados** | OP **sem empenhos** cadastrados | Reimportar o relatório de OP/Empenhos. |

- **pode_montar** é verdadeiro **somente** quando o status é `completa`.
- **faltantes_sem_pedido** = componentes em falta que **não** têm pedido de
  compra em aberto (os mais urgentes para virar compra).

## Prioridade
A prioridade da OP é calculada considerando o status (travada/quase/completa),
os **dias de atraso** e a **data acordada**. OPs mais atrasadas e mais próximas
da data sobem na lista.

## Recálculo
Sempre que um relatório é importado, o sistema **recalcula** o status e a
prioridade de **todas** as OPs com as bases atuais. Não há estado "velho"
pendurado: o que aparece reflete o último upload.
