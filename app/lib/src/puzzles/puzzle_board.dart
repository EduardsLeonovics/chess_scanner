import 'dart:async';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analysis/analysis_page.dart';
import '../community/post_puzzle.dart';
import '../community/share_choice.dart';
import '../engine/engine_service.dart';
import '../settings/appearance.dart';
import '../sound/move_sounds.dart';
import 'puzzle.dart';
import 'puzzle_finder.dart';
import 'puzzle_store.dart';

enum _Phase { intro, yourMove, checking, correct, wrong, solved, revealed }

/// Plays one puzzle: shows the opponent's move, then lets the user find
/// the solution. Moves other than the stored solution are checked with
/// the engine, so an equally good move (e.g. a different mate) also counts.
class PuzzleBoard extends ConsumerStatefulWidget {
  const PuzzleBoard({
    super.key,
    required this.puzzle,
    required this.boardSize,
    required this.onNext,
  });

  final Puzzle puzzle;
  final double boardSize;

  /// Moves on; `attempted` is false for a skip (no move made, no solution shown).
  final void Function(bool attempted) onNext;

  @override
  ConsumerState<PuzzleBoard> createState() => _PuzzleBoardState();
}

class _PuzzleBoardState extends ConsumerState<PuzzleBoard> {
  late Position _pos;
  Move? _lastMove;
  late List<String> _solution;
  int _step = 0;
  _Phase _phase = _Phase.intro;
  bool _failed = false;

  /// The outcome went to the library: once per showing.
  bool _recorded = false;

  /// Position to go back to after a wrong move.
  (Position, Move?)? _undo;
  late final ChessboardController _controller;

  /// Bumped on every user action so stale delayed moves are dropped.
  int _generation = 0;

  Puzzle get _puzzle => widget.puzzle;
  Side get _side => _puzzle.userSide;

  @override
  void initState() {
    super.initState();
    _pos = Chess.fromSetup(Setup.parseFen(_puzzle.fen));
    _solution = _puzzle.solution;
    _controller = ChessboardController(game: _gameData());
    final lead = _puzzle.lastMove;
    if (lead == null) {
      _phase = _Phase.yourMove;
      _controller.updatePosition(_gameData(), animate: false);
    } else {
      _later(const Duration(milliseconds: 600), () {
        _apply(_parse(_pos, lead)!);
        setState(() => _phase = _Phase.yourMove);
        _controller.updatePosition(_gameData());
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    _controller.dispose();
    super.dispose();
  }

  GameData _gameData() => GameData(
        fen: _pos.fen,
        playerSide: _phase == _Phase.yourMove
            ? (_side == Side.white ? PlayerSide.white : PlayerSide.black)
            : PlayerSide.none,
        sideToMove: _pos.turn,
        validMoves: makeLegalMoves(_pos),
        lastMove: _lastMove,
        kingSquareInCheck: _pos.isCheck ? _pos.board.kingOf(_pos.turn) : null,
      );

  void _later(Duration delay, VoidCallback action) {
    final generation = _generation;
    Future.delayed(delay, () {
      if (mounted && generation == _generation) action();
    });
  }

  Move? _parse(Position pos, String uci) {
    final move = Move.parse(uci);
    if (move == null || !pos.isLegal(move)) return null;
    return move is NormalMove ? pos.normalizeMove(move) : move;
  }

  void _apply(Move move) {
    playMoveSound(ref, _pos, move);
    _pos = _pos.play(move);
    _lastMove = move;
  }

  void _refresh({bool animate = true}) {
    setState(() {});
    _controller.updatePosition(_gameData(), animate: animate);
  }

  Future<void> _onUserMove(Move raw) async {
    if (_phase != _Phase.yourMove || !_pos.isLegal(raw)) return;
    final move = raw is NormalMove ? _pos.normalizeMove(raw) : raw;
    final expected = _parse(_pos, _solution[_step]);
    final before = _pos;
    final beforeLast = _lastMove;
    _generation++;
    _apply(move);

    if (move == expected || _pos.isCheckmate) {
      _step++;
      _phase = _Phase.correct;
      _refresh();
      _advance();
      return;
    }

    _phase = _Phase.checking;
    _refresh();
    if (await _acceptAlternative(move)) {
      if (!mounted) return;
      _phase = _Phase.correct;
      _refresh();
      _advance();
      return;
    }
    if (!mounted) return;
    _fail();
    _undo = (before, beforeLast);
    setState(() => _phase = _Phase.wrong);
    _later(const Duration(milliseconds: 800), () {
      _restore();
      _phase = _Phase.yourMove;
      _refresh(animate: false);
    });
  }

  /// Whether [move] (already on the board) is as good as the solution. For
  /// mates, the rest of the solution becomes the engine's mating line.
  Future<bool> _acceptAlternative(Move move) async {
    final EngineEval eval;
    try {
      eval = await ref.read(engineProvider).evaluate(_pos.fen, depth: 16, urgent: true);
    } on StateError {
      return false;
    }
    final best = eval.best;
    if (best == null) return false;
    if (_puzzle.kind == PuzzleKind.mate) {
      final userMovesLeft = (_solution.length - _step + 1) ~/ 2;
      final mate = mateFor(best, _side);
      if (mate == null || mate > userMovesLeft - 1) return false;
      _solution = [..._solution.take(_step), move.uci, ...best.pv];
      _step++;
      return true;
    }
    final tolerance = _puzzle.kind == PuzzleKind.blunder ? PuzzleRules.blunderTolerance : 60;
    if (scoreOf(best, _side) >= _puzzle.bestScore - tolerance) {
      _step = _solution.length;
      return true;
    }
    return false;
  }

  /// After a correct user move: finish, or play the opponent's reply.
  void _advance() {
    if (_step >= _solution.length || _pos.isGameOver) {
      _finish(_Phase.solved);
      return;
    }
    _later(const Duration(milliseconds: 450), () {
      final reply = _parse(_pos, _solution[_step]);
      if (reply == null) {
        _finish(_Phase.solved);
        return;
      }
      _apply(reply);
      _step++;
      _phase = _step >= _solution.length ? _Phase.solved : _Phase.yourMove;
      if (_phase == _Phase.solved) {
        playCorrectSound(ref);
        _record();
      }
      _refresh();
    });
  }

  void _finish(_Phase phase) {
    if (phase == _Phase.solved) playCorrectSound(ref);
    _phase = phase;
    _record();
    _refresh();
  }

  void _fail() {
    _failed = true;
    _recordOnce(PuzzleResult.failed);
  }

  void _record() {
    if (!_failed) _recordOnce(PuzzleResult.solved);
  }

  void _recordOnce(PuzzleResult outcome) {
    if (_recorded) return;
    _recorded = true;
    ref.read(puzzleLibraryProvider.notifier).recordResult(_puzzle.id, outcome);
  }

  void _restore() {
    final undo = _undo;
    if (undo == null) return;
    _pos = undo.$1;
    _lastMove = undo.$2;
    _undo = null;
  }

  void _showSolution() {
    _fail();
    _generation++;
    _restore();
    setState(() => _phase = _Phase.revealed);
    _controller.updatePosition(_gameData());
    void step() {
      if (_step >= _solution.length) return;
      final move = _parse(_pos, _solution[_step]);
      if (move == null) return;
      _apply(move);
      _step++;
      _refresh();
      _later(const Duration(milliseconds: 800), step);
    }

    _later(const Duration(milliseconds: 300), step);
  }

  /// The position the user solves (after the opponent's lead-in move).
  Position _puzzlePosition() {
    final start = Chess.fromSetup(Setup.parseFen(_puzzle.fen));
    final lead = _puzzle.lastMove == null ? null : _parse(start, _puzzle.lastMove!);
    return lead == null ? start : start.play(lead);
  }

  /// Opens the puzzle on the analysis board, solution ready to step
  /// through, with the engine's lines for every position.
  void _analyze() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AnalysisPage(
        initialFen: _puzzlePosition().fen,
        initialMoves: _solution,
        orientation: _side,
        title: 'Puzzle analysis',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appearance = ref.watch(appearanceProvider);
    final pieceAssets = ref.watch(pieceAssetsProvider).value ?? appearance.pieceSet.assets;
    final done = _phase == _Phase.solved || _phase == _Phase.revealed;
    final rating = _puzzle.opponentRating;

    // Only feedback is shown; while it's the user's turn the board speaks for itself.
    final (String? feedback, Color? color) = switch (_phase) {
      _Phase.intro || _Phase.yourMove => (null, null),
      _Phase.checking => ('Checking your move…', null),
      _Phase.correct => ('Correct!', const Color(0xFF4CAF50)),
      _Phase.wrong => ('Not the move. Try again.', theme.colorScheme.error),
      _Phase.solved => (_failed ? 'Solved on a retry.' : 'Solved!', const Color(0xFF4CAF50)),
      _Phase.revealed => ('Here\'s the solution.', null),
    };

    return Column(
      children: [
        Chessboard(
          size: widget.boardSize,
          controller: _controller,
          orientation: _side,
          settings: ChessboardSettings(
            colorScheme: appearance.colorScheme,
            pieceAssets: pieceAssets,
          ),
          onMove: (move, {viaDragAndDrop}) => _onUserMove(move),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 28,
                child: Text(
                  feedback ?? '',
                  style: theme.textTheme.titleMedium?.copyWith(color: color),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'From your ${_puzzle.site.label} game vs ${_puzzle.opponent}'
                '${rating == null ? '' : ' ($rating)'}, '
                '${_formatDate(_puzzle.playedAt)}, move ${_puzzle.moveNumber}.'
                '${done ? ' In the game you played ${_puzzle.playedSan}.' : ''}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (!done)
                    TextButton.icon(
                      onPressed: _phase == _Phase.yourMove || _phase == _Phase.wrong
                          ? _showSolution
                          : null,
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Show solution'),
                    )
                  else
                    TextButton.icon(
                      onPressed: _analyze,
                      icon: const Icon(Icons.insights),
                      label: const Text('Analyze'),
                    ),
                  const Spacer(),
                  Builder(
                    builder: (buttonContext) => IconButton(
                      tooltip: 'Share puzzle',
                      icon: const Icon(Icons.share_outlined),
                      onPressed: () => showShareChoice(
                        buttonContext,
                        ref,
                        linkFen: _puzzlePosition().fen,
                        makeDraft: () async => draftFromPuzzle(_puzzle),
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => widget.onNext(_recorded),
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(done ? 'Next puzzle' : 'Skip'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _formatDate(DateTime date) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
