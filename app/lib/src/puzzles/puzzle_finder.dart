import 'package:dartchess/dartchess.dart';

import '../accounts/game_sources.dart';
import '../engine/engine_service.dart';
import '../engine/uci.dart';
import '../sound/move_sounds.dart' show isCapture;
import 'puzzle.dart';

/// [EngineService.evaluate], injectable for tests.
typedef Evaluate = Future<EngineEval> Function(
  String fen, {
  int multiPv,
  int? depth,
  int? nodes,
});

/// Thresholds, in centipawns from the user's side.
abstract final class PuzzleRules {
  /// "Winning" for the only-move rule: +2.
  static const winning = 200;

  /// The user's move must leave the eval at or below this: 0.
  static const thrownAway = 0;

  /// The second-best move must be at or below this for the best one to be
  /// the only move that keeps the initiative.
  static const secondBestMax = 100;

  /// Winning-capture rule: the capture keeps at least this...
  static const captureMinScore = 150;

  /// ...and the user's move loses at least this much versus the capture...
  static const captureMinSwing = 200;

  /// ...ending up no better than this (no longer clearly winning).
  static const captureMaxAfter = 100;

  /// The capture line must win at least this much material (pawns = 1).
  static const captureMinMaterial = 2;

  static const mateMin = 3;
  static const mateMax = 5;

  /// Plies skipped at the start of each game (opening theory).
  static const openingPlies = 8;

  /// Cheap first pass over every position, then a deep check of candidates.
  static const scanNodes = 60000;
  static const verifyDepth = 16;
}

const _mateScore = 100000;

/// A [PvLine] as one comparable number from [side]'s point of view: mates
/// map just below/above ±[_mateScore], shorter mates being more extreme.
int scoreOf(PvLine line, Side side) {
  final sign = side == Side.white ? 1 : -1;
  final mate = line.mate;
  if (mate != null) {
    final m = mate * sign;
    return m > 0 ? _mateScore - m * 100 : -_mateScore - m * 100;
  }
  return line.cp! * sign;
}

/// Mate distance for [side] in [line] when [side] is the one mating.
int? mateFor(PvLine line, Side side) {
  final mate = line.mate;
  if (mate == null) return null;
  final m = side == Side.white ? mate : -mate;
  return m > 0 ? m : null;
}

/// Walks [game] with the engine and returns the puzzles it contains.
///
/// [isCancelled] is checked between engine calls.
Future<List<Puzzle>> findPuzzles(
  FetchedGame game,
  Evaluate evaluate, {
  bool Function()? isCancelled,
  int skipPlies = PuzzleRules.openingPlies,
}) async {
  final side = game.userSide;
  final positions = <Position>[Chess.fromSetup(Setup.parseFen(game.initialFen))];
  final moves = <Move>[];
  final sans = <String>[];
  for (final san in game.sanMoves) {
    final move = positions.last.parseSan(san);
    if (move == null) break;
    moves.add(move);
    sans.add(san);
    positions.add(positions.last.play(move));
  }

  final puzzles = <Puzzle>[];
  for (var i = skipPlies; i < moves.length; i++) {
    final before = positions[i];
    if (before.turn != side) continue;
    if (isCancelled?.call() ?? false) break;
    // A forced move is no puzzle.
    if (before.legalMoves.values.fold(0, (n, dests) => n + dests.size) < 2) continue;

    // Pass 1: a quick look to rule out the vast majority of moves.
    final quick = (await evaluate(before.fen, nodes: PuzzleRules.scanNodes)).best;
    if (quick == null) continue;
    final played = moves[i];
    final quickBest = _parse(before, quick.pv.first);
    if (quickBest == null || quickBest == played) continue;
    final quickMate = mateFor(quick, side);
    final quickScore = scoreOf(quick, side);
    if (quickMate == null && quickScore < PuzzleRules.captureMinScore) continue;

    final after = positions[i + 1];
    final afterQuick = await _scoreAfter(after, side, evaluate, nodes: PuzzleRules.scanNodes);
    if (afterQuick == null) continue;
    final promising = quickMate != null
        ? afterQuick < _mateScore - 1000 // user no longer has a forced mate
        : (quickScore >= PuzzleRules.winning && afterQuick <= PuzzleRules.thrownAway + 50) ||
            (isCapture(before, quickBest) && quickScore - afterQuick >= PuzzleRules.captureMinSwing - 50);
    if (!promising) continue;
    if (isCancelled?.call() ?? false) break;

    // Pass 2: confirm with a deeper, two-line search.
    final deep = await evaluate(before.fen, multiPv: 2, depth: PuzzleRules.verifyDepth);
    final afterScore = await _scoreAfter(after, side, evaluate, depth: PuzzleRules.verifyDepth);
    final best = deep.best;
    if (best == null || afterScore == null) continue;
    final second = deep.lines.length > 1 ? deep.lines[1] : null;
    final puzzle = classify(
      before: before,
      played: played,
      best: best,
      second: second,
      afterScore: afterScore,
      side: side,
    );
    if (puzzle == null) continue;

    final (kind, solution, mateIn) = puzzle;
    final hasLead = i > 0;
    puzzles.add(Puzzle(
      id: '${game.id}#$i',
      kind: kind,
      fen: hasLead ? positions[i - 1].fen : before.fen,
      lastMove: hasLead ? moves[i - 1].uci : null,
      solution: solution,
      userSide: side,
      playedSan: sans[i],
      bestScore: scoreOf(best, side),
      mateIn: mateIn,
      gameId: game.id,
      site: game.site,
      gameUrl: game.url,
      opponent: game.opponent,
      opponentRating: game.opponentRating,
      playedAt: game.playedAt,
      moveNumber: before.fullmoves,
    ));
  }
  return puzzles;
}

/// Applies the puzzle rules to one position. Returns the kind, solution
/// (UCI, user's move first) and mate distance, or null if it's no puzzle.
///
/// [best] and [second] are the engine's top two lines in [before], with
/// White-POV scores; [afterScore] is the user's score after [played].
(PuzzleKind, List<String>, int?)? classify({
  required Position before,
  required Move played,
  required PvLine best,
  required PvLine? second,
  required int afterScore,
  required Side side,
}) {
  final bestMove = _parse(before, best.pv.first);
  if (bestMove == null || bestMove == played) return null;
  final bestScore = scoreOf(best, side);
  final mate = mateFor(best, side);
  final stillMating = afterScore >= _mateScore - 1000;

  // Missed mate in 3–5. The whole mating line is the solution.
  if (mate != null && mate >= PuzzleRules.mateMin && mate <= PuzzleRules.mateMax) {
    if (stillMating) return null;
    final line = best.pv.take(mate * 2 - 1).toList();
    if (!_endsInMate(before, line)) return null;
    return (PuzzleKind.mate, line, mate);
  }
  if (mate != null && mate < PuzzleRules.mateMin) return null;

  // Missed winning capture: the capture is the best move and wins material,
  // and not playing it swung the eval to no longer winning.
  if (isCapture(before, bestMove)) {
    final swing = bestScore - afterScore;
    if (bestScore >= PuzzleRules.captureMinScore &&
        swing >= PuzzleRules.captureMinSwing &&
        afterScore <= PuzzleRules.captureMaxAfter &&
        _materialGain(before, best.pv, side) >= PuzzleRules.captureMinMaterial) {
      return (PuzzleKind.capture, [bestMove.uci], null);
    }
    return null;
  }

  // Missed only move: +2 or better, a quiet move, every other move gives
  // the edge away, and the user's move dropped the eval to 0 or worse.
  if (bestScore >= PuzzleRules.winning &&
      afterScore <= PuzzleRules.thrownAway &&
      (second == null || scoreOf(second, side) <= PuzzleRules.secondBestMax)) {
    return (PuzzleKind.onlyMove, [bestMove.uci], null);
  }
  return null;
}

/// The user's score after their move, or null if the engine had nothing.
Future<int?> _scoreAfter(
  Position after,
  Side side,
  Evaluate evaluate, {
  int? nodes,
  int? depth,
}) async {
  if (after.isCheckmate) return after.turn == side ? -_mateScore : _mateScore;
  if (after.isGameOver) return 0;
  final line = (await evaluate(after.fen, nodes: nodes, depth: depth)).best;
  return line == null ? null : scoreOf(line, side);
}

/// Parses and normalizes a UCI move (castling as king-takes-rook) so it can
/// be compared with moves parsed from SAN.
Move? _parse(Position position, String uci) {
  final move = Move.parse(uci);
  if (move == null || !position.isLegal(move)) return null;
  return move is NormalMove ? position.normalizeMove(move) : move;
}

bool _endsInMate(Position start, List<String> line) {
  var pos = start;
  for (final uci in line) {
    final move = _parse(pos, uci);
    if (move == null) return false;
    pos = pos.play(move);
  }
  return pos.isCheckmate;
}

const _values = {Role.pawn: 1, Role.knight: 3, Role.bishop: 3, Role.rook: 5, Role.queen: 9};

int _material(Position pos, Side side) {
  var total = 0;
  for (final (_, piece) in pos.board.pieces) {
    final value = _values[piece.role] ?? 0;
    total += piece.color == side ? value : -value;
  }
  return total;
}

/// Material [side] gains along the first plies of [pv], stopping once the
/// exchanges are over, so recaptures are accounted for.
int _materialGain(Position start, List<String> pv, Side side) {
  final initial = _material(start, side);
  var pos = start;
  var result = initial;
  for (final uci in pv.take(6)) {
    final move = _parse(pos, uci);
    if (move == null) break;
    final capture = isCapture(pos, move);
    pos = pos.play(move);
    result = _material(pos, side);
    // After the opponent replies without capturing, the trade is settled.
    if (!capture && pos.turn == side) break;
  }
  return result - initial;
}
