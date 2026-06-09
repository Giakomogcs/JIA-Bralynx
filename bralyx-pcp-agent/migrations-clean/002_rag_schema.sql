-- =============================================
-- Bralyx — 002: RAG schema (sem ACL por categoria/equipe)
-- O RAG é GLOBAL: todo usuário autenticado da empresa acessa todos os
-- documentos (glossário PCP, regras de status de OP, como ler os relatórios
-- do Protheus, políticas de priorização) através do agente de IA.
-- Não há gating por equipe/categoria.
--
-- - Extensões pgvector / pgcrypto
-- - Tabelas: bx_document_metadata, bx_document_rows, bx_documents
-- - Índice HNSW (fallback ivfflat) em embedding
-- Rode APÓS 001_users_and_admin.sql
-- =============================================

-- =======  UP  ========

CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------- metadata por arquivo ----------
CREATE TABLE IF NOT EXISTS bx_document_metadata (
  file_id      TEXT PRIMARY KEY,
  title        TEXT,
  code         TEXT,
  url          TEXT,
  source       TEXT,
  mime_type    TEXT,
  schema       JSONB,
  session_id   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- session_id: anexos enviados pelo chat (com sessão); NULL = documento global.
ALTER TABLE bx_document_metadata ADD COLUMN IF NOT EXISTS session_id TEXT;
CREATE INDEX IF NOT EXISTS idx_bx_meta_code    ON bx_document_metadata(code);
CREATE INDEX IF NOT EXISTS idx_bx_meta_session ON bx_document_metadata(session_id);

DROP TRIGGER IF EXISTS trg_bx_meta_updated_at ON bx_document_metadata;
CREATE TRIGGER trg_bx_meta_updated_at
  BEFORE UPDATE ON bx_document_metadata
  FOR EACH ROW EXECUTE FUNCTION bx_set_updated_at();

-- ---------- linhas tabulares (csv/xlsx) ----------
CREATE TABLE IF NOT EXISTS bx_document_rows (
  id          BIGSERIAL PRIMARY KEY,
  dataset_id  TEXT NOT NULL REFERENCES bx_document_metadata(file_id) ON DELETE CASCADE,
  row_data    JSONB NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_bx_rows_dataset ON bx_document_rows(dataset_id);

-- ---------- chunks vetoriais (LangChain Supabase vector store) ----------
CREATE TABLE IF NOT EXISTS bx_documents (
  id        BIGSERIAL PRIMARY KEY,
  content   TEXT,
  metadata  JSONB,
  embedding vector(1536)
);
CREATE INDEX IF NOT EXISTS idx_bx_docs_file_id
  ON bx_documents ( (metadata->>'file_id') );

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public' AND indexname = 'bx_documents_embedding_hnsw'
  ) THEN
    EXECUTE 'CREATE INDEX bx_documents_embedding_hnsw
             ON bx_documents USING hnsw (embedding vector_cosine_ops)';
  END IF;
EXCEPTION WHEN OTHERS THEN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public' AND indexname = 'bx_documents_embedding_ivfflat'
  ) THEN
    EXECUTE 'CREATE INDEX bx_documents_embedding_ivfflat
             ON bx_documents USING ivfflat (embedding vector_cosine_ops)
             WITH (lists = 100)';
  END IF;
END $$;

-- ---------- upsert atômico de metadata ----------
CREATE OR REPLACE FUNCTION bx_rag_upsert_metadata(
  p_file_id   TEXT,
  p_title     TEXT,
  p_code      TEXT  DEFAULT NULL,
  p_url       TEXT  DEFAULT NULL,
  p_source    TEXT  DEFAULT 'webhook',
  p_mime_type TEXT  DEFAULT NULL,
  p_schema    JSONB DEFAULT NULL
)
RETURNS VOID
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO bx_document_metadata(
    file_id, title, code, url, source, mime_type, schema, updated_at
  )
  VALUES (p_file_id, p_title, p_code, p_url, p_source, p_mime_type, p_schema, NOW())
  ON CONFLICT (file_id) DO UPDATE
    SET title      = COALESCE(EXCLUDED.title,     bx_document_metadata.title),
        code       = COALESCE(EXCLUDED.code,      bx_document_metadata.code),
        url        = COALESCE(EXCLUDED.url,       bx_document_metadata.url),
        source     = COALESCE(EXCLUDED.source,    bx_document_metadata.source),
        mime_type  = COALESCE(EXCLUDED.mime_type, bx_document_metadata.mime_type),
        schema     = COALESCE(EXCLUDED.schema,    bx_document_metadata.schema),
        updated_at = NOW();
END;
$$;

CREATE OR REPLACE FUNCTION bx_rag_purge_file(p_file_id TEXT)
RETURNS TABLE(deleted_chunks bigint, deleted_rows bigint)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  c1 bigint := 0;
  c2 bigint := 0;
BEGIN
  DELETE FROM bx_documents       WHERE metadata->>'file_id' = p_file_id;
  GET DIAGNOSTICS c1 = ROW_COUNT;
  DELETE FROM bx_document_rows   WHERE dataset_id = p_file_id;
  GET DIAGNOSTICS c2 = ROW_COUNT;
  deleted_chunks := c1;
  deleted_rows   := c2;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION bx_admin_rag_delete_file(p_file_id TEXT)
RETURNS VOID
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT bx_is_admin() THEN
    RAISE EXCEPTION 'Acesso negado: apenas administradores.' USING ERRCODE = '42501';
  END IF;
  PERFORM bx_rag_purge_file(p_file_id);
  DELETE FROM bx_document_metadata WHERE file_id = p_file_id;
END;
$$;

CREATE OR REPLACE FUNCTION bx_admin_list_rag_documents()
RETURNS TABLE(
  file_id     TEXT,
  title       TEXT,
  code        TEXT,
  url         TEXT,
  source      TEXT,
  mime_type   TEXT,
  chunk_count BIGINT,
  created_at  TIMESTAMPTZ,
  updated_at  TIMESTAMPTZ
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  IF NOT bx_is_admin() THEN
    RAISE EXCEPTION 'Acesso negado: apenas administradores.' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
    SELECT
      m.file_id, m.title, m.code, m.url, m.source, m.mime_type,
      COALESCE((SELECT COUNT(*) FROM bx_documents d WHERE d.metadata->>'file_id' = m.file_id), 0),
      m.created_at, m.updated_at
    FROM bx_document_metadata m
    ORDER BY COALESCE(m.code, m.title, m.file_id);
END;
$$;

-- Lista para membros (sem ACL — todo membro vê todos os documentos)
CREATE OR REPLACE FUNCTION bx_list_rag_documents()
RETURNS TABLE(
  file_id TEXT,
  title   TEXT,
  code    TEXT,
  url     TEXT
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  IF NOT bx_is_member() THEN
    RAISE EXCEPTION 'Acesso negado.' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
    SELECT m.file_id, m.title, m.code, m.url
      FROM bx_document_metadata m
     ORDER BY COALESCE(m.code, m.title);
END;
$$;

GRANT SELECT  ON bx_document_metadata TO authenticated;
GRANT SELECT  ON bx_document_rows     TO authenticated;
GRANT SELECT  ON bx_documents         TO authenticated;
GRANT EXECUTE ON FUNCTION bx_rag_upsert_metadata(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION bx_rag_purge_file(TEXT)            TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION bx_admin_rag_delete_file(TEXT)     TO authenticated;
GRANT EXECUTE ON FUNCTION bx_admin_list_rag_documents()      TO authenticated;
GRANT EXECUTE ON FUNCTION bx_list_rag_documents()            TO authenticated;

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- DROP FUNCTION IF EXISTS bx_list_rag_documents();
-- DROP FUNCTION IF EXISTS bx_admin_list_rag_documents();
-- DROP FUNCTION IF EXISTS bx_admin_rag_delete_file(TEXT);
-- DROP FUNCTION IF EXISTS bx_rag_purge_file(TEXT);
-- DROP FUNCTION IF EXISTS bx_rag_upsert_metadata(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB);
-- DROP INDEX    IF EXISTS bx_documents_embedding_hnsw;
-- DROP INDEX    IF EXISTS bx_documents_embedding_ivfflat;
-- DROP TABLE    IF EXISTS bx_documents;
-- DROP TABLE    IF EXISTS bx_document_rows;
-- DROP TABLE    IF EXISTS bx_document_metadata;
-- NOTIFY pgrst, 'reload schema';
