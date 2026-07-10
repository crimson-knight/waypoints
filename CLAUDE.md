# waypoints — guide for AI coding agents

`waypoints` is a small Crystal CLI bookmarks manager. The app is deliberately
boring; the repository exists to demonstrate three open-source tools working
together (engram, llamero, shards-alpha). If you are here to change code, read
this first, then `docs/SPEC.md` for the full contract.

## Layout

- `src/waypoints/store.cr` — SQLite store + external-content FTS5 search (bm25).
- `src/waypoints/description.cr` — `describe` seams: `PageFetcher`,
  `DescriptionModel` (real impl `LlameroDescriptionModel`), `Describer`.
- `src/waypoints/cli.cr` — command dispatch and `DBPath` resolution.
- `spec/` — behavior specs in temp dirs; describe specs inject fakes.
- `training_data/waypoints_api_qa.jsonl` — golden Q&A dataset (docs→training).
- `examples/train_waypoints_adapter.cr` — trains + packs a waypoints filter.
- `scripts/compliance.sh` — regenerates `docs/compliance/` via shards-alpha.
- `.agents/memories/` — engram decision history (the "why" behind the code).

## Working here

```sh
shards-alpha install                         # install deps (use the fork, not stock shards)
crystal spec                                 # full suite; never loads MLX or the network
crystal tool format --check src spec examples
crystal build src/waypoints.cr -o bin/waypoints
```

Conventions (AED): every command and public method states its intent, raises a
specific typed error (`UsageError`, `BookmarkAlreadyExistsError`,
`BookmarkNotFoundError`, `FetchError`, `DescribeError`), and carries a doc
comment. Keep commits small and per-feature.

## Before changing load-bearing code, ask engram why

Decisions live as committed memories. Search them before re-opening a settled
question (e.g. why FTS5 instead of a vector DB, why the llamero mock-bridge
fallback, why the llamero branch pin):

```sh
engram sync
engram search "sqlite fts5"
engram search "mock bridge"
```

The `feature/semantic-notes` branch carries extra memories about an
embedding-column plan (and supersedes the FTS5-only search memory). Check it
out and `engram sync` to load that context; switch back to `main` and it's gone.

## The llamero seam (do not break)

Specs must never load MLX or hit the network. The `describe` command's model
call sits behind `Waypoints::DescriptionModel` and its fetch behind
`Waypoints::PageFetcher`. Gate any real-inference path on
`runtime.real_bridge?` and fall back to the heuristic on the mock bridge.
