---
titulo: Perguntas Frequentes (FAQ)
area: faq
tags: [faq, duvidas, pcp, montagem]
---

# FAQ — PCP e Montagem

**Por que uma OP aparece como "travada"?**
Porque ela tem mais componentes em falta do que o limite de "quase completa"
(mais de 3 itens e mais de 10% do total). Veja o detalhe da OP para saber quais.

**O que significa "quase completa"?**
Falta pouco: **até 3** componentes **ou** **até 10%** do total. Costuma ser
resolvida com uma compra/transferência pontual.

**Quando uma OP "pode montar"?**
Somente quando está **completa** — zero componentes em falta. Aí o status é
`completa` e `pode_montar = true`.

**Uma OP apareceu como "sem dados". E agora?**
Ela não tem empenhos cadastrados. Reenvie o relatório de **OP/Empenhos +
Transferência** para que os componentes sejam carregados.

**Qual a diferença entre "falta parcial" e "falta total"?**
`falta_parcial` = parte já foi transferida, mas ainda falta um pedaço.
`falta_total` = nada foi transferido para a OP.

**Um componente está em falta mas "tem pedido". Preciso comprar de novo?**
Não necessariamente — já existe pedido em aberto. Verifique a **data prevista**:
se estiver atrasada, a ação é **cobrar o fornecedor**, não abrir outro pedido.

**Por que devo olhar "faltantes sem pedido"?**
São os componentes que **ainda não viraram compra** — a fila mais urgente do
setor de Compras. Resolver os que travam mais OPs destrava mais produção.

**Os números mudam quando subo um novo CSV?**
Sim. Cada importação **substitui** o relatório anterior do mesmo tipo e o sistema
**recalcula todas as OPs**. O que você vê reflete sempre o último upload.

**Preciso subir os dois CSVs?**
O de **OP/Empenhos** é o essencial (cria OPs e componentes). O de **Prioridades**
enriquece com cliente, montador, datas e situação — recomendado para a priorização
e os dias de atraso.

**O copiloto decide por mim?**
Não. Ele **recomenda e prioriza**. A **decisão é da equipe** e pode ser registrada
para alimentar o aprendizado do padrão do time.

**Posso anexar um arquivo só para esta conversa?**
Sim. Use o clipe (📎) no chat: o arquivo fica disponível **apenas naquela
conversa** (busca por `search_session_files`), sem entrar na base global.
