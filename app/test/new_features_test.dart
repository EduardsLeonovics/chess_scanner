import 'dart:convert';

import 'package:chess_scanner/src/accounts/accounts.dart';
import 'package:chess_scanner/src/accounts/game_sources.dart';
import 'package:chess_scanner/src/analysis/eval_bar.dart';
import 'package:chess_scanner/src/diagnostics/crash_log.dart';
import 'package:chess_scanner/src/engine/uci.dart';
import 'package:chess_scanner/src/puzzles/puzzle_store.dart';
import 'package:chess_scanner/src/settings/appearance.dart';
import 'package:chess_scanner/src/skills/skill_stats.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

PvLine cp(int value) => PvLine(multiPv: 1, depth: 20, pv: const ['e2e4'], cp: value);

void main() {
  group('eval bar label', () {
    test('level, ahead, behind and mates', () {
      expect(evalBarLabel(cp(0)), '0.0');
      expect(evalBarLabel(cp(3)), '0.0');
      expect(evalBarLabel(cp(500)), '+5.0');
      expect(evalBarLabel(cp(-130)), '-1.3');
      expect(evalBarLabel(const PvLine(multiPv: 1, depth: 9, pv: ['e2e4'], mate: 3)), 'M3');
      expect(evalBarLabel(const PvLine(multiPv: 1, depth: 9, pv: ['e2e4'], mate: -2)), '-M2');
    });

    testWidgets('shows the number on the bar', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: EvalBar(line: cp(500)))));
      expect(find.text('+5.0'), findsOneWidget);
    });
  });

  group('thinking time', () {
    List<Position> positions(int plies) {
      final moves = ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6', 'Ba4', 'Nf6'];
      final out = <Position>[Chess.initial];
      for (final san in moves.take(plies)) {
        out.add(out.last.play(out.last.parseSan(san)!));
      }
      return out;
    }

    test('measures each move from the clock, skipping the first', () {
      // White: 60.0 -> 58.0 -> 55.0 -> 50.0 (2 s increment), Black untouched.
      final clocks = [6000, 6000, 5800, 6000, 5500, 6000, 5000, 6000];
      final (moves, seconds) = thinkingTimes(
        side: Side.white,
        positions: positions(8),
        clocks: clocks,
        increment: 2,
      );
      expect(moves[GamePhase.opening.index], 3);
      // (60-58+2) + (58-55+2) + (55-50+2) = 4 + 5 + 7.
      expect(seconds[GamePhase.opening.index], closeTo(16, 0.001));
    });

    test('no clock, no times', () {
      final (moves, _) = thinkingTimes(side: Side.white, positions: positions(8), clocks: null, increment: 0);
      expect(moves, [0, 0, 0]);
    });

    test('stats keep the times and the profile averages them', () {
      final stats = GameSkillStats(
        playedAt: DateTime(2026),
        timedMoves: const [4, 10, 0],
        thinkingTime: const [8, 50, 0],
      );
      final reloaded = GameSkillStats.fromJson(jsonDecode(jsonEncode(stats.toJson())) as Map<String, dynamic>);
      final profile = TimeProfile.from([reloaded, GameSkillStats(playedAt: DateTime(2026))]);
      expect(profile.games, 1);
      expect(profile.averageIn(GamePhase.opening), 2);
      expect(profile.averageIn(GamePhase.middlegame), 5);
      expect(profile.averageIn(GamePhase.endgame), isNull);
      expect(profile.average, closeTo(58 / 14, 0.001));
    });
  });

  test('Chess.com clocks and increment are read from the PGN', () async {
    final end = DateTime.utc(2026, 3, 15).millisecondsSinceEpoch ~/ 1000;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/archives')) {
        return http.Response(jsonEncode({'archives': ['https://api.chess.com/pub/player/me/games/2026/03']}), 200);
      }
      return http.Response(
        jsonEncode({
          'games': [
            {
              'uuid': 'c1',
              'url': 'https://www.chess.com/game/live/c1',
              'rules': 'chess',
              'time_class': 'blitz',
              'time_control': '180+2',
              'end_time': end,
              'pgn': '[Event "Live"]\n\n'
                  '1. e4 {[%clk 0:03:00]} 1... e5 {[%clk 0:03:00]} 2. Nf3 {[%clk 0:02:58.5]} '
                  '2... Nc6 {[%clk 0:02:59]} 3. Bb5 {[%clk 0:02:55]} 3... a6 {[%clk 0:02:57]} '
                  '4. Ba4 {[%clk 0:02:50]} 4... Nf6 {[%clk 0:02:50]} 5. O-O {[%clk 0:02:49]} '
                  '5... Be7 {[%clk 0:02:45]} *',
              'white': {'username': 'Me', 'rating': 1300},
              'black': {'username': 'Rival', 'rating': 1288},
            },
          ],
        }),
        200,
      );
    });
    final batch = await fetchUnanalyzed(
      ChessSite.chessCom,
      'Me',
      coverage: null,
      analyzed: const {},
      want: 5,
      client: client,
    );
    final game = batch.older.single;
    expect(game.increment, 2);
    expect(game.clocks, hasLength(10));
    expect(game.clocks![2], 17850);
    final reloaded = FetchedGame.fromJson(jsonDecode(jsonEncode(game.toJson())) as Map<String, dynamic>);
    expect(reloaded.clocks, game.clocks);
    expect(reloaded.increment, 2);
  });

  group('crash reports', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('send uploads every report, then deletes them', () async {
      final uploaded = <Map<String, dynamic>>[];
      final log = CrashLog(prefs, uploader: (rows) async => uploaded.addAll(rows))
        ..record(StateError('a'), null)
        ..record(StateError('b'), null);
      expect(await log.send(), isTrue);
      expect(uploaded.map((r) => r['error']), [contains('a'), contains('b')]);
      expect(uploaded.first.keys, containsAll(['app_version', 'platform', 'source', 'stack', 'happened_at']));
      expect(log.reports, isEmpty);
      expect(CrashLog(prefs).reports, isEmpty);
    });

    test('a failed upload keeps the reports', () async {
      final log = CrashLog(prefs, uploader: (_) async => throw Exception('offline'))..record(StateError('a'), null);
      await expectLater(log.send(), throwsException);
      expect(log.reports, hasLength(1));
    });

    test('without an uploader, send says so', () async {
      final log = CrashLog(prefs)..record(StateError('a'), null);
      expect(await log.send(), isFalse);
      expect(log.reports, hasLength(1));
    });
  });

  group('library saves', () {
    late ProviderContainer container;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    });

    tearDown(() => container.dispose());

    FetchedGame game(String id) => FetchedGame(
          id: id,
          site: ChessSite.lichess,
          account: 'me',
          url: '',
          userSide: Side.white,
          opponent: 'rival',
          playedAt: DateTime(2026),
          sanMoves: const [],
        );

    test('deferred saves land on flush', () {
      final notifier = container.read(puzzleLibraryProvider.notifier);
      notifier.addGame(game('lichess:1'), const [], null, true);
      notifier.addGame(game('lichess:2'), const [], null, true);
      expect(prefs.getStringList('puzzles.analyzedGames'), isNull);
      notifier.flush();
      expect(prefs.getStringList('puzzles.analyzedGames'), unorderedEquals(['lichess:1', 'lichess:2']));
    });

    test('deferred saves are written when the store goes away', () {
      container.read(puzzleLibraryProvider.notifier).addGame(game('lichess:1'), const [], null, true);
      container.dispose();
      expect(prefs.getStringList('puzzles.analyzedGames'), ['lichess:1']);
      container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    });

    test('games per load is a remembered choice', () {
      expect(container.read(gamesPerLoadProvider), 100);
      container.read(gamesPerLoadProvider.notifier).set(200);
      final restarted = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      addTearDown(restarted.dispose);
      expect(restarted.read(gamesPerLoadProvider), 200);
    });
  });

  test('the background colour is remembered', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    expect(Appearance.fromPrefs(prefs).background, Appearance.defaultBackground);
    await const Appearance(background: Color(0xFF112233)).saveTo(prefs);
    expect(Appearance.fromPrefs(prefs).background, const Color(0xFF112233));
  });
}
