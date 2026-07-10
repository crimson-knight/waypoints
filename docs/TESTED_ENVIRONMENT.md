# Tested environment

This is the exact environment every claim about this repo — the quickstart,
`describe`'s mock-bridge fallback, the `crystal spec` green run, the engram
reviewer-workflow console output on `main`, the compliance suite's PASS
status — was built and verified against. It is not a theoretical support
matrix; every line below was actually run. If you hit a failure this doesn't
explain, **diff your environment against this file first**.

> This branch (`feature/semantic-notes`) intentionally ships without its own
> README — it exists to carry the `notes_embedding` migration and the two
> extra engram memories `main`'s README's Tool 1 section walks a reviewer
> through. Where this file says "the README," that's `main`'s.

Verified twice, deliberately differently:

1. **This working clone**, with the toolchain already installed, `bin/` and
   `lib/` present, and both `engram` (built fresh from the shard dependency)
   and `shards-alpha` on PATH — the "day to day" path.
2. **A fresh, sanitized newcomer simulation** — a `mktemp` clone, an empty
   `$HOME`, and every command run under

   ```
   env -i HOME=<temp home> PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin \
     CRYSTAL_CACHE_DIR=<temp>/.crystal TERM=xterm
   ```

   — so nothing ambient (shell aliases, an already-built `bin/engram`, a
   pre-existing `~/.local/share/waypoints`) could quietly stand in for
   something the README should state explicitly. `OPENAI_API_KEY` /
   `ANTHROPIC_API_KEY` were unset and `LLAMERO_HOME` was absent throughout.

## Host

| | |
|---|---|
| OS | macOS 26.5–26.6 (builds 25F71 / 17F113 seen across sessions) |
| Architecture | arm64 (Apple Silicon) |
| Xcode | 26.5–26.6, CLT installed (`/Applications/Xcode.app/Contents/Developer`) |
| C toolchain | Xcode CLT `cc` + `ld64.lld` (via `clang`) |

**Untested**: Linux (any distro), Intel Mac (x86_64), any BSD, Windows. Apple
Silicon and macOS are givens of the machines this was built on, not a
deliberate scoping decision — every non-Apple-Silicon claim below (mostly
around llamero/MLX) is recorded, never exercised.

## Toolchain

| Tool | Version | Path | Notes |
|---|---|---|---|
| Crystal | 1.20.0 (2026-04-16) | `/opt/homebrew/bin/crystal` | LLVM 22.1.3, default target `aarch64-apple-darwin25.5.0`. `shard.yml` declares `crystal: ">= 1.11.2"`; only 1.20.0 has actually been run. |
| Shards (stock) | 0.20.0 (2025-12-19) | `/opt/homebrew/bin/shards` | **This is what `shards install` + `crystal build` + `crystal spec` run on.** Confirmed sufficient for the entire app — add/list/search/rm/describe, the full spec suite, and building `engram` itself from the vendored dependency. |
| Shards Alpha | 2025.11.25.4 [8bc0c29] (2026-04-23) | `/opt/homebrew/bin/shards-alpha` | The `crimson-knight/shards` fork. Only invoked for `scripts/compliance.sh` and `shards-alpha ai-docs ...` — never by `shard.yml`, `crystal build`, or `crystal spec`. Confirmed: `scripts/compliance.sh` under **stock** shards silently overwrites `audit.json`/`licenses.md` with `shards --help` text instead of failing — the script now asserts the real fork's `--version` output before writing anything (see the header comment in `scripts/compliance.sh`). |
| git | 2.41.0 | `/opt/homebrew/bin/git` | Used for the engram branch story (`git checkout`, the installed hooks). |

**Untested**: any Crystal version other than 1.20.0, any `shards` other than
0.20.0, any git other than 2.41.0.

## SQLite (the runtime dependency `search` depends on)

| | |
|---|---|
| Version | 3.51.0 (2025-06-12) |
| Source | macOS system `libsqlite3` (not vendored, not Homebrew) |
| FTS5 | **Confirmed present and enabled** — exercised directly with `sqlite3` and indirectly via `waypoints search` (bm25 ranking over the external-content table). |

**Untested**: any `libsqlite3` build without FTS5. This is a real, unstated
requirement — some Linux distributions ship `libsqlite3` with FTS5 compiled
out. On such a host, `Store#new`'s `CREATE VIRTUAL TABLE ... USING fts5` would
fail on first use; nothing in this repo currently probes for FTS5 up front the
way engram's `doctor` command does.

## Link-time libraries (`otool -L bin/waypoints`)

```
/usr/lib/libxml2.2.dylib          (system)
/usr/lib/libz.1.dylib              (system)
/opt/homebrew/opt/openssl@3/lib/libssl.3.dylib     (Homebrew openssl@3 3.6.2)
/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib
/usr/lib/libsqlite3.dylib          (system, 3.51.0)
/opt/homebrew/opt/pcre2/lib/libpcre2-8.0.dylib     (Homebrew pcre2 10.47_1)
/opt/homebrew/opt/bdw-gc/lib/libgc.1.dylib         (Homebrew bdw-gc 8.2.12)
/usr/lib/libiconv.2.dylib          (system)
```

`pcre2` and `bdw-gc` (Boehm GC) are pulled in by the Crystal compiler itself,
not by anything in `shard.yml`. One quirk worth recording: the Crystal used
here reports it was **built without LibXML2 support** (`shards-alpha docs`
prints "documentation sanitization disabled"), yet `crystal build` still
successfully links `-lxml2` from the system library above — the compiler's own
XML support and the linked `libxml2` used by dependencies are independent.

**Untested**: a non-Homebrew Crystal install (from-source build, Linux
package, `asdf`/`mise`) will emit a different link line with different library
paths — a property of the Crystal toolchain, not of this repo's dependencies.

## waypoints' own dependencies (`shard.lock`)

| Shard | Version | Source |
|---|---|---|
| `crinja` | 0.9.0 | `github: straight-shoota/crinja` (transitive, via llamero) |
| `db` | 0.13.1 | `github: crystal-lang/crystal-db` |
| `sqlite3` | 0.21.0 | `github: crystal-lang/crystal-sqlite3` |
| `engram` | **0.1.1** | `github: crimson-knight/engram`, `version: ~> 0.1.0` |
| `llamero` | `1.0.0+git.commit.8100b4ca2de4abf75137eac2fa2d5a6fe70867f1` | `github: crimson-knight/llamero`, `branch: v2-cli-backend` |

All fetched from GitHub by `shards install`; nothing else. `shards install`
needs network access to `github.com` the first time (or whenever `shard.lock`
changes).

`engram` is a `shard.yml` dependency but **not** a compiled-in library —
nothing in `src/` does `require "engram"`. It's declared so `shards install`
vendors its source to `lib/engram`, which is what makes `crystal build
lib/engram/src/engram.cr -o bin/engram` (the README's Tool 1 step) reproducible
without a second clone or a version-drift risk against what `shard.lock` pins.

`llamero` is used as a real library (`require "llamero"` in
`src/waypoints/description.cr`), pinned to a branch + exact commit because the
`TrainingFilter`/`DocExtractor` APIs the training pipeline needs aren't on
llamero's default branch yet. See `engram search "llamero pin"` for the full
rationale.

## engram: build, hooks, and the reviewer-workflow console output

| Concern | Verified behavior |
|---|---|
| No `brew install engram` yet | Confirmed: `brew info crimson-knight/tap/engram` finds nothing (only `crimson-knight/tap/shards-alpha` exists in that tap as of this writing). The README's Tool 1 section builds engram straight from the vendored `lib/engram` instead. |
| `crystal build lib/engram/src/engram.cr -o bin/engram` | Succeeds using the same `lib/` shards already installed for waypoints itself (`lib/engram/lib` is a symlink to the shared top-level `lib/`) — no separate `shards install` inside `lib/engram` needed. |
| `engram hook install` under engram 0.1.1 | Bakes the **absolute path** of the binary it was run with into `.git/hooks/{post-checkout,post-merge,post-rewrite}`. Confirmed: with `bin/engram` **not** on PATH, `git checkout` between `main` and `feature/semantic-notes` still correctly applies/rolls back this branch's memories — the hook does not depend on git's own minimal, noninteractive hook PATH finding a bare `engram`. |
| Effect on the README's captured console output | Because the hook now fires the sync automatically on every `git checkout`, a manual `engram sync` run immediately afterward reports `+0 applied` (already applied by the hook) rather than the `+2 applied` / `-2 rolled back` deltas an older, PATH-dependent engram would show. `main`'s README Tool 1 console block was re-captured against 0.1.1 to reflect this — it now demonstrates `git checkout` + `engram search` directly, without an intervening manual `sync`. |
| `engram search`/`.mcp.json`'s MCP server (`command: "engram"`) | Still requires `engram` resolvable on **your interactive/agent-launching shell's** PATH — the 0.1.1 PATH-independence fix is specifically about the noninteractive git-hook PATH, not every invocation. Export it or install it somewhere already on PATH. |

## Requirements vs. graceful degradation

| Concern | Required? | Verified behavior |
|---|---|---|
| `shards install` before `crystal build` | **Required** | `crystal build` fails with `Error: can't find file 'db'` (etc.) if skipped. |
| A pre-existing `bin/` for `-o bin/waypoints` (and `-o bin/engram`) | **Required** | Link fails with an opaque `ld64.lld: ... No such file or directory` unless `mkdir -p bin` runs first — now in `CLAUDE.md` on this branch, and in both `CLAUDE.md` and the README quickstart on `main`. |
| `shards-alpha` (vs. stock `shards`) | **Not required for building or running the app** | Confirmed: stock `shards install` + `crystal build` builds and runs add/list/search/rm/describe and the full spec suite. `shards-alpha` is only needed to *regenerate* `docs/compliance/` and the `.claude/skills/*` AI docs — both already committed here. |
| `engram` on PATH, unbuilt | **The centerpiece reviewer workflow is dead on arrival without it** | `engram sync`/`engram search` return `command not found` (exit 127) until built per `CLAUDE.md`/the README's Tool 1 section. Nothing about this is optional if you want to see the branch-memory story. |
| System `libsqlite3` with FTS5 | **Required** | See "SQLite" above; not independently exercised without it (would require removing/replacing the OS library, out of scope here). |
| Apple Silicon + built llamero MLX dylib + model weights (`mlx-community/Qwen3-0.6B-4bit`) | **Optional — everything degrades honestly without it** | `describe` gates on `runtime.real_bridge?`. Confirmed on this machine (no dylib in `lib/llamero/native/llamero-mlx`, only Swift sources + `build.sh`; `LLAMERO_HOME` unset): `real_bridge?` is `false`, so `describe` prints `(llamero mock bridge — heuristic description used)`, extracts the real `<title>`, falls back to the `{title, tags, summary}` heuristic, and saves the bookmark — exit 0, no crash, no attempt to build MLX. `mlx-community/Qwen3-0.6B-4bit` is the model **id configured** in `src/waypoints/description.cr`'s `DEFAULT_MODEL_ID`; actual inference against it (real, non-mock, model-generated `describe` output) was **not exercised in this environment** — that requires building `lib/llamero/native/llamero-mlx/build.sh` (Xcode/Swift/Metal) and downloading the weights, neither of which was done here. |
| `examples/train_waypoints_adapter.cr` — type-check vs. real training | **Type-check: required and CI-safe. Real run: Apple-Silicon-only, and not exercised here either** | `crystal build --no-codegen examples/train_waypoints_adapter.cr` compiles clean (exit 0) on this machine and in CI. `crystal run examples/train_waypoints_adapter.cr` (real LoRA training) needs the same built MLX dylib + weights as `describe`'s real path above; without it, the example aborts cleanly with `MLX bridge dylib not found. Build it with: cd lib/llamero/native/llamero-mlx && ./build.sh` — it never fakes a trained adapter. |
| Network access to `github.com` / the `describe` target URL | **Required for `shards install` and for `describe`** | Both confirmed to need outbound network; offline, `shards install` can't resolve dependencies and `describe` raises `FetchError`. |
| `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` | **Not required anywhere in this repo** | Left unset throughout verification; llamero's local path and engram's FTS5-only default never reference them. |

## Apple-Silicon-only scenarios, summarized

Everything in the Quickstart, Tool 1 (engram), and Tool 3 (shards-alpha) runs
on any macOS/Linux host with the toolchain above — none of it is Apple-Silicon
specific. The **only** Apple-Silicon-only surface is Tool 2's *real* model
path:

- Real (non-mock) `waypoints describe` output from `mlx-community/Qwen3-0.6B-4bit`.
- An actual `crystal run examples/train_waypoints_adapter.cr` training pass
  and the resulting `dist/waypoints.filter`.

Both require a built `lib/llamero/native/llamero-mlx` dylib (Xcode + Swift +
Metal, via `./build.sh`) and downloaded model weights, on top of everything
else in this file. Neither was exercised in this environment; both degrade
honestly (mock-bridge heuristic; clean abort with a build hint) when absent,
which is what this repo's specs and this document actually verify.

## This branch's own delta

This branch (`feature/semantic-notes`) adds a `notes_embedding` column
migration on top of everything above, plus two engram memories: the embedder
choice (an OpenAI-compatible `/v1/embeddings` endpoint, explicitly not
llamero) and one that `supersedes` `main`'s FTS5-only search decision. Neither
memory nor the column changes anything about the requirements table above —
`crystal spec` here is just as hermetic and MLX/network-free as on `main`.
