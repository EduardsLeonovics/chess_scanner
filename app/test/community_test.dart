import 'package:chess_scanner/src/accounts/accounts.dart';
import 'package:chess_scanner/src/community/community_models.dart';
import 'package:chess_scanner/src/community/post_puzzle.dart';
import 'package:chess_scanner/src/engine/uci.dart';
import 'package:chess_scanner/src/puzzles/puzzle.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

PvLine _line(List<String> pv, {int? cp, int? mate}) => PvLine(multiPv: 1, depth: 18, pv: pv, cp: cp, mate: mate);

void main() {
  group('draftFromLine', () {
    test('a quiet best move is a one-move puzzle', () {
      final draft = draftFromLine(Chess.initial, _line(['e2e4', 'e7e5', 'g1f3'], cp: 30))!;
      expect(draft.fen, Chess.initial.fen);
      expect(draft.solution, ['e2e4']);
      expect(draft.bestScore, 30);
      expect(draft.lastMove, isNull);
    });

    test('a forced mate is played out in full', () {
      const fen = '8/8/8/4k3/8/8/1R6/R6K w - - 0 1';
      const mateLine = ['a1a5', 'e5e6', 'b2b6', 'e6e7', 'a5a7', 'e7e8', 'b6b8', 'x', 'y'];
      final draft = draftFromLine(Chess.fromSetup(Setup.parseFen(fen)), _line(mateLine, mate: 4))!;
      expect(draft.solution, mateLine.take(7));
    });

    test('scores are from the side to move', () {
      final afterE4 = Chess.initial.play(Move.parse('e2e4')!);
      final draft = draftFromLine(afterE4, _line(['e7e5'], cp: 40))!;
      expect(draft.bestScore, -40);
    });

    test('no puzzle without a legal first move', () {
      expect(draftFromLine(Chess.initial, _line(['e2e5'], cp: 0)), isNull);
    });
  });

  test('a personal puzzle posts with its lead-in move and solution', () {
    final puzzle = Puzzle(
      id: 'g#3',
      kind: PuzzleKind.capture,
      fen: Chess.initial.fen,
      lastMove: 'e2e4',
      solution: const ['d7d5'],
      userSide: Side.black,
      playedSan: 'a6',
      bestScore: 250,
      gameId: 'g',
      site: ChessSite.lichess,
      gameUrl: 'https://lichess.org/g',
      opponent: 'x',
      playedAt: DateTime(2026),
      moveNumber: 1,
    );
    final draft = draftFromPuzzle(puzzle);
    expect(draft.lastMove, 'e2e4');
    expect(draft.solution, ['d7d5']);
    expect(draft.withBody('  Find it!  ').toJson('me'), {
      'author_id': 'me',
      'body': 'Find it!',
      'fen': Chess.initial.fen,
      'last_move': 'e2e4',
      'solution': ['d7d5'],
      'best_score': 250,
    });
  });

  test('posts read from the server, with the solver\'s side', () {
    final post = CommunityPost.fromJson({
      'id': 7,
      'author_id': 'u1',
      'author_username': 'magnus_fan',
      'body': 'Black to move',
      'fen': Chess.initial.fen,
      'last_move': 'e2e4',
      'solution': ['e7e5'],
      'best_score': 20,
      'created_at': '2026-10-05T12:00:00Z',
      'comment_count': 3,
    });
    expect(post.authorUsername, 'magnus_fan');
    expect(post.commentCount, 3);
    expect(post.solverSide, Side.black);
    expect(post.createdAt.isUtc, isFalse);
  });

  test('timeAgo reads like a feed', () {
    final now = DateTime(2026, 10, 5, 12);
    expect(timeAgo(now.subtract(const Duration(seconds: 20)), now), 'now');
    expect(timeAgo(now.subtract(const Duration(minutes: 5)), now), '5m');
    expect(timeAgo(now.subtract(const Duration(hours: 3)), now), '3h');
    expect(timeAgo(now.subtract(const Duration(days: 2)), now), '2d');
    expect(timeAgo(DateTime(2026, 9, 1), now), 'Sep 1');
    expect(timeAgo(DateTime(2025, 9, 1), now), 'Sep 1, 2025');
  });

  test('usernames follow the database rule', () {
    expect(usernamePattern.hasMatch('chess_geek99'), isTrue);
    expect(usernamePattern.hasMatch('ab'), isFalse);
    expect(usernamePattern.hasMatch('has space'), isFalse);
    expect(usernamePattern.hasMatch('a' * 21), isFalse);
  });
}
