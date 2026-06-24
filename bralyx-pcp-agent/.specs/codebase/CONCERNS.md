# CONCERNS — Bralyx PCP Agent

Riscos, dívidas técnicas e áreas frágeis. Consulte antes de planejar features que
toquem nestes pontos.

## Alto

- **Sem testes automatizados.** Nenhum runner/gate. Regras críticas
  (`bx_classificar_componente`, `bx_classificar_op`, parsers BR, ingestão) só são
  validadas manualmente. Regressões passam despercebidas. → ver `TESTING.md`.
- **Parser de CSV frágil a duplicatas de header.** A Lista de Prioridades tem
  colunas repetidas ("OP", "Situação"); o parser do `Bralyx-Relatorio.json` faz
  dedup (`seenH`: 2ª "OP" → "OP_PAINEL", 2ª "Situação" → "Situação_PAINEL").
  Mudanças no layout do export podem quebrar silenciosamente o cruzamento.
- **Amostra de `OP_Empenhos` sem nº de OP.** A amostra atual traz só componentes
  agregados (colunas de OP vazias). O cruzamento OP↔componente e os faltantes só
  funcionam quando o export real traz a OP por linha (confirmado pelo usuário,
  mas ainda não validado com dados reais).

## Médio

- **Credenciais como placeholders.** Vários `REPLACE_ME_*` nos workflows e
  `CONFIG` do front apontando para a infra antiga (Welmy/longflatworm). Precisa
  ser ajustado pelo usuário antes de funcionar.
- **Datas sem ano assumem o ano atual.** `bx_parse_ts` completa ano ausente com
  `CURRENT_DATE` (por isso `STABLE`). Importações feitas na virada de ano podem
  classificar datas no ano errado.
- **Front é arquivo único grande embutido em JSON.** `front-bralyx.html` (~127KB)
  é embutido no `Bralyx-Front.json` via script. Esquecer de rodar
  `build-front-workflow.ps1` após editar o HTML deixa o app desatualizado.
- **Atraso usa apenas o campo preenchido.** Decisão de negócio: não inferir
  atraso. OPs sem prazo aparecem como "sem dados", o que pode subestimar a
  urgência real.

## Baixo

- **Referências a "Welmy" remanescentes.** Apenas em docs/origem (intencional).
- **Replace-on-upload apaga histórico.** Cada CSV substitui o anterior
  (`DELETE` em `bx_empenho`); não há versionamento de snapshots além do log único
  em `bx_importacao`.

## Pré-requisitos operacionais (não são bugs)

- Extensão `vector` habilitada no Supabase + Auth ativo.
- Trocar a senha do admin inicial (`admin@bralyx.com.br` / `@Admin123`).
- Projeto de referência `welmy-pcp-agent/` **não deve ser modificado**.
