#!/usr/bin/env bash
# Deploy force-app and run this project's Apex tests (every *Test.cls in the repo).
#
# RunSpecifiedTests rather than RunLocalTests: in a shared Developer Edition org,
# RunLocalTests would also run (and could be blocked by) other projects' tests.
#
# Usage: scripts/deploy.sh [target-org-alias] [extra sf flags, e.g. --dry-run]
set -euo pipefail

ORG="${1:-agentforce-dev}"
shift || true
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

TEST_FLAGS=()
for f in "$ROOT"/force-app/main/default/classes/*Test.cls; do
  TEST_FLAGS+=(--tests "$(basename "$f" .cls)")
done

sf project deploy start -d "$ROOT/force-app" -o "$ORG" \
  --test-level RunSpecifiedTests "${TEST_FLAGS[@]}" --wait 20 "$@"
