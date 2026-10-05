#!/usr/bin/env bash
# Tagged, signed iPhone archive -> App Store Connect upload -> processed build evidence.
set -Eeuo pipefail
cd "$(dirname "$0")/.."

if [[ "${GITHUB_REF_TYPE:-}" != tag || ! "${GITHUB_REF_NAME:-}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo 'Release requires a vMAJOR.MINOR.PATCH tag' >&2
  exit 1
fi
for variable in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8 ASC_TEAM_ID GITHUB_RUN_NUMBER GITHUB_RUN_ATTEMPT RUNNER_TEMP; do
  if [[ -z "${!variable:-}" ]]; then
    echo "Missing release input: $variable" >&2
    exit 1
  fi
done

# Never release an unmerged feature head. Checkout is exact-tag, with full history.
git fetch --no-tags origin main
if ! git merge-base --is-ancestor HEAD origin/main; then
  echo 'Release tag does not point to a commit on main' >&2
  exit 1
fi
[[ "$(git rev-parse HEAD)" == "$(git rev-list -n 1 "$GITHUB_REF_NAME")" ]] || {
  echo 'Checkout does not match release tag' >&2; exit 1;
}
version="${GITHUB_REF_NAME#v}"
[[ "$GITHUB_RUN_NUMBER" =~ ^[0-9]+$ && "$GITHUB_RUN_ATTEMPT" =~ ^[0-9]+$ ]] || {
  echo 'Release run and attempt must be numeric' >&2; exit 1;
}
# A rerun is a fresh upload: ASC forbids reusing a version/build pair.
build_number="$GITHUB_RUN_NUMBER.$GITHUB_RUN_ATTEMPT"
artifact_dir="${RUNNER_TEMP}/gamecrate-release-evidence"
mkdir -p "$artifact_dir"
key_dir="$(mktemp -d "$RUNNER_TEMP/gamecrate-signing.XXXXXX")"
chmod 700 "$key_dir"
key_path="$key_dir/AuthKey.p8"
cleanup() { rm -rf "$key_dir"; }
trap cleanup EXIT
umask 077
printf '%s' "$ASC_KEY_P8" > "$key_path"
unset ASC_KEY_P8
chmod 600 "$key_path"

# The installed application directory name is not proof of its actual Xcode pin.
export DEVELOPER_DIR
DEVELOPER_DIR="$(python3 Scripts/select_xcode.py --toolchain toolchain.json)"
xcodebuild -version > "$artifact_dir/xcode-version.txt"
xcrun --sdk iphoneos --show-sdk-version > "$artifact_dir/iphoneos-sdk.txt"
python3 - "$artifact_dir/release-context.json" "$version" "$build_number" <<'PY'
import json, os, subprocess, sys
with open(sys.argv[1], 'w', encoding='utf-8') as output:
    json.dump({'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
               'tag': os.environ['GITHUB_REF_NAME'], 'version': sys.argv[2],
               'build_number': sys.argv[3],
               'actions_run': os.environ.get('GITHUB_RUN_ID')}, output, indent=2)
PY
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
archive="$RUNNER_TEMP/GameCrate.xcarchive"
export_dir="$RUNNER_TEMP/gamecrate-export"

xcodebuild archive \
  -project GameCrate.xcodeproj -scheme GameCrate -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$archive" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$key_path" -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  DEVELOPMENT_TEAM="$ASC_TEAM_ID" CODE_SIGN_STYLE=Automatic \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
  "MARKETING_VERSION=$version" "CURRENT_PROJECT_VERSION=$build_number" \
  > "$RUNNER_TEMP/gamecrate-archive.log" 2>&1 || {
    python3 Scripts/safe_release_error.py "$RUNNER_TEMP/gamecrate-archive.log" \
      --output "$artifact_dir/archive-error-categories.txt"
    echo 'Archive failed; raw signing log remains on ephemeral runner' >&2; exit 1;
  }

app="$archive/Products/Applications/GameCrate.app"
[[ -f "$app/Info.plist" ]] || { echo 'Archive has no app Info.plist' >&2; exit 1; }
plutil -convert json -o "$artifact_dir/archive-info.json" "$app/Info.plist"
python3 - "$artifact_dir/archive-info.json" "$version" "$build_number" <<'PY'
import json, sys
info = json.load(open(sys.argv[1], encoding='utf-8'))
assert info.get('CFBundleIdentifier') == 'com.infinityball.gamecrate', 'Wrong bundle identifier'
assert info.get('UIDeviceFamily') == [1], 'Archive is not iPhone-only'
assert info.get('CFBundleShortVersionString') == sys.argv[2], 'Wrong marketing version'
assert info.get('CFBundleVersion') == sys.argv[3], 'Wrong build number'
print('Archived app: expected bundle ID, version, build number, UIDeviceFamily == [1]')
PY
codesign --verify --deep --strict "$app"
# ExportOptions is temporary, not uploaded as evidence; Xcode 26 uploads directly.
plutil -create xml1 "$key_dir/ExportOptions.plist"
plutil -insert method -string app-store-connect "$key_dir/ExportOptions.plist"
plutil -insert destination -string upload "$key_dir/ExportOptions.plist"
plutil -insert uploadMethod -string app-store-connect "$key_dir/ExportOptions.plist"
plutil -insert signingStyle -string automatic "$key_dir/ExportOptions.plist"
plutil -insert teamID -string "$ASC_TEAM_ID" "$key_dir/ExportOptions.plist"
plutil -insert manageAppVersionAndBuildNumber -bool NO "$key_dir/ExportOptions.plist"
xcodebuild -exportArchive -archivePath "$archive" -exportPath "$export_dir" \
  -exportOptionsPlist "$key_dir/ExportOptions.plist" \
  -allowProvisioningUpdates -authenticationKeyPath "$key_path" \
  -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  > "$RUNNER_TEMP/gamecrate-export.log" 2>&1 || {
    python3 Scripts/safe_release_error.py "$RUNNER_TEMP/gamecrate-export.log" \
      --output "$artifact_dir/export-error-categories.txt"
    echo 'Upload/export failed; raw signing log remains on ephemeral runner' >&2; exit 1;
  }
python3 Scripts/asc_build_evidence.py \
  --key-path "$key_path" --key-id "$ASC_KEY_ID" --issuer-id "$ASC_ISSUER_ID" \
  --bundle-id com.infinityball.gamecrate --build-number "$build_number" \
  --started-at "$started_at" --evidence "$artifact_dir/processed-build.json"
