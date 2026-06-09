---
titulo: Cruzamento Necessário × Transferido × Falta
area: regras
tags: [cruzamento, empenho, transferencia, estoque, pedido]
---

# Cruzamento — Necessário × Transferido × Falta

Este é o coração do copiloto: como o sistema decide o que falta em cada OP.

## Por componente
Para cada linha de empenho (componente de uma OP):

```
falta = qtd_necessaria − qtd_transferida
```

- `qtd_necessaria` vem de **`Soma de D4_QUANT`** (ou `D4_QUANT`).
- `qtd_transferida` vem de **`D4_XQTRANS`** (o que já foi para a produção/OP).
- `qtd_falta` vem de **`D4_XQFALFI`** quando presente; senão é recalculado pela
  fórmula acima.

O status do componente sai dessa conta (ver `02_status_op_regras`).

## Pedido de compra do componente
Para cada componente em falta, o sistema procura **pedidos de compra em aberto**
do mesmo código:

- **tem_pedido** = existe pedido aberto/parcial para o código.
- **pedido_data_prevista** = a data prevista mais próxima.
- **pedido_atrasado** = a data prevista já passou (`< hoje`).
- **fornecedor** = fornecedor do pedido.

Assim cada faltante é classificado entre **"já tem pedido"** (acompanhar) e
**"sem pedido"** (precisa virar compra).

## Estoque do componente
O **estoque atual** do item (quando conhecido) é exibido junto ao faltante para
ajudar a decidir entre **transferir do estoque** ou **comprar**.

## Da OP para o agregado
- **No detalhe da OP** (`bx_op_detalhe`): lista os componentes em falta daquela
  OP, com pedido/previsão/fornecedor, e separadamente os já transferidos.
- **No agregado** (`bx_componentes_faltantes`): soma o mesmo componente entre
  **todas** as OPs, mostrando **quantas OPs ele trava** e a **quantidade total
  faltante**. É a visão de quem compra: resolver um item destrava várias OPs.

## Substituição a cada importação
Cada importação de **OP/Empenhos** **zera os empenhos anteriores** e recria a
partir do novo arquivo (snapshot). A falta e a transferência refletem **100% o
arquivo mais recente** — não há acúmulo entre uploads.
