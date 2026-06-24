# PROJECT — Bralyx PCP Agent

## Visão

Copiloto de IA para o **PCP da Bralyx** (fabricante de equipamentos para
alimentação — formadoras, empanadeiras, fritadeiras, etc.). Transforma os dados
que **já existem** no ERP Protheus em uma visão clara da situação de cada
**Ordem de Produção (OP)**, sem exigir cruzamento manual entre produção,
estoque, compras e componentes faltantes.

## Problema

Os dados existem, mas entender cada OP exige cruzar manualmente produção,
estoque, compras e faltantes. É lento e propenso a erro. O PCP precisa de
respostas diretas em linguagem natural.

## Perguntas que o produto responde

- **Quais máquinas posso liberar para montagem esta semana?**
- **O que falta para concluir a OP da máquina X?**
- Quais OPs estão travadas por falta de material?
- Quais faltantes já têm pedido de compra? Quais não têm estoque nem pedido?
- Quais compras estão atrasadas? O que devo priorizar?

## Princípios

1. **As regras calculam, o LLM justifica.** Status e priorização são
   determinísticos (RPCs no Postgres); o modelo só redige a explicação.
2. **Human-in-the-loop.** O agente recomenda; o PCP/compras/produção decide.
3. **Não altera o ERP.** Somente leitura via export; organiza e interpreta.
4. **Replace-on-upload.** Cada CSV é um snapshot e substitui o anterior — sem
   sincronização de planilha-mestre.

## Usuários

- **PCP / Planejamento** (principal) — prioriza OPs, libera montagem.
- **Compras** — acompanha faltantes e pedidos atrasados.
- **Produção / Montagem** — vê o que está liberado.
- Papéis: `admin` (gestão de usuários/dados) e `visualizacao` (consulta).

## Escopo atual

Entrega **completa** em primeira versão: migrations, workflows n8n, RAG/base de
conhecimento, front SPA. Pendências são de **configuração** (credenciais, CONFIG
do front, aplicar migrations, enviar CSVs reais), não de desenvolvimento.

## Fora de escopo

- Escrita/integração direta com o Protheus.
- Decisão automática (sem aprovação humana).
- Sincronização de planilha-mestre (substituída por replace-on-upload).
