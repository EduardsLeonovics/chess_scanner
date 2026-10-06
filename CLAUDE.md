# CLAUDE.md

Guidance for Claude Code when working in this repo. See README.md for the
product overview, stack and roadmap.

## Open launch blockers — remind the user at the start of every session

Raise these with the user until each is done, then delete its line:

- **GPL non-compliance:** the GitHub repo
  (https://github.com/EduardsLeonovics/chess_scanner) is private and returns
  404. The app is GPL-3.0 (Stockfish, chessground, dartchess), so the exact
  source of every released version must be available to everyone who gets
  the app. Make the repo public (or publish tagged source per release)
  before distributing any build outside the team.
- **Support email:** none exists. Create one and set
  `AppInfo.supportEmail` (`app/lib/src/app_info.dart`); Play also needs it.
- **Release signing key:** release builds are signed with the debug (test)
  key because `app/android/key.properties` doesn't exist. Create an upload
  key, enrol in Play App Signing, and put its SHA-256 fingerprint in
  `share_site/.well-known/assetlinks.json`.

## Project

ChessGeek: a Flutter app (Android first; iOS builds need macOS) that reads a
chess position from a camera photo or screenshot, analyzes it with on-device
Stockfish, and trains the user on puzzles found in their own Lichess /
Chess.com games.

- `app/` — Flutter app. Dart code under `app/lib/src/`, tests in `app/test/`
  (fixture images in `app/test/fixtures/`).
- `app/third_party/stockfish/` — vendored Stockfish plugin (native, with the
  full NNUE net compiled in: ~114 MB of the APK).
- `app/tool/` — Python scripts that generate the app icon, notification
  icon and board sounds.
- `backend/supabase/schema.sql` — the community backend (tables, RLS,
  functions). Applied by hand in the Supabase SQL Editor; safe to re-run.
  Any change to it only takes effect once the user re-runs it — say so.
- `share_site/` — static page for shared-position links.
- `ml/` — plans only, no code. Recognition does not use ML.

## Features (`app/lib/src/`)

- `analysis/` — Scan tab: capture, board setup, live analysis (eval bar,
  MultiPV lines).
- `recognition/` — classic CV in pure Dart (`image` package): grid finding,
  perspective correction (`perspective.dart`) and piece templates. Runs in
  an isolate via `Isolate.run`.
- `engine/` — `EngineService` (one Stockfish, UCI) and `uci.dart` helpers.
- `puzzles/`, `accounts/` — game download, puzzle finder (background run
  with an Android foreground-service notification), puzzle board, storage.
- `skills/`, `openings/` — stats and repertoire from analyzed games; the
  opening book is `assets/openings/openings.tsv`.
- `community/` — Supabase feed, posts, comments, profiles, auth.
- `settings/`, `home/`, `sound/`, `share/`, `diagnostics/` (crash log,
  uploaded to the `crash_reports` table when the user agrees).

## Conventions

- State management: Riverpod. Keep features in their own folders under
  `app/lib/src/`.
- Positions are passed around as FEN strings; use `dartchess` for all
  legality/FEN logic — never hand-roll chess rules. UCI strings become moves
  with `legalUciMove` (`engine/uci.dart`).
- Stockfish: only `EngineService` talks to it. Live analysis (`analyze`,
  streamed on `evals`) preempts queued one-off searches (`evaluate`). There
  can be only one Stockfish per process: a second Flutter engine (e.g. a
  second activity) starting another one crashes the app. Keep
  `launchMode="singleTask"` in the manifest for that reason.
- Live analysis runs until stopped, so the Scan tab stops it when hidden
  (tab switch via `Visibility.of`, app backgrounded via lifecycle). Nothing
  else may leave Stockfish running in the background except the puzzle
  finder, which shows a notification and only runs when the user starts it
  (an interrupted run is offered as "Continue" at launch, never resumed
  automatically).
- Home tabs live in an `IndexedStack` and are built on first visit
  (Community is built at launch: it handles password-reset links).
- Recognition must run offline on-device. No server calls for inference.
- Recognition output always goes through the editable board-setup screen
  before analysis; never assume it is right.
- Performance changes to recognition must not change its output: compare
  `recognizeScreenshot` results on all of `app/test/fixtures/` and
  `screenshots/` before and after.
- Sounds: `MoveSounds` keeps a fixed set of preloaded players per sound.
  Don't use `AudioPool` with `PlayerMode.lowLatency`: it never reuses its
  players, so every play leaked one.
- Persisted data: SharedPreferences, one key per part of the library
  (`puzzle_store.dart`), written only when that part changes. Changing a
  stored format needs a migration.

## Commands (run from `app/`)

- `flutter pub get`
- `flutter run` — run on connected device/emulator (or double-click
  `Run Chess Scanner.bat` in the repo root for the Pixel_8 emulator)
- `flutter test`
- `flutter analyze` — must be clean before committing
- `flutter build apk --release --split-per-abi` — phone APK is
  `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`. Without
  `android/key.properties` it's signed with the debug key (fine for
  sideloading, not for the Play Store).
- No device is usually attached (`adb` is in
  `%LOCALAPPDATA%\Android\Sdk\platform-tools`); the GitHub CLI isn't
  installed.

## Windows notes

- Scripted file edits in Python must use `encoding='utf-8'`.
