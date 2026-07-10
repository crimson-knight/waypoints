# waypoints

A deliberately small Crystal bookmarks CLI whose **repository** is the real
demo: three open-source tools from the AgentC toolchain working together.

- **[engram](https://github.com/crimson-knight/engram)** — branch-scoped agent
  memory. The repo's decision history lives in `.agents/memories/`, and a
  feature branch carries decision context a reviewer's agent can load and unload.
- **[llamero](https://github.com/crimson-knight/llamero)** — local AI. Bookmark
  auto-description via on-device MLX inference, plus a golden training dataset so
  a small local model can be fine-tuned into a *waypoints expert*.
- **[shards-alpha](https://github.com/crimson-knight/shards)** — AI-docs
  distribution (llamero's and engram's skills arrive via `shards-alpha install`)
  and a supply-chain compliance suite (audit / licenses / policy / SBOM /
  report) generating committed sample outputs.

The app is boring on purpose. Everything interesting here is the workflow.

---

## Quickstart

```sh
# Use the shards-alpha fork (it distributes the AI docs + runs compliance).
shards-alpha install
crystal build src/waypoints.cr -o bin/waypoints

bin/waypoints add https://crystal-lang.org --title "Crystal" --tags language,docs
bin/waypoints search "full text search"
```

The store is a single SQLite file at `~/.local/share/waypoints/waypoints.db`.
Override it with `--db PATH` or `WAYPOINTS_DB` (flag > env > default).

### Commands

```
waypoints add <url> [--title T] [--tags a,b] [--notes N]
waypoints list [--tag t] [--json]
waypoints search <query> [--json]     # FTS5 bm25 over title/tags/notes
waypoints describe <url>              # fetch + local-AI {title,tags,summary}
waypoints rm <url>
waypoints version
```

Real output:

```console
$ waypoints add https://sqlite.org/fts5.html --title "SQLite FTS5" \
    --tags database,search --notes "Full-text search extension"
Added https://sqlite.org/fts5.html

$ waypoints search full text search
SQLite FTS5
  URL: https://sqlite.org/fts5.html
  Tags: database, search
  Notes: Full-text search extension
  Created: 2026-07-10T17:32:35Z
```

Search is FTS5 `bm25()` over an external-content table kept in sync by
insert/update/delete triggers — the verified pattern engram uses for its own
memory search. Query text is reduced to bare `[a-z0-9_]` tokens first, so
punctuation can never form an FTS5 operator.

---

## Tool 1 — engram: the reviewer workflow

Decisions are committed as memory migrations under `.agents/memories/`. On
`main`, three memories explain why the code is the way it is:

- why bookmark search is SQLite FTS5 and **not** a vector DB
- why `describe` degrades to a heuristic on the llamero mock bridge
- why llamero is pinned to `v2-cli-backend` at a tested commit

The centerpiece is the branch story. `feature/semantic-notes` explores a
`notes_embedding` column and carries **two extra memories** — one on the
embedder choice, and one that *supersedes* the main-branch search decision
(FTS5-only → hybrid). Checking the branch out loads that context; switching
back rolls it away. Perfect recall on checkout, clean amnesia on switch:

```console
$ git checkout feature/semantic-notes
$ engram sync
engram: +2 applied, -0 rolled back, 0 updated (4 active)

$ engram search "embedding"
#20260710173056  notes_embedding uses an OpenAI-compatible embedder, not llamero  [search, embedding, architecture]  score=-1.5609
    **Decision:** The `notes_embedding` BLOB column is populated by calling an OpenAI-compatible `/v1/embeddings` endpoint (configurable URL + model + API key env),...
#20260710173057  Search plan: FTS5-only gives way to a hybrid FTS5 + embedding ranking  [search, embedding, architecture]  score=-1.5157
    **Decision:** On this branch the search design moves from FTS5-only to a hybrid ranking: FTS5 bm25 stays the lexical backbone, and a `notes_embedding` vector (s...

$ git checkout main
$ engram sync
engram: +0 applied, -2 rolled back, 0 updated (3 active)

$ engram search "embedding"
No memories found.
```

The agent that reviews `feature/semantic-notes` knows the embedding plan; the
agent on `main` has no idea it exists. `engram hook install` wires
post-checkout/post-merge/post-rewrite hooks so the `engram sync` step happens
automatically on checkout (the hooks call `engram`, so it must be on your PATH).

---

## Tool 2 — llamero: local descriptions and instant expertise

`waypoints describe <url>` fetches the page, extracts its `<title>`, and asks a
local llamero model (`mlx-community/Qwen3-0.6B-4bit`) for a structured
`{title, tags, summary}` via `chat_structured`, then saves the bookmark.

The model call sits behind a small seam (`Waypoints::DescriptionModel`) and the
fetch behind another (`Waypoints::PageFetcher`), so the spec suite injects fakes
and never loads MLX or touches the network. `describe` gates on
`runtime.real_bridge?`: on a machine without the built MLX dylib, llamero's
`Bridge.auto` silently returns a deterministic mock, so waypoints prints
`(llamero mock bridge — heuristic description used)` and falls back to a
heuristic instead of passing mock text off as model output.

**Instant expertise.** waypoints ships its docs as both agent skills *and* a
golden Q&A dataset (`training_data/waypoints_api_qa.jsonl`, 36 pairs). A local
model can be trained on it and packaged as a portable *training filter*:

```sh
crystal build --no-codegen examples/train_waypoints_adapter.cr   # CI-safe type check
crystal run examples/train_waypoints_adapter.cr                  # Apple Silicon + MLX bridge
```

The example loads the dataset, trains a `waypoints` LoRA adapter, and packs it
into `dist/waypoints.filter` with `TrainingFilter.pack`. A consumer with the
same base model activates it (`session.activate_filter`) and their local model
knows waypoints — offline, no in-context teaching. Use a **dense** base model:
Gemma-4 e-series adapters train but have no inference effect (a known upstream
limitation). See the [llamero docs](https://github.com/crimson-knight/llamero).

---

## Tool 3 — shards-alpha: compliance and AI-docs distribution

### Compliance suite

`scripts/compliance.sh` runs the whole supply-chain suite into `docs/compliance/`
(one real generated set is committed):

```sh
scripts/compliance.sh
# audit.json  compliance-report.md  licenses.md  sbom.cyclonedx.json  sbom.spdx.json
```

Current status: **PASS** — 5 dependencies, 0 vulnerabilities, every license
`Allowed` (MIT / Apache-2.0). Two policy files drive it, and they use **two
different schemas**: `.shards-policy.yml` (versioned `rules:` tree — allowed
hosts, `require_license`) and `.shards-license-policy.yml` (top-level `policy:`
key — an SPDX allow-list). Themed API docs come from `shards-alpha docs`, which
appends `docs-theme/style.css` (a small Crystal-purple accent) to the output.

### AI-docs distribution

`shards-alpha install` distributed each dependency's agent skills **into** this
repo, namespaced by shard, and wrote the engram MCP server config:

```console
$ shards-alpha ai-docs status
AI Documentation Status:
  llamero (1.0.0+git.commit.8100b4ca2de4abf75137eac2fa2d5a6fe70867f1):
    .claude/skills/llamero--cloud-providers/SKILL.md  [up to date]
    .claude/skills/llamero--local-inference/SKILL.md  [up to date]
    .claude/skills/llamero--adapter-training/SKILL.md  [up to date]
    .claude/skills/llamero--docs/reference/CLAUDE.md  [up to date]
    .claude/skills/llamero--docs/reference/AGENTS.md  [up to date]
  engram (0.1.0):
    .claude/skills/engram--using-engram/SKILL.md  [up to date]
    .claude/skills/engram--docs/reference/CLAUDE.md  [up to date]
  .mcp-shards.json: engram/engram  [available]

$ shards-alpha ai-docs merge-mcp
I: Merged 1 MCP server(s) into .mcp.json

$ shards-alpha ai-docs merge-mcp   # idempotent: .mcp.json already has it
I: Merged 0 MCP server(s) into .mcp.json
```

`.mcp.json` now contains the engram stdio MCP server, so an MCP-aware agent in
this repo gets engram's `search_memories` / `remember` tools directly. waypoints
dogfoods the same convention onward: it ships its own
`.claude/skills/using-waypoints/SKILL.md` and `CLAUDE.md` for its consumers.

---

## What's demo vs. production

- **Real:** the CLI, SQLite/FTS5 storage and search, the describe seam, the
  engram branch story, the compliance outputs, and the AI-docs distribution —
  all run and are specced (`crystal spec`: green; `crystal tool format`: clean).
- **Needs hardware:** actually running `describe` against a real model and
  `examples/train_waypoints_adapter.cr` requires Apple Silicon with the built
  llamero MLX bridge and the model weights. Both degrade or type-check honestly
  without it; neither fakes model output.
- **Pre-publish:** engram is a local path dependency (`engram: {path: ../engram}`
  with a `# TODO(publish)` in `shard.yml`); flip it to a GitHub dependency once
  engram publishes. The `feature/semantic-notes` embedding work is a **plan**
  captured as a migration + memories, intentionally left unmerged.

## Dependency pin

llamero is pinned to `{github: crimson-knight/llamero, branch: v2-cli-backend}`,
tested at commit `8100b4ca2de4abf75137eac2fa2d5a6fe70867f1` — the branch that
carries the `TrainingFilter` / `DocExtractor` APIs the training pipeline uses.
The rationale is recorded as an engram memory (`engram search "llamero pin"`).

## License

MIT — see [LICENSE](LICENSE).
