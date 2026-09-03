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

## Signer et notariser pour la distribution

Les builds décrits plus haut sont signés « ad hoc » : ils fonctionnent sur la
machine qui les produit, mais Gatekeeper les refuse ailleurs. Pour distribuer
l’image disque, il faut un certificat **Developer ID Application**, qui suppose
une adhésion à l’Apple Developer Program. Un certificat *Apple Development* ne
convient pas : il ne sert qu’au développement, il ne lève pas l’avertissement
sur les autres Mac, et son nom commun contient l’adresse e-mail du compte, qui
se retrouverait alors dans la signature d’un fichier public.

Vérifier ce que contient le trousseau :

```bash
security find-identity -v -p codesigning
```

Une fois `Developer ID Application: … (TEAMID)` présent :

```bash
xcodebuild build \
  -project FloatAssist.xcodeproj \
  -scheme FloatAssist \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath ./build/DerivedData \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM=TEAMID

codesign --verify --strict --verbose=2 \
  "./build/DerivedData/Build/Products/Release/Float Assist.app"

./scripts/create-dmg.sh \
  "./build/DerivedData/Build/Products/Release/Float Assist.app" \
  ./dist

codesign --sign "Developer ID Application" --timestamp ./dist/FloatAssist.dmg
```

La notarisation demande des identifiants App Store Connect. Enregistrez-les
une fois pour toutes vous-même — ils ne doivent apparaître ni dans le dépôt ni
dans un historique de commandes partagé :

```bash
xcrun notarytool store-credentials "AC_NOTARY" \
  --apple-id VOTRE_APPLE_ID --team-id TEAMID
```

Puis, à chaque version :

```bash
xcrun notarytool submit ./dist/FloatAssist.dmg \
  --keychain-profile "AC_NOTARY" --wait
xcrun stapler staple ./dist/FloatAssist.dmg
spctl -a -t open --context context:primary-signature -v ./dist/FloatAssist.dmg
```

La dernière commande doit répondre `accepted`. Quand c’est le cas, retirez des
deux README la mention indiquant que le binaire n’est ni signé ni notarisé.

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
