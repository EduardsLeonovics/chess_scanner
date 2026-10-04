import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stockfish/stockfish.dart';

import 'uci.dart';

enum EngineStatus { starting, ready, unavailable, error }

/// Latest analysis of [fen]: one [PvLine] per MultiPV slot, best first,
/// scores from White's point of view.
class EngineEval {
  const EngineEval({required this.fen, required this.lines});

  final String fen;
  final List<PvLine> lines;

  PvLine? get best => lines.isEmpty ? null : lines.first;
  int get depth => lines.isEmpty ? 0 : lines.first.depth;
}

final engineProvider = Provider<EngineService>((ref) {
  final engine = EngineService()..start();
  ref.onDispose(engine.dispose);
  return engine;
});

/// A running UCI engine. [stdout] closes when the engine exits.
abstract interface class EngineProcess {
  Stream<String> get stdout;

  /// Throws a [StateError] if the engine is no longer running.
  void send(String command);

  void dispose();
}

typedef EngineLauncher = Future<EngineProcess> Function();

class _StockfishProcess implements EngineProcess {
  _StockfishProcess(this._sf);

  final Stockfish _sf;

  @override
  Stream<String> get stdout => _sf.stdout;

  @override
  void send(String command) => _sf.stdin = command;

  @override
  void dispose() {
    if (_sf.state.value == StockfishState.ready) _sf.dispose();
  }
}

Future<EngineProcess> _launchStockfish() async => _StockfishProcess(await stockfishAsync());

/// One `go` command. Searches with a [completer] come from [EngineService.evaluate].
class _Search {
  _Search(
    this.fen, {
    required this.multiPv,
    this.depth,
    this.nodes,
    this.movetime,
    this.completer,
    this.urgent = false,
  });

  final String fen;
  final int multiPv;
  final int? depth;
  final int? nodes;
  final int? movetime;
  final Completer<EngineEval>? completer;

  /// Someone is waiting on screen: runs before, and interrupts, other
  /// background searches.
  final bool urgent;

  bool get isBackground => completer != null;
}

/// Owns the single on-device Stockfish instance and speaks UCI to it.
///
/// Two kinds of work share it:
/// * [analyze] — live analysis for the board on screen, streamed on [evals].
///   Any running search is stopped first and its output discarded.
/// * [evaluate] — one-off background searches (puzzle generation), queued
///   and run whenever live analysis is idle. A live request preempts them;
///   the interrupted search is re-run afterwards.
///
/// If the engine exits it is restarted (a few times at most); the search it
/// was running fails with a [StateError]. If it stops answering for
/// [stallTimeout] it is asked to stop, and then treated as dead.
class EngineService {
  EngineService({
    this.multiPv = 3,
    this.depth = 24,
    EngineLauncher? launcher,
    this.stallTimeout = const Duration(seconds: 30),
  })  : _launcher = launcher,
        _checkPlatform = launcher == null;

  final int multiPv;
  final int depth;
  final Duration stallTimeout;
  final EngineLauncher? _launcher;
  final bool _checkPlatform;

  /// Restarts allowed after the engine dies, before giving up for good.
  static const maxRestarts = 3;

  final status = ValueNotifier(EngineStatus.starting);
  final _evals = StreamController<EngineEval>.broadcast();
  Stream<EngineEval> get evals => _evals.stream;

  EngineProcess? _process;
  StreamSubscription<String>? _stdoutSub;
  bool _disposed = false;
  int _restarts = 0;
  Timer? _watchdog;
  bool _stalled = false;

  _Search? _current;
  bool _stopping = false;
  _Search? _pendingLive;

  /// Urgent searches first, then the rest, each in arrival order.
  final _background = <_Search>[];
  int? _sentMultiPv;
  final _lines = <int, PvLine>{};

  Future<void> start() async {
    // The stockfish package ships native builds for Android and iOS only.
    if (_checkPlatform && (kIsWeb || !(Platform.isAndroid || Platform.isIOS))) {
      status.value = EngineStatus.unavailable;
      _failBackground(StateError('Stockfish is not available on this platform'));
      return;
    }
    await _launch();
  }

  Future<void> _launch() async {
    status.value = EngineStatus.starting;
    try {
      final process = await (_launcher ?? _launchStockfish)();
      if (_disposed) {
        process.dispose();
        return;
      }
      _process = process;
      _sentMultiPv = null;
      _stdoutSub = process.stdout.listen(_onLine, onDone: () => _onDied('Stockfish exited'));
      final threads = math.max(1, math.min(4, Platform.numberOfProcessors - 1));
      process.send('uci');
      process.send('setoption name Threads value $threads');
      process.send('setoption name Hash value 64');
      process.send('isready');
      status.value = EngineStatus.ready;
      _next();
    } catch (e) {
      debugPrint('Stockfish failed to start: $e');
      _process = null;
      if (_disposed) return;
      status.value = EngineStatus.error;
      _failBackground(StateError('Stockfish failed to start'));
    }
  }

  void analyze(String fen) {
    _pendingLive = _Search(fen, multiPv: multiPv, depth: depth);
    if (_current == null) {
      _next();
    } else {
      _stop();
    }
  }

  /// Stops live analysis without starting a new search. Background
  /// evaluations keep running.
  void stop() {
    _pendingLive = null;
    if (_current != null && !_current!.isBackground) _stop();
  }

  /// Searches [fen] to [depth], [nodes] and/or [movetime] (ms) and returns
  /// the final lines.
  ///
  /// [urgent] searches (the user is waiting) jump the queue and interrupt a
  /// running non-urgent one, which is re-run afterwards.
  ///
  /// Throws a [StateError] if the engine can't run on this device, or died
  /// during the search.
  Future<EngineEval> evaluate(
    String fen, {
    int multiPv = 1,
    int? depth,
    int? nodes,
    int? movetime,
    bool urgent = false,
  }) {
    if (status.value == EngineStatus.unavailable || status.value == EngineStatus.error) {
      return Future.error(StateError('Stockfish is not available'));
    }
    final search = _Search(
      fen,
      multiPv: multiPv,
      depth: depth,
      nodes: nodes,
      movetime: movetime,
      completer: Completer<EngineEval>(),
      urgent: urgent,
    );
    if (urgent) {
      _background.insert(_urgentCount, search);
      final current = _current;
      if (current != null && current.isBackground && !current.urgent) _stop();
    } else {
      _background.add(search);
    }
    if (_current == null) _next();
    return search.completer!.future;
  }

  int get _urgentCount {
    var n = 0;
    while (n < _background.length && _background[n].urgent) {
      n++;
    }
    return n;
  }

  void _send(String command) {
    final process = _process;
    if (process == null) return;
    try {
      process.send(command);
    } on StateError catch (e) {
      _onDied(e.message);
    }
  }

  void _stop() {
    if (_current != null && !_stopping) {
      _stopping = true;
      _send('stop');
    }
  }

  /// Starts the next search: live analysis first, then queued evaluations.
  void _next() {
    if (_process == null || _current != null || _disposed) return;
    final search = _pendingLive ?? (_background.isEmpty ? null : _background.removeAt(0));
    if (search == null) return;
    if (identical(search, _pendingLive)) _pendingLive = null;

    _current = search;
    _stopping = false;
    _lines.clear();
    if (_sentMultiPv != search.multiPv) {
      _send('setoption name MultiPV value ${search.multiPv}');
      _sentMultiPv = search.multiPv;
    }
    _send('position fen ${search.fen}');
    _send([
      'go',
      if (search.depth != null) 'depth ${search.depth}',
      if (search.nodes != null) 'nodes ${search.nodes}',
      if (search.movetime != null) 'movetime ${search.movetime}',
    ].join(' '));
    _armWatchdog();
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _stalled = false;
    if (_current == null) return;
    _watchdog = Timer(stallTimeout, _onStall);
  }

  /// No output for [stallTimeout]: ask the engine to stop; if it stays
  /// silent for another [stallTimeout], it's hung.
  void _onStall() {
    if (_current == null) return;
    if (_stalled) {
      _onDied('Stockfish stopped responding');
      return;
    }
    debugPrint('Stockfish silent for $stallTimeout, sending stop');
    _stalled = true;
    // A plain stop: the search's result still counts.
    _send('stop');
    _watchdog = Timer(stallTimeout, _onStall);
  }

  void _onLine(String line) {
    final search = _current;
    if (search == null) return;
    _armWatchdog();

    if (line.startsWith('bestmove')) {
      _watchdog?.cancel();
      final interrupted = _stopping;
      _current = null;
      _stopping = false;
      if (search.isBackground) {
        if (interrupted) {
          // Back in line behind the urgent searches that interrupted it.
          _background.insert(_urgentCount, search);
        } else {
          search.completer!.complete(EngineEval(fen: search.fen, lines: _sortedLines()));
        }
      }
      _next();
      return;
    }
    if (_stopping || !line.startsWith('info')) return;

    final parsed = parseInfoLine(line);
    if (parsed == null) return;
    final whiteToMove = search.fen.split(' ')[1] == 'w';
    _lines[parsed.multiPv] = parsed.toWhitePov(whiteToMove: whiteToMove);
    if (!search.isBackground) {
      _evals.add(EngineEval(fen: search.fen, lines: _sortedLines()));
    }
  }

  List<PvLine> _sortedLines() {
    final keys = _lines.keys.toList()..sort();
    return [for (final k in keys) _lines[k]!];
  }

  /// The engine exited or hung. Fails the search it was running (live
  /// analysis is simply asked for again) and restarts it.
  void _onDied(String reason) {
    if (_process == null || _disposed) return;
    debugPrint('Engine died: $reason');
    _watchdog?.cancel();
    _stdoutSub?.cancel();
    _stdoutSub = null;
    final process = _process!;
    _process = null;
    try {
      process.dispose();
    } catch (_) {
      // Already gone.
    }
    final current = _current;
    _current = null;
    _stopping = false;
    if (current != null) {
      if (current.isBackground) {
        current.completer!.completeError(StateError(reason));
      } else {
        _pendingLive ??= current;
      }
    }
    if (_restarts >= maxRestarts) {
      status.value = EngineStatus.error;
      _failBackground(StateError(reason));
      return;
    }
    _restarts++;
    _launch();
  }

  void _failBackground(Object error) {
    while (_background.isNotEmpty) {
      _background.removeAt(0).completer!.completeError(error);
    }
  }

  void dispose() {
    _disposed = true;
    _watchdog?.cancel();
    _stdoutSub?.cancel();
    try {
      _process?.dispose();
    } catch (_) {
      // Already gone.
    }
    _process = null;
    final current = _current;
    if (current != null && current.isBackground) {
      current.completer!.completeError(StateError('Engine disposed'));
    }
    _failBackground(StateError('Engine disposed'));
    _evals.close();
    status.dispose();
  }
}
