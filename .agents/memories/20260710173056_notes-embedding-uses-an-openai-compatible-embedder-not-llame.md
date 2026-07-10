---
id: 20260710173056
title: notes_embedding uses an OpenAI-compatible embedder, not llamero
topics: [search, embedding, architecture]
supersedes: []
author: crimsonknight
---

**Decision:** The `notes_embedding` BLOB column is populated by calling an
OpenAI-compatible `/v1/embeddings` endpoint (configurable URL + model + API
key env), mirroring engram's own embedder configuration. Embeddings are stored
as packed Float32 blobs and blended into ranking via Reciprocal Rank Fusion
alongside the existing FTS5 bm25 score — exactly how engram fuses cosine
similarity with bm25. It is explicitly NOT llamero.

**Why:** Embedding a bookmark's notes is a batch, text-in/vector-out call with
no state; an OpenAI-compatible endpoint (Ollama locally, or a hosted provider)
is the portable, dependency-light way to get it, and reusing engram's proven
embedder shape means the same RRF fusion code already works. llamero is the
right tool for on-device *generation* (that is what `describe` uses), but
llamero deliberately exposes no embeddings API — the scouting notes say so
plainly — so reaching for it here would mean building an embeddings path llamero
does not have.

**Rejected:** Adding an embeddings API to llamero just to keep one dependency
(out of scope, and llamero's native track is generation-focused); and computing
embeddings on-device through the MLX bridge (needless coupling of an optional
search feature to Apple-Silicon-only inference).
