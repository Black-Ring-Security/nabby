# Contributing to Nabby

Thanks for helping!

1. Open an issue first for anything bigger than a small fix, so we can agree on the approach.
2. Fork, create a branch, make your change.
3. Run `flutter analyze` and `flutter test`. Both must pass.
4. Open a pull request and describe how you tested it.

## Guidelines

- Match the style of the surrounding code; `flutter analyze` must stay clean.
- Never log, print or send passwords, keys or passphrases. Secrets only go through
  `Store` (Android Keystore).
- No analytics, ads or third-party network calls. Nabby only talks to the user's own servers.
- When adding a feature that exists in Tabby, look at `tabby-ssh` / `tabby-terminal`
  in the [Tabby source](https://github.com/Eugeny/tabby) for behavior, but write it fresh in Dart.
- New store text goes in `fastlane/metadata/android/<lang>/`.

## Translations

Store listing translations are welcome in `fastlane/metadata/android/<lang>/`.
