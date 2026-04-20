# Chat UI

## What it does (ELI5)

A single web page served by the .NET API. You type a question, the page sends it
to the server, and the answer appears word by word as the AI generates it. The page
also shows which documents the answer came from, lets you upload new documents, and
lets you see and delete what is already in the system. No installation required —
open a browser and it is ready.

---

## Technical Detail

`wwwroot/index.html` is a self-contained single-page app. No build step, no
framework, no npm. Two CDN dependencies: `marked.js` (Markdown rendering) and
`DOMPurify` (sanitisation before DOM insertion).

### Features

| Feature | Implementation |
|---|---|
| Streaming responses | `fetch` + `ReadableStream` reader; SSE tokens rendered incrementally |
| Markdown rendering | `marked.parse()` + `DOMPurify.sanitize()` before `innerHTML` assignment |
| Source citations | `[SOURCES]` SSE event parsed to chip strip below each response |
| Multi-turn history | Rolling array of last 6 turns; sent as `history[]` with each request |
| Upload modal | `<input type="file">` + drag-and-drop; `POST multipart/form-data` to `localhost:8000/ingest` |
| Documents modal | `GET localhost:8000/documents` → table; `DELETE localhost:8000/documents/{source}` per row |
| Clear conversation | Resets history array and removes all message elements from DOM |

### SSE parsing

The stream reader handles three event types:

```js
if (line.startsWith('data: [SOURCES]'))  → parse sources JSON, render chip strip
if (line === 'data: [DONE]')             → finalise rendering, re-enable input
if (line.startsWith('data: '))           → append token to current bot bubble
```

### Security

All bot response HTML is passed through `DOMPurify.sanitize()` before insertion.
This prevents XSS from malicious content in ingested documents that could otherwise
be reflected into the DOM via Markdown rendering.

### Limitations

- No authentication — anyone who can reach port 5000 can use the UI
- History is in-memory only — lost on page refresh
- Single-user — no session isolation between browser tabs
- No mobile-specific layout — functional but not optimised for small screens

---

## Alternatives

| Option | Pros | Cons |
|---|---|---|
| **Plain HTML/JS** (current) | Zero build toolchain; trivially served as static file | Hard to maintain at scale; no type safety; no component model |
| **React SPA** | Component model; type safety with TypeScript; rich ecosystem | Build step; npm dependency tree; separate deploy target |
| **Vue + Vite** | Gentler learning curve than React; fast HMR; good DX | Still requires build step and toolchain |
| **Open WebUI** | Full-featured chat UI; Ollama-native; multi-user | Separate service; not embedded in the .NET app |
| **Blazor (WebAssembly)** | .NET throughout; full type safety | WASM download size; not idiomatic for simple chat UIs |
