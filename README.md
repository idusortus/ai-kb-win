# AI Knowledge Base — RAG PoC

Local-first RAG pipeline: Python ingestion → Supabase pgvector → .NET 10 API → Chat UI.  
All AI runs locally via **Ollama** by default — no API keys required, no data leaves the machine.  
OpenAI cloud is supported as a drop-in alternative via a single environment variable.

---

## Prerequisites

| Tool | Install | Notes |
|------|---------|-------|
| **Python 3.12** | `winget install Python.Python.3.12` | `py` alias |
| **.NET 10 SDK** | Already installed | |
| **Docker Desktop** | Required for Supabase local | Must be running |
| **Supabase CLI** | `winget install Supabase.CLI` | |
| **Ollama** | `winget install Ollama.Ollama` | Restart terminal after install |
| **Tesseract OCR** | `winget install UB-Mannheim.TesseractOCR` | *Optional* — only for PDF image extraction |

## Quick Start

### 1. Pull Ollama models

```powershell
ollama pull nomic-embed-text    # embedding model (~274MB)
ollama pull llama3.2:3b         # chat model (~2GB, CPU-friendly)
```

### 2. Start local Supabase

```powershell
cd C:\DEV\projects\ai-kb
supabase start                  # first run pulls Docker images (~5 min)
```

Note the **API URL** and **service_role key** printed to console.  
Defaults: `http://127.0.0.1:54321` and the long `eyJ...` JWT.

### 3. Apply the schema

```powershell
# Option A: via Supabase Studio (http://localhost:54323 → SQL Editor)
# Paste contents of supabase/schema.sql and run

# Option B: via psql
psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -f supabase/schema.sql
# password: postgres
```

### 4. Create `.env`

```powershell
Copy-Item .env.example .env
```

Edit `.env` — the defaults work for local Supabase + Ollama. Just verify the
`SUPABASE_SERVICE_KEY` matches what `supabase start` printed.

### 5. Python environment

```powershell
py -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
# For PDF/DOCX/PPTX support, also:
# pip install "unstructured[all-docs]" pillow pytesseract openpyxl
```

### 6. Ingest documents (CLI)

Drop files into `./docs` (TXT, MD, HTML work out of the box; PDF/DOCX/PPTX/XLSX require the optional deps below).

```powershell
py ingest.py ./docs
# Add --clear to wipe and re-ingest
```

**Optional deps** — install these if you need PDF/DOCX/PPTX/XLSX support:

```powershell
pip install "unstructured[all-docs]" pillow pytesseract openpyxl
```

### 7. Run the ingest API (upload service)

Required to use the Upload and Documents features in the web UI.

```powershell
# In a separate terminal, from the project root
uvicorn ingest_api:app --port 8000 --reload
```

### 8. Run the query API

```powershell
cd RagApi
dotnet run
# Listening on http://localhost:5000
```

Smoke test:
```powershell
(Invoke-WebRequest http://localhost:5000/health).Content
```

### 9. Open the UI

Navigate to **http://localhost:5000** in a browser.

- Ask questions about your ingested documents.
- Use **Upload** in the header to add documents directly from the browser.
- Use **Documents** in the header to view and delete indexed documents.

---

## Architecture

```
docs/  ──→  ingest.py (CLI)  ──→  Supabase pgvector (local Docker)
                                            ↑
browser  ──→  ingest_api.py (FastAPI :8000) ┘

browser  ──→  RagApi (.NET :5000)  ──→  Supabase pgvector
                                    ──→  Ollama / OpenAI (embed + chat)

RagApi also serves index.html (the chat UI) as static files.
```

## Switching to OpenAI Cloud

Set `OPENAI_API_KEY` in `.env` — both `ingest.py` and `RagApi` auto-detect it
and switch from Ollama to OpenAI. You will also need to:
1. Change `vector(768)` → `vector(1536)` in `supabase/schema.sql`
2. Re-apply the schema (`DROP TABLE chunks;` then re-run)
3. Re-ingest all documents (`py ingest.py ./docs --clear`)

## Next Steps

- [ ] **Test with real documents** — drop actual PDFs/DOCX/PPTX into `docs/` and ingest
- [ ] **Tune chunk size** — adjust `max_characters` in `ingest.py` if answers lack context
- [ ] **Add hybrid search** — combine BM25 full-text with vector similarity for better recall
- [ ] **Auth** — add API key or JWT auth to the `/chat` endpoint before sharing
- [ ] **Deploy** — containerize with Docker Compose for team/client access
- [ ] **Evaluation** — build a test set of Q&A pairs to measure retrieval quality

---

## Developer Documentation

| Document | Description |
|---|---|
| [Architecture overview](docs/developer/architecture.md) | Component map, data flow, technology rationale, known gaps |
| [RAG PoC guide](docs/developer/rag-kb-poc.md) | Step-by-step build and smoke test reference |
| [PoC implementation guide](docs/developer/ai-poc-guide.md) | All three PoC builds with demo checklists |
| [AI reference](docs/developer/ai-reference.md) | Decision tables and cross-cutting concerns |
| [Chat UI](docs/developer/components/chat-ui.md) | Component detail — wwwroot/index.html |
| [.NET API](docs/developer/components/dotnet-api.md) | Component detail — RagApi/Program.cs |
| [Python ingestion](docs/developer/components/python-ingestion.md) | Component detail — ingest.py / ingest_api.py |
| [Ingest API](docs/developer/components/ingest-api.md) | Component detail — FastAPI upload service |
| [Supabase + pgvector](docs/developer/components/supabase-pgvector.md) | Component detail — schema, index, stored functions |
| [Ollama](docs/developer/components/ollama.md) | Component detail — local inference server |
