#!/usr/bin/env bash
# CrateKit is a pure domain package. UIKit belongs to the app and GRDB belongs
# to CrateStore; importing either here would break Linux testability and layer
# boundaries.
set -euo pipefail

cd "$(dirname "$0")/.."
source_root="Packages/CrateKit/Sources"

if grep -RnE --include='*.swift' '^[[:space:]]*import[[:space:]]+(UIKit|GRDB)([[:space:]]|$)' "$source_root"; then
  echo "CrateKit purity gate: FAIL (UIKit/GRDB import found)" >&2
  exit 1
fi

echo "CrateKit purity gate: PASS (no UIKit/GRDB imports)"
