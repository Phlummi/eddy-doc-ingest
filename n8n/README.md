# n8n Workflow

Siehe `WORKFLOW_DESIGN.md` für das detaillierte Design.

## Import

`eddy-doc-ingest-workflow.json` in n8n importieren:
- n8n UI → Workflows → Import from File
- Alternativ: API Import via `POST /api/v1/workflows`

## Credentials

| Name | ID | Zweck |
|------|-----|-------|
| eddy-knowledge-postgres | Jq2IeHXVMOnpk0fI | PostgreSQL + pgvector |

## Aktive Workflow-ID

`z4re03A65oXIt7Wz` (auf Dattelkarre n8n-Instanz)

## Webhook

- Path: `/webhook/eddy/doc-ingest`
- webhookId: `eddy-doc-ingest-00000010`
- Method: POST

## Docker Environment

Folgende ENV-Variablen sind **zwingend erforderlich**:

```yaml
NODE_FUNCTION_ALLOW_BUILTIN: fs,path,crypto,child_process
NODE_FUNCTION_ALLOW_EXTERNAL: pdf-parse
```

`child_process` wird für die PDF-Extraktion via Helper-Script benötigt.
