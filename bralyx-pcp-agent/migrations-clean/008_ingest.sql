-- =============================================
-- Bralyx — 008: Ingestão dos relatórios do ERP (Protheus)
--
-- Duas fontes, ambas em CSV (sem PDF, sem planilha-mestre sincronizada):
--   1) OP/Empenhos+Transferência  → bx_ingest_ops_empenhos()
--      Colunas: Chave, C2_PRODUTO, C2_XDESCP, C2_QUANT, C2_DATPRI, C2_DATPRF,
--               D4_COD, D4_QTDEORI, "Soma de D4_QUANT", D4_XQFALFI, D4_XQTRANS
--      Cria/atualiza as OPs (cabeçalho SC2) e os empenhos (componentes SD4).
--   2) Lista de Prioridades       → bx_ingest_prioridades()
--      Enriquece as OPs com cliente, montador, mercado, situação, painel e datas.
--
-- REPLACE-ON-UPLOAD: cada importação de OP/Empenhos SUBSTITUI todos os empenhos
-- anteriores (snapshot do ERP). Não há "sincronização de planilha" como na
-- Welmy — basta reenviar o CSV atualizado. O cruzamento é recalculado ao final
-- (bx_recompute_all) e cada importação fica registrada em bx_importacao.
--
-- Chamadas pelo n8n (Postgres direto = bx_is_backend()).
-- Rode APÓS 007_seeds.sql
-- =============================================

-- =======  UP  ========

-- ------------------------------------------------------------------
-- 1) OP/Empenhos + Transferência  (substitui todos os empenhos)
-- ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION bx_ingest_ops_empenhos(p_rows JSONB, p_arquivo TEXT DEFAULT NULL)
RETURNS JSONB
SECURITY DEFINER SET search_path = public LANGUAGE plpgsql AS $$
DECLARE
  r JSONB;
  v_imp_id  UUID := gen_random_uuid();
  v_numero  TEXT;
  v_prod    TEXT;
  v_desc    TEXT;
  v_op_id   UUID;
  v_cod     TEXT;
  v_qori    NUMERIC; v_qnec NUMERIC; v_qfal NUMERIC; v_qtra NUMERIC;
  v_ops     INT := 0;
  v_emp     INT := 0;
  v_ign     INT := 0;
BEGIN
  IF NOT (bx_is_member() OR bx_is_backend()) THEN
    RAISE EXCEPTION 'Acesso negado.' USING ERRCODE = '42501';
  END IF;

  -- snapshot: zera os empenhos anteriores (a falta/transferência vem 100% do novo arquivo)
  DELETE FROM bx_empenho;

  FOR r IN SELECT * FROM jsonb_array_elements(COALESCE(p_rows,'[]'::jsonb))
  LOOP
    -- número da OP (chaves toleradas)
    v_numero := NULLIF(TRIM(COALESCE(
      r->>'OP', r->>'op', r->>'C2_NUM', r->>'c2_num',
      r->>'Chave', r->>'chave', r->>'numero', r->>'numero_op')), '');
    v_cod := bx_norm_codigo(COALESCE(r->>'D4_COD', r->>'d4_cod', r->>'codigo', r->>'componente'));

    -- sem OP e sem componente => linha vazia/subtotal
    IF v_numero IS NULL AND v_cod IS NULL THEN CONTINUE; END IF;

    -- componente sem OP (export agregado por item) => não dá para cruzar
    IF v_numero IS NULL THEN v_ign := v_ign + 1; CONTINUE; END IF;

    v_prod := NULLIF(TRIM(COALESCE(r->>'C2_PRODUTO', r->>'c2_produto', r->>'produto')), '');
    v_desc := NULLIF(TRIM(COALESCE(r->>'C2_XDESCP', r->>'c2_xdescp', r->>'produto_descricao', r->>'descricao_produto')), '');

    -- upsert do cabeçalho da OP (refresca os campos SC2; preserva enriquecimento)
    INSERT INTO bx_op(numero, chave, produto_codigo, produto_descricao, quantidade,
                      data_inicio, data_fim, importacao_id)
    VALUES (
      v_numero,
      NULLIF(TRIM(COALESCE(r->>'Chave', r->>'chave')), ''),
      v_prod, v_desc,
      bx_parse_num(COALESCE(r->>'C2_QUANT', r->>'c2_quant', r->>'quantidade')),
      bx_parse_ts(COALESCE(r->>'C2_DATPRI', r->>'c2_datpri'))::date,
      bx_parse_ts(COALESCE(r->>'C2_DATPRF', r->>'c2_datprf'))::date,
      v_imp_id
    )
    ON CONFLICT (numero) DO UPDATE SET
      chave             = COALESCE(EXCLUDED.chave, bx_op.chave),
      produto_codigo    = COALESCE(EXCLUDED.produto_codigo, bx_op.produto_codigo),
      produto_descricao = COALESCE(EXCLUDED.produto_descricao, bx_op.produto_descricao),
      quantidade        = COALESCE(EXCLUDED.quantidade, bx_op.quantidade),
      data_inicio       = COALESCE(EXCLUDED.data_inicio, bx_op.data_inicio),
      data_fim          = COALESCE(EXCLUDED.data_fim, bx_op.data_fim),
      importacao_id     = EXCLUDED.importacao_id
    RETURNING id INTO v_op_id;

    IF NOT FOUND THEN
      SELECT id INTO v_op_id FROM bx_op WHERE numero = v_numero;
    END IF;
    v_ops := v_ops + 1;

    -- linha de empenho (componente). Pode haver OP sem componente (cabeçalho solto).
    IF v_cod IS NOT NULL THEN
      v_qori := bx_parse_num(COALESCE(r->>'D4_QTDEORI', r->>'d4_qtdeori', r->>'qtd_original'));
      v_qnec := bx_parse_num(COALESCE(r->>'Soma de D4_QUANT', r->>'D4_QUANT', r->>'d4_quant', r->>'qtd_necessaria'));
      v_qfal := bx_parse_num(COALESCE(r->>'D4_XQFALFI', r->>'d4_xqfalfi', r->>'qtd_falta', r->>'falta'));
      v_qtra := bx_parse_num(COALESCE(r->>'D4_XQTRANS', r->>'d4_xqtrans', r->>'qtd_transferida', r->>'transferido'));

      INSERT INTO bx_empenho(op_id, codigo, descricao, qtd_original, qtd_necessaria, qtd_transferida, qtd_falta)
      VALUES (v_op_id, v_cod,
              NULLIF(TRIM(COALESCE(r->>'D4_XDESCP', r->>'descricao', r->>'desc_componente')), ''),
              v_qori, COALESCE(v_qnec, v_qori, 0), COALESCE(v_qtra, 0), COALESCE(v_qfal, 0));

      -- garante o componente no catálogo (estoque preservado se já existia)
      PERFORM bx_upsert_item(v_cod, NULLIF(TRIM(r->>'D4_XDESCP'), ''));
      v_emp := v_emp + 1;
    END IF;
  END LOOP;

  -- recalcula status/prioridade de todas as OPs com as bases atuais
  PERFORM bx_recompute_all();

  -- log da importação (substitui os logs anteriores deste tipo = histórico único)
  DELETE FROM bx_importacao WHERE tipo = 'op_empenhos';
  INSERT INTO bx_importacao(id, tipo, arquivo_nome, ops, empenhos, linhas, ignorados, criado_por)
  VALUES (v_imp_id, 'op_empenhos', p_arquivo, v_ops, v_emp,
          jsonb_array_length(COALESCE(p_rows,'[]'::jsonb)), v_ign, auth.uid());

  RETURN jsonb_build_object('tipo','op_empenhos','ops',v_ops,'empenhos',v_emp,'ignorados',v_ign);
END;
$$;

-- ------------------------------------------------------------------
-- 2) Lista de Prioridades  (enriquece as OPs)
-- ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION bx_ingest_prioridades(p_rows JSONB, p_arquivo TEXT DEFAULT NULL)
RETURNS JSONB
SECURITY DEFINER SET search_path = public LANGUAGE plpgsql AS $$
DECLARE
  r JSONB;
  v_imp_id  UUID := gen_random_uuid();
  v_numero  TEXT;
  v_forn    TEXT;
  v_n       INT := 0;
  v_ign     INT := 0;
BEGIN
  IF NOT (bx_is_member() OR bx_is_backend()) THEN
    RAISE EXCEPTION 'Acesso negado.' USING ERRCODE = '42501';
  END IF;

  FOR r IN SELECT * FROM jsonb_array_elements(COALESCE(p_rows,'[]'::jsonb))
  LOOP
    v_numero := NULLIF(TRIM(COALESCE(r->>'OP', r->>'op', r->>'numero')), '');
    IF v_numero IS NULL THEN v_ign := v_ign + 1; CONTINUE; END IF;

    -- fornecedor do painel → catálogo de fornecedores (tipo 'painel')
    v_forn := NULLIF(TRIM(COALESCE(r->>'Fornecedor', r->>'fornecedor')), '');
    IF v_forn IS NOT NULL AND lower(v_forn) <> 'estoque' THEN
      PERFORM bx_upsert_fornecedor(v_forn, 'painel');
    END IF;

    -- cria a OP se ainda não existir (pode chegar antes do export de empenhos)
    INSERT INTO bx_op(numero, produto_codigo, produto_descricao, importacao_id)
    VALUES (v_numero,
            NULLIF(TRIM(COALESCE(r->>'CÓD', r->>'COD', r->>'cod', r->>'produto_codigo')), ''),
            NULLIF(TRIM(COALESCE(r->>'MÁQUINA', r->>'MAQUINA', r->>'maquina', r->>'produto_descricao')), ''),
            v_imp_id)
    ON CONFLICT (numero) DO NOTHING;

    -- enriquecimento (sobrescreve quando a célula vem preenchida; senão preserva)
    UPDATE bx_op SET
      produto_codigo    = COALESCE(NULLIF(TRIM(COALESCE(r->>'CÓD', r->>'COD', r->>'cod')), ''), produto_codigo),
      produto_descricao = COALESCE(NULLIF(TRIM(COALESCE(r->>'MÁQUINA', r->>'MAQUINA', r->>'maquina')), ''), produto_descricao),
      mercado           = COALESCE(NULLIF(TRIM(COALESCE(r->>'Mercado', r->>'mercado')), ''), mercado),
      cliente           = COALESCE(NULLIF(TRIM(COALESCE(r->>'CLIENTE', r->>'cliente')), ''), cliente),
      montador          = COALESCE(NULLIF(TRIM(COALESCE(r->>'MONTADOR', r->>'montador')), ''), montador),
      ordem_entrega     = COALESCE(NULLIF(TRIM(r->>'Ordem de entrega dos equipamentos'), ''), ordem_entrega),
      situacao_erp      = COALESCE(NULLIF(TRIM(COALESCE(r->>'Situação', r->>'Situacao', r->>'situacao')), ''), situacao_erp),
      faltas_texto      = COALESCE(NULLIF(TRIM(COALESCE(r->>'FALTAS', r->>'Faltas de itens para Painéis', r->>'faltas')), ''), faltas_texto),
      painel_codigo     = COALESCE(NULLIF(TRIM(COALESCE(r->>'CÓDIGO PAINEL', r->>'CODIGO PAINEL', r->>'painel_codigo')), ''), painel_codigo),
      painel_op         = COALESCE(NULLIF(TRIM(r->>'OP_PAINEL'), ''), painel_op),
      painel_fornecedor = COALESCE(v_forn, painel_fornecedor),
      painel_situacao   = COALESCE(NULLIF(TRIM(r->>'Situação_PAINEL'), ''), painel_situacao),
      data_solicitacao  = COALESCE(bx_parse_ts(COALESCE(r->>'Data da Solicitação', r->>'data_solicitacao'))::date, data_solicitacao),
      prazo_comercial   = COALESCE(bx_parse_ts(COALESCE(r->>'Prazo (Comercial)', r->>'prazo_comercial'))::date, prazo_comercial),
      aceite_pcp        = COALESCE(NULLIF(TRIM(COALESCE(r->>'Aceite PCP', r->>'aceite_pcp')), ''), aceite_pcp),
      data_acordada     = COALESCE(bx_parse_ts(COALESCE(r->>'Data final acordada - P.A', r->>'data_acordada'))::date, data_acordada),
      data_entrega      = COALESCE(bx_parse_ts(COALESCE(r->>'Data Entrega', r->>'data_entrega'))::date, data_entrega),
      dias_atraso       = COALESCE(bx_parse_num(COALESCE(r->>'Dias de Atraso', r->>'dias_atraso')), dias_atraso),
      faturada          = COALESCE(NULLIF(TRIM(COALESCE(r->>'Faturada?', r->>'faturada')), ''), faturada),
      observacoes       = COALESCE(NULLIF(TRIM(COALESCE(r->>'Observações', r->>'observacoes')), ''), observacoes),
      importacao_id     = v_imp_id
    WHERE numero = v_numero;

    v_n := v_n + 1;
  END LOOP;

  -- reanalisa (dias_atraso e datas alimentam a prioridade)
  PERFORM bx_recompute_all();

  DELETE FROM bx_importacao WHERE tipo = 'prioridades';
  INSERT INTO bx_importacao(id, tipo, arquivo_nome, ops, linhas, ignorados, criado_por)
  VALUES (v_imp_id, 'prioridades', p_arquivo, v_n,
          jsonb_array_length(COALESCE(p_rows,'[]'::jsonb)), v_ign, auth.uid());

  RETURN jsonb_build_object('tipo','prioridades','ops_enriquecidas',v_n,'ignorados',v_ign);
END;
$$;

GRANT EXECUTE ON FUNCTION bx_ingest_ops_empenhos(JSONB, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION bx_ingest_prioridades(JSONB, TEXT)  TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- DROP FUNCTION IF EXISTS bx_ingest_prioridades(JSONB, TEXT);
-- DROP FUNCTION IF EXISTS bx_ingest_ops_empenhos(JSONB, TEXT);
-- NOTIFY pgrst, 'reload schema';
