#!/usr/bin/env bash
# UI-target network/telemetry hygiene gate (issue #6).
#
# The broader zero-network gate scans every first-party source for raw
# network APIs. This gate adds the issue #6 requirement: assert that no
# network OR telemetry/tracking symbols are reachable from the UI target
# (the app-target sources in App/, which are exactly the app target's
# compile inputs per GameCrate.xcodeproj).
#
# Reachability here is a static approximation with two parts:
#   1. Pattern scan: no network/telemetry/tracking symbols in App/ sources.
#      Allowlist is intentionally EMPTY — any match fails the build.
#   2. Import scan: every `import` line in App/ must come from the small
#      vetted module allowlist (SwiftUI/Observation/Foundation plus the two
#      local packages). The local packages are themselves covered by the
#      zero-network and CrateKit purity gates, so the transitive closure
#      stays clean.
set -euo pipefail

cd "$(dirname "$0")/.."

ROOT="App"
ALLOWLIST=()   # empty by design; extend only with explicit user sign-off

# Fail closed: a missing/unreadable scan root must never yield a false PASS.
if [ ! -d "$ROOT" ] || [ ! -r "$ROOT" ]; then
  echo "UI HYGIENE GATE FAILED — scan root '$ROOT' missing or unreadable"
  exit 1
fi

NETWORK_PATTERNS=(
  '\bURLSession\b'
  '\bNSURLSession\b'
  '\bNWConnection\b'
  '\bNWListener\b'
  '\bNWConnectionGroup\b'
  '\bNWBrowser\b'
  '\bNetService\b'
  '\bCFNetwork\b'
  '\bimport[[:space:]]+Network\b'
  '\bCFStream\b'
  '\bCFSocket\b'
  '\bgetaddrinfo\b'
  '\bsocket[[:space:]]*\('
  '\bconnect[[:space:]]*\('
  '\blisten[[:space:]]*\('
  '\bbind[[:space:]]*\('
  '\baccept[[:space:]]*\('
  '\bcurl_easy\b'
  '\bWebSocket\b'
  '\bCocoaHTTPServer\b'
)

TELEMETRY_PATTERNS=(
  '\bFirebase\b'
  '\bFirebaseAnalytics\b'
  '\bTelemetry\b'
  '\btelemetry\b'
  '\bMixpanel\b'
  '\bAmplitude\b'
  '\bSegmentio\b'
  '\bSEGAnalytics\b'
  '\bPostHog\b'
  '\bmatomo\b'
  '\bATTrackingManager\b'
  '\bNSUserTrackingUsageDescription\b'
  '\bAdvertisingIdentifier\b'
  '\bASIdentifierManager\b'
  '\biAd\b'
  '\bAdSupport\b'
  '\bimport[[:space:]]+AdServices\b'
  '\bimport[[:space:]]+iAd\b'
  '\bGoogleAnalytics\b'
  '\bappsflyer\b'
  '\bAppsflyerSDK\b'
)

matches=""
for pat in "${NETWORK_PATTERNS[@]}" "${TELEMETRY_PATTERNS[@]}"; do
  set +e
  hits=$(grep -RnE --include='*.swift' --include='*.h' --include='*.m' --include='*.c' \
    "$pat" "$ROOT")
  rc=$?
  set -e
  # grep rc: 0 = match, 1 = no match, >=2 = real scan error (fail closed).
  if [ "$rc" -ge 2 ]; then
    echo "UI HYGIENE GATE FAILED — grep could not fully scan '$ROOT' for pattern: $pat (exit $rc)"
    exit 1
  fi
  [ -n "$hits" ] && matches+="$hits"$'\n'
done

if [ -n "$matches" ]; then
  filtered=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    skip=0
    for a in ${ALLOWLIST[@]+"${ALLOWLIST[@]}"}; do
      [[ "$line" == *"$a"* ]] && { skip=1; break; }
    done
    [ "$skip" -eq 0 ] && filtered+="$line"$'\n'
  done <<< "$matches"
  if [ -n "$filtered" ]; then
    echo "UI HYGIENE GATE FAILED — network/telemetry symbol reachable from UI target (allowlist is empty):"
    printf '%s' "$filtered"
    exit 1
  fi
fi

# Import allowlist: modules the UI target may link, beyond the SDK-safe set.
# Foundation is scanned above for socket-style APIs; the two local packages
# are gated by the zero-network and CrateKit purity gates.
# UniformTypeIdentifiers (issue #7) only declares document UTTypes for the
# Files-app pickers — it exposes no transport APIs, and any raw socket use
# would still be caught by the pattern scan above.
IMPORT_ALLOWED=(SwiftUI Observation Foundation CrateKit CrateStore XCTest UniformTypeIdentifiers)

bad_imports=""
# Match `import` at line start including attribute prefixes (@preconcurrency,
# @_exported) and access-level modifiers (public/internal/private/fileprivate/
# package import), so no valid import form slips past the allowlist.
# Explicit rc handling fails closed on scan errors (rc >= 2); only rc 0/1
# (match / no-match) continue.
IMPORT_REGEX='^[[:space:]]*(@[A-Za-z_][A-Za-z0-9_]*[[:space:]]+)*(public[[:space:]]+|internal[[:space:]]+|private[[:space:]]+|fileprivate[[:space:]]+|package[[:space:]]+)?import[[:space:]]+[A-Za-z_]'
set +e
import_hits=$(grep -RnE --include='*.swift' "$IMPORT_REGEX" "$ROOT")
rc=$?
set -e
if [ "$rc" -ge 2 ]; then
  echo "UI HYGIENE GATE FAILED — grep could not fully scan '$ROOT' for imports (exit $rc)"
  exit 1
fi
strip_prefix() { sed -E 's/^[^:]*:[0-9]+://'; }
if [ -n "$import_hits" ]; then
while IFS= read -r line; do
  [ -z "$line" ] && continue
  stmt=$(printf '%s' "$line" | strip_prefix)
  mod=$(printf '%s' "$stmt" | sed -E 's/^[[:space:]]*(@[A-Za-z_][A-Za-z0-9_]*[[:space:]]+)*(public[[:space:]]+|internal[[:space:]]+|private[[:space:]]+|fileprivate[[:space:]]+|package[[:space:]]+)?import[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*$/\3/')
  ok=0
  for a in "${IMPORT_ALLOWED[@]}"; do
    [ "$mod" = "$a" ] && { ok=1; break; }
  done
  [ "$ok" -eq 0 ] && bad_imports+="$line"$'\n'
done <<< "$import_hits"
fi

if [ -n "$bad_imports" ]; then
  echo "UI HYGIENE GATE FAILED — UI target imports a module outside the vetted allowlist:"
  printf '%s' "$bad_imports"
  echo "Allowed: ${IMPORT_ALLOWED[*]}"
  exit 1
fi

echo "UI network/telemetry hygiene gate: PASS (empty allowlist; imports limited to ${IMPORT_ALLOWED[*]})"
