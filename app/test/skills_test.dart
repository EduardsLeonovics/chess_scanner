import 'dart:io' as io;

import 'package:chess_scanner/src/accounts/game_sources.dart';
import 'package:chess_scanner/src/engine/uci.dart';
import 'package:chess_scanner/src/home/speed_filter.dart';
import 'package:chess_scanner/src/puzzles/puzzle_finder.dart';
import 'package:chess_scanner/src/skills/opening_book.dart';
import 'package:chess_scanner/src/skills/skill_stats.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

const _tsv = 'eco\tname\tpgn\n'
    'C00\tFrench Defense\t1. e4 e6\n'
    'C01\tFrench Defense: Exchange\t1. e4 e6 2. d4 d5 3. exd5\n'
    'D00\tQueen Pawn\t1. d4 d5\n';

PvLine line(List<String> pv, {int? cp, int? mate}) =>
    PvLine(multiPv: 1, depth: 12, pv: pv, cp: cp, mate: mate);

/// Replays SAN [moves] from [fen] into positions + moves.
(List<Position>, List<Move>) replay(String fen, List<String> moves) {
  final positions = <Position>[Chess.fromSetup(Setup.parseFen(fen))];
  final played = <Move>[];
  for (final san in moves) {
    final m = positions.last.parseSan(san)!;
    played.add(m);
    positions.add(positions.last.play(m));
  }
  return (positions, played);
}

GameSkillStats measure(
  String fen,
  List<String> moves,
  Map<int, PvLine> scan, {
  Side side = Side.white,
  OpeningBook? book,
}) {
  final (positions, played) = replay(fen, moves);
  final lines = [for (var i = 0; i < positions.length; i++) scan[i]];
  return measureGame(
    playedAt: DateTime(2026),
    side: side,
    positions: positions,
    moves: played,
    scan: lines,
    scoreOf: scoreOf,
    mateFor: mateFor,
    afterScore: (i) => lines[i + 1] == null ? null : scoreOf(lines[i + 1]!, side),
    book: book,
  );
}

void main() {
  group('OpeningBook', () {
    final book = OpeningBook.parse(_tsv);

    test('knows every position along each line, including transpositions', () {
      Position pos = Chess.initial;
      for (final san in ['e4', 'e6', 'd4', 'd5', 'exd5']) {
        pos = pos.play(pos.parseSan(san)!);
        expect(book.contains(pos), isTrue, reason: san);
      }
      expect(book.contains(pos.play(pos.parseSan('exd5')!)), isFalse);
    });

    test('counts each distinct position once', () {
      // Start, e4, e4 e6, +d4, +d5, +exd5, d4, d4 d5.
      expect(book.size, 8);
    });

    test('the bundled data set parses completely', () {
      final tsv = io.File('assets/openings/openings.tsv').readAsStringSync();
      final lines = tsv.split('\n').where((l) => l.isNotEmpty && !l.startsWith('#') && !l.startsWith('eco')).length;
      final real = OpeningBook.parse(tsv);
      expect(lines, greaterThan(3000));
      expect(real.size, greaterThan(lines), reason: 'every line adds positions');
      // Deep theory: the Najdorf's 6. Bg5 position is known.
      Position pos = Chess.initial;
      for (final san in ['e4', 'c5', 'Nf3', 'd6', 'd4', 'cxd4', 'Nxd4', 'Nf6', 'Nc3', 'a6', 'Bg5']) {
        pos = pos.play(pos.parseSan(san)!);
      }
      expect(real.contains(pos), isTrue);
    });
  });

  test('counts theory moves and who left theory first', () {
    final book = OpeningBook.parse(_tsv);
    // White: e4, d4 in theory; Black's ...Nf6 leaves it.
    final opponentLeft = measure(kInitialFEN, ['e4', 'e6', 'd4', 'Nf6'], {}, book: book);
    expect(opponentLeft.theoryMoves, 2);
    expect(opponentLeft.leftTheory, isFalse);
    // White's 2. Nf3 leaves it.
    final userLeft = measure(kInitialFEN, ['e4', 'e6', 'Nf3'], {}, book: book);
    expect(userLeft.theoryMoves, 1);
    expect(userLeft.leftTheory, isTrue);
    // 1. e4 d5?! (out of book) 2. ... transposing back into the French
    // isn't possible here, but a late return to a book position counts:
    // 1. d4 e6 2. e4 d5 reaches the French via transposition.
    final transposed = measure(kInitialFEN, ['d4', 'e6', 'e4', 'd5', 'Nc3'], {}, book: book);
    expect(transposed.theoryMoves, 2, reason: 'd4 and e4, ending in a book position');
    expect(transposed.leftTheory, isTrue, reason: 'Nc3 left the book');
  });

  test('reaching the end of the book is not leaving theory', () {
    final book = OpeningBook.parse(_tsv);
    // 1. e4 e6 2. d4 d5 3. exd5 ends the French Exchange line; Black's
    // recapture is the first move the book doesn't know, but there was none.
    final asBlack = measure(kInitialFEN, ['e4', 'e6', 'd4', 'd5', 'exd5', 'exd5'], {},
        side: Side.black, book: book);
    expect(asBlack.theoryMoves, 2);
    expect(asBlack.theoryExhausted, isTrue);
    expect(asBlack.leftTheory, isFalse);
    // Leaving mid-line is still leaving.
    final left = measure(kInitialFEN, ['e4', 'e6', 'd4', 'c5'], {}, side: Side.black, book: book);
    expect(left.theoryExhausted, isFalse);
    expect(left.leftTheory, isTrue);
  });

  test('a book line followed to its end scores full marks once it is long enough', () {
    GameSkillStats game(int theory) =>
        GameSkillStats(playedAt: DateTime(2026), theoryMoves: theory, theoryExhausted: true);
    final deep = SkillProfile.from([game(8), game(8), game(8)]);
    expect(deep.scores[Skill.openings]!.value, 100);
    final shallow = SkillProfile.from([game(2), game(2), game(2)]);
    expect(shallow.scores[Skill.openings]!.value, isNull, reason: 'too short to say anything');
  });

  group('a combination counts once', () {
    // The engine lines are made up: a mate in 3 starting 1. Re8+ Kf7 2. Re7+,
    // which is a mate in 2 on the user's next move.
    const fen = '1n4k1/6pp/8/8/8/8/6PP/4R1K1 w - - 0 1';
    final start = {
      0: line(['e1e8', 'g8f7', 'e8e7'], mate: 3),
      1: line(['g8f7', 'e8e7'], mate: 3),
      2: line(['e8e7', 'f7f6'], mate: 2),
    };

    test('found and finished', () {
      final stats = measure(fen, ['Re8+', 'Kf7', 'Re7+', 'Kf6'], {
        ...start,
        3: line(['f7f6'], mate: 2),
      });
      expect(stats.tacticChances, 1);
      expect(stats.tacticsFound, 1);
    });

    test('started but not finished', () {
      final stats = measure(fen, ['Re8+', 'Kf7', 'Kf2'], {
        ...start,
        3: line(['f7e8'], cp: 0),
      });
      expect(stats.tacticChances, 1);
      expect(stats.tacticsFound, 0);
    });
  });

  test('time control is kept and filters the games', () {
    final blitz = GameSkillStats(playedAt: DateTime(2026), speed: GameSpeed.blitz);
    final rapid = GameSkillStats(playedAt: DateTime(2026), speed: GameSpeed.rapid);
    expect(GameSkillStats.fromJson(blitz.toJson()).speed, GameSpeed.blitz);
    expect(GameSkillStats.fromJson(GameSkillStats(playedAt: DateTime(2026)).toJson()).speed, isNull);
    expect(filterBySpeed(GameSpeed.rapid, [blitz, rapid], (g) => g.speed), [rapid]);
    expect(filterBySpeed(null, [blitz, rapid], (g) => g.speed), [blitz, rapid]);
    expect(filterBySpeed(GameSpeed.bullet, [blitz, rapid], (g) => g.speed), [blitz, rapid],
        reason: 'a choice with no games falls back to all');
  });

  test('a material win two moves deep is a tactic; taking a loose piece is not', () {
    // White rook takes the knight only after a check drives the king away:
    // 1. Re8+ Kh7 2. Rxb8. (Immediate gain 0, gain by move 2 = 3.)
    const fen = '1n4k1/6pp/8/8/8/8/6PP/4R1K1 w - - 0 1';
    final deep = measure(fen, ['Kf2'], {
      0: line(['e1e8', 'g8f7', 'e8b8', 'f7e6', 'b8b7', 'e6d6'], cp: 400),
      1: line(['b8c6'], cp: -50),
    });
    expect(deep.tacticChances, 1);
    expect(deep.tacticsFound, 0);

    // A knight simply hanging on e4: immediate capture, not a deep tactic.
    const loose = '6k1/8/8/8/4n3/8/8/4R1K1 w - - 0 1';
    final shallow = measure(loose, ['Rxe4'], {
      0: line(['e1e4', 'g8f7', 'e4e5'], cp: 500),
      1: line(['g8f7'], cp: 500),
    });
    expect(shallow.tacticChances, 0);
  });

  test('accuracy follows the win-chance drop', () {
    expect(moveAccuracy(50, 50), 100);
    expect(moveAccuracy(50, 300), 100, reason: 'improving is never penalised');
    expect(moveAccuracy(0, -900), lessThan(20));
    // Lichess's formula: a 50 cp slip in a level position is ~81% accurate.
    expect(moveAccuracy(30, -20), closeTo(81.3, 0.5));
  });

  test('profile hides scores without enough evidence', () {
    final profile = SkillProfile.from([
      GameSkillStats(playedAt: DateTime(2026), tacticChances: 2, tacticsFound: 1),
    ]);
    expect(profile.scores[Skill.tactics]!.value, isNull);
    expect(profile.scores[Skill.tactics]!.basis, 'Found 1 of 2 tactical chances');

    final enough = SkillProfile.from([
      for (var i = 0; i < 3; i++)
        GameSkillStats(
          playedAt: DateTime(2026, 1, i + 1),
          tacticChances: 1,
          tacticsFound: i == 0 ? 0 : 1,
          theoryMoves: 6,
          leftTheory: true,
        ),
    ]);
    expect(enough.scores[Skill.tactics]!.value, closeTo(66.7, 0.1));
    expect(enough.scores[Skill.openings]!.value, 50); // 6 of 12 theory moves
    expect(enough.games, 3);
  });
}
