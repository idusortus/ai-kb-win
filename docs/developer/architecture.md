# Architecture Overview

## What the system does

A local-first Retrieval-Augmented Generation (RAG) pipeline. Documents are ingested
once, chunked, embedded into a vector index, and stored in a Postgres database.
When a user asks a question, the query is embedded, the most semantically similar
document chunks are retrieved, and an LLM synthesises a grounded answer — citing
the exact sources it used.

All AI runs locally by default via Ollama. OpenAI cloud is a drop-in swap with a
single environment variable.

---

## Component Map

```
Developer workstation
├── ingest.py            Python CLI — reads docs, chunks, embeds, upserts
├── ingest_api.py        FastAPI service — exposes ingest logic over HTTP (:8000)
│
├── Supabase (Docker)    Postgres + pgvector — stores chunks and embeddings
│
├── RagApi (.NET 10)     HTTP API — embed query, similarity search, stream answer (:5000)
│   └── wwwroot/
│       └── index.html   Browser chat UI — static file served by the API
│
└── Ollama               Local inference server — embed and chat models (:11434)
     nomic-embed-text    768-dim embedding model
     llama3.2:3b         Chat model
```

---

## Data Flow

### Ingestion path

```
Source file
  → ingest.py or ingest_api.py
  → Chunked by unstructured (semantic / title-aware)
  → Each chunk embedded: POST http://localhost:11434/v1/embeddings
  → Upserted to Supabase: chunks(source, file_type, content, embedding, ingested_at)
```

### Query path

```
Browser → POST /chat { question, history[] }
  → RagApi embeds the question (Ollama or OpenAI)
  → RagApi calls match_chunks() RPC → Supabase returns top-5 chunks by cosine similarity
  → RagApi builds system prompt: "Answer using ONLY this context:\n<chunks>"
  → RagApi calls chat model with full conversation history
  → SSE stream: [SOURCES]{json} → token... → token... → [DONE]
  → UI renders markdown, populates source chips
```

---

## Technology Choices and Rationale

### Supabase + pgvector

**For:** The project already uses Supabase for auth and realtime. pgvector runs
inside the same Postgres instance — no additional infrastructure, no new service to
operate, free tier covers PoC volume (100k+ chunks). HNSW indexing gives
sub-millisecond ANN search at this scale.

**Against at scale:** pgvector tops out around 1–5M vectors before HNSW memory
pressure becomes a problem. A dedicated vector DB (Qdrant, Weaviate) handles
hundreds of millions of vectors more efficiently and adds hybrid BM25 search
without extensions.

### Ollama (local inference)

**For:** Zero API cost, zero data egress, no key management, works offline. The
OpenAI-compatible endpoint means every client that works against OpenAI works
against Ollama without code changes — only the base URL and model name change.

**Against:** Model quality and speed depend on local hardware. On CPU-only machines,
llama3.2:3b is usable but slow for long contexts. nomic-embed-text embedding
throughput is a bottleneck for large ingestion jobs.

### Python ingestion (ingest.py / ingest_api.py)

**For:** `unstructured` is the de facto standard for multi-format document
parsing (PDF, DOCX, PPTX, XLSX, images). Python has the richest ecosystem for
document processing. Keeping ingestion in Python avoids replicating a complex
parsing stack in .NET.

**Against:** Requires a second runtime (Python) alongside .NET. For a pure-.NET
shop, `DocumentFormat.OpenXml` (DOCX/XLSX) and PdfPig (PDF) are viable but more
effort to configure correctly.

### .NET 10 Minimal API (RagApi)

**For:** .NET 10 is already the team stack. The official OpenAI .NET SDK has
first-class SSE streaming support. Minimal API keeps the surface area tiny —
the entire query/chat/serve logic is in one `Program.cs`. The API also serves
the static UI, eliminating a separate web server.

**Against:** For teams that are Python-native, FastAPI with the `openai` SDK
covers the same surface area with less ceremony.

### Plain HTML/JS UI (index.html)

**For:** No build toolchain, no framework version to maintain, no npm dependency
tree. Served as a static file directly from the .NET API. `marked.js` and
`DOMPurify` are loaded from CDN.

**Against:** Difficult to maintain at scale. No component model, no type safety.
A React or Vue SPA would be appropriate if the UI grows (authentication,
history persistence, admin dashboard, multi-user sessions).

### SSE (Server-Sent Events) for streaming

**For:** Native browser support via `EventSource` / `ReadableStream`, no
WebSocket handshake, works through standard HTTP proxies and load balancers,
trivial to implement on the server side.

**Against:** SSE is unidirectional (server → client). It is not appropriate
if the protocol needs client-initiated interruption or bidirectional
communication. WebSockets are the alternative for those requirements.

### Multi-turn conversation history

The client maintains a rolling window of the last 6 turns and sends them as
`history[]` with each request. The API prepends them to the message list before
calling the LLM. This keeps conversation context without server-side session
state — the API remains stateless. The downside is that long sessions generated
on the client side consume more tokens per request.

---

## What is not in the current implementation

| Capability | Status | Notes |
|---|---|---|
| Authentication / authorisation | Not implemented | `/chat` is unauthenticated. Required before sharing beyond localhost. |
| Hybrid search (BM25 + vector) | Not implemented | Pure cosine similarity only. Hybrid would improve recall for keyword-heavy queries. |
| Re-ranking | Not implemented | Top-k re-ranking with a cross-encoder would improve precision. |
| Chunk refresh on document update | Not implemented | Re-ingest with `--clear` is the current update mechanism. |
| Metadata filtering | Not implemented | Queries search across all documents. Per-user or per-department filtering requires schema additions. |
| Observability | Not implemented | No request tracing, no token usage logging, no Langfuse integration. |
| Containerisation | Not implemented | Local dev only. Docker Compose would be required for team or client deployment. |
