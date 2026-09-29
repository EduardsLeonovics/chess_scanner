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

/// Owns the single on-device Stockfish instance and speaks UCI to it.
///
/// Call [analyze] whenever the position changes; any running search is
/// stopped first, and output from the stopped search is discarded.
class EngineService {
  EngineService({this.multiPv = 3, this.depth = 24});

  final int multiPv;
  final int depth;

  final status = ValueNotifier(EngineStatus.starting);
  final _evals = StreamController<EngineEval>.broadcast();
  Stream<EngineEval> get evals => _evals.stream;

  Stockfish? _stockfish;
  StreamSubscription<String>? _stdoutSub;

  bool _searching = false;
  bool _stopping = false;
  String? _pendingFen;
  String? _currentFen;
  final _lines = <int, PvLine>{};

  Future<void> start() async {
    // The stockfish package ships native builds for Android and iOS only.
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      status.value = EngineStatus.unavailable;
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
      sf.stdin = 'setoption name MultiPV value $multiPv';
      sf.stdin = 'isready';
      status.value = EngineStatus.ready;
      final pending = _pendingFen;
      _pendingFen = null;
      if (pending != null) _go(pending);
    } catch (e) {
      debugPrint('Stockfish failed to start: $e');
      status.value = EngineStatus.error;
    }
  }

  void analyze(String fen) {
    if (_stockfish == null || _searching) {
      _pendingFen = fen;
      _stop();
      return;
    }
    _go(fen);
  }

  /// Stops analysis without starting a new search.
  void stop() {
    _pendingFen = null;
    _stop();
  }

  void _stop() {
    if (_searching && !_stopping) {
      _stopping = true;
      _stockfish!.stdin = 'stop';
    }
  }

  void _go(String fen) {
    _currentFen = fen;
    _lines.clear();
    _searching = true;
    _stopping = false;
    _stockfish!
      ..stdin = 'position fen $fen'
      ..stdin = 'go depth $depth';
  }

  void _onLine(String line) {
    if (line.startsWith('bestmove')) {
      _searching = false;
      _stopping = false;
      final pending = _pendingFen;
      _pendingFen = null;
      if (pending != null) _go(pending);
      return;
    }
    if (!_searching || _stopping || !line.startsWith('info')) return;

    final parsed = parseInfoLine(line);
    final fen = _currentFen;
    if (parsed == null || fen == null) return;
    final whiteToMove = fen.split(' ')[1] == 'w';
    _lines[parsed.multiPv] = parsed.toWhitePov(whiteToMove: whiteToMove);
    final sorted = _lines.keys.toList()..sort();
    _evals.add(EngineEval(fen: fen, lines: [for (final k in sorted) _lines[k]!]));
  }

  void dispose() {
    _stdoutSub?.cancel();
    final sf = _stockfish;
    if (sf != null && sf.state.value == StockfishState.ready) sf.dispose();
    _evals.close();
    status.dispose();
  }
}
