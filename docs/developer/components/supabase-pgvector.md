# Supabase + pgvector

## What it does (ELI5)

A database that can store documents as both text and as lists of numbers (vectors)
that represent what each piece of text "means". When you ask a question, the
database finds the stored pieces whose number-lists are most similar to the
question's number-list. This is how the system retrieves relevant context without
needing exact keyword matches.

---

## Technical Detail

The project uses Supabase running locally in Docker. Supabase provides a managed
Postgres instance with the pgvector extension pre-installed. No external Supabase
account is required for local development.

### Schema

```sql
CREATE TABLE chunks (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source      text   NOT NULL,   -- filename (basename)
    file_type   text,              -- extension: pdf, md, txt, etc.
    content     text   NOT NULL,   -- raw chunk text
    embedding   vector(768) NOT NULL,  -- 768 for Ollama; 1536 for OpenAI
    ingested_at timestamptz DEFAULT now()
);
```

### Index

HNSW (Hierarchical Navigable Small Worlds) is used instead of IVFFlat:

```sql
CREATE INDEX ON chunks USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);
```

HNSW does not require a training phase (no `VACUUM` needed before first use) and
has better recall than IVFFlat at PoC scale. The trade-off is higher memory usage
at very large scale (> 5M vectors).

### Similarity search

A stored function `match_chunks` is called via Supabase RPC from the .NET API:

```sql
CREATE OR REPLACE FUNCTION match_chunks(
    query_embedding vector(768),
    match_threshold float,
    match_count     int
) RETURNS TABLE (id bigint, source text, file_type text, content text, similarity float)
```

Returns the top-k chunks ordered by cosine similarity, filtered by a minimum
similarity threshold to suppress irrelevant results.

### Document inventory

`list_documents()` aggregates the `chunks` table by `(source, file_type)` and
returns chunk counts and the most recent `ingested_at` timestamp. Called by the
ingest API's `GET /documents` endpoint.

### Switching to OpenAI embeddings

1. Change `vector(768)` to `vector(1536)` in the schema
2. `DROP TABLE chunks;` and re-run `schema.sql`
3. Set `OPENAI_API_KEY` in `.env`
4. Change `EMBED_MODEL` to `text-embedding-3-small`
5. Re-ingest all documents

### Local Supabase commands

```powershell
supabase start    # start all services (first run pulls Docker images)
supabase stop     # stop without wiping data
supabase db reset # reset to schema.sql (drops all data)
```

Studio is available at http://localhost:54323. Default credentials: `postgres` / `postgres`.

---

## Alternatives

| Option | Pros | Cons |
|---|---|---|
| **Supabase pgvector** (current) | Reuses existing Postgres; free tier; no extra service | Memory-bound at > 5M vectors; no native hybrid search |
| **Qdrant** | Purpose-built for vectors; native hybrid search; dense+sparse indices | Separate service to run and operate |
| **Weaviate** | GraphQL API; multi-modal; hybrid search built-in | Heavier footprint; more complex config |
| **Azure AI Search** | Managed; hybrid BM25+vector; semantic re-ranking | Cloud-only; per-query billing |
| **ChromaDB** | Embedded (no server); very simple API | Not production-hardened; limited multi-tenancy |
| **SQLite-vec** | Truly serverless; zero infrastructure | Limited tooling; alpha maturity |
