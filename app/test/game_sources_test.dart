import 'dart:convert';

import 'package:chess_scanner/src/accounts/accounts.dart';
import 'package:chess_scanner/src/accounts/game_sources.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _moves = 'e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7';

String lichessGame(String id, int createdAt, {String variant = 'standard'}) => jsonEncode({
      'id': id,
      'variant': variant,
      'speed': 'ultraBullet',
      'createdAt': createdAt,
      'moves': _moves,
      'players': {
        'white': {
          'user': {'name': 'Me', 'id': 'me'},
          'rating': 1500,
        },
        'black': {
          'user': {'name': 'Rival', 'id': 'rival'},
          'rating': 1612,
        },
      },
    });

Map<String, dynamic> chessComGame(String uuid, int endTime) => {
      'uuid': uuid,
      'url': 'https://www.chess.com/game/live/$uuid',
      'rules': 'chess',
      'time_class': 'daily',
      'end_time': endTime,
      'pgn': '[Event "Live"]\n\n1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 *',
      'white': {'username': 'Rival', 'rating': 1288},
      'black': {'username': 'Me', 'rating': 1301},
    };

DateTime ms(int millis) => DateTime.fromMillisecondsSinceEpoch(millis);

void main() {
  group('Lichess', () {
    test('first load takes the latest games, newest first, with ratings', () async {
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        return http.Response(
          [lichessGame('b', 2000), lichessGame('a', 1000), lichessGame('x', 900, variant: 'chess960')]
              .join('\n'),
          200,
        );
      });
      final batch = await fetchUnanalyzed(
        ChessSite.lichess,
        'Me',
        coverage: null,
        analyzed: const {},
        want: 5,
        client: client,
      );
      expect(requests.single.queryParameters, containsPair('sort', 'dateDesc'));
      expect(requests.single.queryParameters.containsKey('until'), isFalse);
      expect(batch.newer, isEmpty);
      expect(batch.older.map((g) => g.id), ['lichess:b', 'lichess:a']);
      expect(batch.older.first.opponent, 'Rival');
      expect(batch.older.first.opponentRating, 1612);
      expect(batch.older.first.speed, GameSpeed.bullet);
      expect(batch.older.first.userSide, Side.white);
      expect(batch.reachedFirstGame, isTrue, reason: 'Lichess sent fewer games than asked for');
      expect(batch.warning, isNull);
    });

    test('later loads take newer games oldest-first, then older ones', () async {
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        final q = request.url.queryParameters;
        if (q['sort'] == 'dateAsc') {
          return http.Response([lichessGame('n1', 5100), lichessGame('n2', 5200)].join('\n'), 200);
        }
        return http.Response([lichessGame('o1', 900), lichessGame('o2', 800)].join('\n'), 200);
      });
      final batch = await fetchUnanalyzed(
        ChessSite.lichess,
        'me',
        coverage: Coverage(newest: ms(5000), oldest: ms(1000)),
        analyzed: const {'lichess:o2'},
        want: 4,
        client: client,
      );
      expect(requests[0].queryParameters, allOf(containsPair('since', '5001'), containsPair('max', '4')));
      expect(requests[1].queryParameters, allOf(containsPair('until', '999'), containsPair('max', '2')));
      expect(batch.newer.map((g) => g.id), ['lichess:n1', 'lichess:n2']);
      expect(batch.older.map((g) => g.id), ['lichess:o1'], reason: 'o2 was already analyzed');
      expect(batch.reachedFirstGame, isFalse);
    });

    test('a failed download keeps what arrived and reports it', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) return http.Response(lichessGame('n1', 5100), 200);
        return http.Response('{"error":"boom"}', 500);
      });
      final batch = await fetchUnanalyzed(
        ChessSite.lichess,
        'me',
        coverage: Coverage(newest: ms(5000), oldest: ms(1000)),
        analyzed: const {},
        want: 4,
        client: client,
      );
      expect(batch.newer.map((g) => g.id), ['lichess:n1']);
      expect(batch.warning, contains('500'));
    });
  });

  group('Chess.com', () {
    // Three monthly archives: Jan, Feb, Mar 2026 (end_time in seconds).
    final jan = DateTime.utc(2026, 1, 15).millisecondsSinceEpoch ~/ 1000;
    final feb = DateTime.utc(2026, 2, 15).millisecondsSinceEpoch ~/ 1000;
    final mar = DateTime.utc(2026, 3, 15).millisecondsSinceEpoch ~/ 1000;
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/archives')) {
        return http.Response(
          jsonEncode({
            'archives': [
              for (final m in ['01', '02', '03']) 'https://api.chess.com/pub/player/me/games/2026/$m',
            ],
          }),
          200,
        );
      }
      final games = switch (path.split('/').last) {
        '01' => [chessComGame('j1', jan), chessComGame('j2', jan + 60)],
        '02' => [chessComGame('f1', feb), chessComGame('f2', feb + 60), chessComGame('f3', feb + 120)],
        _ => [chessComGame('m1', mar), chessComGame('m2', mar + 60)],
      };
      return http.Response(jsonEncode({'games': games}), 200);
    });

    test('first load walks back from the latest month', () async {
      final batch = await fetchUnanalyzed(
        ChessSite.chessCom,
        'Me',
        coverage: null,
        analyzed: const {},
        want: 3,
        client: client,
      );
      expect(batch.older.map((g) => g.id), ['chesscom:m2', 'chesscom:m1', 'chesscom:f3']);
      expect(batch.older.first.opponentRating, 1288);
      expect(batch.older.first.speed, GameSpeed.daily);
      expect(batch.older.first.userSide, Side.black);
      expect(batch.reachedFirstGame, isFalse);
    });

    test('later loads fill in newer games, then older ones, until history runs out', () async {
      // Already analyzed: f2 .. f3.
      final batch = await fetchUnanalyzed(
        ChessSite.chessCom,
        'me',
        coverage: Coverage(newest: ms((feb + 120) * 1000), oldest: ms((feb + 60) * 1000)),
        analyzed: const {},
        want: 10,
        client: client,
      );
      expect(batch.newer.map((g) => g.id), ['chesscom:m1', 'chesscom:m2']);
      expect(batch.older.map((g) => g.id), ['chesscom:f1', 'chesscom:j2', 'chesscom:j1']);
      expect(batch.reachedFirstGame, isTrue);
    });
  });

  test('Coverage grows to include analyzed games', () {
    final c = Coverage(newest: ms(5000), oldest: ms(1000));
    expect(c.include(ms(6000)).newest, ms(6000));
    expect(c.include(ms(500)).oldest, ms(500));
    expect(Coverage.fromJson(c.withReachedFirstGame().toJson()).reachedFirstGame, isTrue);
  });
}
