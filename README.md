# EDDY Doc Ingest Pipeline

Dokument-Ingestion-Pipeline für das EDDY Multi-LLM Framework. Verarbeitet PDF, TXT, MD und DOCX Dateien in semantisch durchsuchbare Chunks mit Hybrid-Suche (pgvector + German Fulltext).

**Status:** ✅ Pipeline getestet und funktional (TXT verifiziert, PDF via child_process)

## Architektur

```
📂 ~/eddy-inbox/pending/     ─┐
                               ├──► n8n Workflow ──► PostgreSQL + pgvector
🌐 POST /webhook/eddy/doc-ingest ─┘
```

### Zwei Einstiegspunkte

1. **File-basiert (Manual/Schedule):** `/eddy-inbox/pending/` wird gescannt
2. **API-basiert (Webhook):** `POST /webhook/eddy/doc-ingest` für programmatische Ingestion

### Workflow-Flow (File-Pfad)

```
Manual Trigger / ⏰ Schedule
  → 📂 Scan Inbox
    → 📋 Has Files?
      → 🔍 Duplikat-Check (SHA-256 file_hash)
        → 🆕 Noch nicht ingestiert?
          → 📄 Text Extraction (TXT/MD direkt, PDF via child_process)
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
mkdir -p ~/scripts/eddy-inbox/{pending,processed,failed,scripts}
```

### 3. Helper-Script kopieren

```bash
cp scripts/pdf-extract.js ~/scripts/eddy-inbox/scripts/
```

### 4. Docker Compose konfigurieren

In `docker-compose.yml` beim n8n Service:

```yaml
services:
  n8n:
    volumes:
      - /home/phlummi/scripts/eddy-inbox:/home/node/eddy-inbox
    environment:
      - NODE_FUNCTION_ALLOW_BUILTIN=fs,path,crypto,child_process
      - NODE_FUNCTION_ALLOW_EXTERNAL=pdf-parse
```

**Wichtig:** `child_process` wird für die PDF-Extraktion benötigt (siehe Known Issues).

Danach `docker compose up -d` zum Neustarten.

### 5. Workflow importieren

Datei `n8n/eddy-doc-ingest-workflow.json` in n8n importieren:
- n8n UI → Workflows → Import from File
- Credential "eddy-knowledge-postgres" prüfen (ID: Jq2IeHXVMOnpk0fI)

## Nutzung

### Datei-basiert

Einfach Dateien in `~/scripts/eddy-inbox/pending/` legen:

```bash
cp anleitung.pdf ~/scripts/eddy-inbox/pending/
cp notizen.txt ~/scripts/eddy-inbox/pending/
# → Manuell triggern oder auf Schedule warten
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
| Dateitypen | PDF, TXT, MD (DOCX geplant) |
| DB Credential | eddy-knowledge-postgres |
| Webhook | POST /webhook/eddy/doc-ingest |

## Known Issues & Workarounds

### PDF-Extraktion: n8n Sandbox vs. pdf-parse

n8n's Code-Node Sandbox freezt JavaScript-Prototypen (`Object.freeze`). Die pdf-parse Library modifiziert intern `PasswordException.prototype.constructor`, was zu folgendem Fehler führt:

```
Cannot assign to read only property 'constructor' of function 'PasswordException'
```

**Workaround:** PDF-Extraktion läuft in einem separaten Node.js-Prozess via `child_process.execSync`. Das Helper-Script `scripts/pdf-extract.js` wird über das Volume-Mount im Container bereitgestellt unter `/home/node/eddy-inbox/scripts/pdf-extract.js`.

**Hinweis:** Das Script nutzt den absoluten Pfad zu n8n's gebundeltem pdf-parse Modul. Bei n8n-Updates muss der Pfad ggf. angepasst werden:
```
/usr/local/lib/node_modules/n8n/node_modules/.pnpm/pdf-parse@1.1.1/node_modules/pdf-parse
```

## Dateien

```
eddy-doc-ingest/
├── README.md
├── scripts/
│   └── pdf-extract.js              # PDF Helper (→ ~/eddy-inbox/scripts/)
├── sql/
│   ├── 01_enable_extensions.sql    # pgvector + pg_trgm
│   ├── 02_document_chunks.sql      # Tabelle + Indexes
│   └── 03_search_functions.sql     # Hybrid-Suchfunktionen
└── n8n/
    ├── WORKFLOW_DESIGN.md           # Detailliertes Design-Dokument
    ├── README.md                    # Workflow-spezifische Doku
    └── eddy-doc-ingest-workflow.json # Import-fertiger Workflow
```

## Deployment-Pfade

| Repo-Pfad | Host-Pfad | Container-Pfad |
|-----------|-----------|----------------|
| `scripts/pdf-extract.js` | `~/scripts/eddy-inbox/scripts/pdf-extract.js` | `/home/node/eddy-inbox/scripts/pdf-extract.js` |
| `n8n/eddy-doc-ingest-workflow.json` | n8n Import | Workflow ID: z4re03A65oXIt7Wz |
| `sql/*.sql` | `docker exec -i n8n-postgres psql ...` | DB: eddy_knowledge |

## Teil des EDDY Frameworks

Dieser Workflow ist Teil des EDDY Multi-LLM Collaboration Framework und speist die Knowledge Base, auf die alle EDDY-Instanzen (Claude, Gemini, Ollama) zugreifen können.
