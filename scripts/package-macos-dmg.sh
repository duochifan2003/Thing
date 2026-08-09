#!/bin/sh
set -eu

: "${MACOS_SIGNING_IDENTITY:?MACOS_SIGNING_IDENTITY is required for a release}"
: "${MACOS_NOTARY_PROFILE:?MACOS_NOTARY_PROFILE is required for notarization}"

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
flutter_dir="$repo_root/flutter"
version=$(sed -n 's/^version: //p' "$flutter_dir/pubspec.yaml" | head -n 1)
app_version=${version%%+*}
app_build=${version#*+}
output=${1:-"$flutter_dir/build/Thing-macOS-v$app_version.dmg"}
stage=$(mktemp -d "${TMPDIR:-/tmp}/thing-dmg.XXXXXX")

cleanup() {
  rm -rf "$stage"
}
trap cleanup EXIT

mkdir -p "$(dirname "$output")"
cd "$flutter_dir"
flutter build macos --release --no-pub \
  --dart-define=APP_VERSION="$app_version" \
  --dart-define=APP_BUILD="$app_build"
swift "$repo_root/scripts/create-macos-dmg-background.swift" \
  "$stage/installation-guide.png"

if ! python3 -c 'import dmgbuild' >/dev/null 2>&1; then
  echo "Missing pinned dmgbuild ${DMGBUILD_VERSION:-1.6.5}. Install the release requirements first." >&2
  exit 1
fi
python3 -c 'import importlib.metadata as m, os, sys; expected=os.environ.get("DMGBUILD_VERSION", "1.6.5"); actual=m.version("dmgbuild"); sys.exit(0 if actual == expected else 1)' || {
  echo "dmgbuild version does not match ${DMGBUILD_VERSION:-1.6.5}" >&2
  exit 1
}

python3 - "$output" \
  "$flutter_dir/build/macos/Build/Products/Release/Thing.app" \
  "$stage/installation-guide.png" <<'PY'
import sys

from dmgbuild import build_dmg

output, app_path, background_path = sys.argv[1:]

build_dmg(
    output,
    "Thing Installer",
    settings={
        "files": [(app_path, "Thing.app")],
        "symlinks": {"Applications": "/Applications"},
        "background": background_path,
        "format": "UDZO",
        "filesystem": "HFS+",
        "default_view": "icon-view",
        "window_rect": ((120, 120), (900, 560)),
        "show_toolbar": False,
        "show_status_bar": False,
        "show_sidebar": False,
        "show_pathbar": False,
        "icon_size": 96,
        "text_size": 13,
        "arrange_by": None,
        "icon_locations": {
            "Thing.app": (220, 280),
            "Applications": (680, 280),
        },
    },
)
PY

app="$flutter_dir/build/macos/Build/Products/Release/Thing.app"
codesign --verify --deep --strict --verbose=2 "$app"
codesign_info=$(codesign -dvv "$app" 2>&1)
printf '%s\n' "$codesign_info" | grep -F 'Authority=Developer ID Application' >/dev/null || {
  echo 'macOS release is not signed by a Developer ID Application certificate' >&2
  exit 1
}
printf '%s\n' "$codesign_info" | grep -E 'flags=.*runtime' >/dev/null || {
  echo 'macOS release is missing the hardened runtime' >&2
  exit 1
}
spctl --assess --type execute --verbose=4 "$app"
xcrun notarytool submit "$output" --keychain-profile "$MACOS_NOTARY_PROFILE" --wait
xcrun stapler staple "$output"
xcrun stapler validate "$output"
spctl --assess --type open --context context:primary-signature "$output"
