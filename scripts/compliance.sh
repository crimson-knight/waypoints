#!/usr/bin/env bash
# Regenerates the supply-chain compliance artifacts under docs/compliance/ using
# shards-alpha (crimson-knight/shards fork). One committed set of these outputs
# ships in the repo so reviewers see real audit/license/SBOM/report data without
# running anything. Re-run this after changing dependencies.
#
#   scripts/compliance.sh
#
# Requires: shards-alpha on PATH and an installed lib/ (run `shards-alpha install`).
set -euo pipefail

SHARDS="${SHARDS:-shards-alpha}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/docs/compliance"
cd "$ROOT"

mkdir -p "$OUT"

echo "==> audit (OSV vulnerability scan, JSON)"
# audit interleaves progress logs (I:/W:/E: at column 0) with the JSON body on
# stdout; drop those log lines so the committed file is valid JSON. Never let a
# vulnerability finding (exit 1) abort the whole regeneration.
{ "$SHARDS" audit --format=json || true; } | grep -v '^[IWE]: ' >"$OUT/audit.json"

echo "==> licenses (SPDX inventory + policy check, markdown)"
"$SHARDS" licenses --detect --format=markdown \
  --policy=.shards-license-policy.yml >"$OUT/licenses.md" || true

echo "==> sbom (SPDX)"
"$SHARDS" sbom --format=spdx --output="$OUT/sbom.spdx.json"

echo "==> sbom (CycloneDX)"
"$SHARDS" sbom --format=cyclonedx --output="$OUT/sbom.cyclonedx.json"

echo "==> compliance-report (markdown, aggregate)"
"$SHARDS" compliance-report --format=markdown \
  --output="$OUT/compliance-report.md" || true

echo "==> done. Artifacts in docs/compliance/:"
ls -1 "$OUT"
