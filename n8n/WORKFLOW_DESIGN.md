# EDDY Doc Ingest - n8n Workflow Design

## Übersicht

Der Workflow hat **zwei Einstiegspunkte**:
1. **Manual Trigger / Schedule** → scannt `/eddy-inbox/pending/`
2. **Webhook POST** → nimmt Text + Metadata direkt entgegen

## Schedule Path (Datei-basiert)

```
Manual Trigger / ⏰ Schedule
    │
    ▼
📂 Scan Inbox (Code Node)
    │  - Liest /home/node/eddy-inbox/pending/
    │  - Filtert: .pdf, .txt, .docx, .md
    │  - Berechnet SHA-256 Hash pro Datei
    │
    ▼
📋 Has Files? (IF)
    │  - Prüft ob fileName existiert
    │  - true → weiter, false → Ende
    │
    ▼
🔍 Duplikat-Check (Postgres)
    │  - check_file_ingested(hash)
    │  - Falls bekannt → Skip
    │
    ▼
🆕 Noch nicht ingestiert? (IF)
    │  - is_ingested == false → weiter
    │
    ▼
📄 Text Extraction (Code)
    │  - TXT/MD: fs.readFileSync (direkt)
    │  - PDF: child_process.execSync → pdf-extract.js
    │  - DOCX: [noch nicht implementiert]
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

## PDF-Extraktion: child_process Workaround

n8n's Code-Node Sandbox freezt alle JavaScript-Prototypen. pdf-parse (via pdfjs)
versucht `PasswordException.prototype.constructor` zu modifizieren → Crash.

**Lösung:** Externes Helper-Script wird via `child_process.execSync` aufgerufen:

```javascript
// Im Text Extraction Code Node:
const result = execSync(
  'node /home/node/eddy-inbox/scripts/pdf-extract.js "' + filePath + '"',
  { timeout: 30000, encoding: 'utf-8', maxBuffer: 10 * 1024 * 1024 }
);
const parsed = JSON.parse(result.trim());
```

Das Script liegt persistent im Volume-Mount (`~/scripts/eddy-inbox/scripts/`) und
überlebt Container-Restarts. Es nutzt n8n's gebundeltes pdf-parse Modul.

**Voraussetzung in docker-compose.yml:**
```yaml
environment:
  - NODE_FUNCTION_ALLOW_BUILTIN=fs,path,crypto,child_process
```

## Webhook Path (API-basiert)

```
🌐 POST /webhook/eddy/doc-ingest
    │
    ▼
🔪 Webhook Chunking → 🧬 WH Embedding → 💾 WH Store → ✅ WH Response
```

## Node-Typen (verifiziert in n8n)

| Node | Typ | Version |
|------|-----|---------|
| Manual Trigger | n8n-nodes-base.manualTrigger | 1 |
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
| Credential | eddy-knowledge-postgres | ID: Jq2IeHXVMOnpk0fI |
| Webhook | POST /webhook/eddy/doc-ingest | webhookId: eddy-doc-ingest-00000010 |
| Workflow ID | z4re03A65oXIt7Wz | n8n interne ID |

## IF-Node Routing (Wichtig!)

n8n IF-Nodes haben invertiertes Routing bei bestimmten Operatoren:
- **📋 Has Files?**: `true` Branch (index 0) → Duplikat-Check
- **🆕 Noch nicht ingestiert?**: `notTrue` auf is_ingested → `false` Branch (index 1) → Text Extraction

Bei Reimport des Workflows die Connections prüfen!

## Docker-Voraussetzungen

```yaml
# docker-compose.yml (n8n Service)
environment:
  - NODE_FUNCTION_ALLOW_BUILTIN=fs,path,crypto,child_process
  - NODE_FUNCTION_ALLOW_EXTERNAL=pdf-parse
volumes:
  - /home/phlummi/scripts/eddy-inbox:/home/node/eddy-inbox
```

## Watch Folder Node

n8n hat **keinen nativen Watch Folder Node** der in Docker-Containern funktioniert.
Der `n8n-nodes-base.localFileTrigger` existiert zwar, erkennt aber keine Änderungen
in gemounteten Volumes zuverlässig (inotify funktioniert nicht über Docker-Mounts).

**Lösung:** Manual/Schedule-Trigger + Code-Node ist die Docker-robuste Alternative.
Dateien werden nach Verarbeitung verschoben → kein erneutes Scannen nötig.
