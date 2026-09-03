# Construire Float Assist

Ces commandes construisent Float Assist depuis la racine du dépôt. Le projet
Xcode est `FloatAssist.xcodeproj`, son schéma est `FloatAssist`, et le produit
généré porte le nom Float Assist.

## Prérequis

- macOS 26 ou version ultérieure sur Apple Silicon
- Xcode 26 ou version ultérieure

Le projet utilise uniquement les frameworks système Apple : SwiftUI, AppKit,
WebKit, Foundation, Observation et Carbon. Les tests s’appuient sur XCTest.
Aucune installation de paquet externe n’est nécessaire.

## Build de développement

```bash
xcodebuild build \
  -project FloatAssist.xcodeproj \
  -scheme FloatAssist \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath ./build/DerivedData \
  CODE_SIGNING_ALLOWED=NO
```

Le produit est créé dans :

```text
./build/DerivedData/Build/Products/Debug/Float Assist.app
```

## Tests

```bash
xcodebuild test \
  -project FloatAssist.xcodeproj \
  -scheme FloatAssist \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath ./build/DerivedData \
  CODE_SIGNING_ALLOWED=NO
```

## Build de distribution local

```bash
xcodebuild build \
  -project FloatAssist.xcodeproj \
  -scheme FloatAssist \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath ./build/DerivedData \
  CODE_SIGNING_ALLOWED=NO
```

Le produit est créé dans :

```text
./build/DerivedData/Build/Products/Release/Float Assist.app
```

Ce build est volontairement non signé, ce qui convient à la validation locale.
Avant toute distribution, signez et notarisez l’application avec les
identifiants du propriétaire du projet.

## Créer une image disque

Après le build Release :

```bash
./scripts/create-dmg.sh \
  "./build/DerivedData/Build/Products/Release/Float Assist.app" \
  ./dist
```

Le script crée `./dist/FloatAssist.dmg`. Il utilise uniquement les outils
fournis avec macOS et préserve une image disque existante tant que la création
de la nouvelle image n’a pas abouti. Le volume monté reprend l’icône de
l’application lorsque le bundle en contient une ; si `SetFile` est absent,
l’image se crée quand même avec l’icône de disque par défaut.

`dist/` est ignoré par Git : les images disque ne sont pas versionnées.

## Régénérer l’identité visuelle

L’icône de l’application, le glyphe de la barre de menus, la marque in-app et
les illustrations du README sont dessinés par un script Swift, à partir des
seuls frameworks système :

```bash
swift scripts/generate-branding.swift .
```

Le script réécrit `Resources/Assets.xcassets/AppIcon.appiconset`,
`Resources/Assets.xcassets/AppMark.imageset`,
`Resources/Assets.xcassets/MenuBarMark.imageset` et `docs/assets`. Relancez-le
après toute modification de la géométrie ou des couleurs de la marque, puis
reconstruisez l’application.

## Licence

Le projet est publié sous licence MIT (voir [LICENSE](../LICENSE)). Tout
nouveau fichier source doit reprendre l’en-tête existant :

```swift
//  Copyright (c) 2026 Alban Gerschheimer. Licensed under the MIT License.
```
