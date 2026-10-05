import 'dart:io' as io;

import 'package:chess_scanner/src/recognition/board_recognizer.dart';
import 'package:chess_scanner/src/recognition/screenshot_vision.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _middlegame = 'r1bq1rk1/pp2bppp/2n1pn2/3p4/2PP4/2N1PN2/PP3PPP/R2QKB1R';
const _endgame = '8/5pk1/6p1/3R4/1r6/6P1/5PK1/8';

/// Renders [boardFen] like a site's screenshot: [square]-pixel squares at
/// ([left], [top]) on a [width]x[height] page with some UI clutter around it.
Future<Uint8List> _screenshot(
  String boardFen, {
  PieceSet set = PieceSet.cburnett,
  int width = 540,
  int height = 1170,
  int left = 0,
  int top = 260,
  int square = 67,
  img.Color? light,
  img.Color? dark,
  bool blackAtBottom = false,
  Set<String> highlighted = const {},
  bool coordinates = false,
}) async {
  light ??= img.ColorRgb8(240, 217, 181);
  dark ??= img.ColorRgb8(181, 136, 99);
  final page = img.Image(width: width, height: height)..clear(img.ColorRgb8(38, 36, 33));
  // Clutter: text-like bars above and below the board.
  for (var i = 0; i < 6; i++) {
    img.fillRect(page, x1: 20, y1: 40 + i * 30, x2: 20 + 60 * (i + 2), y2: 52 + i * 30,
        color: img.ColorRgb8(200, 200, 200));
    img.drawString(page, 'Some app text ${i * 7}', font: img.arial24,
        x: 20, y: top + 8 * square + 30 + i * 36, color: img.ColorRgb8(230, 230, 230));
  }

  final board = Board.parseFen(boardFen);
  final pieceImages = <PieceKind, img.Image>{};
  for (final entry in set.assets.entries) {
    final data = await rootBundle.load(entry.value.keyName);
    final decoded = img.decodeImage(data.buffer.asUint8List())!;
    pieceImages[entry.key] = img.copyResize(decoded, width: square, height: square,
        interpolation: img.Interpolation.average);
  }

  for (var row = 0; row < 8; row++) {
    for (var col = 0; col < 8; col++) {
      final sq = blackAtBottom
          ? Square.fromCoords(File(7 - col), Rank(row))
          : Square.fromCoords(File(col), Rank(7 - row));
      final isLight = (sq.file + sq.rank) % 2 == 1;
      var color = isLight ? light : dark;
      if (highlighted.contains(sq.name)) {
        color = isLight ? img.ColorRgb8(245, 246, 130) : img.ColorRgb8(185, 202, 67);
      }
      final x = left + col * square, y = top + row * square;
      img.fillRect(page, x1: x, y1: y, x2: x + square - 1, y2: y + square - 1, color: color);
      if (coordinates && col == 0) {
        img.drawString(page, sq.rank.name, font: img.arial14, x: x + 3, y: y + 2,
            color: isLight ? dark : light);
      }
      if (coordinates && row == 7) {
        img.drawString(page, sq.file.name, font: img.arial14, x: x + square - 11,
            y: y + square - 17, color: isLight ? dark : light);
      }
      final piece = board.pieceAt(sq);
      if (piece != null) {
        img.compositeImage(page, pieceImages[piece.kind]!, dstX: x, dstY: y);
      }
    }
  }
  return img.encodePng(page);
}

Future<RecognizedBoard> _recognize(Uint8List bytes) async =>
    recognizeScreenshot(bytes, await loadPieceTemplates());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('recognizeScreenshot', () {
    test('reads a lichess-style phone screenshot', () async {
      final result = await _recognize(await _screenshot(_middlegame));
      expect(result.board.fen, _middlegame);
      expect(result.blackAtBottom, isFalse);
    });

    test('reads a chess.com-style board with highlights and coordinates', () async {
      final result = await _recognize(await _screenshot(
        _middlegame,
        set: PieceSet.merida,
        light: img.ColorRgb8(235, 236, 208),
        dark: img.ColorRgb8(115, 149, 82),
        left: 30,
        square: 60,
        highlighted: {'c4', 'c2'},
        coordinates: true,
      ));
      expect(result.board.fen, _middlegame);
    });

    test('detects a board shown from Black\'s side', () async {
      final result = await _recognize(await _screenshot(
        _middlegame,
        set: PieceSet.alpha,
        blackAtBottom: true,
      ));
      expect(result.blackAtBottom, isTrue);
      expect(result.board.fen, _middlegame);
    });

    test('reads a landscape desktop screenshot', () async {
      final result = await _recognize(await _screenshot(
        _endgame,
        set: PieceSet.staunty,
        width: 1280,
        height: 720,
        left: 300,
        top: 60,
        square: 76,
        light: img.ColorRgb8(222, 227, 230),
        dark: img.ColorRgb8(140, 162, 173),
      ));
      expect(result.board.fen, _endgame);
    });

    test('reads a real screenshot of this app', () async {
      final bytes = io.File('test/fixtures/emulator_start_position.png').readAsBytesSync();
      final result = await _recognize(bytes);
      expect(result.board.fen, Board.standard.fen);
    });

    // Real screenshots from the web: different sites, themes and piece sets.
    for (final (file, fen, blackAtBottom) in [
      ('real_brown_board.png', 'k1b5/pppN4/1R6/8/Q7/8/3K4/8', false),
      // A phone photo of a curved monitor, at an angle, with moire: found by
      // straightening the board first (perspective.dart).
      ('photo_of_monitor_angled.jpeg', '1r3r2/1pR2N1k/p1b1p1pP/4P2n/8/P7/1P6/1K3R2', false),
      // Another monitor photo: glare breaks the outlines of the white pieces
      // on the h-file, and its pawns match the bishop template almost as well.
      (
        'photo_of_monitor_glare.jpeg',
        'r2r2k1/4ppbp/3p1np1/pq1P3P/1p1B4/1B3P2/PPPQ2P1/1K1R3R',
        false,
      ),
      // real_brown_board.png seen in perspective, on a grey background.
      ('real_brown_board_tilted.png', 'k1b5/pppN4/1R6/8/Q7/8/3K4/8', false),
      // Wood texture: the grain used to stick to a pawn and make it a rook.
      (
        'real_wood_board_black_side.png',
        'r1bqkb1r/pp3ppp/5n2/2p1p3/2B1P3/2N5/PPPP2PP/R1BQ1RK1',
        true,
      ),
      (
        'real_brown_board_black_side.png',
        'r4rk1/pp1qpp2/3p1bpp/4N3/2P3b1/1PN1P3/P2QBPPP/3R1RK1',
        true,
      ),
      // Slightly stretched, blurry image with a piece set we have no template for.
      (
        'real_blue_board_stretched.png',
        '5r1k/pp5p/1bpp1rp1/2q1p3/2P1Q3/P5P1/1PBR1PKP/5R2',
        false,
      ),
    ]) {
      test('reads $file', () async {
        final result = await _recognize(io.File('test/fixtures/$file').readAsBytesSync());
        expect(result.board.fen, fen);
        expect(result.blackAtBottom, blackAtBottom);
      });
    }

    test('rejects an image without a board', () async {
      final page = img.Image(width: 400, height: 800)..clear(img.ColorRgb8(255, 255, 255));
      img.drawString(page, 'no chess here', font: img.arial24, x: 20, y: 100,
          color: img.ColorRgb8(0, 0, 0));
      expect(
        () => _recognize(img.encodePng(page)),
        throwsA(isA<RecognitionException>()),
      );
    });
  });
}
