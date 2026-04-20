# .NET Query API (RagApi)

## What it does (ELI5)

This is the brain of the retrieval system. When you type a question in the chat,
the API turns that question into a vector, searches the database for the most
relevant document chunks, assembles those chunks into context for the AI, and
streams the answer back to your browser word-by-word as the model generates it.
It also serves the chat web page itself.

---

## Technical Detail

`RagApi` is a .NET 10 minimal API (`Program.cs`). It serves three endpoints and
static files from `wwwroot/`.

### Endpoints

| Method | Path | Description |
|---|---|---|
| `POST` | `/chat` | Accept question + history; stream SSE completion |
| `GET` | `/health` | Returns `{ "status": "ok", "ts": "..." }` |
| `GET` | `/` | Serves `wwwroot/index.html` |

### Request schema

```json
{
  "question": "What is the refund policy?",
  "history": [
    { "role": "user",      "content": "..." },
    { "role": "assistant", "content": "..." }
  ]
}
```

`history` is optional. The client maintains a rolling window of the last 6 turns
and sends them on each request.

### Query pipeline

1. Embed `question` using `nomic-embed-text` (Ollama) or `text-embedding-3-small` (OpenAI)
2. Call `match_chunks(query_embedding, threshold: 0.3, count: 5)` via Supabase RPC
3. Emit `data: [SOURCES]{json}\n\n` SSE event with chunk metadata
4. Build system prompt: `"Answer using ONLY the context below:\n\n<chunks>"`
5. Prepend `history[]` turns as `UserChatMessage` / `AssistantChatMessage`
6. Stream `CompleteChatStreamingAsync` tokens as `data: <token>\n\n`
7. Emit `data: [DONE]\n\n`

### SSE stream format

```
data: [SOURCES][{"source":"manual.pdf","file_type":"pdf","similarity":0.92}, ...]

data: The refund window is

data:  30 days from

data:  purchase date.

data: [DONE]
```

The `[SOURCES]` event is emitted before the first text token so the UI can render
citation chips without waiting for the full response.

### Configuration

`appsettings.Development.json` keys (override via environment variables in production):

| Key | Default | Notes |
|---|---|---|
| `OpenAI:BaseUrl` | `http://localhost:11434/v1` | Point to OpenAI cloud if needed |
| `OpenAI:ApiKey` | `ollama` | Real key for OpenAI cloud |
| `OpenAI:EmbedModel` | `nomic-embed-text` | Must match schema vector dimension |
| `OpenAI:ChatModel` | `llama3.2:3b` | |
| `Supabase:Url` | — | Required |
| `Supabase:ServiceKey` | — | Required |

### Running

```powershell
cd RagApi
dotnet run
# Listening on http://localhost:5000
```

---

## Alternatives

| Option | Pros | Cons |
|---|---|---|
| **.NET 10 Minimal API** (current) | Team stack; single file; serves static files; strong OpenAI SDK | Requires .NET runtime; verbose for Python-native teams |
| **FastAPI (Python)** | Same runtime as ingest; minimal boilerplate; async-native | Adds Python complexity if .NET is preferred |
| **Semantic Kernel (.NET)** | Abstracts embeddings, memory, plugins, prompt templates | Higher abstraction; more opinionated; overkill for simple RAG |
| **Azure Functions** | Serverless; auto-scale; no server to manage | Cold starts; SSE streaming requires Premium plan |
| **Node.js + Express** | Large ecosystem; easy SSE | Adds third runtime; less type-safe |
