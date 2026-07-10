---
id: 20260710172822
title: Pinned llamero to the v2-cli-backend branch at a tested commit
topics: [llamero, dependencies, pinning]
supersedes: []
author: crimsonknight
---

**Decision:** `shard.yml` pins llamero to
`{github: crimson-knight/llamero, branch: v2-cli-backend}`, and the README plus
this memory record the exact tested commit
`8100b4ca2de4abf75137eac2fa2d5a6fe70867f1`.

**Why:** `v2-cli-backend` is the branch that carries the `TrainingFilter` and
`DocExtractor` APIs the docs→training-material pipeline depends on
(`examples/train_waypoints_adapter.cr` packs `dist/waypoints.filter` with
`TrainingFilter.pack`). Those types are not on the default branch yet, so a
plain version constraint would resolve to a llamero that does not compile
against this repo. Recording the tested commit means a reviewer can reproduce
the exact dependency the specs and the example were validated against, even as
the branch moves.

**Rejected:** Depending on llamero's default branch or a released version
(missing the training-filter APIs), and pinning the branch without recording a
commit (branches move, so "it worked on the branch" is not reproducible).
