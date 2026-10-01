import 'dart:async';
import 'dart:collection';
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

/// One `go` command. Searches with a [completer] come from [EngineService.evaluate].
class _Search {
  _Search(
    this.fen, {
    required this.multiPv,
    this.depth,
    this.nodes,
    this.completer,
    this.urgent = false,
  });

  final String fen;
  final int multiPv;
  final int? depth;
  final int? nodes;
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
class EngineService {
  EngineService({this.multiPv = 3, this.depth = 24});

  final int multiPv;
  final int depth;

  final status = ValueNotifier(EngineStatus.starting);
  final _evals = StreamController<EngineEval>.broadcast();
  Stream<EngineEval> get evals => _evals.stream;

  Stockfish? _stockfish;
  StreamSubscription<String>? _stdoutSub;

  _Search? _current;
  bool _stopping = false;
  _Search? _pendingLive;
  final _background = Queue<_Search>();
  int? _sentMultiPv;
  final _lines = <int, PvLine>{};

  Future<void> start() async {
    // The stockfish package ships native builds for Android and iOS only.
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      status.value = EngineStatus.unavailable;
      _failBackground(StateError('Stockfish is not available on this platform'));
      return;
    }
    try {
      final sf = await stockfishAsync();
      _stockfish = sf;
      _stdoutSub = sf.stdout.listen(_onLine);
      final threads = math.max(1, math.min(4, Platform.numberOfProcessors - 1));
      sf.stdin = 'uci';
      sf.stdin = 'setoption name Threads value $threads';
      sf.stdin = 'setoption name Hash value 64';
      sf.stdin = 'isready';
      status.value = EngineStatus.ready;
      _next();
    } catch (e) {
      debugPrint('Stockfish failed to start: $e');
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

  /// Searches [fen] to [depth] and/or [nodes] and returns the final lines.
  ///
  /// [urgent] searches (the user is waiting) jump the queue and interrupt a
  /// running non-urgent one, which is re-run afterwards.
  ///
  /// Throws a [StateError] if the engine can't run on this device.
  Future<EngineEval> evaluate(
    String fen, {
    int multiPv = 1,
    int? depth,
    int? nodes,
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
      completer: Completer<EngineEval>(),
      urgent: urgent,
    );
    if (urgent) {
      _background.addFirst(search);
      final current = _current;
      if (current != null && current.isBackground && !current.urgent) _stop();
    } else {
      _background.add(search);
    }
    if (_current == null) _next();
    return search.completer!.future;
  }

  void _stop() {
    if (_current != null && !_stopping) {
      _stopping = true;
      _stockfish!.stdin = 'stop';
    }
  }

  /// Starts the next search: live analysis first, then queued evaluations.
  void _next() {
    if (_stockfish == null || _current != null) return;
    final search = _pendingLive ?? (_background.isEmpty ? null : _background.removeFirst());
    if (search == null) return;
    if (identical(search, _pendingLive)) _pendingLive = null;

    _current = search;
    _stopping = false;
    _lines.clear();
    final sf = _stockfish!;
    if (_sentMultiPv != search.multiPv) {
      sf.stdin = 'setoption name MultiPV value ${search.multiPv}';
      _sentMultiPv = search.multiPv;
    }
    sf.stdin = 'position fen ${search.fen}';
    sf.stdin = [
      'go',
      if (search.depth != null) 'depth ${search.depth}',
      if (search.nodes != null) 'nodes ${search.nodes}',
    ].join(' ');
  }

  void _onLine(String line) {
    final search = _current;
    if (search == null) return;

    if (line.startsWith('bestmove')) {
      final interrupted = _stopping;
      _current = null;
      _stopping = false;
      if (search.isBackground) {
        if (interrupted) {
          _background.addFirst(search);
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

  void _failBackground(Object error) {
    while (_background.isNotEmpty) {
      _background.removeFirst().completer!.completeError(error);
    }
  }

  void dispose() {
    _stdoutSub?.cancel();
    final sf = _stockfish;
    if (sf != null && sf.state.value == StockfishState.ready) sf.dispose();
    final current = _current;
    if (current != null && current.isBackground) {
      current.completer!.completeError(StateError('Engine disposed'));
    }
    _failBackground(StateError('Engine disposed'));
    _evals.close();
    status.dispose();
  }
}
