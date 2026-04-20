# Ollama

## What it does (ELI5)

Ollama runs AI models on your own machine. It handles two jobs: turning text into
vectors (numbers that represent meaning, used for search), and generating answers
to questions (the chat model). It exposes an HTTP server that looks identical to
the OpenAI API, so the rest of the system does not need to know whether it is
talking to a local model or the cloud.

---

## Technical Detail

Ollama runs as a local service on port 11434. Both `ingest.py` and `RagApi` use
the OpenAI SDK client pointed at `http://localhost:11434/v1` with the API key set
to any non-empty string (Ollama ignores it).

### Models in use

| Role | Model | Size | Notes |
|---|---|---|---|
| Embedding | `nomic-embed-text` | ~274 MB | 768-dim vectors; schema must match |
| Chat | `llama3.2:3b` | ~2 GB | CPU-friendly; GPU accelerated if available |

Pull models before first run:

```powershell
ollama pull nomic-embed-text
ollama pull llama3.2:3b
ollama list   # confirm both are available
```

### Provider switching

Both the Python ingestion script and the .NET API auto-detect the provider:

| `OPENAI_API_KEY` | `OPENAI_BASE_URL` / `OpenAI:BaseUrl` | Result |
|---|---|---|
| Not set or empty | `http://localhost:11434/v1` (default) | Ollama |
| Set to a real key | `https://api.openai.com/v1` (default when key is present) | OpenAI cloud |

No code changes are required to switch providers — only environment variables.

### Performance

On CPU-only hardware (no discrete GPU):
- `nomic-embed-text` embedding: ~50–200ms per chunk batch (acceptable for ingestion)
- `llama3.2:3b` chat generation: ~5–20 tokens/sec (usable; long responses take seconds)

With a GPU: embedding is effectively instant; chat throughput rises to
50–150+ tokens/sec depending on VRAM.

### OpenAI-compatible endpoint

Ollama exposes all OpenAI-SDK-compatible endpoints:
- `POST /v1/embeddings`
- `POST /v1/chat/completions` (streaming supported)
- `GET /v1/models`

This means swapping back to OpenAI cloud requires only changing the base URL and
API key — no SDK or prompt changes.

---

## Alternatives

| Option | Pros | Cons |
|---|---|---|
| **Ollama** (current) | Simple install; OpenAI-compatible; broad model library | Single-machine; no HA; model quality limited by hardware |
| **OpenAI API** | Best model quality; managed; no hardware requirement | Costs money; data leaves the machine |
| **LM Studio** | GUI model management; OpenAI-compatible | Intended for interactive use; harder to automate |
| **llama.cpp server** | Maximum control; low-level tuning | Manual setup; no model manager |
| **Azure OpenAI** | Enterprise SLA; data residency within Azure; same API | Cloud-only; approval required for GPT-4 access |
| **vLLM** | Production-grade throughput; batching | Linux/GPU focused; complex setup on Windows |
