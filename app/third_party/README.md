# third_party

## stockfish/

Vendored copy of the [`stockfish`](https://pub.dev/packages/stockfish) pub
package, v1.8.1 (GPLv3, Stockfish engine source under `ios/Stockfish/`).

Why vendored: the published package's `android/build.gradle` declares a legacy
`buildscript` block (AGP 3.5 + jcenter) and `lintOptions`, which fail to
configure under the Android Gradle Plugin 9 used by this app.

Local changes:
- `android/build.gradle`: removed `buildscript`/`rootProject.allprojects`,
  `lintOptions` → `lint`, unconditional `namespace`.
- Removed `example/`.

Drop this copy and go back to the pub.dev version once upstream supports AGP 9.
