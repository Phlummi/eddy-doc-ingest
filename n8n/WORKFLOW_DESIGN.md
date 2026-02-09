# EDDY Doc Ingest - n8n Workflow Design

## Übersicht

Der Workflow hat **zwei Einstiegspunkte**:
1. **Schedule Trigger** (alle 15 Min) → scannt `/eddy-inbox/pending/`
2. **Webhook POST** → nimmt Text + Metadata direkt entgegen

## Schedule Path (Datei-basiert)

```
⏰ Schedule (15min)
    │
    ▼
📂 Scan Inbox (Code Node)
    │  - Liest /eddy-inbox/pending/
    │  - Filtert: .pdf, .txt, .docx, .md
    │  - Berechnet SHA-256 Hash pro Datei
    │
    ▼
📋 Has Files? (IF)
    │
    ▼
🔍 Duplikat-Check (Postgres)
    │  - check_file_ingested(hash)
    │  - Falls bekannt → Skip
    │
    ▼
🆕 Noch nicht ingestiert? (IF)
    │
    ▼
📄 Text Extraction (Code)
    │  - TXT/MD: fs.readFileSync
    │  - PDF: pdftotext (CLI)
    │  - DOCX: pandoc -t plain
    │
    ▼
🔪 Chunking (800/320)
    │  - 800 Zeichen Chunks (~500 Token)
    │  - 320 Zeichen Overlap (~200 Token)
    │  - Satzgrenzen-Erkennung
    │  - SHA-256 pro Chunk
    │
    ▼
🧬 Embedding (mxbai)
    │  - POST http://n8n-ollama:11434/api/embeddings
    │  - model: mxbai-embed-large
    │  - prefix: 'search_document: '
    │
    ▼
💾 Store in pgvector
    │  - INSERT INTO document_chunks
    │  - ON CONFLICT (content_hash) DO NOTHING
    │
    ▼
📁 Move to Processed
    │  - pending/ → processed/
    │  - Bei Fehler: → failed/
```

## Webhook Path (API-basiert)

```
🌐 POST /webhook/eddy/doc-ingest
    │
    ▼
🔪 Webhook Chunking → 🧬 WH Embedding → 💾 WH Store → ✅ Response
```

## Node-Typen (verifiziert in n8n)

| Node | Typ | Version |
|------|-----|---------|
| Schedule | n8n-nodes-base.scheduleTrigger | 1.2 |
| Webhook | n8n-nodes-base.webhook | 2 |
| Code | n8n-nodes-base.code | 2 |
| IF | n8n-nodes-base.if | 2.2 |
| Postgres | n8n-nodes-base.postgres | 2.5 |
| HTTP Request | n8n-nodes-base.httpRequest | 4.2 |
| Respond | n8n-nodes-base.respondToWebhook | 1.1 |

## Konfiguration

| Parameter | Wert | Begründung |
|-----------|------|------------|
| Chunk Size | 800 Zeichen | ~500 Token, guter Embedding-Kontext |
| Overlap | 320 Zeichen | ~200 Token, erhält Satzkontext |
| Embedding | mxbai-embed-large | 1024 Dim, bereits im Stack |
| Doc Prefix | search_document: | mxbai-Standard für Dokumente |
| Query Prefix | search_query: | mxbai-Standard für Suchanfragen |
| Schedule | */15 * * * * | Alle 15 Minuten |
| Credential | eddy-knowledge-postgres | ID: Jq2IeHXVMOnpk0fI |

## Watch Folder Node

n8n hat **keinen nativen Watch Folder Node** der in Docker-Containern funktioniert.
Der `n8n-nodes-base.localFileTrigger` existiert zwar, erkennt aber keine Änderungen
in gemounteten Volumes zuverlässig (inotify funktioniert nicht über Docker-Mounts).

**Lösung:** Schedule-Trigger + Code-Node ist die Docker-robuste Alternative.
Dateien werden nach Verarbeitung verschoben → kein erneutes Scannen nötig.

## Voraussetzungen

1. pgvector Extension aktiviert in eddy_knowledge
2. Inbox-Ordner als Volume im n8n Container gemountet
3. Ollama mit mxbai-embed-large erreichbar (n8n-ollama:11434)
4. Optional: pdftotext und pandoc im n8n Container für PDF/DOCX
