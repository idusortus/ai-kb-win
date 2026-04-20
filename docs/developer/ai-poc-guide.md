# AI Systems — PoC Implementation Guide

Three focused proof-of-concept builds. Each can be demonstrated end-to-end within
a single working session. All code targets the actual project stack.

Stack: .NET 10 · Supabase pgvector · OpenAI API or Ollama · Python · Plain HTML/JS

---

# PoC 1 — RAG Knowledge Base

A working chat interface over a corpus of company documents. Natural-language
queries return grounded, source-cited answers.

| | |
|---|---|
| **Stack** | Supabase pgvector + Ollama (default) or OpenAI + .NET 10 Minimal API + Python ingest + plain HTML/JS |
| **Duration** | 4–6 hours to first working demo |
| **Approx cost** | $0 with Ollama (local); < $1 OpenAI API credit for PoC query volume |
| **Goal** | User types a question, gets a streamed answer citing specific source documents |

## Step 1 — Supabase Schema

See `supabase/schema.sql` in the project root. Key points:

- Default vector dimension is **768** (nomic-embed-text / Ollama).
  Change to 1536 for `text-embedding-3-small` (OpenAI) — requires schema change before first ingest.
- Index type is **HNSW** (not IVFFlat) — no training step needed, better cold-start performance.
- Two stored functions: `match_chunks` (similarity search) and `list_documents` (document inventory).

Apply via Supabase Studio SQL Editor or psql:

```powershell
psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -f supabase/schema.sql
# password: postgres
```

## Step 2 — Python Ingestion (CLI)

`ingest.py` reads a folder of documents, chunks them, generates embeddings, and
upserts to Supabase. The ingestion script is Python — not Node.js.

```powershell
py -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt

# Ingest all files in ./docs
py ingest.py ./docs

# Wipe and re-ingest (drop all chunks first)
py ingest.py ./docs --clear
```

Provider is selected by the presence of `OPENAI_API_KEY` in `.env`:

- **Not set** → Ollama at `OPENAI_BASE_URL` (default `http://localhost:11434/v1`),
  model `nomic-embed-text`.
- **Set** → OpenAI cloud, model `text-embedding-3-small`. Schema dimension must
  be changed to 1536 first.

Supported formats out of the box: `txt`, `md`, `html`.
With optional deps (`unstructured[all-docs]`, `pillow`, `pytesseract`, `openpyxl`):
`pdf`, `docx`, `pptx`, `xlsx`, images.

## Step 3 — Ingest API (Upload Service)

`ingest_api.py` wraps the Python ingest logic in a FastAPI HTTP service. Required
for the browser Upload and Documents features.

```powershell
# Separate terminal, project root
uvicorn ingest_api:app --port 8000 --reload
```

Endpoints: `POST /ingest`, `GET /documents`, `DELETE /documents/{source}`, `GET /health`.

## Step 4 — .NET Query API

`RagApi/Program.cs` — a .NET 10 minimal API:

```powershell
cd RagApi
dotnet run
# Listening on http://localhost:5000
```

The `/chat` endpoint accepts a JSON body with `question` and optional `history`
array (last 6 turns), streams SSE tokens, and emits a `[SOURCES]` event before
the first text token.

Configuration is in `appsettings.Development.json`. Provider mirrors the Python
side: blank `ApiKey` + `BaseUrl` pointing to Ollama, or a real key for OpenAI.

## Step 5 — Chat UI

Served from `wwwroot/index.html` at `http://localhost:5000`. No build step.

Features: streaming markdown responses, source citation chips, multi-turn
conversation history, drag-and-drop upload modal, document management modal.

## Step 6 — Demo Checklist

| # | Action | Expected result |
|---|--------|----------------|
| 1 | `supabase start` | Studio at http://localhost:54323 |
| 2 | Apply schema | `match_chunks` and `list_documents` functions visible in Studio |
| 3 | `py ingest.py ./docs` | Rows in `chunks` table visible in Studio |
| 4 | `uvicorn ingest_api:app --port 8000` | `GET /health` → 200 |
| 5 | `cd RagApi && dotnet run` | `GET /health` → `{"status":"ok"}` |
| 6 | Ask a question whose answer is in the docs | Streamed answer + source chips |
| 7 | Ask something not in any document | Model declines to speculate |
| 8 | Upload a new file via Upload modal | Chunk count increments |
| 9 | Delete the document via Documents modal | Chunks removed from table |

---

# PoC 2 — Agentic Workflow Automation

A system that monitors a trigger, reasons about what to do, calls tools (APIs,
DBs, services), and completes a multi-step business process — with or without a
human approval gate.

| | |
|---|---|
| **Stack** | n8n (Docker) + OpenAI API — or — .NET 10 Worker Service + Semantic Kernel Agents |
| **Duration** | 2–3 hours (n8n path); 4–6 hours (.NET path) |
| **Approx cost** | $0 (n8n self-hosted free, OpenAI < $0.50 for PoC volume) |
| **Goal** | Email arrives → agent classifies + drafts reply → human reviews in Slack before sending |

## Path A — n8n (Fastest Demo)

```powershell
docker run -it --rm `
  -p 5678:5678 `
  -e N8N_BASIC_AUTH_ACTIVE=false `
  -v n8n_data:/home/node/.n8n `
  docker.n8n.io/n8nio/n8n

# Open http://localhost:5678
```

### Workflow: Email Triage Agent

| # | Node | Configuration |
|---|------|---------------|
| 1 | Webhook / Email Trigger | HTTP POST `{ subject, body, from }` — or connect Gmail OAuth |
| 2 | AI Agent (OpenAI) | System: classify intent as billing / technical / general; return JSON `{intent, priority, draft_reply}` |
| 3 | IF node | Route on intent to the appropriate Slack channel |
| 4 | Slack node | Post draft with Approve / Edit buttons |
| 5 | Wait node | Resume when Slack button clicked |
| 6 | Send reply | Gmail or SMTP send with approved draft |

Use n8n's built-in Test Webhook to fire test payloads. No real email needed for
the demo. Export the workflow JSON to version-control it.

## Path B — .NET 10 Worker Service + Semantic Kernel Agents

For clients who want a fully owned, observable codebase.

```powershell
dotnet new worker -n TriageAgent && cd TriageAgent
dotnet add package Microsoft.SemanticKernel
dotnet add package Microsoft.SemanticKernel.Agents.Core
```

Define `KernelFunction`-attributed plugin classes for Email, Slack, and CRM.
Register them with `kernel.ImportPluginFromObject(...)`. Create a
`ChatCompletionAgent` with an instruction prompt that enforces the approval gate.
Log every step to a JSONL file or Langfuse.

## Demo Checklist

| # | Action |
|---|--------|
| 1 | Fire a test POST to the webhook with sample email JSON |
| 2 | Watch the agent classify, look up CRM, draft reply in the n8n log or console |
| 3 | Observe the Slack message appear with the draft and approval buttons |
| 4 | Click Approve — watch the reply send |
| 5 | Show the JSONL / Langfuse trace |

---

# PoC 3 — Customer-Facing Conversational AI

A live chat widget where the agent answers questions grounded in both static docs
(RAG) and live API data (inventory / order status). Streams responses, handles
escalation, never invents data.

| | |
|---|---|
| **Stack** | .NET 10 Minimal API + OpenAI function calling + SSE streaming + plain HTML/JS widget |
| **Duration** | 5–7 hours |
| **Approx cost** | < $1 OpenAI API credit for PoC demo volume |
| **Goal** | Customer asks about order status or product — agent calls mock API, streams real data |

## Step 1 — Define Tools

Use `ChatTool.CreateFunctionTool(...)` to declare tools the agent can call:
`get_order_status`, `get_inventory`, `escalate_to_human`. The LLM sends a
structured JSON invocation; your dispatcher executes it and returns the result.

## Step 2 — Tool Dispatch Loop

```csharp
while (true)
{
    var completion = await client.CompleteChatAsync(messages,
        new ChatCompletionOptions { Tools = AgentTools.All });

    if (completion.Value.FinishReason == ChatFinishReason.ToolCalls)
    {
        messages.Add(new AssistantChatMessage(completion));
        foreach (var call in completion.Value.ToolCalls)
        {
            var result = await ToolDispatcher.Dispatch(
                call.FunctionName, call.FunctionArguments.ToString());
            messages.Add(new ToolChatMessage(call.Id, result));
        }
        continue;
    }

    // Stream final text response
    await foreach (var chunk in client.CompleteChatStreamingAsync(messages))
        foreach (var part in chunk.ContentUpdate)
            await response.WriteAsync($"data: {part.Text}\n\n");

    await response.WriteAsync("data: [DONE]\n\n");
    break;
}
```

Always include an explicit `default` branch in the dispatcher that returns a
structured error — never let an unknown tool call through silently.

## Step 3 — Embeddable Widget

A vanilla JS class (~100 lines) dropped into the client's site. Maintains a
sliding history window (last 10 turns), renders streaming SSE tokens, shows a
typing indicator.

## Demo Checklist

| # | Action | Expected result |
|---|--------|----------------|
| 1 | Ask: "Where is my order ORD-001?" | Agent calls `get_order_status`, streams real mock data |
| 2 | Ask: "Is SKU-ABC in stock?" | Agent calls `get_inventory`, returns count |
| 3 | Ask something out of scope | Agent calls `escalate_to_human`, shows handoff message |
| 4 | Ask: "Make up a status for ORD-999" | Returns "Order not found" from tool — no hallucination |
| 5 | Show JSONL / console log | Every tool call and result is traceable |

### Extending for Production

- Replace mock services with real ERP / Shopify / SAP API calls
- Add Supabase auth — pass JWT to scope data per customer
- Add Teams or WhatsApp via surface adapter on the same backend
- Add the PoC 1 RAG tool — agent can answer product questions AND check live data in the same turn
- Add Langfuse for conversation observability and cost tracking

---

*— end of implementation guide —*
