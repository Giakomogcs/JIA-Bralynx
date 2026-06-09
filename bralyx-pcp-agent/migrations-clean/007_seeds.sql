-- =============================================
-- Bralyx — 007: Seeds (apenas admin bootstrap)
--
-- - Cria/atualiza o admin (admin@bralynx.com.br / @Admin123)
--     * a senha NÃO é sobrescrita em re-execuções (preserva rotações em prod)
--
-- IMPORTANTE — sem dados de exemplo:
--   Fornecedores, itens, OPs e empenhos NÃO são semeados. TODOS os dados de
--   produção, estoque e compras entram exclusivamente pelos relatórios do ERP
--   (Protheus): OP/Empenhos e Lista de Prioridades.
-- ALERTA: troque a senha do admin logo após o primeiro login.
-- Rode APÓS 006_pcp_rpc.sql
-- =============================================

-- =======  UP  ========

DO $$
DECLARE
  v_email     TEXT := 'admin@bralynx.com.br';
  v_password  TEXT := '@Admin123';
  v_user_id   UUID;
  -- company_name é o identificador interno usado pelos guards (bx_is_admin/bx_is_member)
  -- e filtros de usuários: TEM de ser 'bralyx' (NÃO mexer). Só o e-mail/marca é "Bralynx".
  v_meta      JSONB := '{"role":"admin","company_name":"bralyx","full_name":"Administrador Bralynx"}'::jsonb;
BEGIN
  SELECT id INTO v_user_id FROM auth.users WHERE email = v_email LIMIT 1;

  IF v_user_id IS NULL THEN
    v_user_id := gen_random_uuid();
    INSERT INTO auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at,
      confirmation_token, email_change, email_change_token_new, recovery_token
    ) VALUES (
      '00000000-0000-0000-0000-000000000000',
      v_user_id, 'authenticated', 'authenticated', v_email,
      crypt(v_password, gen_salt('bf')),
      NOW(),
      jsonb_build_object('provider','email','providers',ARRAY['email']),
      v_meta, NOW(), NOW(), '', '', '', ''
    );
    INSERT INTO auth.identities (
      id, user_id, provider_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) VALUES (
      gen_random_uuid(), v_user_id, v_user_id::text,
      jsonb_build_object('sub', v_user_id::text, 'email', v_email, 'email_verified', true),
      'email', NOW(), NOW(), NOW()
    );
    RAISE NOTICE 'Bralynx bootstrap admin criado: %', v_email;
  ELSE
    UPDATE auth.users
       SET raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb) || v_meta,
           updated_at = NOW()
     WHERE id = v_user_id;
    RAISE NOTICE 'Bralynx bootstrap admin já existe, metadata atualizada: %', v_email;
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- DELETE FROM auth.identities WHERE user_id IN (SELECT id FROM auth.users WHERE email='admin@bralynx.com.br');
-- DELETE FROM auth.users WHERE email='admin@bralynx.com.br';
-- NOTIFY pgrst, 'reload schema';
