---
name: using-waypoints
description: Save, search, describe, and manage bookmarks with the waypoints CLI and Crystal library — SQLite FTS5 search, local-AI auto-description, and a --db/WAYPOINTS_DB overridable store. Use when adding or finding bookmarks, or when calling the Waypoints::Store / Describer API from Crystal.
---

# Using waypoints

`waypoints` is a small Crystal bookmarks manager: a CLI over a SQLite store
with FTS5 full-text search and optional local-AI auto-description via llamero.
This skill ships onward to projects that depend on waypoints (distributed by
`shards-alpha install` into their `.claude/skills/waypoints--using-waypoints/`).

## CLI

The database defaults to `~/.local/share/waypoints/waypoints.db`. Override it
with the global `--db PATH` flag or the `WAYPOINTS_DB` environment variable
(flag wins over env wins over default).

```sh
waypoints add <url> [--title T] [--tags a,b] [--notes N]   # save a bookmark
waypoints list [--tag t] [--json]                          # newest-first, optional exact-tag filter
waypoints search <query> [--json]                          # FTS5 bm25 over title/tags/notes
waypoints describe <url>                                   # fetch + local-AI {title,tags,summary}, then save
waypoints rm <url>                                         # delete by URL
waypoints version
```

Exit codes: `0` success, `1` a runtime error (duplicate URL, URL not found,
model unavailable), `2` a usage error (unknown command, missing argument).

## Search

`search` reduces the query to bare `[a-z0-9_]` tokens (so punctuation can never
form an FTS5 operator), ANDs them, and ranks with `bm25()` ascending over an
external-content FTS5 table kept in sync by insert/update/delete triggers. A
query with no usable tokens returns nothing rather than erroring.

## describe and the mock bridge

`describe` fetches the page (10s timeout, http→https upgrade), extracts the
`<title>`, and asks a local llamero model (`mlx-community/Qwen3-0.6B-4bit`) for
a structured `{title, tags, summary}`. On a machine without the built MLX
bridge it prints `(llamero mock bridge — heuristic description used)` and falls
back to a deterministic heuristic — mock output is never sold as model output.

## Library API

```crystal
require "waypoints"

store = Waypoints::Store.new(db_path)      # creates dirs + schema as needed
store.add("https://crystal-lang.org", "Crystal", ["language"], "notes")
store.list                                  # Array(Waypoints::Bookmark), newest first
store.list("language")                      # filter by exact normalized tag
store.search("full text query")             # bm25-ranked matches
store.remove("https://crystal-lang.org")    # raises BookmarkNotFoundError if absent
store.close
```

`Waypoints::Store#add` raises `BookmarkAlreadyExistsError` on a duplicate URL.
Tags are normalized (trimmed, lowercased, de-duplicated). A `Waypoints::Bookmark`
carries `url`, `title`, `tags`, `notes`, and `created_at`, and is
JSON-serializable for `--json` output.

To auto-describe from code, inject the seams (a `PageFetcher` and a
`DescriptionModel`) into a `Waypoints::Describer` — this is how the specs run
`describe` without loading MLX or touching the network.
