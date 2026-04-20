# RAG Knowledge Base — PoC Developer Guide

This document is the canonical step-by-step reference for building and running the
local RAG pipeline from scratch. It is written for developers who are new to the
project. All steps assume Windows and the toolchain listed in the README.

---

## Overview

The pipeline has three layers:

1. **Ingestion** — Python script or FastAPI service reads source documents, splits
   them into chunks, generates embeddings, and upserts to Supabase pgvector.
2. **Retrieval + generation** — .NET 10 API receives a question, embeds it,
   performs cosine-similarity search, builds a context prompt, and streams a
   completion from Ollama (default) or OpenAI.
3. **UI** — Single-page HTML served as a static file from the .NET API. Supports
   multi-turn conversation, source citations, drag-and-drop upload, and document
   management.

---

## Step 1 — Supabase Schema

Apply `supabase/schema.sql` before ingesting.

Key elements:

```sql
-- Embedding dimension matches the model in use.
-- Ollama nomic-embed-text  → 768
-- OpenAI text-embedding-3-small → 1536  (requires schema change before ingest)
CREATE TABLE chunks (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source      text   NOT NULL,
    file_type   text,
    content     text   NOT NULL,
    embedding   vector(768) NOT NULL,
    ingested_at timestamptz DEFAULT now()
);

-- HNSW index for sub-millisecond ANN search at PoC scale
CREATE INDEX ON chunks USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

-- Stored function used by the .NET API to perform similarity search
CREATE OR REPLACE FUNCTION match_chunks(
    query_embedding vector(768),
    match_threshold float,
    match_count     int
) RETURNS TABLE (
    id bigint, source text, file_type text,
    content text, similarity float
) ...

-- Stored function used by the ingest API to list documents
CREATE OR REPLACE FUNCTION list_documents()
RETURNS TABLE (source text, file_type text, chunk_count bigint, ingested_at timestamptz)
...
```

Run via Supabase Studio SQL Editor or psql:

```powershell
psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -f supabase/schema.sql
# password: postgres
```

---

## Step 2 — Python Ingestion

`ingest.py` is the CLI ingest path. `ingest_api.py` wraps the same logic in a
FastAPI service that the web UI calls.

### Configuration (`.env`)

```
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_SERVICE_KEY=<service_role key from supabase start>
OPENAI_API_KEY=                  # leave blank to use Ollama
OPENAI_BASE_URL=http://localhost:11434/v1   # Ollama endpoint (default)
EMBED_MODEL=nomic-embed-text     # Ollama default; text-embedding-3-small for OpenAI
CHAT_MODEL=llama3.2:3b
VISION_MODEL=llama3.2:3b
CHUNK_MAX_CHARS=1500
CHUNK_OVERLAP=200
```

### Provider detection

Both `ingest.py` and the .NET API check `OPENAI_API_KEY`:

- **Blank / unset** → client is pointed at the Ollama OpenAI-compatible endpoint
  (`OPENAI_BASE_URL`, default `http://localhost:11434/v1`).
- **Set** → standard OpenAI cloud endpoint is used; `EMBED_MODEL` should be
  changed to `text-embedding-3-small` and the schema dimension updated to 1536.

### CLI usage

```powershell
# Activate the virtual environment first
.venv\Scripts\Activate.ps1

# Ingest a folder
py ingest.py ./docs

# Wipe and re-ingest
py ingest.py ./docs --clear
```

### Supported file types (out of the box)

`txt`, `md`, `html` — no extra dependencies required.

### Optional dependencies for richer formats

```powershell
pip install "unstructured[all-docs]" pillow pytesseract openpyxl
```

Enables: `pdf`, `docx`, `pptx`, `xlsx`, images (via Tesseract OCR or vision LLM).

---

## Step 3 — Ingest API (Upload Service)

`ingest_api.py` exposes the Python ingest logic over HTTP so the browser UI can
upload files without requiring CLI access.

```powershell
# From project root, in a separate terminal
uvicorn ingest_api:app --port 8000 --reload
```

Endpoints:

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/ingest` | Upload a file; returns chunk count and source name |
| `GET` | `/documents` | List all indexed documents (via `list_documents()`) |
| `DELETE` | `/documents/{source}` | Delete all chunks for a document |
| `GET` | `/health` | Health check |

CORS is open (`*`). File paths are sanitized to basename before writing to disk.

---

## Step 4 — .NET Query API

`RagApi` is a minimal .NET 10 web API with three endpoints:

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/chat` | Accept question + optional history; stream SSE completion |
| `GET` | `/health` | Returns `{"status":"ok","ts":"..."}` |
| `GET` | `/` | Serves `wwwroot/index.html` (static files) |

### Chat request shape

```json
{
  "question": "What is the refund policy?",
  "history": [
    { "role": "user",      "content": "..." },
    { "role": "assistant", "content": "..." }
  ]
}
```

`history` is optional. The client trims it to the last 6 turns before sending.

### SSE stream format

```
data: [SOURCES][{"source":"policy.pdf","file_type":"pdf","similarity":0.91}, ...]

data: The refund window is 30 days...

data: [DONE]
```

The `[SOURCES]` event is emitted first (before any text), so the UI can render
citation chips immediately.

### Configuration (`appsettings.json` / environment variables)

| Key | Default | Notes |
|-----|---------|-------|
| `OpenAI:BaseUrl` | `http://localhost:11434/v1` | Ollama endpoint |
| `OpenAI:ApiKey` | `ollama` | Ignored by Ollama; set real key for cloud |
| `OpenAI:EmbedModel` | `nomic-embed-text` | Must match schema vector dimension |
| `OpenAI:ChatModel` | `llama3.2:3b` | |
| `Supabase:Url` | — | Required |
| `Supabase:ServiceKey` | — | Required |

---

## Step 5 — Chat UI

`wwwroot/index.html` is a self-contained single-page app served by the .NET API.
No build step, no framework.

Key behaviours:

- **Multi-turn**: sends the last 6 turns as `history[]` with each request.
- **Streaming**: SSE reader renders assistant tokens as they arrive.
- **Markdown**: bot responses are parsed by `marked.js` and sanitized by
  `DOMPurify` before insertion.
- **Source chips**: `[SOURCES]` event populates a citation strip below each
  response with filename and similarity score.
- **Upload modal**: drag-and-drop or file-picker; calls `POST http://localhost:8000/ingest`.
- **Documents modal**: lists indexed docs; calls `GET /DELETE http://localhost:8000/documents`.

---

## Step 6 — End-to-End Smoke Test

| # | Action | Expected |
|---|--------|----------|
| 1 | `supabase start` | Studio at http://localhost:54323 |
| 2 | Apply schema | `match_chunks` and `list_documents` functions exist |
| 3 | `py ingest.py ./docs` | Rows visible in `chunks` table |
| 4 | `uvicorn ingest_api:app --port 8000` | `GET /health` → 200 |
| 5 | `cd RagApi && dotnet run` | `GET /health` → `{"status":"ok"}` |
| 6 | Open http://localhost:5000, ask a question | Streamed answer + source chips |
| 7 | Ask about content NOT in any document | Model should respond that it does not have that information |
| 8 | Upload a new file via the Upload modal | Chunk count increments in Documents modal |
| 9 | Delete the document in the Documents modal | Chunks removed from table |

---

## Key Decision Reference

| Decision | Current choice | Alternative |
|----------|---------------|-------------|
| Chunking strategy | `chunk_by_title` (semantic) | Fixed-size; only useful if docs have no headings |
| Chunk size | 1500 chars, 200 overlap | Larger for narrative; smaller for FAQ |
| Embedding model | `nomic-embed-text` 768-dim (Ollama) | `text-embedding-3-small` 1536-dim (OpenAI) |
| Vector store | Supabase pgvector | Qdrant — better for >1M chunks or hybrid search |
| Chat model | `llama3.2:3b` (Ollama) | `gpt-4o-mini` (OpenAI) |
| Retrieval | Pure cosine similarity | Hybrid BM25 + vector (production upgrade) |
| Image indexing | Tesseract OCR | Vision LLM for diagrams and charts |
| Deployment | Local Ollama | OpenAI cloud (set `OPENAI_API_KEY`) |
