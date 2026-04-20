# ingest_api.py — HTTP wrapper around ingest.py
# Usage: uvicorn ingest_api:app --port 8000 --reload

import tempfile
from pathlib import Path

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware

# Re-use all ingest logic (and the already-configured supabase + ai clients)
from ingest import IMAGE_EXT, SUPPORTED, ingest_document, ingest_image, supabase

app = FastAPI(title="KB Ingest API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.post("/ingest")
async def ingest_file(file: UploadFile = File(...)):
    """Accept a single file upload, chunk, embed, and upsert into the KB."""
    # Sanitise: use only the basename (no path traversal)
    name   = Path(file.filename).name
    suffix = Path(name).suffix.lower()

    if suffix not in SUPPORTED and suffix not in IMAGE_EXT:
        raise HTTPException(
            status_code=415,
            detail=(
                f"Unsupported file type '{suffix}'. "
                f"Supported: {sorted(SUPPORTED | IMAGE_EXT)}"
            ),
        )

    tmp_dir  = tempfile.mkdtemp()
    tmp_path = Path(tmp_dir) / name
    try:
        tmp_path.write_bytes(await file.read())

        # Always replace existing chunks so re-uploading refreshes the doc.
        supabase.table("chunks").delete().eq("source", name).execute()

        if suffix in IMAGE_EXT:
            n = ingest_image(tmp_path)
        else:
            # clear_existing=False because we already deleted above
            n = ingest_document(tmp_path, clear_existing=False)

        return {"source": name, "chunks_added": n, "status": "ok"}
    finally:
        if tmp_path.exists():
            tmp_path.unlink()
        try:
            Path(tmp_dir).rmdir()
        except OSError:
            pass


@app.get("/documents")
def list_documents():
    """Return one row per indexed document with chunk count and last-ingested date."""
    result = supabase.rpc("list_documents", {}).execute()
    return result.data or []


@app.delete("/documents/{source}")
def delete_document(source: str):
    """Remove all chunks belonging to a source document."""
    supabase.table("chunks").delete().eq("source", source).execute()
    return {"deleted": source, "status": "ok"}


@app.get("/health")
def health():
    return {"status": "ok"}
