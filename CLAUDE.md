# CLAUDE.md

Guidance for Claude Code when working in this repo. See README.md for the
product overview, stack and roadmap.

## Open launch blockers — remind the user at the start of every session

Raise these with the user until each is done, then delete its line:

- **Supabase redirect URL:** the URL scheme is now `chesshive://`, so in
  Supabase → Authentication → URL Configuration add
  `chesshive://login-callback` to the redirect URLs (keep the old
  `chessgeek://` one until old builds are gone).
- **Website:** `share_site/` is the site for https://chesshive.app (home,
  privacy, terms, share links, assetlinks.json). Connect it to Cloudflare
  Pages and add the custom domain (steps in `share_site/README.md`); the
  app's share links and legal links already point there.
- **Play App Signing:** the upload key exists (keystore in
  `C:\Users\Eduards\keys\`, passwords in the git-ignored
  `app/android/key.properties`) and its fingerprint is in
  `share_site/.well-known/assetlinks.json`. Still to do: back the keystore
  and passwords up off this PC, enrol in Play App Signing, and add Play's
  app signing key SHA-256 (Play Console → App integrity) to assetlinks.json
  next to the upload key's.
- **Production email:** Supabase's built-in mailer only sends a few
  emails an hour. Set up Resend as custom SMTP in Supabase for
  chesshive.app (sender noreply@chesshive.app), check the reset-password
  template's link, and raise the email rate limit.
- **Privacy policy and Terms of Use:** `share_site/privacy/index.html` and
  `share_site/terms/index.html`. Still to fill in: the postal address
  (highlighted); confirm the Supabase region (EU, Ireland) in Project
  Settings. Update the "Last updated" date when publishing, and have
  someone qualified read them.

## Project

ChessHive: a Flutter app (Android first; iOS builds need macOS) that reads a
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
- `share_site/` — the chesshive.app website (Cloudflare Pages): home,
  privacy policy, terms, shared-position page, assetlinks.json.
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
- `backup/` — `LibraryBackup`: keeps the signed-in user's linked
  usernames and game library (not the queue) in the `libraries` table,
  merged with the phone's on sign-in, uploaded part by part on change.
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
- Any material can be set up, viewed and shared (20 queens a side is
  fine) as long as each side has one king and the side to move isn't
  already checkmated (`positionFromBoard`, `checkNotCheckmate`). But only
  positions passing `materialProblem` / `isAnalyzableFen`
  (`board/board_setup.dart`) may reach Stockfish: beyond real-game material
  its fixed tables (32 NNUE pieces, 128 threats, 256 moves) overflow and
  crash the app. The analysis board says why instead. The vendored
  Stockfish's `position` command also refuses them (patch in `uci.cpp`).
- Piece sets: only sets licensed for commercial use.
  chessground is vendored in `app/third_party/chessground` with the rest
  removed; licences in its LICENSES.md. Geo, Ink and Bubble are our own,
  drawn by `app/tool/make_piece_sets.py`.
- No ads and no tracking SDKs. Usage statistics
  (`privacy/usage_stats.dart`) are anonymous daily totals, sent only after
  the user turns them on in Settings → Privacy (off by default); never add
  user/device ids, location or content to them.
- Community safety: reports have categories (keep `ReportCategory` and the
  `reports_category_check` in schema.sql in sync — a test checks it);
  blocking works both ways on the server (`blocked_between`).
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
  stored format needs a migration, on the phone and for backups already
  in the `libraries` table (`LibraryBackupData.fromRow`).
- Connecting Lichess / Chess.com and loading games need a ChessHive
  sign-in (`signedInProvider`). Signing out or deleting the account goes
  through `LibraryBackup`, which removes the library from the phone.

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
