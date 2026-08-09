# Helia browser smoke test

Run `../tool/verify_helia_browser.sh` from this directory for the automated
browser check. It loads the packaged Helia asset, starts a browser node,
writes and reads UnixFS bytes via IndexedDB, and stops the node.

`flutter run -d chrome` remains useful for manual inspection; the page reports
`PASS` after the same sequence.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
