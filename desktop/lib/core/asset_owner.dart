/// The package Flutter should look in for this app's bundled assets.
///
/// `null` in the desktop app, where `harness` IS the root package and
/// `Image.asset('assets/…')` resolves against its own manifest. An app that
/// DEPENDS on `harness` — `../mobile` — gets those same files registered under
/// `packages/harness/assets/…` instead, which only `package:` reaches.
///
/// Set once, from that app's `main()`, before the first frame. A mutable global
/// rather than a `--dart-define` on purpose: a flag that has to be passed on
/// every `flutter run` and `flutter build` is a flag someone will forget, and
/// the symptom — every icon silently missing — looks nothing like its cause.
String? harnessAssetPackage;
