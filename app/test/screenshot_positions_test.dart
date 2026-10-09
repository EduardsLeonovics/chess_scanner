import 'dart:io' as io;

import 'package:chess_scanner/src/recognition/board_recognizer.dart';
import 'package:chess_scanner/src/recognition/screenshot_vision.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real screenshots and photos of screens (test/fixtures/screenshots), with
/// their positions read by hand square by square: file -> (board FEN,
/// black at the bottom). Every one must read exactly.
const _positions = {
  '1.jpeg': ('1r3r2/1pR2N1k/p1b1p1pP/4P2n/8/P7/1P6/1K3R2', false),
  '3.jpeg': ('r2r2k1/4ppbp/3p1np1/pq1P3P/1p1B4/1B3P2/PPPQ2P1/1K1R3R', false),
  '6.jpeg': ('r1r3k1/1Q3ppp/5n2/2q1p3/2pnP3/3BNP1P/P5P1/R1R4K', true),
  '7.jpeg': ('2q4r/2krnpp1/R3n1p1/2P1p3/Q2p4/P6P/1PP2PP1/2K2R2', false),
  '8.jpeg': ('r1b1k2r/pp3pQp/2n1p3/2bp3q/8/6P1/PPPPBn1P/RNB1K1NR', true),
  '9.jpeg': ('1Q6/5pk1/4p3/6K1/2BP3p/4P2P/5qP1/8', true),
  '10.jpeg': ('6k1/1b3p1p/pp4pb/2p2q2/PnPp4/1Q1P2BP/1P1NrPP1/3RN1K1', true),
  '11.png': ('r1bqkb1r/pp3ppp/5n2/2p1p3/2B1P3/2N5/PPPP2PP/R1BQ1RK1', true),
  '12.png': ('r4rk1/pp1qpp2/3p1bpp/4N3/2P3b1/1PN1P3/P2QBPPP/3R1RK1', true),
  '16.png': ('5r1k/pp5p/1bpp1rp1/2q1p3/2P1Q3/P5P1/1PBR1PKP/5R2', false),
  '17.png': ('k1b5/pppN4/1R6/8/Q7/8/3K4/8', false),
  '18.png': ('r1b2rk1/pp4p1/4pp2/2npP2Q/q2N1P2/7R/2P3PP/1R4K1', false),
  '19.png': ('rnbqkb1r/1p2pppp/p2p1n2/8/3NP3/4B3/PPP2PPP/RN1QKB1R', true),
  '20.png': ('rnbqkb1r/1p2pppp/p2p1n2/8/3NP3/4B3/PPPN1PPP/R2QKB1R', true),
  '21.png': ('rq3rk1/1b2bppp/pNQ1pn2/2np4/3NP3/2P1BP2/1P2B1PP/R3R1K1', true),
  '22.png': ('rnbqkbnr/pp2pppp/3p4/2p5/1P2P3/P7/2PP1PPP/RNBQKBNR', true),
  '23.png': ('2k4r/pp4p1/2prpp1p/3n4/3P1PPP/2PN4/PP6/1K1R3R', false),
  '24.png': ('r3k2r/pp1n1pp1/2pqpn1p/3p4/3P2PP/2NQPP2/PPP1N3/2KR3R', false),
  '25.png': ('8/6r1/8/8/1K2Q3/8/5kp1/8', false),
  '26.png': ('8/6p1/6k1/6p1/P7/4RP2/KP3r2/8', false),
  '27.png': ('r6r/p1qb3p/3b1kp1/2p1pp2/2Pp4/5N2/PP1NQPPP/R3R1K1', true),
  '28.png': ('rn2r1k1/pp4pp/2p1p3/4P3/2Bp1BQ1/4P3/PPP2P2/2KN4', false),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('real screenshots', () {
    late List<PieceTemplate> templates;
    setUpAll(() async => templates = await loadPieceTemplates());

    for (final MapEntry(key: file, value: (fen, blackAtBottom)) in _positions.entries) {
      test('reads $file', () {
        final bytes = io.File('test/fixtures/screenshots/$file').readAsBytesSync();
        final result = recognizeScreenshot(bytes, templates);
        expect(result.board.fen, fen);
        expect(result.blackAtBottom, blackAtBottom);
      });
    }
  });
}
