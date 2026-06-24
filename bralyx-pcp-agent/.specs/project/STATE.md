# STATE — Bralyx PCP Agent

> Memória persistente: decisões, blockers, lições, todos e ideias adiadas.
> Carregar no início de cada sessão.

## Decisões

- **Replace-on-upload** em vez de planilha-mestre sincronizada: cada CSV é um
  snapshot e substitui o anterior. Único ID fixo = pasta Drive do RAG
  `18enOlOFXT_r4TH5w7cC16fYhfls7PItB`.
- **As regras calculam, o LLM justifica** — status/priorização em RPCs
  determinísticas; modelo só redige.
- **Objeto central = OP** (Ordem de Produção); cruzamento
  `necessidade × transferido × falta × pedido de compra`.
- **Datas sem ano ⇒ ano atual** (`bx_parse_ts` é `STABLE`).
- **Atraso usa só o campo preenchido** — não inferir; sem prazo = "sem dados".
- **Vocabulário de ação:** liberar_montagem | priorizar_compra | cobrar_fornecedor
  | transferir | aguardar.
- Projeto derivado de **welmy-pcp-agent/** (referência — **não modificar**).
- Prefixos: tabelas/RPCs `bx_`, webhooks `bralyx-*`.

## Blockers / pendências (do usuário, p/ go-live)

- Trocar credenciais `REPLACE_ME_*` nos workflows n8n.
- Ajustar `CONFIG` do front (ainda aponta p/ infra Welmy/longflatworm) + rebuild.
- Aplicar migrations no Supabase + habilitar `vector`/Auth.
- Enviar os 2 CSVs reais e validar.

## Lições aprendidas

- **Header duplicado no CSV de Prioridades** ("OP"/"Situação" × 2) quebrava o
  cruzamento — corrigido com dedup no parser (`seenH` → `OP_PAINEL`/`Situação_PAINEL`).
- **Datas pt "DD-mmm"** não parseavam — `bx_parse_ts` tornou-se `STABLE` e trata
  `DD-mmm` pt / `DD-mmm-YY` / `DD/MM`.
- **Front embutido em JSON**: sempre rodar `.scripts/build-front-workflow.ps1`
  após editar `front-bralyx.html`.
- Amostra de `OP_Empenhos` veio agregada sem nº de OP → faltantes só com export real.

## Todos (desenvolvimento futuro)

- [ ] F1 Testes de regras (pgTAP/SQL) — `bx_classificar_*`, parsers.
- [ ] F2 Validar com export real de `OP_Empenhos`.
- [ ] F3 Smoke test do front (Playwright).
- [ ] F4 Hardening do parser de CSV.
- [ ] F5 Versionamento de snapshots de importação.

## Ideias adiadas

- Integração de escrita com Protheus (fora de escopo).
- Decisão automática sem aprovação humana (viola human-in-the-loop).

## Preferences

- (vazio — registrar aqui preferências do usuário p/ não repetir dicas)

## Status atual

MVP de desenvolvimento **completo** (migrations + workflows + front + RAG +
knowledge). Próximo: Marco 1 (config/go-live) e Marco 2 (robustez/testes).
SDD inicializado em `.specs/` em 2026-06-23.
