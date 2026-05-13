#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

VERSION="$(
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' manifest.json | head -n1
)"

if [[ -z "${VERSION}" ]]; then
  echo "Failed to read version from manifest.json" >&2
  exit 1
fi

OUT_FILE="zotero-mineru-${VERSION}.xpi"

FILES=(
  manifest.json
  bootstrap.js
  mineru.js
  preferences.js
  preferences.xhtml
  preferences.css
  prefs.js
  icon.svg
  icon16.svg
  locale
)

rm -f "$OUT_FILE"

# Pick a libarchive-based tar; bsdtar supports --format zip, GNU tar does not.
# CI installs libarchive-tools which provides `bsdtar`. On Windows the bundled
# C:\Windows\System32\tar.exe is libarchive-based, but Git Bash's `tar` shadows
# it with GNU tar — so we reach past $PATH to the absolute path.
if command -v bsdtar >/dev/null 2>&1; then
  TAR=bsdtar
elif [[ -x /c/Windows/System32/tar.exe ]]; then
  TAR=/c/Windows/System32/tar.exe
else
  echo "Need bsdtar (or Windows libarchive tar) for --format zip" >&2
  exit 1
fi

"$TAR" --format zip -cf "$OUT_FILE" "${FILES[@]}"

echo "Built: $ROOT_DIR/$OUT_FILE"
file "$OUT_FILE"
