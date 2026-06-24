# ROADMAP — Bralyx PCP Agent

## Marco 0 — MVP entregue ✅

Toda a base de desenvolvimento está pronta (ver `STATE.md` para detalhes).

| Componente | Status |
|---|---|
| Migrations `001`–`008` (auth, RAG, PCP schema, motor de regras, ingestão) | ✅ |
| Workflows n8n (10: Front, Agent, Bridge, Relatorio, RAG, RAG-Admin, AdminUser, 3× Chat) | ✅ |
| Front SPA `front-bralyx.html` (painel + ops/faltantes/compras/montagem/dados/docs/usuários/chat) | ✅ |
| Base de conhecimento `knowledge/` (9 docs + README) | ✅ |
| Scripts `.scripts/` (build front, scaffold infra) | ✅ |

## Marco 1 — Go-live (configuração) ⏳

Pendências do **usuário**, não de desenvolvimento:

- [ ] Trocar `REPLACE_ME_*` por credenciais reais nos workflows n8n.
- [ ] Ajustar `CONFIG` do `front-bralyx.html` para a infra Bralyx + rebuild.
- [ ] Aplicar `migrations-clean/*.sql` no Supabase (em ordem).
- [ ] Habilitar extensão `vector` + Supabase Auth.
- [ ] Enviar os 2 CSVs reais do Protheus e validar `bx_stats()` / dashboards.
- [ ] Trocar a senha do admin inicial.

## Marco 2 — Robustez (próximas features candidatas)

Backlog priorizado para a próxima etapa de desenvolvimento (SDD):

| # | Feature | Tamanho est. | Toca CONCERNS |
|---|---|---|---|
| F1 | **Testes de regras (pgTAP/SQL)** para `bx_classificar_*` e parsers BR | Médio | Sem testes (Alto) |
| F2 | **Validação com export real** de `OP_Empenhos` (OP por linha) | Médio | Amostra sem nº OP |
| F3 | **Smoke test do front** (Playwright: login + painel) | Médio | Sem testes |
| F4 | **Hardening do parser de CSV** (tolerância a mudança de layout/headers) | Médio | Parser frágil |
| F5 | **Versionamento de snapshots** de importação (além do log único) | Grande | Replace apaga histórico |

> Ao iniciar qualquer feature: Specify → (Design) → (Tasks) → Execute, com
> profundidade auto-dimensionada (ver `SKILL.md`). Consultar `CONCERNS.md` antes.

## Não planejado (fora de escopo)

- Integração de escrita com o Protheus.
- Decisão automática sem aprovação humana.
