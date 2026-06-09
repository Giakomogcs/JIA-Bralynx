-- =============================================
-- Bralyx — 006: PCP / Estoque / Compras (RPCs / motor de regras)
--
-- O motor de regras (determinístico) calcula o status de cada componente
-- (empenho) e de cada OP a partir do cruzamento necessidade × transferido ×
-- falta × pedido de compra. O LLM só escreve a justificativa executiva.
--
-- Inclui:
--   * bx_is_backend()                          — libera chamadas do n8n
--   * CRUD fornecedores / itens / pedidos
--   * bx_classificar_componente(...) / bx_classificar_op(...) — regras puras
--   * bx_recompute_op() / bx_recompute_all()  — recalcula status e prioridade
--   * bx_dashboard_ops() / bx_op_detalhe()    — visão priorizada + detalhe da OP
--   * bx_componentes_faltantes() / bx_compras_atrasadas() / bx_liberar_montagem()
--   * bx_record_decision() / bx_learning_signals() / bx_list_importacoes() / bx_stats()
-- Rode APÓS 005_pcp_schema.sql
-- =============================================

-- =======  UP  ========

-- chamadas de backend (n8n: service_role ou role de serviço do Postgres)
CREATE OR REPLACE FUNCTION bx_is_backend()
RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    current_setting('request.jwt.claim.role', true) = 'service_role'
    OR auth.role() = 'service_role'
    OR current_user IN ('postgres','service_role','supabase_admin'),
    false
  );
$$;

-- ===================================================================
-- CRUD: FORNECEDORES
-- ===================================================================
CREATE OR REPLACE FUNCTION bx_list_fornecedores(p_only_active BOOLEAN DEFAULT FALSE)
RETURNS SETOF bx_fornecedor
SECURITY DEFINER SET search_path = public LANGUAGE plpgsql STABLE AS $$
BEGIN
  IF NOT (bx_is_member() OR bx_is_backend()) THEN
    RAISE EXCEPTION 'Acesso negado.' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY SELECT * FROM bx_fornecedor f
   WHERE (NOT p_only_active OR f.ativo) ORDER BY f.nome;
END;
$$;

-- upsert por nome (backend/admin) — usado pela ingestão da Lista de Prioridades
CREATE OR REPLACE FUNCTION bx_upsert_fornecedor(
  p_nome TEXT, p_tipo TEXT DEFAULT 'fornecedor', p_cnpj TEXT DEFAULT NULL,
  p_lead_time_medio_dias NUMERIC DEFAULT NULL, p_contato TEXT DEFAULT NULL,
  p_observacoes TEXT DEFAULT NULL
)
RETURNS UUID
SECURITY DEFINER SET search_path = public LANGUAGE plpgsql AS $$
DECLARE v_id UUID; v_nome TEXT := NULLIF(TRIM(p_nome), '');
BEGIN
  IF NOT (bx_is_admin() OR bx_is_backend()) THEN
    RAISE EXCEPTION 'Acesso negado.' USING ERRCODE = '42501';
  END IF;
  IF v_nome IS NULL THEN RETURN NULL; END IF;
  SELECT id INTO v_id FROM bx_fornecedor WHERE lower(nome) = lower(v_nome) LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO bx_fornecedor(nome,tipo,cnpj,lead_time_medio_dias,contato,observacoes)
    VALUES (v_nome, COALESCE(p_tipo,'fornecedor'), p_cnpj, p_lead_time_medio_dias, p_contato, p_observacoes)
    RETURNING id INTO v_id;
  ELSE
    UPDATE bx_fornecedor SET
      tipo=COALESCE(p_tipo,tipo), cnpj=COALESCE(p_cnpj,cnpj),
      lead_time_medio_dias=COALESCE(p_lead_time_medio_dias,lead_time_medio_dias),
      contato=COALESCE(p_contato,contato), observacoes=COALESCE(p_observacoes,observacoes)
    WHERE id=v_id;
  END IF;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION bx_admin_delete_fornecedor(p_id UUID)
RETURNS VOID SECURITY DEFINER SET search_path = public LANGUAGE plpgsql AS $$
BEGIN
  IF NOT bx_is_admin() THEN RAISE EXCEPTION 'Acesso negado.' USING ERRCODE='42501'; END IF;
  DELETE FROM bx_fornecedor WHERE id=p_id;
END;
$$;

-- ===================================================================
-- CRUD: ITENS / COMPONENTES (catálogo + estoque)
-- ===================================================================
CREATE OR REPLACE FUNCTION bx_list_itens(
  p_grupo TEXT DEFAULT NULL, p_search TEXT DEFAULT NULL,
  p_limit INT DEFAULT 100, p_offset INT DEFAULT 0
)
RETURNS TABLE(
  id UUID, codigo TEXT, descricao TEXT, grupo TEXT, unidade TEXT,
  fornecedor_id UUID, fornecedor_nome TEXT, lead_time_dias NUMERIC,
  estoque_atual NUMERIC, estoque_atualizado_em TIMESTAMPTZ, ativo BOOLEAN, total_count BIGINT
)
SECURITY DEFINER SET search_path = public LANGUAGE plpgsql STABLE AS $$
BEGIN
  IF NOT (bx_is_member() OR bx_is_backend()) THEN
    RAISE EXCEPTION 'Acesso negado.' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
    SELECT i.id, i.codigo, i.descricao, i.grupo, i.unidade,
           i.fornecedor_id, f.nome, i.lead_time_dias,
           i.estoque_atual, i.estoque_atualizado_em, i.ativo,
           COUNT(*) OVER()
      FROM bx_item i
      LEFT JOIN bx_fornecedor f ON f.id = i.fornecedor_id
     WHERE (p_grupo IS NULL OR i.grupo = p_grupo)
       AND (p_search IS NULL OR i.codigo ILIKE '%'||p_search||'%' OR i.descricao ILIKE '%'||p_search||'%')
     ORDER BY i.codigo
     LIMIT COALESCE(p_limit,100) OFFSET COALESCE(p_offset,0);
END;
$$;

-- upsert por código (backend/admin) — usado pela ingestão e por patches manuais
CREATE OR REPLACE FUNCTION bx_upsert_item(
  p_codigo TEXT, p_descricao TEXT DEFAULT NULL, p_grupo TEXT DEFAULT NULL,
  p_unidade TEXT DEFAULT NULL, p_fornecedor_id UUID DEFAULT NULL,
  p_lead_time_dias NUMERIC DEFAULT NULL, p_estoque_atual NUMERIC DEFAULT NULL
)
RETURNS UUID
SECURITY DEFINER SET search_path = public LANGUAGE plpgsql AS $$
DECLARE v_id UUID; v_codigo TEXT := bx_norm_codigo(p_codigo);
BEGIN
  IF NOT (bx_is_admin() OR bx_is_backend()) THEN
    RAISE EXCEPTION 'Acesso negado.' USING ERRCODE = '42501';
  END IF;
  IF v_codigo IS NULL THEN RETURN NULL; END IF;
  INSERT INTO bx_item(codigo, descricao, grupo, unidade, fornecedor_id, lead_time_dias,
                      estoque_atual, estoque_atualizado_em)
  VALUES (v_codigo, p_descricao, COALESCE(p_grupo,'comprado'), COALESCE(p_unidade,'un'),
          p_fornecedor_id, p_lead_time_dias, p_estoque_atual,
          CASE WHEN p_estoque_atual IS NOT NULL THEN NOW() END)
  ON CONFLICT (codigo) DO UPDATE SET
    descricao     = COALESCE(EXCLUDED.descricao, bx_item.descricao),
    grupo         = COALESCE(EXCLUDED.grupo, bx_item.grupo),
    unidade       = COALESCE(EXCLUDED.unidade, bx_item.unidade),
    fornecedor_id = COALESCE(EXCLUDED.fornecedor_id, bx_item.fornecedor_id),
    lead_time_dias= COALESCE(EXCLUDED.lead_time_dias, bx_item.lead_time_dias),
    estoque_atual = COALESCE(EXCLUDED.estoque_atual, bx_item.estoque_atual),
    estoque_atualizado_em = CASE WHEN EXCLUDED.estoque_atual IS NOT NULL THEN NOW()
                                 ELSE bx_item.estoque_atualizado_em END
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION bx_admin_delete_item(p_id UUID)
RETURNS VOID SECURITY DEFINER SET search_path = public LANGUAGE plpgsql AS $$
BEGIN
  IF NOT bx_is_admin() THEN RAISE EXCEPTION 'Acesso negado.' USING ERRCODE='42501'; END IF;
  DELETE FROM bx_item WHERE id=p_id;
END;
$$;

-- ===================================================================
-- PEDIDOS de compra / acionamentos
-- ===================================================================
CREATE OR REPLACE FUNCTION bx_upsert_pedido(
  p_id UUID, p_numero TEXT, p_codigo TEXT, p_quantidade NUMERIC,
  p_data_pedido DATE, p_data_prevista DATE, p_status TEXT DEFAULT 'aberto',
  p_fornecedor_id UUID DEFAULT NULL, p_observacoes TEXT DEFAULT NULL
)
RETURNS UUID
SECURITY DEFINER SET search_path = public LANGUAGE plpgsql AS $$
DECLARE v_id UUID; v_item UUID; v_codigo TEXT := bx_norm_codigo(p_codigo);
BEGIN
  IF NOT (bx_is_admin() OR bx_is_backend()) THEN
    RAISE EXCEPTION 'Acesso negado.' USING ERRCODE = '42501';
  END IF;
  SELECT id INTO v_item FROM bx_item WHERE codigo = v_codigo LIMIT 1;
  IF p_id IS NULL THEN
    INSERT INTO bx_pedido_compra(numero,item_id,codigo,fornecedor_id,quantidade,data_pedido,data_prevista,status,observacoes)
    VALUES (p_numero,v_item,v_codigo,p_fornecedor_id,COALESCE(p_quantidade,0),p_data_pedido,p_data_prevista,COALESCE(p_status,'aberto'),p_observacoes)
    RETURNING id INTO v_id;
  ELSE
    UPDATE bx_pedido_compra SET
      numero=p_numero,item_id=v_item,codigo=v_codigo,fornecedor_id=p_fornecedor_id,
      quantidade=COALESCE(p_quantidade,0),data_pedido=p_data_pedido,data_prevista=p_data_prevista,
      status=COALESCE(p_status,'aberto'),observacoes=p_observacoes
    WHERE id=p_id RETURNING id INTO v_id;
  END IF;
  RETURN v_id;
END;
$$;

-- pedidos em aberto agregados por código (qtd total + chegada mais próxima + atraso)
CREATE OR REPLACE FUNCTION bx_pedidos_abertos_por_codigo(p_codigo TEXT)
RETURNS TABLE(qtd NUMERIC, data_prevista DATE, atrasado BOOLEAN, fornecedor_nome TEXT)
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(SUM(p.quantidade),0),
         MIN(p.data_prevista),
         BOOL_OR(p.status='atrasado' OR (p.data_prevista IS NOT NULL AND p.data_prevista < CURRENT_DATE)),
         (SELECT f.nome FROM bx_pedido_compra pp
            LEFT JOIN bx_fornecedor f ON f.id = pp.fornecedor_id
           WHERE pp.codigo = bx_norm_codigo(p_codigo)
             AND pp.status IN ('aberto','parcial','atrasado')
           ORDER BY pp.data_prevista NULLS LAST LIMIT 1)
    FROM bx_pedido_compra p
   WHERE p.codigo = bx_norm_codigo(p_codigo)
     AND p.status IN ('aberto','parcial','atrasado');
$$;

-- ===================================================================
-- MOTOR DE REGRAS
-- ===================================================================
-- status de um componente/empenho a partir de necessária × transferida × falta
CREATE OR REPLACE FUNCTION bx_classificar_componente(
  p_qtd_necessaria NUMERIC, p_qtd_transferida NUMERIC, p_qtd_falta NUMERIC
)
RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  nec    NUMERIC := COALESCE(p_qtd_necessaria, 0);
  transf NUMERIC := COALESCE(p_qtd_transferida, 0);
  falta  NUMERIC := COALESCE(p_qtd_falta, 0);
BEGIN
  IF falta <= 0 THEN
    IF nec > 0 AND transf >= nec THEN
      RETURN 'transferido';      -- já em produção
    END IF;
    RETURN 'ok';                 -- disponível / empenhado sem falta
  END IF;
  IF nec > 0 AND falta < nec THEN
    RETURN 'falta_parcial';
  END IF;
  RETURN 'falta_total';
END;
$$;

-- status + prioridade de uma OP a partir dos rollups dos empenhos
CREATE OR REPLACE FUNCTION bx_classificar_op(
  p_total INT, p_falta_count INT, p_qtd_falta_total NUMERIC,
  p_faltantes_sem_pedido INT, p_dias_atraso NUMERIC DEFAULT NULL
)
RETURNS TABLE(status TEXT, pode_montar BOOLEAN, prioridade INT)
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v_status TEXT;
  v_pode   BOOLEAN;
  v_prio   INT;
  v_total  INT := COALESCE(p_total, 0);
  v_falta  INT := COALESCE(p_falta_count, 0);
  v_atraso NUMERIC := GREATEST(COALESCE(p_dias_atraso, 0), 0);
BEGIN
  IF v_total <= 0 THEN
    v_status := 'sem_dados';
  ELSIF v_falta = 0 THEN
    v_status := 'completa';
  ELSIF v_falta <= 3 OR (v_falta::NUMERIC / v_total) <= 0.10 THEN
    v_status := 'quase_completa';
  ELSE
    v_status := 'travada';
  END IF;

  v_pode := (v_status = 'completa');

  -- prioridade de ATENÇÃO do PCP (maior = analisar/agir antes):
  --  quase_completa no topo (pequeno esforço destrava a montagem),
  --  depois travada, depois completa (já pronta) e sem_dados.
  v_prio := CASE v_status
              WHEN 'quase_completa' THEN 300
              WHEN 'travada'        THEN 200
              WHEN 'completa'       THEN 120
              ELSE 40
            END
          + COALESCE(p_faltantes_sem_pedido, 0) * 8     -- falta sem pedido = mais crítico
          + LEAST(v_atraso, 60)::INT * 2                -- atraso pesa na fila
          + CASE WHEN v_status='travada' THEN LEAST(v_falta, 20) ELSE 0 END;

  status := v_status; pode_montar := v_pode; prioridade := v_prio;
  RETURN NEXT;
END;
$$;

-- recalcula status dos empenhos + rollups + status/prioridade de UMA OP
CREATE OR REPLACE FUNCTION bx_recompute_op(p_op_id UUID)
RETURNS VOID
SECURITY DEFINER SET search_path = public LANGUAGE plpgsql AS $$
DECLARE
  e RECORD;
  v_ped RECORD;
  v_total INT := 0; v_ok INT := 0; v_falta INT := 0; v_transf INT := 0;
  v_qfalta NUMERIC := 0; v_com_pedido INT := 0; v_sem_pedido INT := 0;
  v_status_comp TEXT;
  v_cls RECORD;
  v_atraso NUMERIC;
BEGIN
  IF NOT (bx_is_member() OR bx_is_backend()) THEN
    RAISE EXCEPTION 'Acesso negado.' USING ERRCODE = '42501';
  END IF;

  FOR e IN SELECT * FROM bx_empenho WHERE op_id = p_op_id LOOP
    v_status_comp := bx_classificar_componente(e.qtd_necessaria, e.qtd_transferida, e.qtd_falta);
    SELECT qtd, data_prevista, atrasado, fornecedor_nome INTO v_ped
      FROM bx_pedidos_abertos_por_codigo(e.codigo);

    UPDATE bx_empenho SET
      item_id              = COALESCE((SELECT id FROM bx_item WHERE codigo = e.codigo LIMIT 1), item_id),
      status_componente    = v_status_comp,
      tem_pedido           = COALESCE(v_ped.qtd,0) > 0,
      pedido_qtd           = NULLIF(COALESCE(v_ped.qtd,0),0),
      pedido_data_prevista = v_ped.data_prevista,
      pedido_atrasado      = v_ped.atrasado,
      fornecedor_nome      = COALESCE(v_ped.fornecedor_nome,
                                      (SELECT f.nome FROM bx_item i LEFT JOIN bx_fornecedor f ON f.id=i.fornecedor_id
                                        WHERE i.codigo = e.codigo LIMIT 1))
    WHERE id = e.id;

    v_total := v_total + 1;
    IF v_status_comp IN ('falta_parcial','falta_total') THEN
      v_falta  := v_falta + 1;
      v_qfalta := v_qfalta + GREATEST(COALESCE(e.qtd_falta,0), 0);
      IF COALESCE(v_ped.qtd,0) > 0 THEN v_com_pedido := v_com_pedido + 1;
      ELSE v_sem_pedido := v_sem_pedido + 1; END IF;
    ELSE
      v_ok := v_ok + 1;
      IF v_status_comp = 'transferido' THEN v_transf := v_transf + 1; END IF;
    END IF;
  END LOOP;

  SELECT dias_atraso INTO v_atraso FROM bx_op WHERE id = p_op_id;
  SELECT * INTO v_cls FROM bx_classificar_op(v_total, v_falta, v_qfalta, v_sem_pedido, v_atraso);

  UPDATE bx_op SET
    total_componentes        = v_total,
    componentes_ok           = v_ok,
    componentes_falta        = v_falta,
    componentes_transferidos = v_transf,
    qtd_falta_total          = v_qfalta,
    faltantes_com_pedido     = v_com_pedido,
    faltantes_sem_pedido     = v_sem_pedido,
    status_calculado         = v_cls.status,
    pode_montar              = v_cls.pode_montar,
    prioridade               = v_cls.prioridade,
    analisada_em             = NOW()
  WHERE id = p_op_id;
END;
$$;

-- recalcula TODAS as OPs (após uma importação)
CREATE OR REPLACE FUNCTION bx_recompute_all()
RETURNS INT
SECURITY DEFINER SET search_path = public LANGUAGE plpgsql AS $$
DECLARE r RECORD; n INT := 0;
BEGIN
  IF NOT (bx_is_member() OR bx_is_backend()) THEN
    RAISE EXCEPTION 'Acesso negado.' USING ERRCODE = '42501';
  END IF;
  FOR r IN SELECT id FROM bx_op LOOP
    PERFORM bx_recompute_op(r.id);
    n := n + 1;
  END LOOP;
  RETURN n;
END;
$$;

-- ===================================================================
-- DASHBOARD / CONSULTAS (ferramentas do agente)
-- ===================================================================
-- Lista priorizada de OPs (filtros por status/mercado/busca).
CREATE OR REPLACE FUNCTION bx_dashboard_ops(
  p_status TEXT DEFAULT NULL, p_mercado TEXT DEFAULT NULL,
  p_search TEXT DEFAULT NULL, p_sort TEXT DEFAULT NULL,
  p_limit INT DEFAULT 50, p_offset INT DEFAULT 0
)
RETURNS TABLE(
  id UUID, numero TEXT, produto_codigo TEXT, produto_descricao TEXT, quantidade NUMERIC,
  mercado TEXT, cliente TEXT, montador TEXT, situacao_erp TEXT,
  status_calculado TEXT, pode_montar BOOLEAN,
  total_componentes INT, componentes_falta INT, componentes_transferidos INT,
  qtd_falta_total NUMERIC, faltantes_com_pedido INT, faltantes_sem_pedido INT,
  data_acordada DATE, data_entrega DATE, dias_atraso NUMERIC,
  prioridade INT, total_count BIGINT
)
SECURITY DEFINER SET search_path = public LANGUAGE plpgsql STABLE AS $$
BEGIN
  IF NOT (bx_is_member() OR bx_is_backend()) THEN
    RAISE EXCEPTION 'Acesso negado.' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
    WITH base AS (
      SELECT o.*, COUNT(*) OVER() AS total_count
        FROM bx_op o
       WHERE (p_status IS NULL OR o.status_calculado = p_status)
         AND (p_mercado IS NULL OR o.mercado = p_mercado)
         AND (p_search IS NULL
              OR o.numero ILIKE '%'||p_search||'%'
              OR o.produto_codigo ILIKE '%'||p_search||'%'
              OR o.produto_descricao ILIKE '%'||p_search||'%'
              OR o.cliente ILIKE '%'||p_search||'%')
    )
    SELECT b.id, b.numero, b.produto_codigo, b.produto_descricao, b.quantidade,
           b.mercado, b.cliente, b.montador, b.situacao_erp,
           b.status_calculado, b.pode_montar,
           b.total_componentes, b.componentes_falta, b.componentes_transferidos,
           b.qtd_falta_total, b.faltantes_com_pedido, b.faltantes_sem_pedido,
           b.data_acordada, b.data_entrega, b.dias_atraso,
           b.prioridade, b.total_count
      FROM base b
     ORDER BY
       CASE WHEN p_sort='entrega' THEN b.data_acordada END ASC NULLS LAST,
       CASE WHEN p_sort='atraso'  THEN b.dias_atraso END DESC NULLS LAST,
       b.prioridade DESC, b.numero
     LIMIT COALESCE(p_limit,50) OFFSET COALESCE(p_offset,0);
END;
$$;

-- Detalhe de uma OP: cabeçalho + componentes faltantes (com pedido/previsão/fornecedor).
CREATE OR REPLACE FUNCTION bx_op_detalhe(p_numero TEXT)
RETURNS JSONB
SECURITY DEFINER SET search_path = public LANGUAGE plpgsql STABLE AS $$
DECLARE v_op bx_op; v JSONB;
BEGIN
  IF NOT (bx_is_member() OR bx_is_backend()) THEN
    RAISE EXCEPTION 'Acesso negado.' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_op FROM bx_op WHERE numero = TRIM(p_numero) LIMIT 1;
  IF v_op.id IS NULL THEN
    RETURN jsonb_build_object('encontrada', false, 'numero', p_numero);
  END IF;

  SELECT jsonb_build_object(
    'encontrada', true,
    'op', to_jsonb(v_op),
    'faltantes', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'codigo', e.codigo, 'descricao', e.descricao,
               'qtd_necessaria', e.qtd_necessaria, 'qtd_transferida', e.qtd_transferida,
               'qtd_falta', e.qtd_falta, 'status', e.status_componente,
               'estoque_atual', i.estoque_atual,
               'tem_pedido', e.tem_pedido, 'pedido_qtd', e.pedido_qtd,
               'pedido_data_prevista', e.pedido_data_prevista, 'pedido_atrasado', e.pedido_atrasado,
               'fornecedor', e.fornecedor_nome
             ) ORDER BY (e.status_componente='falta_total') DESC, e.codigo)
        FROM bx_empenho e
        LEFT JOIN bx_item i ON i.codigo = e.codigo
       WHERE e.op_id = v_op.id AND e.status_componente IN ('falta_parcial','falta_total')
    ), '[]'::jsonb),
    'transferidos', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('codigo', e.codigo, 'descricao', e.descricao,
               'qtd_necessaria', e.qtd_necessaria, 'qtd_transferida', e.qtd_transferida)
             ORDER BY e.codigo)
        FROM bx_empenho e
       WHERE e.op_id = v_op.id AND e.status_componente = 'transferido'
    ), '[]'::jsonb)
  ) INTO v;
  RETURN v;
END;
$$;

-- Componentes faltantes agregados entre todas as OPs (com/sem pedido).
CREATE OR REPLACE FUNCTION bx_componentes_faltantes(
  p_sem_pedido BOOLEAN DEFAULT FALSE, p_search TEXT DEFAULT NULL, p_limit INT DEFAULT 100
)
RETURNS TABLE(
  codigo TEXT, descricao TEXT, ops_afetadas BIGINT, qtd_falta_total NUMERIC,
  tem_pedido BOOLEAN, pedido_data_prevista DATE, pedido_atrasado BOOLEAN, fornecedor_nome TEXT,
  estoque_atual NUMERIC
)
SECURITY DEFINER SET search_path = public LANGUAGE plpgsql STABLE AS $$
BEGIN
  IF NOT (bx_is_member() OR bx_is_backend()) THEN
    RAISE EXCEPTION 'Acesso negado.' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
    SELECT e.codigo,
           MAX(e.descricao),
           COUNT(DISTINCT e.op_id),
           SUM(GREATEST(COALESCE(e.qtd_falta,0),0)),
           BOOL_OR(e.tem_pedido),
           MIN(e.pedido_data_prevista),
           BOOL_OR(e.pedido_atrasado),
           MAX(e.fornecedor_nome),
           MAX(i.estoque_atual)
      FROM bx_empenho e
      LEFT JOIN bx_item i ON i.codigo = e.codigo
     WHERE e.status_componente IN ('falta_parcial','falta_total')
       AND (NOT p_sem_pedido OR e.tem_pedido = FALSE)
       AND (p_search IS NULL OR e.codigo ILIKE '%'||p_search||'%' OR e.descricao ILIKE '%'||p_search||'%')
     GROUP BY e.codigo
     ORDER BY (NOT BOOL_OR(e.tem_pedido)) DESC, COUNT(DISTINCT e.op_id) DESC, SUM(GREATEST(COALESCE(e.qtd_falta,0),0)) DESC
     LIMIT COALESCE(p_limit,100);
END;
$$;

-- Pedidos de compra atrasados (e faltantes que dependem deles).
CREATE OR REPLACE FUNCTION bx_compras_atrasadas()
RETURNS TABLE(
  numero TEXT, codigo TEXT, descricao TEXT, fornecedor_nome TEXT,
  quantidade NUMERIC, data_pedido DATE, data_prevista DATE, dias_atraso INT,
  ops_dependentes BIGINT
)
SECURITY DEFINER SET search_path = public LANGUAGE plpgsql STABLE AS $$
BEGIN
  IF NOT (bx_is_member() OR bx_is_backend()) THEN
    RAISE EXCEPTION 'Acesso negado.' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
    SELECT p.numero, p.codigo, COALESCE(i.descricao, p.codigo), f.nome,
           p.quantidade, p.data_pedido, p.data_prevista,
           (CURRENT_DATE - p.data_prevista)::INT,
           COALESCE((SELECT COUNT(DISTINCT e.op_id) FROM bx_empenho e
                      WHERE e.codigo = p.codigo AND e.status_componente IN ('falta_parcial','falta_total')),0)
      FROM bx_pedido_compra p
      LEFT JOIN bx_item i ON i.id = p.item_id OR i.codigo = p.codigo
      LEFT JOIN bx_fornecedor f ON f.id = p.fornecedor_id
     WHERE p.status IN ('aberto','parcial','atrasado')
       AND p.data_prevista IS NOT NULL
       AND p.data_prevista < CURRENT_DATE
     ORDER BY p.data_prevista ASC;
END;
$$;

-- OPs que podem ir para montagem (completas) ou estão quase lá (quase_completa).
CREATE OR REPLACE FUNCTION bx_liberar_montagem(p_incluir_quase BOOLEAN DEFAULT TRUE, p_limit INT DEFAULT 50)
RETURNS TABLE(
  numero TEXT, produto_codigo TEXT, produto_descricao TEXT, cliente TEXT, montador TEXT,
  status_calculado TEXT, componentes_falta INT, faltantes_sem_pedido INT,
  data_acordada DATE, dias_atraso NUMERIC, prioridade INT
)
SECURITY DEFINER SET search_path = public LANGUAGE plpgsql STABLE AS $$
BEGIN
  IF NOT (bx_is_member() OR bx_is_backend()) THEN
    RAISE EXCEPTION 'Acesso negado.' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
    SELECT o.numero, o.produto_codigo, o.produto_descricao, o.cliente, o.montador,
           o.status_calculado, o.componentes_falta, o.faltantes_sem_pedido,
           o.data_acordada, o.dias_atraso, o.prioridade
      FROM bx_op o
     WHERE o.status_calculado = 'completa'
        OR (p_incluir_quase AND o.status_calculado = 'quase_completa')
     ORDER BY (o.status_calculado='completa') DESC, o.prioridade DESC, o.data_acordada NULLS LAST
     LIMIT COALESCE(p_limit,50);
END;
$$;

-- ===================================================================
-- DECISÕES / IMPORTAÇÕES / STATS
-- ===================================================================
CREATE OR REPLACE FUNCTION bx_record_decision(
  p_op_numero TEXT, p_acao TEXT, p_concorda BOOLEAN DEFAULT NULL,
  p_motivo TEXT DEFAULT NULL, p_origem TEXT DEFAULT 'humano'
)
RETURNS JSONB
SECURITY DEFINER SET search_path = public LANGUAGE plpgsql AS $$
DECLARE o bx_op;
BEGIN
  IF NOT (bx_is_member() OR bx_is_backend()) THEN RAISE EXCEPTION 'Acesso negado.' USING ERRCODE='42501'; END IF;
  SELECT * INTO o FROM bx_op WHERE numero = TRIM(p_op_numero) LIMIT 1;
  INSERT INTO bx_decision_log(op_id, op_numero, status_calculado, acao, concorda, motivo, origem, snapshot, user_id)
  VALUES (o.id, COALESCE(o.numero, p_op_numero), o.status_calculado, p_acao, p_concorda, p_motivo,
          COALESCE(p_origem,'humano'), to_jsonb(o), auth.uid());
  RETURN jsonb_build_object('ok', true, 'op_numero', COALESCE(o.numero, p_op_numero), 'acao', p_acao);
END;
$$;

CREATE OR REPLACE FUNCTION bx_learning_signals()
RETURNS TABLE(status_calculado TEXT, acao TEXT, total BIGINT, concordancias BIGINT, taxa NUMERIC)
SECURITY DEFINER SET search_path = public LANGUAGE plpgsql STABLE AS $$
BEGIN
  IF NOT (bx_is_member() OR bx_is_backend()) THEN RAISE EXCEPTION 'Acesso negado.' USING ERRCODE='42501'; END IF;
  RETURN QUERY
    SELECT d.status_calculado, d.acao, COUNT(*),
           COUNT(*) FILTER (WHERE d.concorda),
           ROUND(COUNT(*) FILTER (WHERE d.concorda)::NUMERIC / NULLIF(COUNT(*),0), 2)
      FROM bx_decision_log d
     GROUP BY d.status_calculado, d.acao
     ORDER BY 1,2;
END;
$$;

CREATE OR REPLACE FUNCTION bx_list_importacoes(p_limit INT DEFAULT 30)
RETURNS SETOF bx_importacao
SECURITY DEFINER SET search_path = public LANGUAGE plpgsql STABLE AS $$
BEGIN
  IF NOT (bx_is_member() OR bx_is_backend()) THEN RAISE EXCEPTION 'Acesso negado.' USING ERRCODE='42501'; END IF;
  RETURN QUERY SELECT * FROM bx_importacao ORDER BY created_at DESC LIMIT COALESCE(p_limit,30);
END;
$$;

-- contadores do painel (visão geral das OPs + faltantes)
CREATE OR REPLACE FUNCTION bx_stats()
RETURNS JSONB
SECURITY DEFINER SET search_path = public LANGUAGE plpgsql STABLE AS $$
DECLARE v JSONB;
BEGIN
  IF NOT (bx_is_member() OR bx_is_backend()) THEN RAISE EXCEPTION 'Acesso negado.' USING ERRCODE='42501'; END IF;
  SELECT jsonb_build_object(
    'ops_total',          COALESCE((SELECT COUNT(*) FROM bx_op),0),
    'ops_completas',      COALESCE((SELECT COUNT(*) FROM bx_op WHERE status_calculado='completa'),0),
    'ops_quase',          COALESCE((SELECT COUNT(*) FROM bx_op WHERE status_calculado='quase_completa'),0),
    'ops_travadas',       COALESCE((SELECT COUNT(*) FROM bx_op WHERE status_calculado='travada'),0),
    'ops_sem_dados',      COALESCE((SELECT COUNT(*) FROM bx_op WHERE status_calculado='sem_dados'),0),
    'componentes_faltantes', COALESCE((SELECT COUNT(DISTINCT codigo) FROM bx_empenho WHERE status_componente IN ('falta_parcial','falta_total')),0),
    'faltantes_sem_pedido',  COALESCE((SELECT COUNT(DISTINCT codigo) FROM bx_empenho WHERE status_componente IN ('falta_parcial','falta_total') AND tem_pedido=FALSE),0),
    'compras_atrasadas',  COALESCE((SELECT COUNT(*) FROM bx_pedido_compra WHERE status IN ('aberto','parcial','atrasado') AND data_prevista IS NOT NULL AND data_prevista < CURRENT_DATE),0),
    'ultima_importacao',  (SELECT MAX(created_at) FROM bx_importacao)
  ) INTO v;
  RETURN v;
END;
$$;

-- ---------- grants ----------
GRANT EXECUTE ON FUNCTION bx_is_backend()                                                TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION bx_list_fornecedores(BOOLEAN)                                   TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION bx_upsert_fornecedor(TEXT,TEXT,TEXT,NUMERIC,TEXT,TEXT)          TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION bx_admin_delete_fornecedor(UUID)                                TO authenticated;
GRANT EXECUTE ON FUNCTION bx_list_itens(TEXT,TEXT,INT,INT)                                TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION bx_upsert_item(TEXT,TEXT,TEXT,TEXT,UUID,NUMERIC,NUMERIC)        TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION bx_admin_delete_item(UUID)                                      TO authenticated;
GRANT EXECUTE ON FUNCTION bx_upsert_pedido(UUID,TEXT,TEXT,NUMERIC,DATE,DATE,TEXT,UUID,TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION bx_pedidos_abertos_por_codigo(TEXT)                             TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION bx_classificar_componente(NUMERIC,NUMERIC,NUMERIC)              TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION bx_classificar_op(INT,INT,NUMERIC,INT,NUMERIC)                  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION bx_recompute_op(UUID)                                           TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION bx_recompute_all()                                              TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION bx_dashboard_ops(TEXT,TEXT,TEXT,TEXT,INT,INT)                   TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION bx_op_detalhe(TEXT)                                             TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION bx_componentes_faltantes(BOOLEAN,TEXT,INT)                      TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION bx_compras_atrasadas()                                          TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION bx_liberar_montagem(BOOLEAN,INT)                                TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION bx_record_decision(TEXT,TEXT,BOOLEAN,TEXT,TEXT)                 TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION bx_learning_signals()                                          TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION bx_list_importacoes(INT)                                        TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION bx_stats()                                                      TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- (use DROP FUNCTION IF EXISTS … para cada função acima; tabelas em 005)
-- NOTIFY pgrst, 'reload schema';
