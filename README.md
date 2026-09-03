# Float Assist

Float Assist est une application macOS native écrite en Swift. Elle place une
fenêtre d’assistance web compacte à portée de raccourci clavier, puis la laisse
disparaître lorsque vous revenez à votre travail.

## Fonctionnalités

- Afficher ou masquer le panneau flottant depuis le clavier.
- Épingler le panneau lorsque vous souhaitez le garder visible.
- Ouvrir rapidement le contenu du presse-papiers dans le panneau.
- Passer d’un panneau compact à une fenêtre de navigation complète.
- Régler les raccourcis globaux et réinitialiser les données de site depuis les
  réglages macOS de l’application.
- Conserver les sessions web dans le stockage WebKit de votre Mac.

Float Assist affiche les services web que vous choisissez. L’authentification,
les données saisies et les règles de chaque service restent gérées par le site
ouvert dans l’application.

## Configuration requise

- macOS 26 ou version ultérieure
- Mac Apple Silicon

Pour compiler depuis les sources, Xcode 26 ou une version ultérieure est
nécessaire.

## Utilisation

Lancez Float Assist puis utilisez le raccourci configuré dans les réglages pour
afficher le panneau. Le raccourci par défaut peut être modifié à tout moment.
Vous pouvez également épingler le panneau ou l’ouvrir dans une fenêtre plus
grande selon votre façon de travailler.

## Construire depuis les sources

Depuis la racine du dépôt :

```bash
xcodebuild build \
  -project FloatAssist.xcodeproj \
  -scheme FloatAssist \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO
```

Pour les tests, la compilation de distribution et la création d’une image disque,
consultez [docs/BUILD.md](docs/BUILD.md).

## Technologies natives

Float Assist s’appuie sur les frameworks fournis par Apple : SwiftUI, AppKit,
WebKit, Foundation, Observation et Carbon. Les tests utilisent XCTest. Aucune
bibliothèque ou aucun paquet externe n’est requis par les instructions de build
de ce dépôt.

## Licence

Les conditions de distribution du projet sont celles indiquées dans
[LICENSE](LICENSE).
