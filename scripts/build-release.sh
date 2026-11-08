#!/usr/bin/env bash
# Compile Copicol en Release (binaire universel, signature ad hoc) et produit
# build/release/Copicol-<version>.zip et sa somme SHA-256. Utilisé par la CI.
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml)
if [ -z "$version" ]; then
  echo "MARKETING_VERSION introuvable dans project.yml" >&2
  exit 1
fi

xcodegen generate --quiet
xcodebuild -project Copicol.xcodeproj -scheme Copicol -configuration Release \
  -derivedDataPath build -destination 'generic/platform=macOS' -quiet build

app=build/Build/Products/Release/Copicol.app
archs=$(lipo -archs "$app/Contents/MacOS/Copicol")
if [[ "$archs" != *arm64* || "$archs" != *x86_64* ]]; then
  echo "Binaire non universel : $archs" >&2
  exit 1
fi
codesign --verify --strict "$app"

out=build/release
zip="Copicol-$version.zip"
mkdir -p "$out"
rm -f "$out/$zip" "$out/$zip.sha256"
ditto -c -k --sequesterRsrc --keepParent "$app" "$out/$zip"
(cd "$out" && shasum -a 256 "$zip" > "$zip.sha256")

echo "$out/$zip ($archs)"
