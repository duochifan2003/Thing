#!/bin/sh
set -eu

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
  echo "Missing dmgbuild. Install it with: python3 -m pip install --user dmgbuild" >&2
  exit 1
fi

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
