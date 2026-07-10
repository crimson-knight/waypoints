---
id: 20260710172821
title: describe degrades to a heuristic when the llamero bridge is a mock
topics: [llamero, describe, ai]
supersedes: []
author: crimsonknight
---

**Decision:** `waypoints describe` gates on `runtime.real_bridge?`. When the
llamero bridge is the real MLX bridge it uses the model's structured
`{title, tags, summary}`. When it is the mock bridge, it prints
`(llamero mock bridge — heuristic description used)` and falls back to a
deterministic heuristic (page `<title>` plus a host-derived tag). The model
call sits behind the `Waypoints::DescriptionModel` seam and the fetch behind
`Waypoints::PageFetcher`, so specs inject fakes and never load MLX or hit the
network.

**Why:** `Llamero::Native::Bridge.auto` silently falls back to a deterministic
mock on any machine without the built MLX dylib. Presenting that mock text as
model output would be dishonest and would make the demo look like it did local
inference when it did not. Gating on `real_bridge?` keeps mock output clearly
labeled and keeps the command useful (a real, if shallow, bookmark) even with
no model present. The seam is what lets `crystal spec` stay hermetic.

**Rejected:** Calling the model unconditionally and hoping the mock output
looks plausible; and requiring the MLX bridge for `describe` to run at all
(which would make the command unusable in CI and on non-Apple hardware).
