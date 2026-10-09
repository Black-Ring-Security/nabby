# Nabby

SSH & SFTP client for Android, built with Flutter and modelled after the
[Tabby](https://tabby.sh) desktop terminal (reference source in `../tabby-source`).

## Features

- **SSH terminal**: xterm-256color emulation, multiple tabs (drag to reorder), tab
  title from the remote shell, pinch-to-zoom, copy/paste, multi-line paste warning
- **Extra keys bar**: ESC, TAB, sticky CTRL/ALT, arrows (hold to repeat), HOME/END,
  PGUP/PGDN, ^C ^D ^Z ^L ^R, F1-F12
- **Auth**: password, private key (Ed25519 / RSA / ECDSA, OpenSSH or PEM, encrypted
  or not), keyboard-interactive (2FA/OTP), auto mode
- **Key manager**: generate Ed25519 keys, import from file or paste, copy/share public key
- **Security**: secrets in the Android Keystore (flutter_secure_storage); host key
  verification with known hosts and a loud warning when a key changes
- **Jump hosts** (ProxyJump chains) and **port forwarding**: local, remote, dynamic SOCKS5
- **SFTP browser**: navigate, upload, download/save, open with/share, built-in text
  editor, rename/move, chmod, new file/folder, recursive delete, hidden files, sorting
- **Themes**: all 192 Tabby color schemes, per-host scheme override, dark/light/system
  app theme, accent colors, font size, cursor style
- **Profiles**: groups, favorites, recent, tag colors, startup commands, keepalive,
  quick connect (`user@host:port`)
- **Import from Tabby desktop** (`~/.config/tabby/config.yaml`), JSON backup/restore
- **Background**: foreground service keeps sessions alive while the app is in the background

## Build

```bash
flutter pub get
flutter build apk --release          # build/app/outputs/flutter-apk/app-release.apk
flutter build apk --split-per-abi    # smaller per-architecture APKs
```

Release signing reads `android/key.properties` + `android/app/nabby-release.jks`
(both git-ignored). **Back them up**: Android only accepts updates signed with the
same key. Without `key.properties` the build falls back to the debug key.

## Tests

```bash
flutter test                                     # unit tests
# End-to-end against a real sshd (see test/ssh_integration_test.dart):
NABBY_TEST_DIR=... NABBY_TEST_HOSTKEY="ssh-ed25519 SHA256:..." flutter test test/ssh_integration_test.dart
```

## Regenerating assets

```bash
python3 tool/convert_schemes.py ../tabby-source/tabby-community-color-schemes/schemes assets/color_schemes.json
python3 tool/make_icons.py android/app/src/main/res
```
