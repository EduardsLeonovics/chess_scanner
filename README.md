# ChessGeek

Cross-platform (Android + iOS) app: photograph a physical chess board or upload a
screenshot, get the position recognized automatically, then analyze it with an
on-device Stockfish engine (eval bar + best lines, like chess.com's analysis board).

## Stack

| Concern              | Choice                                                        |
|----------------------|---------------------------------------------------------------|
| App framework        | Flutter (Dart) — one codebase for Android and iOS             |
| Engine               | Stockfish, vendored in `app/third_party/stockfish` (native, on device) |
| Board UI             | `chessground` (Lichess's board widget)                        |
| Chess rules / FEN    | `dartchess`                                                   |
| Camera / gallery     | `image_picker`                                                |
| Vision               | Classic CV + piece templates in pure Dart (`image` package), no ML model yet |
| Community            | Supabase (accounts, posts, comments, follows), `supabase_flutter` |

## Repository layout

```
app/        Flutter application (created with `flutter create`, see below)
backend/    Supabase schema and setup for the community (backend/supabase/README.md)
ml/         Plans for trained recognition models (no code yet, see ml/README.md)
```

## Recognition pipeline

1. **Board detection** — find the 4 board corners (keypoint model, or classic
   CV/Hough lines for screenshots).
2. **Perspective warp** — rectify to a top-down square image.
3. **Square classification** — split into 64 crops, classify each as one of 13
   classes (empty + 6 white + 6 black). For 3D photos a piece *detector*
   (YOLO-style) on the un-warped image, mapped to squares via the homography,
   handles tall pieces that overlap neighbouring squares much better.
4. **Build FEN** — user confirms/edits the board, picks side to move, then
   analysis starts.

Flat boards photographed at an angle (a phone photo of a monitor, a printed
diagram) are straightened first: Hough lines, a projective 9-line grid fit
per direction and a homography (`app/lib/src/recognition/perspective.dart`).

Screenshots (2D digital boards) are the easy case and should ship first;
real 3D photos need a trained model and are the hard part.

## Setup (Windows)

1. Flutter SDK 3.47.5 lives in `%USERPROFILE%\develop\flutter` (on user PATH).
2. Install Android Studio (Android SDK + emulator), then run `flutter doctor`
   and fix the Android items (the Visual Studio item is only for Windows
   desktop apps and can be ignored).
3. The app was created with
   `flutter create --org com.eduards --project-name chess_scanner --platforms android,ios app`.
   Run it: `cd app && flutter run`.
4. **iOS**: building for iPhone requires macOS + Xcode (or a cloud CI such as
   Codemagic / GitHub Actions macOS runners). Develop on Android first.

## Roadmap

- [x] M1: Flutter app skeleton, analysis board with manual piece setup
- [x] M2: Stockfish integration — eval bar, top 3 lines (MultiPV), depth
- [x] M3: Screenshot import → FEN (2D boards; classic CV + piece-set templates, no model yet)
- [x] M4: Board editor to correct recognition mistakes, side-to-move / castling
- [ ] M5: Camera capture of real 3D boards → FEN (trained model)
- [ ] M6: Polish: move arrows, game tree, save/share FEN/PGN

## License

Copyright (C) 2026 Eduards Leonovics

ChessGeek is free software: you can redistribute it and/or modify it under the
terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version. See [LICENSE](LICENSE) for the full text.

It has to be: the app ships Stockfish, chessground and dartchess, which are all
GPLv3. Anyone who gets the app must be able to get this source code.

As permitted by section 7(e) of the GPL, no rights are granted under
trademark law to the name "ChessGeek" or its logo: modified versions must be
published under a different name and icon.

ChessGeek is not affiliated with or endorsed by Lichess or Chess.com.
