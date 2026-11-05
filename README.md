# simplex_blender

Flutter port of a browser-based breathing-gas blending calculator. It works out
how to fill a cylinder from supply banks to a target pressure and mix, and
reports the recipe, safety limits, thermal behavior, tank contents, and cost.

The port follows the original JavaScript app's logic. The optimizer,
thermodynamics, and validation modules are line-by-line ports, and the Dart
tests check the same expected values. The Dart files cite the JavaScript
sources by path (`js/optimizer.js`, `js/main.js`, and so on). Those sources
are not in this repository.

## Features

Primary screens (side rail at 840 px and wider, bottom bar below that):

- **Blending**: the fill form, then the results: recipe, ternary diagram,
  thermal graph, in-water pressures, tanks and costs, and technical details.
  Also includes the Compare recipe editor, interim readings, and salvage
  details.
- **What-if**: manual scenario rows with a summary, recipe, thermal, and tank
  view.
- **Inventory**: supply banks (equipment and gas banks), with price
  suggestions.
- **Settings**: general options, gas models, gas and cylinder presets,
  compressor and booster equipment, costs, and cylinder pressure-limit
  behavior (hard stop or warning). Presets can be imported from a JSON file or
  a URL.
- **About**: application name, license, and the Flutter open-source license
  page.

The first launch shows an eight-step guided tour.

Targets: Android, iOS (iPhone and iPad), Linux, macOS, and Windows.

## Requirements

- **Flutter 3.47.9**, the version in `.flutter-version`. CI and the container
  image use the same version.
- Dart SDK `^3.13.7`, which ships with that Flutter version.
- Platform toolchains for the targets you build:
  - Linux: `clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev`
  - Android: JDK 17, and an Android SDK with platform 36 and NDK
    `28.2.13676358`
  - macOS and iOS: Xcode, on macOS only
  - Windows: Visual Studio with the C++ desktop workload

Run `flutter doctor -v` and resolve anything it reports for your targets.

## Quick start

```sh
git clone git@github.com:speleobrad/simplex-blender-app.git
cd simplex-blender-app
flutter pub get
flutter run -d linux     # or macos, windows, a connected Android device, or an iOS simulator
```

Use `https://github.com/speleobrad/simplex-blender-app.git` instead if you do
not have SSH keys set up with GitHub.

### Analytics

Analytics is disabled unless a key is supplied at build time. Without a key,
the app uses a no-op implementation and makes no analytics network calls:

```sh
flutter run -d linux --dart-define=APTABASE_APP_KEY=<your-app-key>
```

## Checks before pushing

CI runs the first three checks. Run them locally before pushing:

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter test --coverage    # writes coverage/lcov.info (gitignored)
```

Run one test file with `flutter test test/domain/optimizer_test.dart`.

## Building

```sh
flutter build linux --release
flutter build apk --release            # Android APK
flutter build appbundle --release      # Android AAB
flutter build windows --release
flutter build macos --release
flutter build ios --release --no-codesign
```

Add `--dart-define=APTABASE_APP_KEY=<key>` to any build to enable analytics.

Output locations:

| Target  | Output                                                                                                  |
|---------|---------------------------------------------------------------------------------------------------------|
| Android | `build/app/outputs/flutter-apk/app-release.apk`, `build/app/outputs/bundle/release/app-release.aab`     |
| Linux   | `build/linux/x64/release/bundle/`                                                                       |
| Windows | `build/windows/x64/runner/Release/`                                                                     |
| macOS   | `build/macos/Build/Products/Release/simplex_blender.app`                                                |
| iOS     | `build/ios/iphoneos/Runner.app` (unsigned; CI packages it as an IPA)                                    |

Release builds for Android are signed with the Flutter template debug key
(`android/app/build.gradle.kts`). The APK installs, but it needs a real
release signing config before store distribution.

## Continuous integration

`.github/workflows/ci.yml` runs on push, pull request, and manual dispatch:

1. `test`: format check, `flutter analyze`, `flutter test --coverage`.
2. Build jobs, each run after `test`: `build-android` (APK and AAB),
   `build-linux`, `build-windows`, `build-macos`, and `build-ios` (unsigned
   IPA). Each job uploads its artifact for 14 days.

The analytics key comes from the GitHub secret `APTABASE_APP_KEY`. If the
secret is not set, the build has no key and analytics stays off.

## Local CI-mirror build

`tool/ci/Containerfile` builds an Ubuntu 24.04 image with the pinned Flutter,
JDK 17, the Android SDK packages, and the Linux GTK dependencies. Use it to
build Linux and Android without installing those toolchains on the host. It is
not identical to the GitHub-hosted runners.

```sh
podman build -t simplex-blender-ci -f tool/ci/Containerfile tool/ci
podman run --rm -v "$PWD:/work:Z" -w /work simplex-blender-ci \
  flutter build linux --release
podman run --rm -v "$PWD:/work:Z" -w /work simplex-blender-ci \
  flutter build apk --release
```

The image sets no `USER`, so the process inside the container runs as root.
What that means on the host depends on how Podman runs. With rootful Podman,
files the container writes into the project (`build/`, `.dart_tool/`, and
possibly `android/local.properties`) are owned by root on the host. With
rootless Podman, container root maps to your host user, so the files are
owned by you. Either way, `android/local.properties` may contain container SDK
paths. Delete those generated files, or run `flutter pub get` on the host,
before building on the host.

## Project layout

```
lib/
  main.dart                  Entry point: analytics setup, then the app shell
  src/
    domain/                  Pure Dart logic, no Flutter imports
      optimizer.dart         Blend optimizer (port of js/optimizer.js)
      optimizer/             Optimizer internals: LP, salvage, thermal, safety
      thermodynamics.dart, physics.dart, simplex.dart, ...
      preset_import.dart, preset_validation.dart, settings.dart, ...
    controllers/             ChangeNotifier state: app, blend, what-if
    data/                    shared_preferences storage, settings migrations, preset file and URL loading
    analytics/               Analytics interface, event definitions, Aptabase adapter
    ui/                      Screens and widgets, grouped by feature
test/
  domain/                    Domain logic tests
  controllers/, data/,       Controller, storage, analytics, and UI tests
  widget/, ui/, analytics/
  fixtures/                  Preset JSON used by the import tests
  support/                   In-memory storage for tests
assets/presets/              Bundled preset JSON
tool/ci/Containerfile        Local CI-mirror image
```

## Conventions

- **Porting.** Formulas, constants, tolerances, iteration limits, and branch
  order match the JavaScript source. Do not refactor the math. User-visible
  error messages are kept identical to the web app (see `domain_error.dart`).
- **Purity.** Code under `lib/src/domain/` must not import `package:flutter`.
- **Persistence.** Storage keys and the settings JSON shape follow the web
  app's localStorage layout, so exported presets import unchanged. Settings
  migrations port `js/settings.js`.
- **Analytics.** Only the events defined in
  `lib/src/analytics/analytics_events.dart` are sent. Their properties are
  closed string values and counts. Bank names, gas values, pressures, prices,
  and free text are never sent. Analytics failures are caught and never
  reach the calculator.
- **Generated files.** Do not commit `build/`, `.dart_tool/`, `coverage/`,
  `android/local.properties`, or the generated plugin registrants. The
  `.gitignore` covers them.

## License

GPL-3.0-only. See [LICENSE](LICENSE).
