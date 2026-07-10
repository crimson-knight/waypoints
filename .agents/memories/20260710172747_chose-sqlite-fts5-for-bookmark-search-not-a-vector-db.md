---
id: 20260710172747
title: Chose SQLite FTS5 for bookmark search, not a vector DB
topics: [search, storage, architecture]
supersedes: []
author: crimsonknight
---

**Decision:** Full-text search over bookmarks is SQLite FTS5 (bm25) over an
external-content table synchronized by AFTER INSERT/UPDATE/DELETE triggers —
the same verified pattern engram uses for memory search. No vector database
and no semantic ranking on the main branch.

**Why:** A bookmarks manager is a keyword tool. Users search for words that
appear in the title, tags, or notes they typed themselves, so lexical bm25 is
exactly the right ranking and needs zero extra infrastructure — the index
lives in the same single-file SQLite database that already stores the
bookmarks. It works offline, has no model to download, and keeps the app
"boring on purpose" so the interesting part of the repo stays the toolchain.

**Rejected:** A vector DB (or model-backed semantic search) for the app
itself. The per-user setup cost (a model or an API key, a second store to keep
in sync) buys almost nothing for short human-authored bookmark text, and it
would make the default `waypoints search` path depend on a model. Semantic
search is explored as an opt-in on the `feature/semantic-notes` branch
instead, not baked into the default.
