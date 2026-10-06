import 'dart:async';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analysis/analysis_page.dart';
import '../engine/engine_service.dart';
import '../puzzles/puzzle_finder.dart';
import '../settings/appearance.dart';
import '../sound/move_sounds.dart';
import 'community_models.dart';

enum _Phase { intro, yourMove, checking, correct, wrong, solved, revealed }

/// A post's puzzle, playable right in the feed: shows the lead-in move,
/// then lets anyone find the solution. A right move plays the chime; moves
/// other than the stored one are checked with the engine, so an equally
/// good move counts too.
class FeedPuzzle extends ConsumerStatefulWidget {
  const FeedPuzzle({super.key, required this.post, required this.size});

  final CommunityPost post;
  final double size;

  @override
  ConsumerState<FeedPuzzle> createState() => _FeedPuzzleState();
}

class _FeedPuzzleState extends ConsumerState<FeedPuzzle> with AutomaticKeepAliveClientMixin {
  late Position _pos;
  Move? _lastMove;
  late List<String> _solution;
  int _step = 0;
  _Phase _phase = _Phase.intro;
  bool _failed = false;
  late final ChessboardController _controller;

  /// Bumped on every user action so stale delayed moves are dropped.
  int _generation = 0;

  CommunityPost get _post => widget.post;
  Side get _side => _post.solverSide;

  // Keep a puzzle's progress while it scrolls out of view and back.
  @override
  bool get wantKeepAlive => _phase != _Phase.intro && _phase != _Phase.yourMove || _step > 0 || _failed;

  @override
  void initState() {
    super.initState();
    _start();
    _controller = ChessboardController(game: _gameData());
  }

  void _start() {
    _pos = Chess.fromSetup(Setup.parseFen(_post.fen));
    _lastMove = null;
    _solution = _post.solution;
    _step = 0;
    _failed = false;
    final lead = _post.lastMove == null ? null : _parse(_pos, _post.lastMove!);
    if (lead == null) {
      _phase = _Phase.yourMove;
    } else {
      // Shown already played: in a scrolling feed an animated lead-in would
      // play for boards nobody is looking at yet.
      _pos = _pos.play(lead);
      _lastMove = lead;
      _phase = _Phase.yourMove;
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
    updateKeepAlive();
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
      _correct();
      return;
    }
    _phase = _Phase.checking;
    _refresh();
    if (await _acceptAlternative(move)) {
      if (mounted) _correct();
      return;
    }
    if (!mounted) return;
    _failed = true;
    setState(() => _phase = _Phase.wrong);
    _later(const Duration(milliseconds: 800), () {
      _pos = before;
      _lastMove = beforeLast;
      _phase = _Phase.yourMove;
      _refresh(animate: false);
    });
  }

  void _correct() {
    _step++;
    _phase = _Phase.correct;
    _refresh();
    _advance();
  }

  /// Whether the move just played is as good as the solution. For mates,
  /// the rest of the solution becomes the engine's mating line.
  Future<bool> _acceptAlternative(Move move) async {
    final EngineEval eval;
    try {
      eval = await ref.read(engineProvider).evaluate(_pos.fen, depth: 16, urgent: true);
    } on StateError {
      return false;
    }
    final best = eval.best;
    if (best == null) return false;
    if (mateFor(best, _side) case final mate? when _post.bestScore >= 90000) {
      final userMovesLeft = (_solution.length - _step + 1) ~/ 2;
      if (mate > userMovesLeft - 1) return false;
      _solution = [..._solution.take(_step), move.uci, ...best.pv];
      return true;
    }
    if (scoreOf(best, _side) >= _post.bestScore - 60) {
      _solution = [..._solution.take(_step), move.uci];
      return true;
    }
    return false;
  }

  /// After a right move: finish, or play the reply.
  void _advance() {
    if (_step >= _solution.length || _pos.isGameOver) {
      playCorrectSound(ref);
      setState(() => _phase = _Phase.solved);
      return;
    }
    _later(const Duration(milliseconds: 450), () {
      final reply = _parse(_pos, _solution[_step]);
      if (reply == null) {
        playCorrectSound(ref);
        _phase = _Phase.solved;
        _refresh();
        return;
      }
      _apply(reply);
      _step++;
      _phase = _step >= _solution.length ? _Phase.solved : _Phase.yourMove;
      if (_phase == _Phase.solved) playCorrectSound(ref);
      _refresh();
    });
  }

  void _showSolution() {
    _failed = true;
    _generation++;
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

  /// Opens the puzzle on the analysis board with the solution to step
  /// through and the engine's lines.
  void _analyze() {
    Position start = Chess.fromSetup(Setup.parseFen(_post.fen));
    final lead = _post.lastMove == null ? null : _parse(start, _post.lastMove!);
    if (lead != null) start = start.play(lead);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AnalysisPage(
        initialFen: start.fen,
        initialMoves: _solution,
        orientation: _side,
        title: 'Puzzle analysis',
      ),
    ));
  }

  void _retry() {
    _generation++;
    setState(_start);
    _refresh(animate: false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final appearance = ref.watch(appearanceProvider);
    final pieceAssets = ref.watch(pieceAssetsProvider).value ?? appearance.pieceSet.assets;
    final done = _phase == _Phase.solved || _phase == _Phase.revealed;
    final toMove = _side == Side.white ? 'White' : 'Black';

    final (String text, Color? color) = switch (_phase) {
      _Phase.intro || _Phase.yourMove => ('$toMove to move', null),
      _Phase.checking => ('Checking your move…', null),
      _Phase.correct => ('Correct!', const Color(0xFF4CAF50)),
      _Phase.wrong => ('Not the move. Try again.', theme.colorScheme.error),
      _Phase.solved => (_failed ? 'Solved on a retry.' : 'Solved!', const Color(0xFF4CAF50)),
      _Phase.revealed => ('Here\'s the solution.', null),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Chessboard(
          size: widget.size,
          controller: _controller,
          orientation: _side,
          settings: ChessboardSettings(
            colorScheme: appearance.colorScheme,
            pieceAssets: pieceAssets,
            enableCoordinates: false,
          ),
          onMove: (move, {viaDragAndDrop}) => _onUserMove(move),
        ),
        SizedBox(
          height: 44,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
                ),
              ),
              if (done) ...[
                TextButton.icon(
                  onPressed: _analyze,
                  icon: const Icon(Icons.insights, size: 18),
                  label: const Text('Analyze'),
                ),
                TextButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.replay, size: 18),
                  label: const Text('Again'),
                ),
              ] else
                TextButton.icon(
                  onPressed: _phase == _Phase.yourMove || _phase == _Phase.wrong ? _showSolution : null,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Solution'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
