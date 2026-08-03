#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
flutter_dir="$repo_root/flutter"
version=$(sed -n 's/^version: //p' "$flutter_dir/pubspec.yaml" | head -n 1)
app_version=${version%%+*}
output=${1:-"$flutter_dir/build/Thing-macOS-v$app_version.dmg"}
stage=$(mktemp -d "${TMPDIR:-/tmp}/thing-dmg.XXXXXX")

cleanup() {
  rm -rf "$stage"
}
trap cleanup EXIT

cd "$flutter_dir"
flutter build macos --release --no-pub
ditto "build/macos/Build/Products/Release/Thing.app" "$stage/Thing.app"
ln -s /Applications "$stage/Applications"
hdiutil create \
  -volname Thing \
  -srcfolder "$stage" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$output"
