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
shards install                               # stock shards is all the build needs
mkdir -p bin                                  # bin/ is gitignored; crystal build won't create it
crystal build src/waypoints.cr -o bin/waypoints
crystal spec                                 # full suite; never loads MLX or the network
crystal tool format --check src spec examples
```

`shards-alpha` (the `crimson-knight/shards` fork) is only needed to regenerate
`docs/compliance/` (`scripts/compliance.sh`) or redistribute AI docs
(`shards-alpha ai-docs ...`) — both already committed here, so day-to-day work
on the app doesn't require it. See the README's Quickstart for the full
stock-vs-fork framing and `docs/TESTED_ENVIRONMENT.md` for exact versions.

Conventions (AED): every command and public method states its intent, raises a
specific typed error (`UsageError`, `BookmarkAlreadyExistsError`,
`BookmarkNotFoundError`, `FetchError`, `DescribeError`), and carries a doc
comment. Keep commits small and per-feature.

## Before changing load-bearing code, ask engram why

Decisions live as committed memories. `engram` isn't on PATH by default —
build it once from the vendored dependency `shards install` already fetched
(no separate clone needed), then use it as below. `engram hook install`
(engram >= 0.1.1) bakes the binary's absolute path into the git hooks, so
checkout/merge/rebase sync automatically even without `engram` on PATH; you
still need it on PATH to type these commands yourself:

```sh
crystal build lib/engram/src/engram.cr -o bin/engram
export PATH="$PWD/bin:$PATH"

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
