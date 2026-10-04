import 'package:chess_scanner/src/accounts/accounts.dart';
import 'package:chess_scanner/src/accounts/game_sources.dart';
import 'package:chess_scanner/src/puzzles/puzzle.dart';
import 'package:chess_scanner/src/puzzles/puzzle_store.dart';
import 'package:chess_scanner/src/settings/appearance.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Puzzle puzzle(String id) => Puzzle(
      id: id,
      kind: PuzzleKind.onlyMove,
      fen: kInitialFEN,
      solution: const ['e2e4'],
      userSide: Side.white,
      playedSan: 'a3',
      bestScore: 300,
      gameId: 'g',
      site: ChessSite.lichess,
      gameUrl: '',
      opponent: 'rival',
      opponentRating: 1500,
      playedAt: DateTime(2026),
      moveNumber: 1,
    );

void main() {
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
  });

  tearDown(() => container.dispose());

  test('reset progress keeps puzzles but marks them unsolved', () {
    final notifier = container.read(puzzleLibraryProvider.notifier);
    notifier.addGame(gameAt(DateTime(2026)), [puzzle('a'), puzzle('b')]);
    notifier.recordResult('a', PuzzleResult.solved);
    notifier.recordResult('b', PuzzleResult.failed);
    notifier.resetProgress();
    final library = container.read(puzzleLibraryProvider);
    expect(library.puzzles, hasLength(2));
    expect(library.puzzles.every((p) => p.result == PuzzleResult.unsolved), isTrue);
    expect(library.puzzles.first.opponentRating, 1500, reason: 'other fields survive');
  });

  test('delete all forgets puzzles, analyzed games and coverage', () {
    final notifier = container.read(puzzleLibraryProvider.notifier);
    notifier.addGame(gameAt(DateTime(2026)), [puzzle('a')]);
    notifier.deleteAll();
    final library = container.read(puzzleLibraryProvider);
    expect(library.puzzles, isEmpty);
    expect(library.analyzedGames, isEmpty);
    expect(library.coverage, isEmpty);
  });

  /// A fresh store over the same saved data, as after restarting the app.
  PuzzleLibrary reopen() {
    final prefs = container.read(sharedPreferencesProvider);
    final restarted = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(restarted.dispose);
    return restarted.read(puzzleLibraryProvider);
  }

  test('everything loaded is still there after a restart', () {
    container.read(puzzleLibraryProvider.notifier).addGame(gameAt(DateTime(2026)), [puzzle('a')]);
    final library = reopen();
    expect(library.puzzles, hasLength(1));
    expect(library.analyzedGames, {'lichess:g'});
    expect(library.openingGames.keys, ['lichess:g']);
  });

  test('an analysis upgrade re-analyzes games but keeps puzzles and openings', () {
    container.read(puzzleLibraryProvider.notifier).addGame(gameAt(DateTime(2026)), [puzzle('a')]);
    container.read(sharedPreferencesProvider).setInt('puzzles.dataVersion', 1);
    final library = reopen();
    expect(library.analyzedGames, isEmpty);
    expect(library.puzzles, hasLength(1));
    expect(library.openingGames.keys, ['lichess:g']);
  });

  test('one unreadable part of the saved data does not lose the rest', () {
    container.read(puzzleLibraryProvider.notifier).addGame(gameAt(DateTime(2026)), [puzzle('a')]);
    container.read(sharedPreferencesProvider).setString('puzzles.list', '[{"broken": true}]');
    final library = reopen();
    expect(library.puzzles, isEmpty);
    expect(library.openingGames.keys, ['lichess:g']);
    expect(library.coverage, isNotEmpty);
  });
}

FetchedGame gameAt(DateTime playedAt) => FetchedGame(
      id: 'lichess:g',
      site: ChessSite.lichess,
      account: 'me',
      url: '',
      userSide: Side.white,
      opponent: 'rival',
      playedAt: playedAt,
      sanMoves: const [],
    );
