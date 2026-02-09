# EDDY Doc Ingest Pipeline

Dokument-Ingestion-Pipeline für das EDDY Multi-LLM Framework. Verarbeitet PDF, TXT, MD und DOCX Dateien in semantisch durchsuchbare Chunks mit Hybrid-Suche (pgvector + German Fulltext).

## Architektur

```
📂 ~/eddy-inbox/pending/     ─┐
                               ├──► n8n Workflow ──► PostgreSQL + pgvector
🌐 POST /webhook/eddy/doc-ingest ─┘
```

### Zwei Einstiegspunkte

1. **File-basiert (Schedule):** Alle 15 Minuten wird `/eddy-inbox/pending/` gescannt
2. **API-basiert (Webhook):** `POST /webhook/eddy/doc-ingest` für programmatische Ingestion

### Workflow-Flow (File-Pfad)

```
⏰ Schedule (15min)
  → 📂 Scan Inbox
    → 📋 Has Files?
      → 🔍 Duplikat-Check (SHA-256 file_hash)
        → 🆕 Noch nicht ingestiert?
          → 📄 Text Extraction (PDF/TXT/MD/DOCX)
            → 🔪 Chunking (800 chars / 320 overlap)
              → 🧬 Embedding (mxbai-embed-large, 1024 dim)
                → 💾 Store in pgvector
                  → 📁 Move to Processed
```

## Setup

### 1. Datenbank vorbereiten

```bash
# Extensions aktivieren
docker exec -i n8n-postgres psql -U n8n -d eddy_knowledge < sql/01_enable_extensions.sql

# Tabelle erstellen
docker exec -i n8n-postgres psql -U n8n -d eddy_knowledge < sql/02_document_chunks.sql

# Such-Funktionen installieren
docker exec -i n8n-postgres psql -U n8n -d eddy_knowledge < sql/03_search_functions.sql
```

### 2. Inbox-Verzeichnis erstellen

```bash
mkdir -p ~/eddy-inbox/{pending,processed,failed}
```

### 3. Docker Volume mounten

In `docker-compose.yml` beim n8n Service hinzufügen:

```yaml
volumes:
  - /home/phlummi/eddy-inbox:/eddy-inbox
```

Danach `docker compose up -d` zum Neustarten.

### 4. Workflow importieren

Datei `n8n/eddy-doc-ingest-workflow.json` in n8n importieren:
- n8n UI → Workflows → Import from File
- Credential "eddy-knowledge-postgres" prüfen (ID: Jq2IeHXVMOnpk0fI)

### 5. Optional: PDF/DOCX Tools

Für PDF- und DOCX-Extraktion im n8n Container:

```bash
docker exec -u root n8n-app apt-get update && apt-get install -y poppler-utils pandoc
```

## Nutzung

### Datei-basiert

Einfach Dateien in `~/eddy-inbox/pending/` legen:

```bash
cp anleitung.pdf ~/eddy-inbox/pending/
# → Wird beim nächsten 15-Minuten-Scan verarbeitet
```

### API-basiert

```bash
curl -X POST http://localhost:5678/webhook/eddy/doc-ingest \
  -H "Content-Type: application/json" \
  -d '{
    "content": "Docker Networking Guide: Bridge-Netzwerke verbinden Container...",
    "metadata": {
      "source_file": "docker-networking.md",
      "source_type": "md",
      "category": "infrastructure",
      "tags": ["docker", "networking"]
    }
  }'
```

### Suche

```sql
-- Semantische Suche
SELECT * FROM semantic_search('Docker bridge Netzwerk konfigurieren', 5);

-- Volltext-Suche (deutsch)
SELECT * FROM fulltext_search('Container Netzwerk', 5);

-- Hybrid-Suche (empfohlen: 70% semantisch, 30% fulltext)
SELECT * FROM hybrid_search('Docker Netzwerk Konfiguration', 10, 0.7, 0.3);

-- Status prüfen
SELECT * FROM get_ingest_summary();
```

## Technische Details

| Parameter | Wert |
|-----------|------|
| Embedding Model | mxbai-embed-large (1024 dim) |
| Chunk Size | 800 Zeichen (~500 Token) |
| Overlap | 320 Zeichen (~200 Token) |
| Deduplizierung | SHA-256 (file_hash + content_hash) |
| Vector Index | HNSW (m=16, ef_construction=64) |
| Fulltext | German tsvector + pg_trgm |
| Hybrid Scoring | Reciprocal Rank Fusion (RRF) |
| Dateitypen | PDF, TXT, MD, DOCX |
| DB Credential | eddy-knowledge-postgres |
| Schedule | Alle 15 Minuten |
| Webhook | POST /webhook/eddy/doc-ingest |

## Dateien

```
eddy-doc-ingest/
├── README.md
├── sql/
│   ├── 01_enable_extensions.sql    # pgvector + pg_trgm
│   ├── 02_document_chunks.sql      # Tabelle + Indexes
│   └── 03_search_functions.sql     # Hybrid-Suchfunktionen
└── n8n/
    ├── WORKFLOW_DESIGN.md           # Detailliertes Design-Dokument
    ├── README.md                    # Workflow-spezifische Doku
    └── eddy-doc-ingest-workflow.json # Import-fertiger Workflow
```

## Teil des EDDY Frameworks

Dieser Workflow ist Teil des EDDY Multi-LLM Collaboration Framework und speist die Knowledge Base, auf die alle EDDY-Instanzen (Claude, Gemini, Ollama) zugreifen können.
