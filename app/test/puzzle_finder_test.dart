import 'package:chess_scanner/src/accounts/accounts.dart';
import 'package:chess_scanner/src/accounts/game_sources.dart';
import 'package:chess_scanner/src/engine/engine_service.dart';
import 'package:chess_scanner/src/engine/uci.dart';
import 'package:chess_scanner/src/puzzles/puzzle.dart';
import 'package:chess_scanner/src/puzzles/puzzle_finder.dart';
import 'package:chess_scanner/src/puzzles/puzzle_store.dart';
import 'package:chess_scanner/src/sound/move_sounds.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

PvLine line(List<String> pv, {int? cp, int? mate, int multiPv = 1}) =>
    PvLine(multiPv: multiPv, depth: 20, pv: pv, cp: cp, mate: mate);

/// An engine that answers from a table of FEN -> lines (White POV).
Evaluate stubEngine(Map<String, List<PvLine>> table) {
  return (fen, {multiPv = 1, depth, nodes}) async {
    // Positions the test doesn't care about get no engine opinion.
    final lines = table[fen] ?? const <PvLine>[];
    return EngineEval(fen: fen, lines: lines.take(multiPv).toList());
  };
}

FetchedGame game(String fen, List<String> sans, {Side side = Side.white}) => FetchedGame(
      id: 'test:1',
      site: ChessSite.lichess,
      account: 'me',
      url: 'https://lichess.org/test',
      userSide: side,
      opponent: 'opponent',
      playedAt: DateTime(2026, 9, 1),
      sanMoves: sans,
      initialFen: fen,
    );

String after(String fen, String san) {
  final pos = Chess.fromSetup(Setup.parseFen(fen));
  return pos.play(pos.parseSan(san)!).fen;
}

void main() {
  group('findPuzzles', () {
    test('finds a missed mate in 4 with the whole mating line', () async {
      const start = '8/8/8/4k3/8/8/1R6/R6K w - - 0 1';
      const mateLine = ['a1a5', 'e5e6', 'b2b6', 'e6e7', 'a5a7', 'e7e8', 'b6b8'];
      final puzzles = await findPuzzles(
        game(start, ['Kg1', 'Kd4']),
        stubEngine({
          start: [line(mateLine, mate: 4), line(['a1a4'], cp: 900, multiPv: 2)],
          after(start, 'Kg1'): [line(['e5d4'], cp: 900)],
        }),
        skipPlies: 0,
      );
      expect(puzzles, hasLength(1));
      final puzzle = puzzles.single;
      expect(puzzle.kind, PuzzleKind.mate);
      expect(puzzle.mateIn, 4);
      expect(puzzle.category, PuzzleCategory.mateIn4);
      expect(puzzle.solution, mateLine);
      expect(puzzle.playedSan, 'Kg1');
      expect(puzzle.lastMove, isNull);
    });

    test('finds a missed winning capture', () async {
      const start = '4k3/8/8/3q4/8/8/3R4/4K3 w - - 0 1';
      final puzzles = await findPuzzles(
        game(start, ['Kf1', 'Qd2']),
        stubEngine({
          start: [line(['d2d5', 'e8e7'], cp: 600), line(['e1f1'], cp: -400, multiPv: 2)],
          after(start, 'Kf1'): [line(['d5d2'], cp: -400)],
        }),
        skipPlies: 0,
      );
      expect(puzzles.single.kind, PuzzleKind.capture);
      expect(puzzles.single.solution, ['d2d5']);
    });

    test('finds a missed only move that threw away +2', () async {
      final puzzles = await findPuzzles(
        game(kInitialFEN, ['a3', 'e5']),
        stubEngine({
          kInitialFEN: [line(['e2e4'], cp: 250), line(['d2d4'], cp: 40, multiPv: 2)],
          after(kInitialFEN, 'a3'): [line(['e7e5'], cp: -20)],
        }),
        skipPlies: 0,
      );
      expect(puzzles.single.kind, PuzzleKind.onlyMove);
      expect(puzzles.single.solution, ['e2e4']);
    });

    test('no only-move puzzle when a second move also keeps the edge', () async {
      final puzzles = await findPuzzles(
        game(kInitialFEN, ['a3', 'e5']),
        stubEngine({
          kInitialFEN: [line(['e2e4'], cp: 250), line(['d2d4'], cp: 230, multiPv: 2)],
          after(kInitialFEN, 'a3'): [line(['e7e5'], cp: -20)],
        }),
        skipPlies: 0,
      );
      expect(puzzles, isEmpty);
    });

    test('no puzzle when the user found the best move', () async {
      const start = '4k3/8/8/3q4/8/8/3R4/4K3 w - - 0 1';
      final puzzles = await findPuzzles(
        game(start, ['Rxd5', 'Ke7']),
        stubEngine({
          start: [line(['d2d5', 'e8e7'], cp: 600)],
        }),
        skipPlies: 0,
      );
      expect(puzzles, isEmpty);
    });

    test('works from Black\'s side with the opponent\'s move as lead-in', () async {
      // 1. e4 and Black misses ...Qh4-style nothing: use a stubbed +2 for Black.
      final afterE4 = after(kInitialFEN, 'e4');
      final puzzles = await findPuzzles(
        game(kInitialFEN, ['e4', 'a6', 'Nf3'], side: Side.black),
        stubEngine({
          afterE4: [line(['e7e5'], cp: -300), line(['c7c5'], cp: 0, multiPv: 2)],
          after(afterE4, 'a6'): [line(['g1f3'], cp: 30)],
        }),
        skipPlies: 0,
      );
      final puzzle = puzzles.single;
      expect(puzzle.kind, PuzzleKind.onlyMove);
      expect(puzzle.userSide, Side.black);
      expect(puzzle.fen, kInitialFEN);
      expect(puzzle.lastMove, 'e2e4');
    });
  });

  test('scoreOf ranks mates beyond any centipawn score', () {
    expect(scoreOf(line(['a'], mate: 3), Side.white), greaterThan(scoreOf(line(['a'], cp: 5000), Side.white)));
    expect(scoreOf(line(['a'], mate: 3), Side.white), greaterThan(scoreOf(line(['a'], mate: 5), Side.white)));
    expect(scoreOf(line(['a'], mate: 3), Side.black), lessThan(-90000));
    expect(scoreOf(line(['a'], cp: -150), Side.black), 150);
  });

  test('mixPuzzles interleaves categories', () {
    Puzzle p(String id, PuzzleKind kind, [int? mateIn]) => Puzzle(
          id: id,
          kind: kind,
          mateIn: mateIn,
          fen: kInitialFEN,
          solution: const ['e2e4'],
          userSide: Side.white,
          playedSan: 'a3',
          bestScore: 300,
          gameId: 'g',
          site: ChessSite.lichess,
          gameUrl: '',
          opponent: '',
          playedAt: DateTime(2026),
          moveNumber: 1,
        );
    final mixed = mixPuzzles([
      p('o1', PuzzleKind.onlyMove),
      p('o2', PuzzleKind.onlyMove),
      p('o3', PuzzleKind.onlyMove),
      p('m1', PuzzleKind.mate, 3),
      p('m2', PuzzleKind.mate, 5),
      p('c1', PuzzleKind.capture),
    ]);
    expect(mixed.take(4).map((p) => p.category).toList(), [
      PuzzleCategory.mateIn3,
      PuzzleCategory.mateIn5,
      PuzzleCategory.onlyMove,
      PuzzleCategory.capture,
    ]);
    expect(mixed.skip(4).map((p) => p.id), ['o2', 'o3']);
  });

  group('soundFor', () {
    Position pos(String fen) => Chess.fromSetup(Setup.parseFen(fen));

    test('quiet move, capture, castle and check', () {
      expect(soundFor(Chess.initial, Move.parse('e2e4')!), MoveSound.move);
      final capture = pos('4k3/8/8/3q4/8/8/3R4/4K3 w - - 0 1');
      expect(soundFor(capture, Move.parse('d2d5')!), MoveSound.capture);
      final castle = pos('4k3/8/8/8/8/8/8/4K2R w K - 0 1');
      expect(soundFor(castle, castle.normalizeMove(Move.parse('e1g1')! as NormalMove)), MoveSound.castle);
      expect(soundFor(castle, Move.parse('h1h8')!), MoveSound.check);
    });
  });
}
