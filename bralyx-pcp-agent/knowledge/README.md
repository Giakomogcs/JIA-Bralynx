# Base de Conhecimento (RAG) — Bralyx PCP

Documentos internos que alimentam o **Copiloto de PCP** via RAG. O assistente
busca trechos aqui (`search_knowledge_base`) para fundamentar respostas e seguir
as regras do domínio.

## Conteúdo
| Arquivo | Tema |
|---|---|
| `00_visao_geral_bralyx.md` | O que o copiloto faz, OPs/empenhos, fontes de dados, princípio humano-decide. |
| `01_glossario_pcp.md` | Glossário (OP, empenho, transferido, falta, pedido, painel…). |
| `02_status_op_regras.md` | Regras determinísticas de status do componente e da OP. |
| `03_cruzamento_necessidade_transferido_falta.md` | Como necessário × transferido × falta é calculado. |
| `04_faltantes_compras.md` | Faltantes agregados, pedidos e compras atrasadas. |
| `05_como_ler_relatorios_protheus.md` | Colunas dos CSVs OP/Empenhos e Prioridades. |
| `06_decisoes_e_acoes.md` | Vocabulário de ações, registro de decisão e learning. |
| `07_playbook_agente.md` | Ferramentas e fluxos do agente. |
| `08_faq_pcp.md` | Perguntas frequentes da operação. |

## Como indexar
1. Abra o app (front) → tela **Documentos (RAG)** → **Enviar documento** (admin).
   Cada `.md` é extraído, dividido em trechos e indexado em `bx_documents`.
2. Ou coloque os arquivos na pasta do **Google Drive** conectada
   (`18enOlOFXT_r4TH5w7cC16fYhfls7PItB`) usada pelo workflow **Bralyx-RAG**.

## Boas práticas
- Mantenha os documentos **curtos e objetivos**, com tabelas quando ajudar.
- Ao mudar uma regra no banco, **atualize o `.md` correspondente** e reindexe.
- Não inclua segredos/credenciais — o conteúdo fica acessível a todos os usuários.
