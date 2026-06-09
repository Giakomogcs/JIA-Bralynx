-- =============================================
-- Bralyx — 005: PCP / Estoque / Compras (schema)
--
-- Modela o domínio do "Copiloto de PCP" da Bralyx. A dor central: os dados já
-- existem no ERP (Protheus), mas entender a situação real de cada Ordem de
-- Produção (OP) exige cruzamento manual entre produção, estoque, compras e
-- componentes faltantes. Este schema guarda o resultado desse cruzamento.
--
--   * bx_fornecedor    — fornecedores / terceiros / fabricantes de painel
--   * bx_item          — catálogo de componentes/peças + saldo em estoque
--   * bx_op            — Ordens de Produção (cabeçalho SC2 + enriquecimento da
--                        Lista de Prioridades: cliente, montador, status, datas)
--   * bx_empenho       — componentes necessários por OP (empenhos SD4):
--                        qtd necessária, qtd transferida p/ produção, qtd falta
--   * bx_pedido_compra — pedidos de compra / acionamentos em aberto (qtd + data
--                        prevista de chegada) p/ cruzar com os faltantes
--   * bx_importacao    — log de cada importação de relatório (OP/Empenhos e
--                        Prioridades) — cada upload SUBSTITUI o anterior
--   * bx_decision_log  — decisões da equipe (base de aprendizado)
--
-- Princípio: motor de regras determinístico calcula o status da OP e dos
-- componentes; o LLM só explica. Human-in-the-loop: o agente recomenda, o PCP
-- decide. O agente NÃO altera o ERP.
-- Rode APÓS 004_chat_messages.sql
-- =============================================

-- =======  UP  ========

-- helper: parse de data BR ('DD/MM/YYYY [HH24:MI:SS]', 'DD-mon' ou ISO) -> timestamptz
CREATE OR REPLACE FUNCTION bx_parse_ts(p_txt TEXT)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v TIMESTAMPTZ;
BEGIN
  IF p_txt IS NULL OR TRIM(p_txt) = '' THEN
    RETURN NULL;
  END IF;
  BEGIN v := p_txt::timestamptz; RETURN v; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN RETURN to_timestamp(p_txt, 'DD/MM/YYYY HH24:MI:SS'); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN RETURN to_timestamp(p_txt, 'DD/MM/YYYY'); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN RETURN to_timestamp(p_txt, 'YYYYMMDD'); EXCEPTION WHEN OTHERS THEN RETURN NULL; END;
END;
$$;

-- helper: parse numérico tolerante a formato BR ("1.234,56" / "1234.56" / "1,5")
CREATE OR REPLACE FUNCTION bx_parse_num(p_txt TEXT)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  s TEXT;
BEGIN
  IF p_txt IS NULL THEN RETURN NULL; END IF;
  s := regexp_replace(p_txt, '[^0-9,.-]', '', 'g');
  IF s = '' THEN RETURN NULL; END IF;
  -- formato BR: vírgula decimal e ponto de milhar
  IF position(',' in s) > 0 AND position('.' in s) > 0 THEN
    s := replace(s, '.', '');
    s := replace(s, ',', '.');
  ELSIF position(',' in s) > 0 THEN
    s := replace(s, ',', '.');
  END IF;
  BEGIN RETURN s::NUMERIC; EXCEPTION WHEN OTHERS THEN RETURN NULL; END;
END;
$$;

-- helper: normaliza código do ERP (tira espaços de padding do Protheus)
CREATE OR REPLACE FUNCTION bx_norm_codigo(p_txt TEXT)
RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $$
  SELECT NULLIF(UPPER(TRIM(COALESCE(p_txt, ''))), '');
$$;

-- ---------- fornecedores / terceiros / fabricantes de painel ----------
CREATE TABLE IF NOT EXISTS bx_fornecedor (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nome               TEXT NOT NULL,
  cnpj               TEXT,
  tipo               TEXT NOT NULL DEFAULT 'fornecedor'
                     CHECK (tipo IN ('fornecedor','terceiro','painel','montagem')),
  lead_time_medio_dias NUMERIC,        -- prazo médio nominal (dias)
  atraso_medio_dias    NUMERIC NOT NULL DEFAULT 0,  -- histórico de atraso
  contato            TEXT,
  observacoes        TEXT,
  ativo              BOOLEAN NOT NULL DEFAULT TRUE,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_bx_fornecedor_ativo ON bx_fornecedor(ativo);

DROP TRIGGER IF EXISTS trg_bx_fornecedor_updated_at ON bx_fornecedor;
CREATE TRIGGER trg_bx_fornecedor_updated_at
  BEFORE UPDATE ON bx_fornecedor
  FOR EACH ROW EXECUTE FUNCTION bx_set_updated_at();

-- ---------- itens / componentes / peças (catálogo + estoque) ----------
-- O saldo em estoque é opcional aqui: o relatório de OP/Empenhos já traz a
-- "quantidade que falta" (D4_XQFALFI) e "quantidade transferida" (D4_XQTRANS)
-- por OP — a falta já considera o estoque alocado no Protheus. bx_item guarda
-- o catálogo (descrição/fornecedor) e, quando houver, o saldo físico global.
CREATE TABLE IF NOT EXISTS bx_item (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo             TEXT UNIQUE NOT NULL,           -- chave de cruzamento (empenho/pedido)
  descricao          TEXT,
  grupo              TEXT NOT NULL DEFAULT 'comprado'
                     CHECK (grupo IN ('materia_prima','comprado','fabricado','fabricado_terceiro','painel','embalagem')),
  unidade            TEXT DEFAULT 'un',
  fornecedor_id      UUID REFERENCES bx_fornecedor(id) ON DELETE SET NULL,
  lead_time_dias     NUMERIC,                         -- prazo de reposição (quando conhecido)
  estoque_atual      NUMERIC,                         -- saldo físico global (opcional)
  estoque_atualizado_em TIMESTAMPTZ,
  ativo              BOOLEAN NOT NULL DEFAULT TRUE,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_bx_item_grupo ON bx_item(grupo);
CREATE INDEX IF NOT EXISTS idx_bx_item_ativo ON bx_item(ativo);
CREATE INDEX IF NOT EXISTS idx_bx_item_forn  ON bx_item(fornecedor_id);

DROP TRIGGER IF EXISTS trg_bx_item_updated_at ON bx_item;
CREATE TRIGGER trg_bx_item_updated_at
  BEFORE UPDATE ON bx_item
  FOR EACH ROW EXECUTE FUNCTION bx_set_updated_at();

-- ---------- pedidos de compra / acionamentos em aberto ----------
-- Cruzam com os faltantes: "este item que falta já tem pedido? quando chega?".
-- Também usados para os painéis (acionamento ao fabricante do painel).
CREATE TABLE IF NOT EXISTS bx_pedido_compra (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  numero          TEXT,
  item_id         UUID REFERENCES bx_item(id) ON DELETE CASCADE,
  codigo          TEXT,                                -- redundante p/ itens não cadastrados
  fornecedor_id   UUID REFERENCES bx_fornecedor(id) ON DELETE SET NULL,
  quantidade      NUMERIC NOT NULL DEFAULT 0,
  data_pedido     DATE,
  data_prevista   DATE,                                -- chegada prevista (cruza com a necessidade)
  status          TEXT NOT NULL DEFAULT 'aberto'
                  CHECK (status IN ('aberto','parcial','recebido','atrasado','cancelado')),
  recebido_em     DATE,
  observacoes     TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_bx_pedido_item   ON bx_pedido_compra(item_id);
CREATE INDEX IF NOT EXISTS idx_bx_pedido_codigo ON bx_pedido_compra(codigo);
CREATE INDEX IF NOT EXISTS idx_bx_pedido_status ON bx_pedido_compra(status);

DROP TRIGGER IF EXISTS trg_bx_pedido_updated_at ON bx_pedido_compra;
CREATE TRIGGER trg_bx_pedido_updated_at
  BEFORE UPDATE ON bx_pedido_compra
  FOR EACH ROW EXECUTE FUNCTION bx_set_updated_at();

-- ---------- ordens de produção (SC2 + enriquecimento da Lista de Prioridades) ----------
CREATE TABLE IF NOT EXISTS bx_op (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  numero             TEXT UNIQUE NOT NULL,             -- número da OP (chave de negócio)
  chave              TEXT,                              -- chave composta do Protheus (C2_NUM+ITEM+SEQ)
  -- cabeçalho da OP (SC2)
  produto_codigo     TEXT,                              -- C2_PRODUTO (código da máquina/equipamento)
  produto_descricao  TEXT,                              -- C2_XDESCP / nome da máquina
  quantidade         NUMERIC,                           -- C2_QUANT
  data_inicio        DATE,                              -- C2_DATPRI (início previsto)
  data_fim           DATE,                              -- C2_DATPRF (fim previsto)
  -- enriquecimento (Lista de Prioridades)
  mercado            TEXT,                              -- MI / ME / PCP
  cliente            TEXT,
  montador           TEXT,
  ordem_entrega      TEXT,                              -- "Ordem de entrega dos equipamentos"
  situacao_erp       TEXT,                              -- Situação textual (Finalizada/Montagem/Separada/Aguardando/…)
  faltas_texto       TEXT,                              -- FALTAS / "Faltas de itens" (texto livre do relatório)
  -- painel
  painel_codigo      TEXT,
  painel_op          TEXT,
  painel_fornecedor  TEXT,
  painel_situacao    TEXT,
  -- datas comerciais / PCP
  data_solicitacao   DATE,
  prazo_comercial    DATE,
  aceite_pcp         TEXT,
  data_acordada      DATE,                              -- "Data final acordada - P.A"
  data_entrega       DATE,
  dias_atraso        NUMERIC,
  faturada           TEXT,
  observacoes        TEXT,
  -- saídas calculadas (motor de regras)
  status_calculado   TEXT NOT NULL DEFAULT 'sem_dados'
                     CHECK (status_calculado IN ('completa','quase_completa','travada','sem_dados')),
  total_componentes  INT NOT NULL DEFAULT 0,
  componentes_ok     INT NOT NULL DEFAULT 0,
  componentes_falta  INT NOT NULL DEFAULT 0,
  componentes_transferidos INT NOT NULL DEFAULT 0,
  qtd_falta_total    NUMERIC NOT NULL DEFAULT 0,
  faltantes_com_pedido INT NOT NULL DEFAULT 0,
  faltantes_sem_pedido INT NOT NULL DEFAULT 0,
  pode_montar        BOOLEAN NOT NULL DEFAULT FALSE,
  prioridade         INT NOT NULL DEFAULT 0,            -- score de atenção do PCP (maior = mais)
  analisada_em       TIMESTAMPTZ,
  importacao_id      UUID,                              -- última importação que tocou a OP
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_bx_op_status   ON bx_op(status_calculado);
CREATE INDEX IF NOT EXISTS idx_bx_op_prio     ON bx_op(prioridade DESC);
CREATE INDEX IF NOT EXISTS idx_bx_op_produto  ON bx_op(produto_codigo);
CREATE INDEX IF NOT EXISTS idx_bx_op_cliente  ON bx_op(cliente);

DROP TRIGGER IF EXISTS trg_bx_op_updated_at ON bx_op;
CREATE TRIGGER trg_bx_op_updated_at
  BEFORE UPDATE ON bx_op
  FOR EACH ROW EXECUTE FUNCTION bx_set_updated_at();

-- ---------- empenhos: componentes necessários por OP (SD4) ----------
CREATE TABLE IF NOT EXISTS bx_empenho (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  op_id              UUID NOT NULL REFERENCES bx_op(id) ON DELETE CASCADE,
  item_id            UUID REFERENCES bx_item(id) ON DELETE SET NULL,
  codigo             TEXT NOT NULL,                     -- D4_COD (componente)
  descricao          TEXT,
  qtd_original       NUMERIC,                           -- D4_QTDEORI
  qtd_necessaria     NUMERIC NOT NULL DEFAULT 0,        -- D4_QUANT (necessidade do empenho)
  qtd_transferida    NUMERIC NOT NULL DEFAULT 0,        -- D4_XQTRANS (já transferido p/ produção)
  qtd_falta          NUMERIC NOT NULL DEFAULT 0,        -- D4_XQFALFI (ainda falta)
  -- saídas calculadas
  status_componente  TEXT NOT NULL DEFAULT 'ok'
                     CHECK (status_componente IN ('ok','transferido','falta_parcial','falta_total')),
  tem_pedido         BOOLEAN NOT NULL DEFAULT FALSE,
  pedido_qtd         NUMERIC,
  pedido_data_prevista DATE,
  pedido_atrasado    BOOLEAN,
  fornecedor_nome    TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_bx_emp_op     ON bx_empenho(op_id);
CREATE INDEX IF NOT EXISTS idx_bx_emp_codigo ON bx_empenho(codigo);
CREATE INDEX IF NOT EXISTS idx_bx_emp_status ON bx_empenho(status_componente);

-- ---------- log de importações (cada upload substitui o anterior) ----------
CREATE TABLE IF NOT EXISTS bx_importacao (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo            TEXT NOT NULL CHECK (tipo IN ('op_empenhos','prioridades')),
  arquivo_nome    TEXT,
  ops             INT NOT NULL DEFAULT 0,
  empenhos        INT NOT NULL DEFAULT 0,
  linhas          INT NOT NULL DEFAULT 0,
  ignorados       INT NOT NULL DEFAULT 0,
  criado_por      UUID,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_bx_importacao_tipo ON bx_importacao(tipo, created_at DESC);

-- ---------- log de decisões (base de aprendizado) ----------
CREATE TABLE IF NOT EXISTS bx_decision_log (
  id              BIGSERIAL PRIMARY KEY,
  op_id           UUID REFERENCES bx_op(id) ON DELETE SET NULL,
  op_numero       TEXT,
  status_calculado TEXT,
  acao            TEXT NOT NULL,                          -- decisão tomada
  concorda        BOOLEAN,                                -- concorda com a leitura do agente?
  motivo          TEXT,
  origem          TEXT NOT NULL DEFAULT 'humano' CHECK (origem IN ('humano','ia')),
  snapshot        JSONB,
  user_id         UUID,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_bx_declog_op   ON bx_decision_log(op_id);
CREATE INDEX IF NOT EXISTS idx_bx_declog_acao ON bx_decision_log(acao);

-- ---------- RLS: leitura para membros, escrita via RPC/service_role ----------
ALTER TABLE bx_fornecedor    ENABLE ROW LEVEL SECURITY;
ALTER TABLE bx_item          ENABLE ROW LEVEL SECURITY;
ALTER TABLE bx_pedido_compra ENABLE ROW LEVEL SECURITY;
ALTER TABLE bx_op            ENABLE ROW LEVEL SECURITY;
ALTER TABLE bx_empenho       ENABLE ROW LEVEL SECURITY;
ALTER TABLE bx_importacao    ENABLE ROW LEVEL SECURITY;
ALTER TABLE bx_decision_log  ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS bx_fornecedor_read ON bx_fornecedor;
CREATE POLICY bx_fornecedor_read ON bx_fornecedor FOR SELECT USING (bx_is_member());
DROP POLICY IF EXISTS bx_item_read ON bx_item;
CREATE POLICY bx_item_read ON bx_item FOR SELECT USING (bx_is_member());
DROP POLICY IF EXISTS bx_pedido_read ON bx_pedido_compra;
CREATE POLICY bx_pedido_read ON bx_pedido_compra FOR SELECT USING (bx_is_member());
DROP POLICY IF EXISTS bx_op_read ON bx_op;
CREATE POLICY bx_op_read ON bx_op FOR SELECT USING (bx_is_member());
DROP POLICY IF EXISTS bx_empenho_read ON bx_empenho;
CREATE POLICY bx_empenho_read ON bx_empenho FOR SELECT USING (bx_is_member());
DROP POLICY IF EXISTS bx_importacao_read ON bx_importacao;
CREATE POLICY bx_importacao_read ON bx_importacao FOR SELECT USING (bx_is_member());
DROP POLICY IF EXISTS bx_declog_read ON bx_decision_log;
CREATE POLICY bx_declog_read ON bx_decision_log FOR SELECT USING (bx_is_member());

GRANT SELECT ON bx_fornecedor, bx_item, bx_pedido_compra, bx_op, bx_empenho, bx_importacao, bx_decision_log
  TO authenticated;

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- DROP TABLE IF EXISTS bx_decision_log;
-- DROP TABLE IF EXISTS bx_importacao;
-- DROP TABLE IF EXISTS bx_empenho;
-- DROP TABLE IF EXISTS bx_op;
-- DROP TABLE IF EXISTS bx_pedido_compra;
-- DROP TABLE IF EXISTS bx_item;
-- DROP TABLE IF EXISTS bx_fornecedor;
-- DROP FUNCTION IF EXISTS bx_norm_codigo(TEXT);
-- DROP FUNCTION IF EXISTS bx_parse_num(TEXT);
-- DROP FUNCTION IF EXISTS bx_parse_ts(TEXT);
-- NOTIFY pgrst, 'reload schema';
