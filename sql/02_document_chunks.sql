-- EDDY Doc Ingest: Document Chunks Table
-- ========================================
-- Hybrid: pgvector (semantic) + tsvector (fulltext)
--
-- docker exec -i n8n-postgres psql -U n8n -d eddy_knowledge &lt; 02_document_chunks.sql

-- ============================================================================
-- TABLE: document_chunks
-- ============================================================================
CREATE TABLE IF NOT EXISTS document_chunks (
    id SERIAL PRIMARY KEY,
    
    -- Content
    content TEXT NOT NULL,
    content_hash VARCHAR(64) NOT NULL,              -- SHA-256 für Duplikat-Erkennung
    
    -- Vector Embedding (mxbai-embed-large = 1024 Dimensionen)
    embedding vector(1024),
    
    -- Fulltext Search (automatisch generiert)
    content_tsv tsvector GENERATED ALWAYS AS (
        to_tsvector('german', content)
    ) STORED,
    
    -- Document Metadata
    source_file VARCHAR(500) NOT NULL,
    source_path VARCHAR(1000),
    source_type VARCHAR(20) NOT NULL DEFAULT 'unknown',
    file_hash VARCHAR(64),
    
    -- Chunk Position
    chunk_index INTEGER NOT NULL DEFAULT 0,
    total_chunks INTEGER,
    
    -- Classification
    category VARCHAR(100),
    tags TEXT[],
    
    -- Timestamps
    ingested_at TIMESTAMP DEFAULT NOW(),
    source_modified_at TIMESTAMP,
    
    -- Constraints
    CONSTRAINT unique_chunk_hash UNIQUE (content_hash)
);

-- ============================================================================
-- INDEXES
-- ============================================================================

-- HNSW für schnelle Vektor-Suche (Cosine Distance)
CREATE INDEX IF NOT EXISTS idx_doc_chunks_embedding 
    ON document_chunks 
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

-- GIN für Fulltext
CREATE INDEX IF NOT EXISTS idx_doc_chunks_tsv 
    ON document_chunks 
    USING gin (content_tsv);

-- Trigram für LIKE/ILIKE (Fehlercodes, Config-Keys)
CREATE INDEX IF NOT EXISTS idx_doc_chunks_content_trgm 
    ON document_chunks 
    USING gin (content gin_trgm_ops);

-- B-Tree Indexes
CREATE INDEX IF NOT EXISTS idx_doc_chunks_source_file ON document_chunks (source_file);
CREATE INDEX IF NOT EXISTS idx_doc_chunks_source_type ON document_chunks (source_type);
CREATE INDEX IF NOT EXISTS idx_doc_chunks_category ON document_chunks (category);
CREATE INDEX IF NOT EXISTS idx_doc_chunks_file_hash ON document_chunks (file_hash);
CREATE INDEX IF NOT EXISTS idx_doc_chunks_tags ON document_chunks USING gin (tags);

COMMENT ON TABLE document_chunks IS 'EDDY Knowledge Base: Chunked documents with vector + fulltext search for LLM retrieval';
