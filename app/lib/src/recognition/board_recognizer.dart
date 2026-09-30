import 'dart:isolate';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/services.dart';

import 'screenshot_vision.dart';

export 'screenshot_vision.dart' show RecognitionException, RecognizedBoard;

/// Piece sets used as shape references. Chosen to cover the common looks of
/// chess sites and apps; novelty sets (pixel, letters, xkcd, …) are left out.
const templateSets = [
  PieceSet.cburnett,
  PieceSet.merida,
  PieceSet.alpha,
  PieceSet.california,
  PieceSet.cardinal,
  PieceSet.maestro,
  PieceSet.staunty,
  PieceSet.companion,
  PieceSet.leipzig,
  PieceSet.fresca,
  PieceSet.gioco,
  PieceSet.tatiana,
  PieceSet.governor,
  PieceSet.chessnut,
  PieceSet.kosal,
  PieceSet.riohacha,
  PieceSet.pirouetti,
  PieceSet.icpieces,
  PieceSet.mpchess,
  PieceSet.dubrovny,
  PieceSet.cooke,
  PieceSet.reillycraig,
  PieceSet.celtic,
  PieceSet.monarchy,
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
///
/// Throws [RecognitionException] if no board is found.
Future<RecognizedBoard> recognizeBoard(Uint8List imageBytes) async {
  final templates = await loadPieceTemplates();
  return Isolate.run(() => recognizeScreenshot(imageBytes, templates));
}
