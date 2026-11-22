#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-1.0.0}"
cd "$ROOT_DIR"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION must be X.Y.Z." >&2
  exit 2
fi
mkdir -p docs/downloads
cp "dist/TokenCodexInfo-$VERSION-universal.dmg" docs/downloads/TokenCodexInfo-universal.dmg
cp "dist/TokenCodexInfo-$VERSION-universal.zip" docs/downloads/TokenCodexInfo-universal.zip
(
  cd docs/downloads
  shasum -a 256 TokenCodexInfo-universal.dmg TokenCodexInfo-universal.zip > SHA256SUMS.txt
)
printf '{"version":"%s"}\n' "$VERSION" > docs/downloads/release.json
# Export only intended public files. Never archive the whole working folder:
# ignored credentials, logs, or editor files could otherwise be included.
PAGE_EXPORT="$ROOT_DIR/.build/download-page/docs"
rm -rf "$PAGE_EXPORT"
mkdir -p "$PAGE_EXPORT/assets" "$PAGE_EXPORT/downloads"
for name in index.html styles.css page.js .nojekyll; do
  cp "docs/$name" "$PAGE_EXPORT/$name"
done
for name in app-icon.png app-preview.png install-guide.png; do
  cp "docs/assets/$name" "$PAGE_EXPORT/assets/$name"
done
for name in TokenCodexInfo-universal.dmg TokenCodexInfo-universal.zip SHA256SUMS.txt release.json; do
  cp "docs/downloads/$name" "$PAGE_EXPORT/downloads/$name"
done
ditto -c -k --keepParent "$PAGE_EXPORT" dist/TokenCodexInfo-download-page.zip
echo "Download page with bundled installers: $ROOT_DIR/docs/index.html"
