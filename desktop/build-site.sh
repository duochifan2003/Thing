#!/bin/bash
set -euo pipefail

root="$SRCROOT/.."
site="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/site"

command -v npm >/dev/null || { echo "npm is required to build the embedded web app."; exit 1; }
command -v node >/dev/null || { echo "node is required to run the embedded web app."; exit 1; }

cd "$root"
npm run build
rm -rf "$site"
mkdir -p "$site"
rsync -a --delete --exclude .git --exclude desktop --exclude .next --exclude .vinext --exclude .wrangler --exclude node_modules/.cache "$root/" "$site/"
mkdir -p "$site/node/bin"
cp "$(command -v node)" "$site/node/bin/node"
