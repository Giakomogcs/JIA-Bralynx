---
titulo: Glossário de PCP e Montagem
area: glossario
tags: [glossario, op, empenho, transferido, falta, protheus]
---

# Glossário — PCP, OPs e Empenhos

| Termo | Significado |
|---|---|
| **OP (Ordem de Produção)** | Ordem para fabricar/montar um produto. Identificada por um **número**. Origem: tabela **SC2** do Protheus. |
| **Empenho** | Reserva de um **componente** para uma OP específica. Origem: tabela **SD4** do Protheus. Cada OP tem vários empenhos. |
| **Componente** | Item (peça, matéria-prima, conjunto) que entra na montagem da OP. |
| **Qtd. necessária** | Quanto do componente a OP precisa (campo `Soma de D4_QUANT`). |
| **Qtd. transferida** | Quanto já foi separado/transferido para a OP (`D4_XQTRANS`). |
| **Qtd. falta** | Quanto ainda falta = necessária − transferida (`D4_XQFALFI`). |
| **Pedido de compra** | Ordem de compra de um componente (fornecedor, quantidade, data prevista). |
| **Pedido atrasado** | Pedido de compra cuja **data prevista já passou**. |
| **Mercado** | Segmento/destino da OP (vem da Lista de Prioridades). |
| **Montador** | Responsável pela montagem da OP. |
| **Cliente** | Cliente da OP. |
| **Situação (ERP)** | Status da OP no Protheus (texto livre do relatório de prioridades). |
| **Painel** | Subconjunto elétrico associado à OP (código, OP do painel, fornecedor, situação). |
| **Data acordada** | Data final acordada com o comercial (P.A) para a entrega. |
| **Dias de atraso** | Dias de atraso da OP em relação à data acordada/entrega. |
| **Importação** | Cada upload de um relatório do Protheus. Mantém histórico único por tipo. |
| **Decisão** | Registro do que a equipe decidiu para uma OP (ver `06_decisoes_e_acoes`). |

## Status (resumo — detalhe em `02_status_op_regras`)
- **Componente:** `ok` · `transferido` · `falta_parcial` · `falta_total`.
- **OP:** `completa` · `quase_completa` · `travada` · `sem_dados`.
