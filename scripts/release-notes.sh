#!/usr/bin/env bash
# Affiche les notes de version publiées sur GitHub : la section de CHANGELOG.md correspondant
# à la version demandée, suivie des instructions d'installation.
# Usage : scripts/release-notes.sh 0.1.0
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:?usage: scripts/release-notes.sh <version>}"

notes=$(awk -v version="$version" '
  index($0, "## [" version "]") == 1 { found = 1; next }
  found && (/^## \[/ || /^\[[^]]+\]: /) { exit }
  found { print }
' CHANGELOG.md)

if [ -z "${notes//[[:space:]]/}" ]; then
  echo "Aucune section « ## [$version] » dans CHANGELOG.md" >&2
  exit 1
fi

cat <<EOF
$notes

## Install

1. Download \`Copicol-$version.zip\` below, unzip it and move \`Copicol.app\` to your \`Applications\` folder.
2. Copicol is not notarized yet. On first launch, open **System Settings › Privacy & Security** and click **Open Anyway**, or run \`xattr -dr com.apple.quarantine /Applications/Copicol.app\`.
3. Updating from a previous version? Remove Copicol from **System Settings › Privacy & Security › Accessibility**, then allow it again.

Verify the download with \`shasum -a 256 -c Copicol-$version.zip.sha256\`.
EOF
