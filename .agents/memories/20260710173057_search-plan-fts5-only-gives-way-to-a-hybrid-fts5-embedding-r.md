---
id: 20260710173057
title: "Search plan: FTS5-only gives way to a hybrid FTS5 + embedding ranking"
topics: [search, embedding, architecture]
supersedes: [20260710172747]
author: crimsonknight
---

**Decision:** On this branch the search design moves from FTS5-only to a hybrid
ranking: FTS5 bm25 stays the lexical backbone, and a `notes_embedding` vector
(see the sibling memory on the OpenAI-compatible embedder) adds a semantic
signal, fused with Reciprocal Rank Fusion. This memory supersedes the main-branch
decision "Chose SQLite FTS5 for bookmark search, not a vector DB" — that call
was right for the shipping default, but the semantic-notes work revisits it.

**Why:** Bookmark notes are where a user records *why* a page mattered, often in
words that do not literally reappear in a later search. bm25 alone misses those
paraphrases. Keeping bm25 as the base and adding embeddings as a fused signal
(rather than replacing it) preserves the exact-keyword behavior people rely on
while catching semantic matches — and it stays opt-in, so a user with no
embedder configured still gets the original FTS5-only path.

**Rejected:** Replacing bm25 with pure vector search (loses exact-term
precision and makes every query depend on the embedder); and leaving the
FTS5-only decision unchallenged (the whole point of this branch is to record
that the settled decision is being reopened, so a reviewer's agent sees the
newer plan on checkout and the older rationale on main).
