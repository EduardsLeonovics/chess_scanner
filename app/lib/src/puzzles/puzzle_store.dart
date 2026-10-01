import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../accounts/accounts.dart';
import '../accounts/game_sources.dart';
import '../engine/engine_service.dart';
import '../settings/appearance.dart';
import 'puzzle.dart';
import 'puzzle_finder.dart';

/// The user's puzzles and which games have already been searched for them.
@immutable
class PuzzleLibrary {
  const PuzzleLibrary({
    this.puzzles = const [],
    this.analyzedGames = const {},
    this.coverage = const {},
  });

  /// In play order: a mix of categories, see [mixPuzzles].
  final List<Puzzle> puzzles;
  final Set<String> analyzedGames;

  /// Per account (see [accountKeyOf]): the span of games already analyzed.
  final Map<String, Coverage> coverage;

  PuzzleLibrary copyWith({
    List<Puzzle>? puzzles,
    Set<String>? analyzedGames,
    Map<String, Coverage>? coverage,
  }) =>
      PuzzleLibrary(
        puzzles: puzzles ?? this.puzzles,
        analyzedGames: analyzedGames ?? this.analyzedGames,
        coverage: coverage ?? this.coverage,
      );
}

/// Interleaves the categories (mate in 3, mate in 4, …, only move, capture,
/// mate in 3, …), newest first within each, so a session isn't all one kind.
List<Puzzle> mixPuzzles(Iterable<Puzzle> puzzles) {
  final byCategory = {
    for (final category in PuzzleCategory.values)
      category: puzzles.where((p) => p.category == category).toList()
        ..sort((a, b) => b.playedAt.compareTo(a.playedAt)),
  };
  final mixed = <Puzzle>[];
  for (var i = 0; byCategory.values.any((list) => i < list.length); i++) {
    for (final list in byCategory.values) {
      if (i < list.length) mixed.add(list[i]);
    }
  }
  return mixed;
}

final puzzleLibraryProvider =
    NotifierProvider<PuzzleLibraryNotifier, PuzzleLibrary>(PuzzleLibraryNotifier.new);

class PuzzleLibraryNotifier extends Notifier<PuzzleLibrary> {
  static const _puzzlesKey = 'puzzles.list';
  static const _gamesKey = 'puzzles.analyzedGames';
  static const _coverageKey = 'puzzles.coverage';

  @override
  PuzzleLibrary build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    var puzzles = <Puzzle>[];
    var coverage = <String, Coverage>{};
    try {
      final raw = prefs.getString(_puzzlesKey);
      if (raw != null) {
        puzzles = [
          for (final json in jsonDecode(raw) as List<dynamic>)
            Puzzle.fromJson(json as Map<String, dynamic>),
        ];
      }
      final rawCoverage = prefs.getString(_coverageKey);
      if (rawCoverage != null) {
        coverage = {
          for (final MapEntry(:key, :value) in (jsonDecode(rawCoverage) as Map<String, dynamic>).entries)
            key: Coverage.fromJson(value as Map<String, dynamic>),
        };
      }
    } catch (e) {
      debugPrint('Discarding unreadable puzzle data: $e');
    }
    return PuzzleLibrary(
      puzzles: mixPuzzles(puzzles),
      analyzedGames: (prefs.getStringList(_gamesKey) ?? const []).toSet(),
      coverage: coverage,
    );
  }

  /// Records that [game] was analyzed and found [found].
  void addGame(FetchedGame game, List<Puzzle> found) {
    final known = {for (final p in state.puzzles) p.id};
    final key = game.accountKey;
    final span = state.coverage[key];
    _save(state.copyWith(
      puzzles: mixPuzzles([...state.puzzles, ...found.where((p) => !known.contains(p.id))]),
      analyzedGames: {...state.analyzedGames, game.id},
      coverage: {
        ...state.coverage,
        key: span?.include(game.playedAt) ??
            Coverage(newest: game.playedAt, oldest: game.playedAt),
      },
    ));
  }

  /// Notes that everything back to the first game of [accountKey] is done.
  void markReachedFirstGame(String accountKey) {
    final span = state.coverage[accountKey];
    if (span == null || span.reachedFirstGame) return;
    _save(state.copyWith(coverage: {...state.coverage, accountKey: span.withReachedFirstGame()}));
  }

  /// Records the first attempt at a puzzle; later attempts don't change it.
  void recordResult(String id, PuzzleResult result) {
    final index = state.puzzles.indexWhere((p) => p.id == id);
    if (index < 0 || state.puzzles[index].result != PuzzleResult.unsolved) return;
    _save(state.copyWith(
      puzzles: [...state.puzzles]..[index] = state.puzzles[index].withResult(result),
    ));
  }

  /// Marks every puzzle unsolved again, keeping the puzzles.
  void resetProgress() => _save(state.copyWith(
        puzzles: [for (final p in state.puzzles) p.withResult(PuzzleResult.unsolved)],
      ));

  /// Deletes all puzzles and forgets which games were analyzed, so the next
  /// load starts again from the latest games.
  void deleteAll() => _save(const PuzzleLibrary());

  void _save(PuzzleLibrary library) {
    state = library;
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setString(_puzzlesKey, jsonEncode([for (final p in library.puzzles) p.toJson()]));
    prefs.setStringList(_gamesKey, library.analyzedGames.toList());
    prefs.setString(
      _coverageKey,
      jsonEncode({for (final e in library.coverage.entries) e.key: e.value.toJson()}),
    );
  }
}

/// Which categories the user wants to practise. Persisted.
final puzzleCategoriesProvider =
    NotifierProvider<PuzzleCategoriesNotifier, Set<PuzzleCategory>>(PuzzleCategoriesNotifier.new);

class PuzzleCategoriesNotifier extends Notifier<Set<PuzzleCategory>> {
  static const _key = 'puzzles.categories';

  @override
  Set<PuzzleCategory> build() {
    final saved = ref.watch(sharedPreferencesProvider).getStringList(_key);
    if (saved == null) return PuzzleCategory.values.toSet();
    final byName = PuzzleCategory.values.asNameMap();
    return {for (final name in saved) ?byName[name]};
  }

  void set(Set<PuzzleCategory> categories) {
    state = categories;
    ref.read(sharedPreferencesProvider).setStringList(_key, [for (final c in categories) c.name]);
  }
}

/// Progress of "load my games".
@immutable
class GeneratorState {
  const GeneratorState({
    this.running = false,
    this.done = 0,
    this.total = 0,
    this.found = 0,
    this.message,
    this.warning = false,
  });

  final bool running;
  final int done;
  final int total;
  final int found;

  /// What's happening, or how the last run ended. Null hides the banner.
  final String? message;

  /// [message] reports a problem (e.g. a site limiting downloads).
  final bool warning;
}

final puzzleGeneratorProvider =
    NotifierProvider<PuzzleGenerator, GeneratorState>(PuzzleGenerator.new);

/// Downloads the user's not-yet-analyzed games and searches them for puzzles.
class PuzzleGenerator extends Notifier<GeneratorState> {
  /// Games analyzed per load, over all connected accounts.
  static const gameCount = 100;

  bool _cancelled = false;

  @override
  GeneratorState build() => const GeneratorState();

  void cancel() => _cancelled = true;

  /// Hides the banner of a finished run.
  void dismiss() {
    if (!state.running) state = const GeneratorState();
  }

  Future<void> run() async {
    if (state.running) return;
    _cancelled = false;
    state = const GeneratorState(running: true, message: 'Downloading your games…');

    final accounts = ref.read(accountsProvider);
    final libraryNotifier = ref.read(puzzleLibraryProvider.notifier);
    final library = ref.read(puzzleLibraryProvider);

    // Download from each site on its own, so one failing doesn't stop the other.
    final warnings = <String>[];
    final newer = <FetchedGame>[];
    final older = <FetchedGame>[];
    final finished = <String>[];
    for (final site in ChessSite.values) {
      final username = accounts.of(site);
      if (username == null || _cancelled) continue;
      final key = accountKeyOf(site, username);
      final batch = await fetchUnanalyzed(
        site,
        username,
        coverage: library.coverage[key],
        analyzed: library.analyzedGames,
        want: gameCount,
        onStatus: (status) {
          if (state.running) state = GeneratorState(running: true, message: status);
        },
      );
      if (batch.warning case final warning?) warnings.add(warning);
      newer.addAll(batch.newer);
      older.addAll(batch.older);
      if (batch.reachedFirstGame) finished.add(key);
    }

    // Newer games oldest-first, then older games newest-first: analyzing in
    // this order keeps every account's analyzed span free of gaps.
    newer.sort((a, b) => a.playedAt.compareTo(b.playedAt));
    older.sort((a, b) => b.playedAt.compareTo(a.playedAt));
    final games = [...newer, ...older].take(gameCount).toList();

    if (games.isEmpty) {
      for (final key in finished) {
        libraryNotifier.markReachedFirstGame(key);
      }
      state = GeneratorState(
        message: warnings.isNotEmpty
            ? warnings.join(' ')
            : 'No new games to analyze — you\'re all caught up.',
        warning: warnings.isNotEmpty,
      );
      return;
    }

    var found = 0;
    var done = 0;
    try {
      final engine = ref.read(engineProvider);
      for (final game in games) {
        if (_cancelled) break;
        state = GeneratorState(
          running: true,
          done: done,
          total: games.length,
          found: found,
          message: 'Analyzing game ${done + 1} of ${games.length}',
        );
        final puzzles = await findPuzzles(game, engine.evaluate, isCancelled: () => _cancelled);
        if (_cancelled) break;
        libraryNotifier.addGame(game, puzzles);
        found += puzzles.length;
        done++;
      }
    } on StateError catch (e) {
      warnings.add(e.message);
    }

    // An account's history is exhausted only if all of its older games got analyzed.
    if (done == games.length) {
      for (final key in finished) {
        if (older.every((g) => g.accountKey != key || games.contains(g))) {
          libraryNotifier.markReachedFirstGame(key);
        }
      }
    }

    state = GeneratorState(
      done: done,
      total: games.length,
      found: found,
      warning: warnings.isNotEmpty,
      message: [
        _cancelled ? 'Stopped after $done games' : 'Analyzed $done games',
        'found $found new puzzle${found == 1 ? '' : 's'}.',
        ...warnings,
      ].join(' · '),
    );
  }
}
