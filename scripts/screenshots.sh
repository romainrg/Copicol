#!/usr/bin/env bash
# Régénère les images de docs/images à partir des vraies vues de l'app, rendues hors écran
# avec des données de démonstration (aucune autorisation système requise).
# À relancer après toute modification visible de l'étagère ou de l'icône.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project Copicol.xcodeproj -scheme CopicolScreenshots -configuration Debug \
  -derivedDataPath build -quiet build

build/Build/Products/Debug/CopicolScreenshots.app/Contents/MacOS/CopicolScreenshots "$PWD/docs/images"
cp Copicol/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png docs/images/icon.png
