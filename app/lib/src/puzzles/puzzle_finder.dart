import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';

import '../accounts/game_sources.dart';
import '../engine/engine_service.dart';
import '../engine/uci.dart';
import '../skills/opening_book.dart';
import '../skills/skill_stats.dart';
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

  /// Blunder rule: the position was balanced, within this either way...
  static const balanced = 100;

  /// ...and the user's move left them at this or worse.
  static const blunderAfter = -500;

  /// A blunder puzzle accepts any move within this of the best one: a
  /// balanced position usually has several good moves.
  static const blunderTolerance = 100;

  static const mateMin = 1;
  static const mateMax = 5;

  /// Too easy to be a puzzle: the user is this much material ahead (pawns
  /// = 1)...
  static const easyMaterialLead = 8;

  /// ...and each of the engine's top this-many moves keeps at least
  /// [easyWinning], so almost anything wins.
  static const easyLines = 5;
  static const easyWinning = 300;

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

/// What one game yields: its puzzles and the user's skill measurements
/// (null if the game was cancelled part-way).
class GameAnalysis {
  const GameAnalysis(this.puzzles, this.skills);

  final List<Puzzle> puzzles;
  final GameSkillStats? skills;
}

/// Walks [game] with the engine and returns the puzzles it contains.
Future<List<Puzzle>> findPuzzles(
  FetchedGame game,
  Evaluate evaluate, {
  bool Function()? isCancelled,
  int skipPlies = PuzzleRules.openingPlies,
}) async =>
    (await analyzeGame(game, evaluate, isCancelled: isCancelled, skipPlies: skipPlies)).puzzles;

/// Evaluates every position of [game] once, then derives both its puzzles
/// and the user's skill measurements from that single pass.
///
/// [isCancelled] is checked between engine calls.
Future<GameAnalysis> analyzeGame(
  FetchedGame game,
  Evaluate evaluate, {
  OpeningBook? book,
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
  bool cancelled() => isCancelled?.call() ?? false;

  // Pass 1: a quick look at every position (both sides to move), so each of
  // the user's moves has a score before and after.
  final scan = List<PvLine?>.filled(positions.length, null);
  // The first plies are theory and skipped, except the user's moves there
  // that leave the book: the opening skill rates those too.
  final theory = game.initialFen == kInitialFEN ? book : null;
  final early = <int>{
    if (theory != null)
      for (var i = 0; i < math.min(skipPlies, moves.length); i++)
        if (positions[i].turn == side && !theory.contains(positions[i + 1])) ...[i, i + 1],
  };
  for (final i in [...early.where((i) => i < skipPlies), for (var i = skipPlies; i < positions.length; i++) i]) {
    if (cancelled()) return const GameAnalysis([], null);
    if (positions[i].isGameOver) continue;
    final line = (await evaluate(positions[i].fen, nodes: PuzzleRules.scanNodes)).best;
    if (line != null && line.pv.isNotEmpty) scan[i] = line;
  }

  int? scoreAfter(int i) {
    final after = positions[i + 1];
    if (after.isCheckmate) return after.turn == side ? -_mateScore : _mateScore;
    if (after.isGameOver) return 0;
    final line = scan[i + 1];
    return line == null ? null : scoreOf(line, side);
  }

  final puzzles = <Puzzle>[];
  for (var i = skipPlies; i < moves.length; i++) {
    final before = positions[i];
    if (before.turn != side) continue;
    // A forced move is no puzzle.
    if (before.legalMoves.values.fold(0, (n, dests) => n + dests.size) < 2) continue;

    final quick = scan[i];
    final afterQuick = scoreAfter(i);
    if (quick == null || afterQuick == null) continue;
    final played = moves[i];
    final quickBest = legalUciMove(before, quick.pv.first);
    if (quickBest == null || quickBest == played) continue;
    final quickMate = mateFor(quick, side);
    final quickScore = scoreOf(quick, side);
    final blunder = quickMate == null &&
        quickScore.abs() <= PuzzleRules.balanced + 50 &&
        afterQuick <= PuzzleRules.blunderAfter + 100;
    if (!blunder && quickMate == null && quickScore < PuzzleRules.captureMinScore) continue;
    final promising = blunder ||
        (quickMate != null
            ? afterQuick < _mateScore - 1000 // user no longer has a forced mate
            : (quickScore >= PuzzleRules.winning && afterQuick <= PuzzleRules.thrownAway + 50) ||
                (isCapture(before, quickBest) && quickScore - afterQuick >= PuzzleRules.captureMinSwing - 50));
    if (!promising) continue;
    if (cancelled()) return const GameAnalysis([], null);

    // Pass 2: confirm with a deeper, two-line search.
    final deep = await evaluate(before.fen, multiPv: 2, depth: PuzzleRules.verifyDepth);
    final afterScore = await _deepScoreAfter(positions[i + 1], side, evaluate);
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
    if (await isTooEasy(before, side, evaluate)) continue;

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

  final skills = measureGame(
    playedAt: game.playedAt,
    speed: game.speed,
    side: side,
    positions: positions,
    moves: moves,
    scan: scan,
    scoreOf: scoreOf,
    afterScore: scoreAfter,
    mateFor: mateFor,
    book: theory,
    clocks: game.clocks,
    increment: game.increment,
  );
  return GameAnalysis(puzzles, skills);
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
  final bestMove = legalUciMove(before, best.pv.first);
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

  // Blunder: a balanced position (within ±1) that the user's move turned
  // into −5 or worse. The solution is the best move; others that keep the
  // balance are accepted too (see [PuzzleRules.blunderTolerance]).
  if (mate == null &&
      bestScore.abs() <= PuzzleRules.balanced &&
      afterScore <= PuzzleRules.blunderAfter) {
    return (PuzzleKind.blunder, [bestMove.uci], null);
  }

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

/// Whether [side], to move in [before], is so far ahead that the puzzle is
/// pointless: a big material lead and every top engine move still winning.
/// Only searches when the material lead is there.
Future<bool> isTooEasy(Position before, Side side, Evaluate evaluate) async {
  if (materialBalance(before, side) < PuzzleRules.easyMaterialLead) return false;
  final legal = before.legalMoves.values.fold(0, (n, dests) => n + dests.size);
  final want = legal < PuzzleRules.easyLines ? legal : PuzzleRules.easyLines;
  final eval = await evaluate(
    before.fen,
    multiPv: PuzzleRules.easyLines,
    depth: PuzzleRules.verifyDepth,
  );
  if (eval.lines.length < want) return false;
  return eval.lines.take(want).every((l) => scoreOf(l, side) >= PuzzleRules.easyWinning);
}

/// The user's score after their move from a deep search, or null if the
/// engine had nothing.
Future<int?> _deepScoreAfter(Position after, Side side, Evaluate evaluate) async {
  if (after.isCheckmate) return after.turn == side ? -_mateScore : _mateScore;
  if (after.isGameOver) return 0;
  final line = (await evaluate(after.fen, depth: PuzzleRules.verifyDepth)).best;
  return line == null ? null : scoreOf(line, side);
}

/// Parses and normalizes a UCI move (castling as king-takes-rook) so it can
/// be compared with moves parsed from SAN.
bool _endsInMate(Position start, List<String> line) {
  var pos = start;
  for (final uci in line) {
    final move = legalUciMove(pos, uci);
    if (move == null) return false;
    pos = pos.play(move);
  }
  return pos.isCheckmate;
}

/// Material [side] gains along the first plies of [pv], stopping once the
/// exchanges are over, so recaptures are accounted for.
int _materialGain(Position start, List<String> pv, Side side) {
  final initial = materialBalance(start, side);
  var pos = start;
  var result = initial;
  for (final uci in pv.take(6)) {
    final move = legalUciMove(pos, uci);
    if (move == null) break;
    final capture = isCapture(pos, move);
    pos = pos.play(move);
    result = materialBalance(pos, side);
    // After the opponent replies without capturing, the trade is settled.
    if (!capture && pos.turn == side) break;
  }
  return result - initial;
}
