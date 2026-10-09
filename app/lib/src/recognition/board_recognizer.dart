import 'dart:isolate';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import 'screenshot_vision.dart';

export 'screenshot_vision.dart' show RecognitionException, RecognizedBoard;

/// Piece sets used as shape references: every bundled set with a classic
/// look (novelty sets like pixel and letter are left out), plus ChessHive's
/// own so screenshots of this app read back.
const templateSets = [
  PieceSet.cburnett,
  PieceSet.merida,
  PieceSet.chessnut,
  PieceSet.pirouetti,
  PieceSet.mpchess,
  PieceSet.celtic,
  PieceSet.fantasy,
  PieceSet.spatial,
  PieceSet.firi,
  PieceSet.kiwenSuwi,
  PieceSet.totoy,
  PieceSet.rhosgfx,
  PieceSet.geo,
  PieceSet.ink,
];

List<PieceTemplate>? _templates;

/// Loads the piece templates once; later calls return the cached list.
Future<List<PieceTemplate>> loadPieceTemplates() async {
  final cached = _templates;
  if (cached != null) return cached;
  final images = <(Uint8List, PieceKind)>[];
  for (final set in templateSets) {
    for (final entry in set.assets.entries) {
      final data = await rootBundle.load(entry.value.keyName);
      images.add((data.buffer.asUint8List(), entry.key));
    }
  }
  final templates = await Isolate.run(() => [
        for (final (bytes, kind) in images) ?templateFromPieceImage(bytes, kind.role),
      ]);
  return _templates = templates;
}

/// Reads the chess position from a screenshot, off the UI thread.
/// [pieceColors]: colours this app draws its pieces in (see
/// [recognizeScreenshot]'s pieceHues), so its own screenshots read back.
///
/// Throws [RecognitionException] if no board is found.
Future<RecognizedBoard> recognizeBoard(Uint8List imageBytes, {List<Color> pieceColors = const []}) async {
  final templates = await loadPieceTemplates();
  final hues = [
    for (final c in pieceColors)
      // Only clearly coloured ones: greys have no meaningful hue.
      if (HSVColor.fromColor(c).saturation >= 0.2 && HSVColor.fromColor(c).value >= 0.15)
        HSVColor.fromColor(c).hue,
  ];
  return Isolate.run(() => recognizeScreenshot(imageBytes, templates, pieceHues: hues));
}
