-- Enable pgvector extension
create extension if not exists vector;

-- Main chunks table
-- One row per chunk, regardless of source format
create table chunks (
  id          bigserial primary key,
  source      text    not null,   -- original filename
  file_type   text    not null,   -- .pdf | .docx | .pptx | .xlsx | .txt | .md | image
  content     text    not null,   -- chunk text (or vision description for images)
  embedding   vector(768),        -- nomic-embed-text (Ollama). Use vector(1536) for OpenAI.
  metadata    jsonb   default '{}',
    -- pdf:   { page_number, section_title }
    -- docx:  { section_title, table_index }
    -- pptx:  { slide_number, slide_title }
    -- xlsx:  { sheet_name, row_range }
    -- image: { source_image, description_model }
  ingested_at timestamptz default now()
);

-- HNSW index — works well at any data size (better than IVFFlat for small corpora)
create index on chunks
  using hnsw (embedding vector_cosine_ops);

-- Document listing function called by ingest API
create or replace function list_documents()
returns table (
  source        text,
  file_type     text,
  chunk_count   bigint,
  last_ingested timestamptz
) language sql stable as $$
  select source, file_type, count(*) as chunk_count, max(ingested_at) as last_ingested
  from   chunks
  group  by source, file_type
  order  by max(ingested_at) desc;
$$;

-- Similarity search function called by .NET API
create or replace function match_chunks(
  query_embedding  vector(768),
  match_count      int     default 5,
  filter_file_type text    default null  -- optional: restrict to one format
) returns table (
  id          bigint,
  source      text,
  file_type   text,
  content     text,
  metadata    jsonb,
  similarity  float
) language sql stable as $$
  select id, source, file_type, content, metadata,
         1 - (embedding <=> query_embedding) as similarity
  from   chunks
  where  filter_file_type is null
    or   file_type = filter_file_type
  order  by embedding <=> query_embedding
  limit  match_count;
$$;
