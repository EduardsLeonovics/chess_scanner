# CLAUDE.md

Guidance for Claude Code when working in this repo. See README.md for the
product overview, stack and roadmap.

## Project

Flutter app (Android + iOS) that recognizes a chess position from a camera photo
or screenshot and analyzes it with on-device Stockfish.

- `app/` — Flutter app. Dart code under `app/lib/`.
- `ml/` — Python training code for the recognition models (exported to TFLite
  and copied into `app/assets/models/`).

## Conventions

- State management: Riverpod. Keep engine, recognition, and UI in separate
  feature folders under `app/lib/src/` (`engine/`, `recognition/`, `board/`,
  `capture/`).
- Positions are passed around as FEN strings; use `dartchess` for all
  legality/FEN logic — never hand-roll chess rules.
- Stockfish talks UCI. Wrap it in one `EngineService` that owns the process,
  exposes a stream of `{depth, scoreCp|mate, pv}` per MultiPV line, and always
  sends `stop` before a new `position`.
- Recognition must run offline on-device. No server calls for inference.
- Recognition output always goes through the editable board-setup screen
  before analysis; never assume the model is right.

## Commands (run from `app/`)

- `flutter pub get`
- `flutter run` — run on connected device/emulator
- `flutter test`
- `flutter analyze` — must be clean before committing
