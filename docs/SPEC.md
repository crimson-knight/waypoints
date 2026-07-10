# waypoints — demo app: the AgentC open-source toolchain used in conjunction

**Status:** v0.1.0 build contract (2026-07-10). Builder: Codex (gpt-5.6-sol). Reviewer: Claude workflow.
Repo: `/Users/crimsonknight/open_source_coding_projects/waypoints`

## Purpose

A deliberately small, readable Crystal CLI — a bookmarks manager — whose *repository* demonstrates three open-source tools working together:

1. **engram** (`../engram`, also on PATH after `crystal build`) — branch-scoped agent memory: the repo's decision history lives in `.agents/memories/` and a feature branch carries decision context a reviewer's agent can load and unload.
2. **llamero** (github: crimson-knight/llamero) — local AI: bookmark auto-description via on-device MLX inference, plus a golden training dataset so a local model can be fine-tuned into a waypoints expert (the docs→training-material pipeline).
3. **shards-alpha** (crimson-knight/shards fork; binary `/opt/homebrew/bin/shards-alpha`) — AI docs distribution (llamero's and engram's skills arrive via `shards-alpha install`), plus the compliance suite (audit/licenses/policy/sbom/compliance-report) configured and generating committed sample outputs.

Keep the app itself boring on purpose. Every interesting thing in this repo is about the workflow.

## The app

`waypoints` CLI, SQLite storage (default `~/.local/share/waypoints/waypoints.db`, overridable with `--db PATH` and `WAYPOINTS_DB`):

- `waypoints add <url> [--title T] [--tags a,b] [--notes N]`
- `waypoints list [--tag t] [--json]`
- `waypoints search <query> [--json]` — FTS5 bm25 over title/tags/notes (same verified external-content-table + triggers + `bm25() ASC` pattern engram uses; see engram's `src/engram/store.cr` for the working reference).
- `waypoints describe <url>` — fetches the page (stdlib HTTP::Client, 10s timeout, https upgrade), extracts `<title>`, then asks llamero for `{title, tags, summary}` via `chat_structured`, and saves the bookmark.
- `waypoints rm <url>`
- `waypoints version`

### llamero rules (from verified scouting — do not deviate)

- Dependency pin: `llamero: {github: crimson-knight/llamero, branch: v2-cli-backend}` — v2-cli-backend is required for `TrainingFilter`/`DocExtractor`. Record the tested commit (8100b4ca2de4abf75137eac2fa2d5a6fe70867f1) in README + a memory.
- Runtime: `Llamero::Native::MLXRuntime.new(model_id: "mlx-community/Qwen3-0.6B-4bit")` → `runtime.start_session` → `session.load_model` → `session.chat_structured(messages, response_schema: BookmarkDescription)`. Response text is `.content`; structured result `.parsed`.
- **Gate on `runtime.real_bridge?`**: `Bridge.auto` silently falls back to a deterministic mock on machines without the built MLX dylib. When mock: print `(llamero mock bridge — heuristic description used)` and fall back to the `<title>`-tag heuristic. Never present mock output as model output.
- `load_model` auto-downloads from HuggingFace on first use; surface `ModelUnavailableError` with its message (it already explains HF_TOKEN for gated models).
- Do NOT call any embeddings API on llamero — none exists.

### Docs → training material (the pipeline the forum post is about)

- `training_data/waypoints_api_qa.jsonl` — 30+ `{"prompt": "...", "completion": "..."}` pairs covering every command, flag, error, and the library API (mirror llamero's own `llamero_api_qa.jsonl` format; loadable via `TrainingDataset.from_pairs_jsonl`).
- `examples/train_waypoints_adapter.cr` — compilable example: load Qwen3-0.6B-4bit, `session.train_adapter("waypoints", dataset, AdapterTrainingConfig.new(iterations: 200))`, then `TrainingFilter.pack(adapter_dir: ..., dest: "dist/waypoints.filter", name: "waypoints", version: "0.1.0", base_model: ..., lora: ..., provenance: ...)`. Must COMPILE (`crystal build --no-codegen examples/...`); actually running it requires Apple Silicon + the model, say so in a header comment. Note in comments: dense base models only (Gemma-4 e-series adapters train but have no inference effect — known upstream limitation).
- README section "Instant expertise": ship the filter with the library; a consumer loads it (`session.activate_filter`) and their local model knows waypoints. One paragraph, link to llamero docs.

### shards-alpha showcase (files this repo must contain)

- `shard.yml` with the llamero dep above and `engram: {path: ../engram}` (flip to github after publish — leave a `# TODO(publish)` comment).
- `.shards-policy.yml` (dependency policy: allowed_hosts [github.com], require_license: true) and `.shards-license-policy.yml` (allowed: [MIT, Apache-2.0, BSD-3-Clause]) — note these are TWO different schemas; copy shapes from shards-alpha's docs/compliance-guide.md.
- `scripts/compliance.sh` — runs `shards-alpha audit --format=json`, `licenses --check`, `sbom --format=spdx`, `sbom --format=cyclonedx`, `compliance-report --format=markdown`, writing into `docs/compliance/`; commit one set of real generated outputs.
- `docs-theme/style.css` — a small Crystal-purple accent override proving `shards docs` theming; README shows the command.
- `.claude/skills/using-waypoints/SKILL.md` + `CLAUDE.md` — the AI docs THIS repo ships onward to its own consumers (dogfooding the convention).
- README section walking through what `shards-alpha install` distributed INTO this repo (`.claude/skills/llamero--*`, `.claude/skills/engram--*`, `.mcp-shards.json` with the engram server, `shards-alpha ai-docs` status output) — with real captured output, not hypotheticals. Run `shards-alpha ai-docs merge-mcp` so `.mcp.json` contains the engram server.

### engram story (the branch narrative — the demo's centerpiece)

On `main`, `.agents/memories/` contains (real, run through `engram sync`):
- `..._chose_sqlite_fts5_for_search.md` (why not a vector DB for a bookmarks app)
- `..._llamero_mock_bridge_fallback.md` (why describe degrades to heuristic, `real_bridge?` gating)
- `..._pinned_llamero_v2_cli_backend.md` (why the branch pin + tested commit)

Branch `feature/semantic-notes` (create it, leave it unmerged — it exists for reviewers to visit):
- adds a `notes_embedding` column migration to the app (small real diff, compiles, specs pass)
- carries TWO extra memories: one explaining the embedding-column decision (an OpenAI-compatible endpoint, mirroring engram's embedder config — and explicitly NOT llamero, with the why), and one that `supersedes` the main-branch search memory (FTS5-only → hybrid).
- README (on main) "The reviewer workflow" section: `git checkout feature/semantic-notes && engram sync && engram search "embedding"` → the agent knows the plan; `git checkout main && engram sync` (hooks make this automatic after `engram hook install`) → `engram search "embedding"` comes back empty. Perfect recall on checkout, clean amnesia on switch. Show real captured output.

## Quality bar

- `crystal spec` green: CLI behavior specs in temp dirs (add/list/search/rm, FTS ranking, describe with an injected fake llamero session — design the llamero call behind a small seam so specs never load MLX or the network), db-path resolution, JSON output shapes.
- `crystal tool format` clean; AED conventions (statements of intent, specific errors, doc comments on public methods).
- README is the artifact that gets linked on the Crystal forum: quickstart, the three-tools-in-conjunction tour, the reviewer workflow with real output, honest "what's demo vs what's production" caveats.
- git history: small, legible commits per feature (scaffold, storage, search, describe, training data, compliance, memories, branch story).
