import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';

/// One principal variation reported by the engine.
///
/// Scores are stored from White's point of view once passed through
/// [PvLine.toWhitePov]; raw UCI scores are relative to the side to move.
class PvLine {
  const PvLine({
    required this.multiPv,
    required this.depth,
    required this.pv,
    this.cp,
    this.mate,
  });

  final int multiPv;
  final int depth;

  /// Centipawns. Null when [mate] is set.
  final int? cp;

  /// Moves to mate; positive means the side the score is relative to mates.
  final int? mate;

  /// Moves in UCI notation, e.g. `e2e4`, `e7e8q`.
  final List<String> pv;

  PvLine toWhitePov({required bool whiteToMove}) => whiteToMove
      ? this
      : PvLine(
          multiPv: multiPv,
          depth: depth,
          pv: pv,
          cp: cp == null ? null : -cp!,
          mate: mate == null ? null : -mate!,
        );

  /// Human-readable score, e.g. `+0.35`, `-1.20`, `M3`, `-M2`.
  String get scoreLabel {
    if (mate != null) return mate! < 0 ? '-M${-mate!}' : 'M$mate';
    final pawns = cp! / 100;
    return '${pawns >= 0 ? '+' : ''}${pawns.toStringAsFixed(2)}';
  }

  /// Expected share of the points for White in 0..1, for the eval bar.
  /// Uses the same logistic curve as Lichess's "winning chances".
  double get whiteShare {
    if (mate != null) return mate! > 0 ? 1 : 0;
    return 1 / (1 + math.exp(-0.00368208 * cp!));
  }
}

/// Parses a UCI `info` line into a [PvLine].
///
/// Returns null for lines that carry no usable score + PV (e.g. `info string`,
/// `currmove` updates, or bound-only scores from aspiration windows).
PvLine? parseInfoLine(String line) {
  final t = line.trim().split(RegExp(r'\s+'));
  if (t.isEmpty || t.first != 'info') return null;

  int? depth;
  int multiPv = 1;
  int? cp;
  int? mate;
  List<String>? pv;

  for (var i = 1; i < t.length; i++) {
    switch (t[i]) {
      case 'depth':
        depth = int.tryParse(t[++i]);
      case 'multipv':
        multiPv = int.tryParse(t[++i]) ?? 1;
      case 'score':
        final kind = t[++i];
        final value = int.tryParse(t[++i]);
        if (kind == 'cp') cp = value;
        if (kind == 'mate') mate = value;
        if (i + 1 < t.length &&
            (t[i + 1] == 'lowerbound' || t[i + 1] == 'upperbound')) {
          return null;
        }
      case 'pv':
        pv = t.sublist(i + 1);
        i = t.length;
    }
  }

  if (depth == null || pv == null || pv.isEmpty) return null;
  if (cp == null && mate == null) return null;
  return PvLine(multiPv: multiPv, depth: depth, pv: pv, cp: cp, mate: mate);
}

/// The legal move [uci] (e.g. "e2e4") from [position], with castling as
/// king-takes-rook as dartchess expects, or null if it's not a legal move.
Move? legalUciMove(Position position, String uci) {
  final move = Move.parse(uci);
  if (move == null || !position.isLegal(move)) return null;
  return move is NormalMove ? position.normalizeMove(move) : move;
}
