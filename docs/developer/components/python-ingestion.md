# Python Ingestion

## What it does (ELI5)

Imagine you have a stack of manuals and PDFs. The ingestion script reads each one,
cuts the text into manageable pieces, asks an AI model to describe what each piece
"means" as a list of numbers (a vector), and saves those pieces and numbers into a
database. Later, when someone asks a question, the database can find the pieces
that mean something similar to the question.

---

## Technical Detail

`ingest.py` is the CLI entry point. `ingest_api.py` exposes the same logic over
HTTP so the browser UI can trigger ingestion without terminal access.

### Chunking

Uses `unstructured` for document parsing. The default chunking strategy is
`chunk_by_title` — it splits on heading boundaries and produces semantically
coherent chunks rather than fixed-size blocks. This significantly improves
retrieval quality for structured documents.

| Setting | Value | Notes |
|---|---|---|
| `CHUNK_MAX_CHARS` | 1500 | Increase for narrative docs, decrease for dense FAQs |
| `CHUNK_OVERLAP` | 200 | ~13% overlap prevents context loss at boundaries |

### Embedding

Chunks are embedded in batches using the OpenAI-compatible endpoint. Provider is
selected by environment variable:

| `OPENAI_API_KEY` | Provider | Model | Dimension |
|---|---|---|---|
| Not set | Ollama (`OPENAI_BASE_URL`) | `nomic-embed-text` | 768 |
| Set | OpenAI cloud | `text-embedding-3-small` | 1536 |

Changing provider requires updating the schema vector dimension and re-ingesting
all documents.

### Storage

Chunks are upserted to the `chunks` table in Supabase via the REST API
(`supabase-py`). The `source` column is the filename (basename only — no path
traversal risk from the API path). The `file_type` column is the extension.

### CLI usage

```powershell
py ingest.py ./docs           # ingest all supported files in a folder
py ingest.py ./docs --clear   # drop all existing chunks, then re-ingest
```

### Supported formats

| Format | Requires |
|---|---|
| `txt`, `md`, `html` | Base install only |
| `pdf`, `docx`, `pptx` | `pip install "unstructured[all-docs]"` |
| `xlsx` | `pip install openpyxl` |
| Images (OCR) | `pip install pillow pytesseract` + Tesseract binary |
| Images (vision) | Vision-capable LLM configured as `VISION_MODEL` |

---

## Alternatives

| Option | Pros | Cons |
|---|---|---|
| **unstructured** (current) | Broad format support, semantic chunking, active development | Heavy install; pip install can be slow or conflict |
| **LangChain document loaders** | Large ecosystem, well-documented | Tight coupling to LangChain abstractions; heavier dependency |
| **llama-parse** | Excellent PDF/table handling | Requires API key (not local); paid above free tier |
| **Azure Document Intelligence** | Production-grade OCR, table extraction | Cloud-only, cost per page |
| **Fixed-size chunking (manual)** | Zero dependencies, deterministic | Poor recall for structured docs; splits mid-sentence |
