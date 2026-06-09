---
titulo: Como Ler os Relatórios do Protheus
area: operacao
tags: [protheus, csv, op_empenhos, prioridades, importacao]
---

# Como Ler os Relatórios do Protheus

São **dois CSVs** (separador `;`). O sistema reconhece cada tipo pelas colunas e
roteia para a ingestão certa. Cada novo arquivo **substitui** o anterior do mesmo
tipo.

## 1) OP/Empenhos + Transferência
Cria as OPs e seus componentes. Colunas reconhecidas:

| Coluna | Conteúdo |
|---|---|
| `Chave` | Chave/identificador da OP no Protheus. |
| `C2_PRODUTO` | Código do produto da OP. |
| `C2_XDESCP` | Descrição do produto. |
| `C2_QUANT` | Quantidade da OP. |
| `C2_DATPRI` / `C2_DATPRF` | Datas de início/fim previstas. |
| `D4_COD` | Código do **componente** (empenho). |
| `D4_QTDEORI` | Quantidade original do empenho. |
| `Soma de D4_QUANT` | **Quantidade necessária** do componente. |
| `D4_XQFALFI` | **Quantidade em falta**. |
| `D4_XQTRANS` | **Quantidade transferida** para a OP. |

> Linhas sem OP **e** sem componente (subtotais/vazias) são ignoradas.

## 2) Lista de Prioridades
Enriquece as OPs existentes (ou cria as que faltarem). Colunas reconhecidas:

| Coluna | Conteúdo |
|---|---|
| `OP` | Número da OP (chave de ligação). |
| `Mercado` | Mercado/segmento. |
| `CLIENTE` | Cliente. |
| `MONTADOR` | Montador responsável. |
| `CÓD` / `MÁQUINA` | Código e descrição do produto. |
| `Situação` | Situação da OP no ERP. |
| `FALTAS` | Texto de faltas de itens para painéis. |
| `CÓDIGO PAINEL` / `OP_PAINEL` / `Fornecedor` / `Situação_PAINEL` | Dados do painel. |
| `Data da Solicitação`, `Prazo (Comercial)`, `Data final acordada - P.A`, `Data Entrega` | Datas. |
| `Dias de Atraso` | Atraso da OP. |
| `Faturada?` | Se já foi faturada. |
| `Observações` | Observações. |

## Onde subir
Tela **Atualizar dados** → arraste os CSVs (pode soltar os dois juntos). O
histórico aparece em **Importações**. Após cada upload o sistema recalcula
**todas** as OPs.

## Dicas de leitura
- Números no padrão brasileiro (`1.234,56`) são interpretados corretamente.
- Acentos (MÁQUINA, Situação) são tratados; o arquivo pode estar em UTF-8 ou
  Latin-1.
- Se uma OP aparecer como **sem_dados**, o relatório de **OP/Empenhos** ainda não
  trouxe os componentes dela — reenvie esse CSV.
