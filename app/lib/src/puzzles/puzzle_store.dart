import 'dart:async';
import 'dart:convert';

import 'package:dartchess/dartchess.dart' show Chess, Move, Position, Setup, kInitialFEN;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../accounts/accounts.dart';
import '../accounts/game_sources.dart';
import '../diagnostics/crash_log.dart';
import '../engine/engine_service.dart';
import '../openings/repertoire.dart';
import '../settings/appearance.dart';
import '../skills/opening_book.dart';
import '../skills/skill_stats.dart';
import 'background_work.dart';
import 'puzzle.dart';
import 'puzzle_finder.dart';
import 'review.dart';

/// The user's puzzles and which games have already been searched for them.
@immutable
class PuzzleLibrary {
  const PuzzleLibrary({
    this.puzzles = const [],
    this.analyzedGames = const {},
    this.coverage = const {},
    this.gameStats = const {},
    this.openingGames = const {},
    this.queue,
  });

  /// In play order: a mix of categories, see [mixPuzzles].
  final List<Puzzle> puzzles;
  final Set<String> analyzedGames;

  /// Per account (see [accountKeyOf]): the span of games already analyzed.
  final Map<String, Coverage> coverage;

  /// Per analyzed game: the user's skill measurements (see [SkillProfile]).
  final Map<String, GameSkillStats> gameStats;

  /// Per analyzed standard game: its first moves, for the opening study.
  final Map<String, RepertoireGame> openingGames;

  /// Downloaded games still waiting to be analyzed, or null if none: a run
  /// that was interrupted (app killed, engine died, Stop) resumes from here.
  final GameQueue? queue;

  /// Games still in [queue].
  int get queuedGames => queue?.games.where((g) => !analyzedGames.contains(g.id)).length ?? 0;

  /// Every game downloaded so far: analyzed, plus waiting in [queue].
  int get totalGames => analyzedGames.length + queuedGames;

  /// E.g. "Games in database: 240 (200 analyzed, 40 waiting)".
  String get gameCountLabel {
    final waiting = queuedGames;
    return 'Games in database: $totalGames'
        '${waiting == 0 ? '' : ' (${analyzedGames.length} analyzed, $waiting waiting)'}';
  }

  PuzzleLibrary copyWith({
    List<Puzzle>? puzzles,
    Set<String>? analyzedGames,
    Map<String, Coverage>? coverage,
    Map<String, GameSkillStats>? gameStats,
    Map<String, RepertoireGame>? openingGames,
    GameQueue? Function()? queue,
  }) =>
      PuzzleLibrary(
        puzzles: puzzles ?? this.puzzles,
        analyzedGames: analyzedGames ?? this.analyzedGames,
        coverage: coverage ?? this.coverage,
        gameStats: gameStats ?? this.gameStats,
        openingGames: openingGames ?? this.openingGames,
        queue: queue == null ? this.queue : queue(),
      );
}

/// Games of one load, in the order to analyze them (see [PuzzleGenerator]).
@immutable
class GameQueue {
  const GameQueue({required this.games, this.exhausted = const {}});

  final List<FetchedGame> games;

  /// Accounts whose whole history is in [games]: once all of them are
  /// analyzed, there's nothing older left to fetch.
  final Set<String> exhausted;

  Map<String, dynamic> toJson() => {
        'games': [for (final g in games) g.toJson()],
        'exhausted': exhausted.toList(),
      };

  factory GameQueue.fromJson(Map<String, dynamic> json) => GameQueue(
        games: [
          for (final g in json['games'] as List<dynamic>) FetchedGame.fromJson(g as Map<String, dynamic>),
        ],
        exhausted: (json['exhausted'] as List<dynamic>).cast<String>().toSet(),
      );
}

/// Interleaves the categories (mate in 1, mate in 2, …, only move, capture,
/// blunder, mate in 1, …), newest first within each, so a session isn't all one kind.
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
  static const _statsKey = 'skills.games';
  static const _openingsKey = 'openings.games';
  static const _queueKey = 'puzzles.queue';
  static const _versionKey = 'puzzles.dataVersion';

  /// 2: games are analyzed for skills and openings too. 3: theory length
  /// counts transpositions back into the book. 4: time controls are kept,
  /// combinations count once, the end of the book isn't leaving theory, and
  /// blunders are measured in win chance. 5: games yield "avoid the
  /// blunder" puzzles. Games analyzed under an older version are forgotten
  /// and re-analyzed. Puzzles and the opening games (just the moves played,
  /// which no analysis change affects) are kept.
  static const _dataVersion = 5;

  /// What's in storage, part by part (compared by identity), so a save only
  /// rewrites the parts that changed.
  PuzzleLibrary? _saved;

  /// A save waiting to happen, see [addGame]'s `deferSave`.
  Timer? _saveTimer;
  static const _saveDelay = Duration(seconds: 3);

  /// Kept from [build]: the dispose hook may not use `ref`.
  late SharedPreferences _prefs;

  @override
  PuzzleLibrary build() {
    ref.onDispose(() {
      // Write what's still pending; the state is gone by now, so use the
      // copy the timer would have saved.
      final pending = _pending;
      _saveTimer?.cancel();
      _saveTimer = null;
      if (pending != null) _write(pending);
    });
    final prefs = _prefs = ref.watch(sharedPreferencesProvider);
    if ((prefs.getInt(_versionKey) ?? 1) < _dataVersion) {
      prefs.remove(_gamesKey);
      prefs.remove(_coverageKey);
      prefs.remove(_statsKey);
      prefs.setInt(_versionKey, _dataVersion);
    }
    var puzzles = <Puzzle>[];
    var coverage = <String, Coverage>{};
    var gameStats = <String, GameSkillStats>{};
    var openingGames = <String, RepertoireGame>{};
    GameQueue? queue;
    // Each part on its own, so one unreadable part doesn't lose the others.
    void read(String key, void Function(Object? json) parse) {
      final raw = prefs.getString(key);
      if (raw == null) return;
      try {
        parse(jsonDecode(raw));
      } catch (e) {
        debugPrint('Discarding unreadable $key: $e');
      }
    }

    read(_puzzlesKey, (json) {
      puzzles = [for (final p in json as List<dynamic>) Puzzle.fromJson(p as Map<String, dynamic>)];
    });
    read(_coverageKey, (json) {
      coverage = {
        for (final MapEntry(:key, :value) in (json as Map<String, dynamic>).entries)
          key: Coverage.fromJson(value as Map<String, dynamic>),
      };
    });
    read(_statsKey, (json) {
      gameStats = {
        for (final MapEntry(:key, :value) in (json as Map<String, dynamic>).entries)
          key: GameSkillStats.fromJson(value as Map<String, dynamic>),
      };
    });
    read(_openingsKey, (json) {
      final games = [
        for (final g in json as List<dynamic>) RepertoireGame.fromJson(g as Map<String, dynamic>),
      ];
      openingGames = {for (final g in games) g.id: g};
    });
    read(_queueKey, (json) => queue = GameQueue.fromJson(json as Map<String, dynamic>));
    final library = PuzzleLibrary(
      puzzles: mixPuzzles(puzzles),
      analyzedGames: (prefs.getStringList(_gamesKey) ?? const []).toSet(),
      coverage: coverage,
      gameStats: gameStats,
      openingGames: openingGames,
      queue: queue,
    );
    _saved = library;
    return library;
  }

  /// Remembers the games about to be analyzed, replacing any earlier queue.
  void setQueue(GameQueue? queue) => _save(state.copyWith(queue: () => queue));

  /// Records that [game] was analyzed and found [found] and [skills], and
  /// drops the queue once all its games are analyzed. A game whose analysis failed is recorded with
  /// nothing found, so it isn't downloaded again.
  ///
  /// With [deferSave] (game analysis, one game after another), the library
  /// is written a few seconds later, together with the games that follow,
  /// instead of after every game; call [flush] when the run ends.
  void addGame(FetchedGame game, List<Puzzle> found, [GameSkillStats? skills, bool deferSave = false]) {
    final known = found.isEmpty ? const <String>{} : {for (final p in state.puzzles) p.id};
    final added = [for (final p in found) if (!known.contains(p.id)) p];
    final key = game.accountKey;
    final span = state.coverage[key];
    final analyzed = {...state.analyzedGames, game.id};
    // Everything that reads the queue skips analyzed games, so it's only
    // dropped once all of them are done: rewriting it after every game
    // re-saved up to hundreds of games' moves each time.
    final queue = state.queue;
    final queueDone = queue != null && queue.games.every((g) => analyzed.contains(g.id));
    _save(state.copyWith(
      // Unchanged (and so not saved again) when the game had no new puzzles.
      puzzles: added.isEmpty ? null : mixPuzzles([...state.puzzles, ...added]),
      analyzedGames: analyzed,
      coverage: {
        ...state.coverage,
        key: span?.include(game.playedAt) ??
            Coverage(newest: game.playedAt, oldest: game.playedAt),
      },
      gameStats: skills == null ? null : {...state.gameStats, game.id: skills},
      openingGames: game.initialFen != kInitialFEN
          ? null
          : {
              ...state.openingGames,
              game.id: RepertoireGame(
                id: game.id,
                side: game.userSide,
                sanMoves: game.sanMoves.take(repertoirePlies).toList(),
                playedAt: game.playedAt,
                speed: game.speed,
              ),
            },
      queue: queueDone ? () => null : null,
    ), defer: deferSave);
  }

  /// Notes that everything back to the first game of [accountKey] is done.
  void markReachedFirstGame(String accountKey) {
    final span = state.coverage[accountKey];
    if (span == null || span.reachedFirstGame) return;
    _save(state.copyWith(coverage: {...state.coverage, accountKey: span.withReachedFirstGame()}));
  }

  /// Records an attempt at a puzzle that ended in [outcome] (solved or
  /// failed), and when it's due again (see [reviewed]).
  void recordResult(String id, PuzzleResult outcome, {DateTime? now}) =>
      _update(id, (p) => reviewed(p, outcome, now ?? DateTime.now()));

  /// The user moved on from a puzzle without attempting it.
  void skip(String id, {DateTime? now}) => _update(id, (p) => skipped(p, now ?? DateTime.now()));

  void _update(String id, Puzzle Function(Puzzle) change) {
    final index = state.puzzles.indexWhere((p) => p.id == id);
    if (index < 0) return;
    _save(state.copyWith(
      puzzles: [...state.puzzles]..[index] = change(state.puzzles[index]),
    ));
  }

  /// Removes the puzzles with these ids.
  void removePuzzles(Set<String> ids) {
    if (ids.isEmpty) return;
    _save(state.copyWith(puzzles: [for (final p in state.puzzles) if (!ids.contains(p.id)) p]));
  }

  /// Marks every puzzle as never attempted, keeping the puzzles.
  void resetProgress() => _save(state.copyWith(
        puzzles: [for (final p in state.puzzles) p.withoutReview()],
      ));

  /// Deletes all puzzles and forgets which games were analyzed, so the next
  /// load starts again from the latest games.
  void deleteAll() => _save(const PuzzleLibrary());

  /// The library waiting for a deferred save.
  PuzzleLibrary? _pending;

  void _save(PuzzleLibrary library, {bool defer = false}) {
    state = library;
    if (defer) {
      _pending = library;
      _saveTimer ??= Timer(_saveDelay, flush);
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = null;
    _pending = null;
    _write(library);
  }

  /// Writes a deferred save now.
  void flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    final pending = _pending;
    _pending = null;
    if (pending != null) _write(pending);
  }

  /// Saves the parts of [library] that changed since the last write. The
  /// game data grows with every analyzed game, so rewriting all of it each
  /// time made long runs slow and could run the phone out of memory.
  void _write(PuzzleLibrary library) {
    final old = _saved;
    _saved = library;
    bool changed(Object? Function(PuzzleLibrary l) part) => old == null || !identical(part(old), part(library));
    final prefs = _prefs;
    if (changed((l) => l.puzzles)) {
      prefs.setString(_puzzlesKey, jsonEncode([for (final p in library.puzzles) p.toJson()]));
    }
    if (changed((l) => l.analyzedGames)) {
      prefs.setStringList(_gamesKey, library.analyzedGames.toList());
    }
    if (changed((l) => l.coverage)) {
      prefs.setString(
        _coverageKey,
        jsonEncode({for (final e in library.coverage.entries) e.key: e.value.toJson()}),
      );
    }
    if (changed((l) => l.openingGames)) {
      prefs.setString(
        _openingsKey,
        jsonEncode([for (final g in library.openingGames.values) g.toJson()]),
      );
    }
    if (changed((l) => l.gameStats)) {
      prefs.setString(
        _statsKey,
        jsonEncode({for (final e in library.gameStats.entries) e.key: e.value.toJson()}),
      );
    }
    if (changed((l) => l.queue)) {
      final queue = library.queue;
      if (queue == null) {
        prefs.remove(_queueKey);
      } else {
        prefs.setString(_queueKey, jsonEncode(queue.toJson()));
      }
    }
  }
}

/// Which categories the user wants to practise. Persisted as the ones
/// turned off, so categories added in an update start out on.
final puzzleCategoriesProvider =
    NotifierProvider<PuzzleCategoriesNotifier, Set<PuzzleCategory>>(PuzzleCategoriesNotifier.new);

class PuzzleCategoriesNotifier extends Notifier<Set<PuzzleCategory>> {
  static const _offKey = 'puzzles.categoriesOff';

  /// Before mate in 1–2 existed: the categories turned on.
  static const _legacyKey = 'puzzles.categories';
  static const _legacyCategories = {
    PuzzleCategory.mateIn3,
    PuzzleCategory.mateIn4,
    PuzzleCategory.mateIn5,
    PuzzleCategory.onlyMove,
    PuzzleCategory.capture,
  };

  @override
  Set<PuzzleCategory> build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final byName = PuzzleCategory.values.asNameMap();
    final legacy = prefs.getStringList(_legacyKey);
    if (legacy != null) {
      final on = {for (final name in legacy) ?byName[name]};
      prefs.setStringList(_offKey, [for (final c in _legacyCategories.difference(on)) c.name]);
      prefs.remove(_legacyKey);
    }
    final off = {for (final name in prefs.getStringList(_offKey) ?? const <String>[]) ?byName[name]};
    return PuzzleCategory.values.toSet().difference(off);
  }

  void set(Set<PuzzleCategory> categories) {
    state = categories;
    ref.read(sharedPreferencesProvider).setStringList(_offKey, [
      for (final c in PuzzleCategory.values)
        if (!categories.contains(c)) c.name,
    ]);
  }
}

/// How many games one "load my games" downloads and analyzes. Persisted.
/// More games take longer (roughly 5–15 seconds each, depending on the
/// phone); whatever isn't finished continues on the next load.
final gamesPerLoadProvider = NotifierProvider<GamesPerLoadNotifier, int>(GamesPerLoadNotifier.new);

class GamesPerLoadNotifier extends Notifier<int> {
  static const _key = 'puzzles.gamesPerLoad';
  static const choices = [50, 100, 200, 500];
  static const defaultCount = 100;

  @override
  int build() {
    final saved = ref.watch(sharedPreferencesProvider).getInt(_key);
    return choices.contains(saved) ? saved! : defaultCount;
  }

  void set(int count) {
    state = count;
    ref.read(sharedPreferencesProvider).setInt(_key, count);
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
///
/// The downloaded games are saved as a [GameQueue] first and taken off it
/// one by one as they're analyzed, so a run cut short (app killed, Stop,
/// engine trouble) continues where it left off: see [resume].
class PuzzleGenerator extends Notifier<GeneratorState> {
  /// Games downloaded per load, over all connected accounts (a setting).
  int get gameCount => ref.read(gamesPerLoadProvider);

  bool _cancelled = false;

  /// Analyzes one game. Replaceable for tests.
  @visibleForTesting
  Future<GameAnalysis> Function(FetchedGame game, Evaluate evaluate, OpeningBook? book, bool Function() isCancelled)
      analyze = (game, evaluate, book, isCancelled) =>
          analyzeGame(game, evaluate, book: book, isCancelled: isCancelled);

  @override
  GeneratorState build() => const GeneratorState();

  void cancel() => _cancelled = true;

  /// Hides the banner of a finished run.
  void dismiss() {
    if (!state.running) state = const GeneratorState();
  }

  /// Analyzes the games left over from an interrupted run, if any, else
  /// downloads up to [gameCount] new ones (newer than any analyzed so far,
  /// then older) and analyzes those.
  Future<void> run() async {
    if (state.running) return;
    _cancelled = false;
    state = const GeneratorState(running: true, message: 'Downloading your games…');
    try {
      await _run();
    } catch (e, stack) {
      _log(e, stack);
      state = GeneratorState(message: 'Analysis stopped: $e', warning: true);
    } finally {
      ref.read(puzzleLibraryProvider.notifier).flush();
      if (state.running) state = const GeneratorState();
      await BackgroundWork.stop();
    }
  }

  /// Games an interrupted run left to analyze, if it can be continued.
  int get resumable => ref.read(accountsProvider).any ? ref.read(puzzleLibraryProvider).queuedGames : 0;

  void _log(Object error, StackTrace stack) {
    debugPrint('Puzzle generator: $error\n$stack');
    try {
      ref.read(crashLogProvider).record(error, stack, source: 'puzzle generator');
    } catch (_) {
      // No crash log (tests).
    }
  }

  Future<void> _run() async {
    final libraryNotifier = ref.read(puzzleLibraryProvider.notifier);
    final warnings = <String>[];
    var queue = ref.read(puzzleLibraryProvider).queue;
    if (queue == null || ref.read(puzzleLibraryProvider).queuedGames == 0) {
      final (downloaded, downloadWarnings) = await _download();
      warnings.addAll(downloadWarnings);
      queue = downloaded;
      if (queue.games.isEmpty) {
        libraryNotifier.setQueue(null);
        for (final key in queue.exhausted) {
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
      libraryNotifier.setQueue(queue);
    }

    final analyzed = ref.read(puzzleLibraryProvider).analyzedGames;
    final games = [for (final g in queue.games) if (!analyzed.contains(g.id)) g];
    final engine = ref.read(engineProvider);
    await _sweepTooEasy(engine);

    await BackgroundWork.start('Starting…', onStop: cancel);
    var found = 0;
    var done = 0;
    var failed = 0;
    for (final game in games) {
      if (_cancelled) break;
      final message = 'Analyzing game ${done + 1} of ${games.length}';
      state = GeneratorState(
        running: true,
        done: done,
        total: games.length,
        found: found,
        message: message,
      );
      BackgroundWork.update('$message · $found puzzle${found == 1 ? '' : 's'} found');

      final analysis = await _analyze(game, engine);
      if (_cancelled) break;
      if (analysis == null) {
        final status = engine.status.value;
        if (status == EngineStatus.error || status == EngineStatus.unavailable) {
          warnings.add('The chess engine stopped working. Restart the app to continue.');
          break;
        }
        // This game can't be analyzed; don't let it block the rest.
        failed++;
        libraryNotifier.addGame(game, const [], null, true);
      } else {
        libraryNotifier.addGame(game, analysis.puzzles, analysis.skills, true);
        found += analysis.puzzles.length;
      }
      done++;
    }

    libraryNotifier.flush();
    // An account's history is exhausted only once all of its older games got analyzed.
    if (ref.read(puzzleLibraryProvider).queue == null) {
      for (final key in queue.exhausted) {
        libraryNotifier.markReachedFirstGame(key);
      }
    }
    final left = games.length - done;
    state = GeneratorState(
      done: done,
      total: games.length,
      found: found,
      warning: warnings.isNotEmpty || failed > 0,
      message: [
        _cancelled ? 'Stopped after $done games' : 'Analyzed $done games',
        'found $found new puzzle${found == 1 ? '' : 's'}',
        if (failed > 0) '$failed game${failed == 1 ? '' : 's'} couldn\'t be analyzed',
        if (left > 0) '$left left, load again to continue',
        ...warnings,
      ].join(' · '),
    );
  }

  static const _easySweptKey = 'puzzles.easySwept';

  /// Once: drops puzzles found before the too-easy rule ([isTooEasy]) that
  /// break it.
  Future<void> _sweepTooEasy(EngineService engine) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs.getBool(_easySweptKey) ?? false) return;
    final easy = <String>{};
    try {
      for (final puzzle in ref.read(puzzleLibraryProvider).puzzles) {
        if (_cancelled) return;
        Position pos = Chess.fromSetup(Setup.parseFen(puzzle.fen));
        if (puzzle.lastMove case final uci?) {
          final move = Move.parse(uci);
          if (move == null || !pos.isLegal(move)) continue;
          pos = pos.play(move);
        }
        if (await isTooEasy(pos, puzzle.userSide, engine.evaluate)) easy.add(puzzle.id);
      }
    } on StateError {
      return; // Engine trouble: try again next run.
    }
    ref.read(puzzleLibraryProvider.notifier).removePuzzles(easy);
    prefs.setBool(_easySweptKey, true);
  }

  /// One game, retried once if the engine died during it (it restarts
  /// itself). Null if it couldn't be analyzed or the run was cancelled.
  Future<GameAnalysis?> _analyze(FetchedGame game, EngineService engine) async {
    OpeningBook? book;
    try {
      book = await ref.read(openingBookProvider.future);
    } catch (e) {
      debugPrint('Opening book unavailable: $e');
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final analysis = await analyze(game, engine.evaluate, book, () => _cancelled);
        return analysis.skills == null ? null : analysis;
      } on StateError catch (e, stack) {
        if (attempt == 1) _log(e, stack);
      } catch (e, stack) {
        _log(e, stack);
        return null;
      }
    }
    return null;
  }

  /// New games from every connected account, in the order to analyze them.
  Future<(GameQueue, List<String>)> _download() async {
    final accounts = ref.read(accountsProvider);
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
    final ids = {for (final g in games) g.id};
    return (
      GameQueue(
        games: games,
        exhausted: {
          for (final key in finished)
            if (older.every((g) => g.accountKey != key || ids.contains(g.id))) key,
        },
      ),
      warnings,
    );
  }
}
