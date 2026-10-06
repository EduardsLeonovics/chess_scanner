import 'package:dartchess/dartchess.dart';

import '../board/board_setup.dart';
import '../engine/engine_service.dart';
import '../engine/uci.dart';
import '../puzzles/puzzle.dart';
import '../puzzles/puzzle_finder.dart';
import 'community_models.dart';

/// Engine depth for the solution of a posted position.
const postSearchDepth = 18;

/// [position] as a puzzle to post, solved by the engine's [best] line: a
/// forced mate (up to mate in 5) is played out in full, anything else is
/// "find the best move". Null if the line has no legal first move.
PostDraft? draftFromLine(Position position, PvLine best) {
  final side = position.turn;
  final mate = mateFor(best, side);
  final plies = mate != null && mate <= PuzzleRules.mateMax ? mate * 2 - 1 : 1;
  final solution = <String>[];
  var pos = position;
  for (final uci in best.pv.take(plies)) {
    final move = Move.parse(uci);
    if (move == null || !pos.isLegal(move)) break;
    solution.add(uci);
    pos = pos.play(move);
  }
  if (solution.isEmpty) return null;
  return PostDraft(fen: position.fen, solution: solution, bestScore: scoreOf(best, side));
}

/// One of the user's own puzzles, to post as it is.
PostDraft draftFromPuzzle(Puzzle puzzle) => PostDraft(
      fen: puzzle.fen,
      lastMove: puzzle.lastMove,
      solution: puzzle.solution,
      bestScore: puzzle.bestScore,
    );

/// Asks the engine for the solution of [position]. Throws
/// [PostPuzzleException] when it can't be a puzzle.
Future<PostDraft> draftFromPosition(Position position, EngineService engine) async {
  if (position.isGameOver) {
    throw const PostPuzzleException('The game is over in this position: there is no move to find.');
  }
  final problem = materialProblem(position.board);
  if (problem != null) {
    throw PostPuzzleException(
      'Stockfish can\'t work out a solution here ($problem). Share it as a link instead.',
    );
  }
  final EngineEval eval;
  try {
    eval = await engine.evaluate(position.fen, depth: postSearchDepth, urgent: true);
  } on StateError {
    throw const PostPuzzleException('Stockfish isn\'t available, so the solution can\'t be worked out.');
  }
  final best = eval.best;
  final draft = best == null ? null : draftFromLine(position, best);
  if (draft == null) throw const PostPuzzleException('Stockfish found no move here.');
  return draft;
}

class PostPuzzleException implements Exception {
  const PostPuzzleException(this.message);

  final String message;

  @override
  String toString() => message;
}
