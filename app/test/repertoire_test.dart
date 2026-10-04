import 'package:chess_scanner/src/openings/opening_study_page.dart' show Verdict;
import 'package:chess_scanner/src/openings/repertoire.dart';
import 'package:chess_scanner/src/skills/opening_book.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

const _tsv = 'eco\tname\tpgn\n'
    'B20\tSicilian Defense\t1. e4 c5\n'
    'B50\tSicilian Defense: Modern Variations\t1. e4 c5 2. Nf3 d6\n'
    'C00\tFrench Defense\t1. e4 e6\n';

RepertoireGame game(String id, Side side, String moves) => RepertoireGame(
      id: id,
      side: side,
      sanMoves: moves.split(' '),
      playedAt: DateTime(2026),
    );

void main() {
  final book = OpeningBook.parse(_tsv);
  final games = [
    game('1', Side.white, 'e4 c5 Nf3 d6 d4'),
    game('2', Side.white, 'e4 c5 Nc3 Nc6'),
    game('3', Side.white, 'e4 e6 d4 d5'),
    game('4', Side.white, 'd4 d5 c4'),
    game('5', Side.black, 'e4 c5 Nf3'),
  ];

  test('groups games by opening family, most played first, "Other" last', () {
    final white = OpeningFamily.group(games, Side.white, book);
    expect(white.map((f) => f.name), ['Sicilian Defense', 'French Defense', 'Other openings']);
    expect(white.first.games.map((g) => g.id), ['1', '2']);
    expect(OpeningFamily.group(games, Side.black, book).single.games.single.id, '5');
  });

  test('the tree counts what was played from each position', () {
    final tree = OpeningTree(games.where((g) => g.side == Side.white));
    expect(tree.at(Chess.initial)!.ranked.first, isA<MapEntry<String, int>>()
        .having((e) => e.key, 'move', 'e2e4')
        .having((e) => e.value, 'count', 3));
    final afterC5 = Chess.initial.play(Move.parse('e2e4')!).play(Move.parse('c7c5')!);
    expect(tree.at(afterC5)!.moves, {'g1f3': 1, 'b1c3': 1});
    expect(tree.at(afterC5)!.total, 2);
  });

  test('verdicts by centipawns lost', () {
    expect(Verdict.of(0), Verdict.good);
    expect(Verdict.of(49), Verdict.good);
    expect(Verdict.of(50), Verdict.inaccuracy);
    expect(Verdict.of(150), Verdict.mistake);
    expect(Verdict.of(900), Verdict.blunder);
  });
}
