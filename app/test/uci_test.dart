import 'package:chess_scanner/src/analysis/analysis_page.dart';
import 'package:chess_scanner/src/engine/uci.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseInfoLine', () {
    test('parses a MultiPV centipawn line', () {
      final line = parseInfoLine(
        'info depth 20 seldepth 28 multipv 2 score cp -35 nodes 123 nps 456 '
        'hashfull 10 tbhits 0 time 300 pv e7e5 g1f3 b8c6',
      )!;
      expect(line.depth, 20);
      expect(line.multiPv, 2);
      expect(line.cp, -35);
      expect(line.mate, isNull);
      expect(line.pv, ['e7e5', 'g1f3', 'b8c6']);
    });

    test('parses a mate score', () {
      final line = parseInfoLine('info depth 5 score mate -3 pv h7h6 d1h5')!;
      expect(line.mate, -3);
      expect(line.multiPv, 1);
    });

    test('ignores bound scores, info strings and lines without pv', () {
      expect(parseInfoLine('info depth 18 score cp 20 lowerbound pv e2e4'), isNull);
      expect(parseInfoLine('info string NNUE evaluation using nn.nnue'), isNull);
      expect(parseInfoLine('info depth 3 currmove e2e4 currmovenumber 1'), isNull);
      expect(parseInfoLine('bestmove e2e4 ponder e7e5'), isNull);
    });
  });

  group('PvLine', () {
    const line = PvLine(multiPv: 1, depth: 10, pv: ['e7e5'], cp: 120);

    test('converts to White point of view', () {
      expect(line.toWhitePov(whiteToMove: true).cp, 120);
      expect(line.toWhitePov(whiteToMove: false).cp, -120);
    });

    test('formats scores', () {
      expect(line.scoreLabel, '+1.20');
      expect(const PvLine(multiPv: 1, depth: 1, pv: ['a'], cp: -5).scoreLabel, '-0.05');
      expect(const PvLine(multiPv: 1, depth: 1, pv: ['a'], mate: 2).scoreLabel, 'M2');
      expect(const PvLine(multiPv: 1, depth: 1, pv: ['a'], mate: -4).scoreLabel, '-M4');
    });

    test('eval bar share is balanced at 0 and saturates on mate', () {
      expect(const PvLine(multiPv: 1, depth: 1, pv: ['a'], cp: 0).whiteShare, 0.5);
      expect(line.whiteShare, greaterThan(0.5));
      expect(const PvLine(multiPv: 1, depth: 1, pv: ['a'], mate: -1).whiteShare, 0);
    });
  });

  group('pvToSan', () {
    test('numbers moves from the start position', () {
      expect(pvToSan(Chess.initial, ['e2e4', 'e7e5', 'g1f3']), '1. e4 e5 2. Nf3');
    });

    test('uses ellipsis when Black moves first and handles castling', () {
      final pos = Chess.fromSetup(Setup.parseFen(
        'r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 10',
      ));
      expect(pvToSan(pos, ['e8g8', 'e1c1']), '10... O-O 11. O-O-O');
    });

    test('stops at the first illegal move', () {
      expect(pvToSan(Chess.initial, ['e2e4', 'e2e4']), '1. e4');
    });
  });
}
