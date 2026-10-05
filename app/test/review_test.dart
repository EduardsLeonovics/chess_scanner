import 'dart:async';

import 'package:chess_scanner/src/accounts/accounts.dart';
import 'package:chess_scanner/src/accounts/game_sources.dart';
import 'package:chess_scanner/src/engine/engine_service.dart';
import 'package:chess_scanner/src/engine/uci.dart';
import 'package:chess_scanner/src/puzzles/puzzle.dart';
import 'package:chess_scanner/src/puzzles/puzzle_finder.dart';
import 'package:chess_scanner/src/puzzles/puzzle_store.dart';
import 'package:chess_scanner/src/puzzles/review.dart';
import 'package:chess_scanner/src/settings/appearance.dart';
import 'package:chess_scanner/src/skills/skill_stats.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'puzzle_store_test.dart' show puzzle;

final _now = DateTime(2026, 10, 4, 12);

FetchedGame _game(String id) => FetchedGame(
      id: id,
      site: ChessSite.lichess,
      account: 'me',
      url: '',
      userSide: Side.white,
      opponent: 'rival',
      playedAt: DateTime(2026, 9, int.parse(id.split(':').last)),
      sanMoves: const ['e4', 'e5'],
      speed: GameSpeed.blitz,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('scheduling', () {
    test('each solve in a row pushes a puzzle further out', () {
      var p = puzzle('a');
      final gaps = <Duration>[];
      for (var i = 0; i < 6; i++) {
        p = reviewed(p, PuzzleResult.solved, _now);
        gaps.add(p.dueAt!.difference(_now));
      }
      expect(gaps, [
        const Duration(days: 1),
        const Duration(days: 3),
        const Duration(days: 7),
        const Duration(days: 21),
        const Duration(days: 60),
        const Duration(days: 60),
      ]);
      expect(p.attempts, 6);
      expect(p.streak, 6);
    });

    test('a failure starts over and comes back soon', () {
      final p = reviewed(reviewed(puzzle('a'), PuzzleResult.solved, _now), PuzzleResult.failed, _now);
      expect(p.streak, 0);
      expect(p.result, PuzzleResult.failed);
      expect(p.dueAt, _now.add(ReviewRules.retryAfter));
    });

    test('a skip only pushes a puzzle back a little', () {
      final p = skipped(puzzle('a'), _now);
      expect(p.attempts, 0);
      expect(p.lastSeen, _now);
      expect(p.dueAt, _now.add(ReviewRules.skipFor));
      final solved = reviewed(puzzle('b'), PuzzleResult.solved, _now);
      expect(skipped(solved, _now).dueAt, solved.dueAt, reason: 'not brought forward');
    });
  });

  group('pickNext', () {
    test('due puzzles first, most overdue first, then new ones in order', () {
      final fresh1 = puzzle('fresh1');
      final fresh2 = puzzle('fresh2');
      final later = reviewed(puzzle('later'), PuzzleResult.solved, _now);
      final due = reviewed(puzzle('due'), PuzzleResult.failed, _now.subtract(const Duration(hours: 1)));
      final overdue = reviewed(puzzle('overdue'), PuzzleResult.failed, _now.subtract(const Duration(days: 1)));
      final all = [fresh1, later, due, fresh2, overdue];
      expect(pickNext(all, _now)!.id, 'overdue');
      expect(pickNext([fresh1, later, due, fresh2], _now)!.id, 'due');
      expect(pickNext([fresh1, later, fresh2], _now)!.id, 'fresh1');
      expect(pickNext([later], _now)!.id, 'later', reason: 'nothing else: the soonest due');
    });

    test('never the same puzzle twice in a row, unless it is the only one', () {
      final a = reviewed(puzzle('a'), PuzzleResult.failed, _now.subtract(const Duration(days: 1)));
      final b = reviewed(puzzle('b'), PuzzleResult.solved, _now);
      expect(pickNext([a, b], _now, previous: 'a')!.id, 'b');
      expect(pickNext([a], _now, previous: 'a')!.id, 'a');
      expect(pickNext([], _now), isNull);
    });

    test('cycles through all puzzles instead of looping on two', () {
      var puzzles = [for (var i = 0; i < 12; i++) puzzle('p$i')];
      final shown = <String>{};
      String? previous;
      for (var i = 0; i < 12; i++) {
        final next = pickNext(puzzles, _now, previous: previous)!;
        shown.add(next.id);
        previous = next.id;
        puzzles = [for (final p in puzzles) p.id == next.id ? reviewed(p, PuzzleResult.solved, _now) : p];
      }
      expect(shown, hasLength(12));
    });
  });

  test('puzzles saved before spaced repetition get a schedule', () {
    final json = puzzle('a').toJson()
      ..remove('attempts')
      ..remove('streak')
      ..remove('lastSeen')
      ..remove('dueAt');
    final solved = Puzzle.fromJson({...json, 'result': 'solved'});
    expect(solved.streak, 1);
    expect(solved.dueAt!.isAfter(DateTime.now()), isTrue);
    final failed = Puzzle.fromJson({...json, 'result': 'failed'});
    expect(failed.dueAt!.isAfter(DateTime.now()), isFalse);
    final fresh = Puzzle.fromJson({...json, 'result': 'unsolved'});
    expect(fresh.lastSeen, isNull);
  });

  test('a review survives saving', () {
    final p = reviewed(puzzle('a'), PuzzleResult.solved, _now);
    final back = Puzzle.fromJson(p.toJson());
    expect(back.dueAt, p.dueAt);
    expect(back.lastSeen, p.lastSeen);
    expect(back.streak, 1);
    expect(back.attempts, 1);
  });

  group('store', () {
    late ProviderContainer container;

    Future<void> open(Map<String, Object> saved, {List<Override> overrides = const []}) async {
      SharedPreferences.setMockInitialValues(saved);
      final prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...overrides,
      ]);
      addTearDown(container.dispose);
    }

    test('categories chosen before mate in 1–2 existed keep their choice; new ones start on', () async {
      await open({'puzzles.categories': ['mateIn3', 'capture']});
      expect(container.read(puzzleCategoriesProvider), {
        PuzzleCategory.mateIn1,
        PuzzleCategory.mateIn2,
        PuzzleCategory.mateIn3,
        PuzzleCategory.capture,
        PuzzleCategory.blunder,
      });
    });

    test('the queue and game count survive a restart', () async {
      await open({});
      final notifier = container.read(puzzleLibraryProvider.notifier);
      notifier.setQueue(GameQueue(games: [_game('lichess:1'), _game('lichess:2'), _game('lichess:3')]));
      notifier.addGame(_game('lichess:1'), const []);
      final library = container.read(puzzleLibraryProvider);
      expect(library.totalGames, 3);
      expect(library.queuedGames, 2);
      expect(library.gameCountLabel, 'Games in database: 3 (1 analyzed, 2 waiting)');

      final prefs = container.read(sharedPreferencesProvider);
      final restarted = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      addTearDown(restarted.dispose);
      expect(restarted.read(puzzleLibraryProvider).queue!.games.map((g) => g.id), ['lichess:2', 'lichess:3']);
    });

    test('a game that throws is skipped and the rest are still analyzed', () async {
      final engine = EngineService(launcher: () async => _SilentProcess());
      await open({}, overrides: [engineProvider.overrideWithValue(engine)]);
      await engine.start();
      addTearDown(engine.dispose);
      container.read(puzzleLibraryProvider.notifier).setQueue(
            GameQueue(games: [_game('lichess:1'), _game('lichess:2'), _game('lichess:3')]),
          );
      final generator = container.read(puzzleGeneratorProvider.notifier);
      generator.analyze = (game, evaluate, book, isCancelled) async {
        if (game.id == 'lichess:2') throw const FormatException('bad game');
        return GameAnalysis(const [], _stats);
      };
      await generator.run();

      final library = container.read(puzzleLibraryProvider);
      expect(library.analyzedGames, {'lichess:1', 'lichess:2', 'lichess:3'});
      expect(library.queue, isNull);
      final state = container.read(puzzleGeneratorProvider);
      expect(state.running, isFalse);
      expect(state.message, contains('1 game couldn\'t be analyzed'));
    });
  });

  group('isTooEasy', () {
    // White: queen, two rooks and king against a lone king: +19.
    const crushing = '6k1/8/8/8/8/8/1Q6/R3K2R w - - 0 1';
    // Even material.
    const even = 'r3k2r/8/8/8/8/8/8/R3K2R w - - 0 1';

    Evaluate engine(List<int> scores) => (fen, {multiPv = 1, depth, nodes}) async => EngineEval(
          fen: fen,
          lines: [
            for (var i = 0; i < scores.length && i < multiPv; i++)
              PvLine(multiPv: i + 1, depth: 16, pv: const ['a1a2'], cp: scores[i]),
          ],
        );

    Position pos(String fen) => Chess.fromSetup(Setup.parseFen(fen));

    test('far ahead with every top move winning is too easy', () async {
      expect(await isTooEasy(pos(crushing), Side.white, engine([900, 800, 700, 600, 500])), isTrue);
    });

    test('far ahead but only one move wins is a real puzzle', () async {
      expect(await isTooEasy(pos(crushing), Side.white, engine([900, 800, 700, 600, 100])), isFalse);
    });

    test('even material never asks the engine', () async {
      var asked = false;
      Future<EngineEval> spy(String fen, {int multiPv = 1, int? depth, int? nodes}) async {
        asked = true;
        return EngineEval(fen: fen, lines: const []);
      }

      expect(await isTooEasy(pos(even), Side.white, spy), isFalse);
      expect(asked, isFalse);
    });
  });
}

final _stats = GameSkillStats(playedAt: DateTime(2026));

/// Never answers: the tests above don't search.
class _SilentProcess implements EngineProcess {
  final _out = StreamController<String>();

  @override
  Stream<String> get stdout => _out.stream;

  @override
  void send(String command) {}

  @override
  void dispose() => _out.close();
}
