# Ingest API

## What it does (ELI5)

The ingestion script normally runs from the command line. The ingest API wraps that
same logic in a small web service so the browser can upload a file, and the system
handles all the chunking and indexing without anyone needing to open a terminal. It
also lets the UI see what documents are already in the system, and delete them.

---

## Technical Detail

`ingest_api.py` is a FastAPI application. It imports and calls the same chunking
and embedding logic as `ingest.py`. Run it alongside the .NET API:

```powershell
uvicorn ingest_api:app --port 8000 --reload
```

### Endpoints

| Method | Path | Description |
|---|---|---|
| `POST` | `/ingest` | Upload a file (multipart). Returns `{ source, chunk_count }` |
| `GET` | `/documents` | List all indexed documents via `list_documents()` RPC |
| `DELETE` | `/documents/{source}` | Delete all chunks where `source = {source}` |
| `GET` | `/health` | Returns `{ status: "ok" }` |

### File handling

Uploaded files are written to a temporary path using the basename only (`os.path.basename`).
This prevents path traversal: a filename like `../../etc/passwd` is reduced to
`passwd` before writing. Files are deleted from disk after ingestion.

### CORS

CORS is open (`*`) because the browser UI is served from `localhost:5000` and the
ingest API runs on `:8000`. Restrict origins before deploying beyond localhost.

### Authentication

None. All endpoints are unauthenticated. Add an API key header check or reverse-
proxy authentication before exposing this service on a network.

---

## Alternatives

| Option | Pros | Cons |
|---|---|---|
| **FastAPI** (current) | Minimal boilerplate, fast, Pydantic validation | Adds Python runtime requirement alongside .NET |
| **Implement in .NET (RagApi)** | Single runtime; no cross-origin issue | Replicates complex document parsing stack in C# |
| **Background job queue (Celery/RQ)** | Files queued asynchronously; upload returns immediately | More infrastructure; overkill at PoC scale |
| **Cloud storage trigger (Azure Blob)** | Upload from anywhere; scales automatically | Cloud-only; adds storage cost and infrastructure |
