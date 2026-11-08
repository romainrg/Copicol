#!/usr/bin/env bash
# Compile Copicol en Release (binaire universel, signature ad hoc) et produit
# build/release/Copicol-<version>.dmg et sa somme SHA-256. Utilisé par la CI.
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml)
if [ -z "$version" ]; then
  echo "MARKETING_VERSION introuvable dans project.yml" >&2
  exit 1
fi

# MARK: - Compilation

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

# MARK: - Image disque

out=build/release
dmg="Copicol-$version.dmg"
staging="$out/dmg"
mkdir -p "$out"
rm -rf "$staging" "$out/$dmg" "$out/$dmg.sha256"

# Contenu de la fenêtre ouverte par le Finder : l'app et un raccourci vers Applications.
mkdir "$staging"
ditto "$app" "$staging/Copicol.app"
ln -s /Applications "$staging/Applications"

# Sur les runners GitHub, hdiutil échoue parfois avec « Resource busy » : on réessaie.
create_dmg() {
  hdiutil create -quiet -volname Copicol -srcfolder "$staging" -fs HFS+ \
    -format UDZO -imagekey zlib-level=9 -ov "$out/$dmg"
}
create_dmg || { sleep 5; create_dmg; } || { sleep 15; create_dmg; }
rm -rf "$staging"

# MARK: - Vérification de l'image

hdiutil verify -quiet "$out/$dmg"
mountpoint=$(mktemp -d)
trap 'hdiutil detach -quiet "$mountpoint" 2>/dev/null || true; rmdir "$mountpoint" 2>/dev/null || true' EXIT
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$mountpoint" "$out/$dmg"
codesign --verify --strict "$mountpoint/Copicol.app"
if [ "$(readlink "$mountpoint/Applications")" != /Applications ]; then
  echo "Raccourci vers Applications absent de l'image disque" >&2
  exit 1
fi

(cd "$out" && shasum -a 256 "$dmg" > "$dmg.sha256")

echo "$out/$dmg ($archs)"
