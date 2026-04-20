

**AI Systems**

Architecture Reference

Three Core Deliverables: RAG Knowledge Base  •  Agentic Workflow  •  Conversational AI

*April 2026  —  .NET / Supabase / Python / Ollama stack*

# **1 — RAG Knowledge Base**

Query static or near-static documents (PDFs, DOCX, SharePoint, wikis, SOPs) using natural language. The model never invents — it retrieves and synthesises grounded context.

## **1.1  Core Pipeline**

| Ingest | Chunk | Embed | Store | Query | Retrieve | Synthesise |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| Docs / PDFs / HTML | Semantic / overlap | Vector model | Vector DB | Embed \+ search | Top-k \+ re-rank | LLM \+ context |

## **1.2  Key Decisions**

| Decision Point | Option A | Option B |
| :---- | :---- | :---- |
| **Chunking strategy** | Fixed-size (fast, naive) | Semantic / sentence-aware (better recall) |
| **Embedding model** | nomic-embed-text via Ollama (default, free, 768-dim) | text-embedding-3-small via OpenAI (1536-dim, requires schema change) |
| **Vector store** | Supabase pgvector (already in stack) | Qdrant / Azure AI Search (hybrid BM25) |
| **Retrieval mode** | Pure vector similarity | Hybrid (semantic \+ BM25) \+ re-rank |
| **Metadata filtering** | None — flat corpus | Per-doc tags (dept, date, access tier) |
| **LLM** | Ollama llama3.2:3b (default, local, free) | OpenAI gpt-4o-mini (cloud, fast) |

## **1.3  Implementation Stacks**

| Scenario | Stack |
| :---- | :---- |
| **This project (default)** | Supabase pgvector + Ollama (nomic-embed-text + llama3.2:3b) + .NET 10 Minimal API + Python ingest |
| **Cloud alternative** | Supabase pgvector + OpenAI API (text-embedding-3-small + gpt-4o-mini) — set `OPENAI_API_KEY` and update schema dimension |
| **Fastest to market (MS shop)** | Azure AI Search + Azure OpenAI + Semantic Kernel (.NET) |
| **Custom mid-market** | Qdrant + OpenAI + .NET 10 Minimal API + React chat UI |

## **1.4  Critical Gotchas**

* Ingestion pipeline is always underscoped — budget for doc sync, format normalisation, chunk refresh on update

* Naive chunking is the #1 cause of poor retrieval — use overlapping semantic windows

* Hybrid retrieval (semantic + BM25) meaningfully outperforms pure vector — default to it for production

* Every chunk needs metadata (source, file_type, ingested_at) before go-live; add dept and access tier before sharing

* Semantic Kernel is your home turf — it abstracts embeddings, memory, retrieval, and prompt templates for .NET

* Changing embedding model requires a full re-ingest and schema dimension change — decide early

## **1.5  What to Know**

* Vector similarity ≠ relevance — re-ranking with a cross-encoder model (e.g. ms-marco-MiniLM) is a big win

* Chunking overlap (\~15–20%) prevents context loss at boundaries

* 'Does my data train the model?' — Azure OpenAI: No. OpenAI API: No by default. Anthropic API: No. Know this cold.

* Supabase pgvector is free tier viable for PoC — enough for 100k+ chunks

# **2 — Agentic Workflow Automation**

A system that monitors a trigger, reasons about what to do, calls tools (APIs, DBs, services), and completes a multi-step business process — with or without a human approval gate.

## **2.1  Core Architecture**

| Trigger | Orchestrator | Tool Dispatch | Tools | HITL Gate | Output Action |
| :---: | :---: | :---: | :---: | :---: | :---: |
| Email / webhook / cron / form | Reason \+ plan | Function calling | DB / API / File / Email | Approve / reject | Write / send / post |

## **2.2  Patterns**

### **ReAct Loop**

Reason → Act → Observe → repeat. Agent decides which tool to call based on intermediate observations. Best for dynamic, unpredictable inputs.

### **Plan-and-Execute**

Planner generates a fixed task list upfront; executor runs it sequentially. More deterministic — better for structured processes like invoice handling.

### **Hub-and-Spoke**

Orchestrator delegates to specialised sub-agents. Best for complex workflows with distinct domain steps (e.g. triage → draft → approval → post).

## **2.3  Implementation Stacks**

| Scenario | Stack |
| :---- | :---- |
| **Non-technical client, MS shop** | Copilot Studio \+ Power Automate |
| **Low-code, more control** | n8n (self-hosted Docker) \+ AI nodes \+ webhooks |
| **Dev-built, cloud** | LangGraph or Semantic Kernel Agents \+ Azure Functions / .NET Worker |
| **Full custom, on-prem** | .NET 10 Worker Service \+ Ollama \+ custom tool registry |

## **2.4  High-Value SMB Workflow Targets**

| Workflow | Steps |
| :---- | :---- |
| **Invoice / PO** | Email arrives → extract fields → validate vs ERP → flag exceptions → post or queue approval |
| **Support Triage** | Inbound ticket → classify intent \+ sentiment → route \+ draft reply → human reviews and sends |
| **Report Generation** | Scheduled trigger → query DB → summarise with LLM → format → email distribution list |
| **HR Screening** | Resume ingested → score vs job criteria → draft shortlist summary → hiring manager reviews |

## **2.5  Critical Gotchas**

* Observability is non-negotiable — use Langfuse (OSS) or structured logging with correlation IDs. Agents fail silently.

* Error handling and retry logic must be designed in from day one. LLM calls fail. APIs time out. Never a hung process.

* Don't let LLM freestyle structured outputs — use JSON schema / constrained output for anything that writes to a DB or handles money.

* Always design the human-in-the-loop gate upfront — even if the client says they don't want one.

# **3 — Customer-Facing Conversational AI**

A chat interface (web widget, Teams, WhatsApp, SMS) where the agent calls live systems — inventory, order status, CRM, booking, pricing — and synthesises real-time responses. Not a FAQ bot.

## **3.1  Core Architecture**

| Chat Surface | Session Mgr | Intent \+ Route | Tool Agent | Live Tools | Escalation |
| :---: | :---: | :---: | :---: | :---: | :---: |
| Web / Teams / WhatsApp | Stateful, Redis / DB | LLM routing layer | Function calling | Inventory / CRM / Orders | Human handoff |

## **3.2  Key Difference vs. Pure RAG**

The agent has tools that call live systems at query time. The LLM decides which tool to call based on user intent, executes it, and synthesises the result. This is OpenAI / Anthropic function calling / tool use in practice — not document retrieval.

## **3.3  Implementation Stacks**

| Scenario | Stack |
| :---- | :---- |
| **Fastest viable product** | Voiceflow or BotPress \+ OpenAI \+ API connectors |
| **MS Teams integration** | Azure Bot Service \+ Azure OpenAI \+ custom skills (.NET) |
| **Embeddable web widget** | .NET Minimal API \+ OpenAI tool use \+ React streaming widget |
| **WhatsApp / SMS channel** | Twilio \+ .NET webhook receiver \+ same agent backend |

## **3.4  Critical Design Concerns**

| Decision Point | Option A | Option B |
| :---- | :---- | :---- |
| **Response delivery** | Polling (simple, slow UX) | SSE streaming (required for UX) |
| **Customer identity** | Anonymous (public FAQ only) | JWT from host app (personalised data) |
| **API failure handling** | Let LLM improvise fallback | Scripted fallback per tool (required) |
| **History management** | Full history (hits token ceiling) | Sliding window \+ summarisation pass |
| **Escalation trigger** | Explicit user request only | 3 failed attempts \+ intent types |
| **Topic guardrails** | None | Restrict to domain; log off-topic |

## **3.5  Critical Gotchas**

* API failure handling must be scripted — never let the LLM invent an order number or stock count

* Streaming is non-negotiable for UX — wire SSE through from the LLM to the chat surface

* Long sessions eat context fast — implement sliding window or summarisation at \~10 turns

* Adversarial testing surface is enormous — users will say anything. Budget for it.

* Always require an escalation path before go-live — define trigger, handoff channel, and ownership

# **4 — Cross-Cutting Concerns**

## **4.1  Know These Cold**

| Topic | What to Know |
| :---- | :---- |
| **Data privacy** | Azure OpenAI: No training. OpenAI API: No by default. Anthropic API: No. Know tier-specific terms. |
| **Prompt versioning** | Treat system prompts as code. Version-controlled. Timestamped flat files or DB rows. |
| **Cost modelling** | Token usage × price × volume \= monthly API bill. Build a simple estimator into every discovery call. |
| **Observability** | Langfuse (OSS), LangSmith, or structured JSONL logs with correlation IDs. Non-negotiable for production. |
| **Hallucination mitigation** | Ground responses in tool output. Never let model invent structured data. Cite sources in RAG. |
| **Change management** | 30–40% of project effort. Identify the internal champion before signing. Who owns it post-handoff? |
| **Supabase as backbone** | pgvector \+ auth \+ realtime \+ edge functions covers all three patterns. Use it — you already know it. |

## **4.2  Discovery Call Checklist**

* What is the specific pain this should eliminate or reduce?

* What's the existing stack (DB, CRM, ERP, cloud provider)?

* Where does the relevant data live today — and what format is it in?

* Who is the internal technical champion / owner post-handoff?

* What does success look like in 90 days — and how will they measure it?

* Any data residency, compliance, or security constraints?

* Estimated monthly volume (queries / docs / transactions)?

## **4.3  Productised Package Map**

| Package | Deliverable | Timeframe | Price Range |
| :---- | :---- | :---- | :---- |
| **Codebase AI Audit** | Report \+ recommendations for AI injection points | 3–5 days | $750–$1,500 |
| **RAG Knowledge Base** | Working RAG system on client docs, chat UI, admin ingest | 1–2 weeks | $3k–$6k |
| **First Agent Build** | One scoped agentic workflow, end-to-end with observability | 2 weeks | $3k–$7k |
| **Chat Widget** | Embeddable conversational AI with 3–5 live data hooks | 2–3 weeks | $4k–$8k |
| **Dev Team Onboarding** | Half-day workshop: Copilot \+ agentic patterns for dev team | 1 day | $1,500–$2,500 |
| **AI Retainer** | 5–10 hrs/mo on-call, advisory \+ implementation | Monthly | $1,200–$2,500/mo |

*— end of reference document —*