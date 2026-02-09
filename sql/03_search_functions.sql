-- EDDY Doc Ingest: Search Functions
-- ===================================
-- Hybrid search: Vector similarity + Fulltext + optional filters
--
-- docker exec -i n8n-postgres psql -U n8n -d eddy_knowledge < 03_search_functions.sql

-- ============================================================================
-- FUNCTION: semantic_search
-- ============================================================================
CREATE OR REPLACE FUNCTION semantic_search(
    query_embedding vector(1024),
    result_limit INTEGER DEFAULT 5,
    min_similarity FLOAT DEFAULT 0.3,
    filter_category VARCHAR DEFAULT NULL,
    filter_source_type VARCHAR DEFAULT NULL
)
RETURNS TABLE (
    id INTEGER,
    content TEXT,
    source_file VARCHAR,
    source_type VARCHAR,
    category VARCHAR,
    tags TEXT[],
    chunk_index INTEGER,
    similarity FLOAT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        dc.id, dc.content, dc.source_file, dc.source_type,
        dc.category, dc.tags, dc.chunk_index,
        (1 - (dc.embedding <=> query_embedding))::FLOAT AS similarity
    FROM document_chunks dc
    WHERE dc.embedding IS NOT NULL
      AND (filter_category IS NULL OR dc.category = filter_category)
      AND (filter_source_type IS NULL OR dc.source_type = filter_source_type)
      AND (1 - (dc.embedding <=> query_embedding)) >= min_similarity
    ORDER BY dc.embedding <=> query_embedding
    LIMIT result_limit;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: fulltext_search
-- ============================================================================
CREATE OR REPLACE FUNCTION fulltext_search(
    search_query TEXT,
    result_limit INTEGER DEFAULT 5,
    filter_category VARCHAR DEFAULT NULL
)
RETURNS TABLE (
    id INTEGER, content TEXT, source_file VARCHAR,
    source_type VARCHAR, category VARCHAR, tags TEXT[], rank FLOAT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        dc.id, dc.content, dc.source_file, dc.source_type,
        dc.category, dc.tags,
        ts_rank(dc.content_tsv, plainto_tsquery('german', search_query))::FLOAT
    FROM document_chunks dc
    WHERE dc.content_tsv @@ plainto_tsquery('german', search_query)
      AND (filter_category IS NULL OR dc.category = filter_category)
    ORDER BY ts_rank(dc.content_tsv, plainto_tsquery('german', search_query)) DESC
    LIMIT result_limit;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: hybrid_search (RRF - Reciprocal Rank Fusion)
-- ============================================================================
CREATE OR REPLACE FUNCTION hybrid_search(
    query_embedding vector(1024),
    search_text TEXT,
    result_limit INTEGER DEFAULT 5,
    vector_weight FLOAT DEFAULT 0.7,
    filter_category VARCHAR DEFAULT NULL
)
RETURNS TABLE (
    id INTEGER, content TEXT, source_file VARCHAR, source_type VARCHAR,
    category VARCHAR, tags TEXT[],
    vector_similarity FLOAT, text_rank FLOAT, combined_score FLOAT
) AS $$
BEGIN
    RETURN QUERY
    WITH vector_results AS (
        SELECT dc.id,
            ROW_NUMBER() OVER (ORDER BY dc.embedding <=> query_embedding) AS v_rank,
            (1 - (dc.embedding <=> query_embedding))::FLOAT AS v_similarity
        FROM document_chunks dc
        WHERE dc.embedding IS NOT NULL
          AND (filter_category IS NULL OR dc.category = filter_category)
        ORDER BY dc.embedding <=> query_embedding
        LIMIT result_limit * 3
    ),
    text_results AS (
        SELECT dc.id,
            ROW_NUMBER() OVER (ORDER BY ts_rank(dc.content_tsv, plainto_tsquery('german', search_text)) DESC) AS t_rank,
            ts_rank(dc.content_tsv, plainto_tsquery('german', search_text))::FLOAT AS t_score
        FROM document_chunks dc
        WHERE dc.content_tsv @@ plainto_tsquery('german', search_text)
          AND (filter_category IS NULL OR dc.category = filter_category)
        LIMIT result_limit * 3
    ),
    combined AS (
        SELECT COALESCE(vr.id, tr.id) AS cid,
            COALESCE(vr.v_similarity, 0) AS vsim,
            COALESCE(tr.t_score, 0) AS tscore,
            vector_weight * (1.0 / (60 + COALESCE(vr.v_rank, 1000))) 
            + (1 - vector_weight) * (1.0 / (60 + COALESCE(tr.t_rank, 1000))) AS rrf_score
        FROM vector_results vr
        FULL OUTER JOIN text_results tr ON vr.id = tr.id
    )
    SELECT dc.id, dc.content, dc.source_file, dc.source_type,
        dc.category, dc.tags, c.vsim, c.tscore, c.rrf_score
    FROM combined c
    JOIN document_chunks dc ON dc.id = c.cid
    ORDER BY c.rrf_score DESC
    LIMIT result_limit;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================
CREATE OR REPLACE FUNCTION check_file_ingested(p_file_hash VARCHAR)
RETURNS TABLE (is_ingested BOOLEAN, chunk_count BIGINT, ingested_at TIMESTAMP) AS $$
BEGIN
    RETURN QUERY
    SELECT COUNT(*) > 0, COUNT(*), MIN(dc.ingested_at)
    FROM document_chunks dc WHERE dc.file_hash = p_file_hash;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION delete_file_chunks(p_file_hash VARCHAR)
RETURNS INTEGER AS $$
DECLARE deleted_count INTEGER;
BEGIN
    DELETE FROM document_chunks WHERE file_hash = p_file_hash;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_ingest_summary()
RETURNS TABLE (total_chunks BIGINT, total_files BIGINT, types TEXT, newest TIMESTAMP) AS $$
BEGIN
    RETURN QUERY
    SELECT COUNT(*), COUNT(DISTINCT file_hash),
        string_agg(DISTINCT source_type, ', '), MAX(ingested_at)
    FROM document_chunks;
END;
$$ LANGUAGE plpgsql;
