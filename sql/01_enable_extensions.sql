-- EDDY Doc Ingest: Enable Required Extensions
-- =============================================
-- Run in eddy_knowledge database:
-- docker exec -i n8n-postgres psql -U n8n -d eddy_knowledge < 01_enable_extensions.sql

CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;  -- Für Fulltext-Trigram-Suche

-- Verify
SELECT extname, extversion FROM pg_extension WHERE extname IN ('vector', 'pg_trgm');
