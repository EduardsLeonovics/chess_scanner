import 'dart:async';
import 'dart:math' as math;

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/engine_service.dart';
import '../engine/uci.dart';
import 'eval_bar.dart';

/// A position in the move history and the move that led to it.
class _Ply {
  const _Ply(this.position, [this.move, this.san]);

  final Position position;
  final Move? move;
  final String? san;
}

class AnalysisPage extends ConsumerStatefulWidget {
  const AnalysisPage({super.key, this.initialFen});

  /// Starting position, e.g. from board recognition. Defaults to the
  /// standard starting position.
  final String? initialFen;

  @override
  ConsumerState<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends ConsumerState<AnalysisPage> {
  late final EngineService _engine;
  late final ChessboardController _controller;
  StreamSubscription<EngineEval>? _evalSub;

  late List<_Ply> _history;
  int _cursor = 0;
  Side _orientation = Side.white;
  EngineEval? _eval;

  Position get _pos => _history[_cursor].position;

  @override
  void initState() {
    super.initState();
    final start = widget.initialFen == null
        ? Chess.initial
        : Chess.fromSetup(Setup.parseFen(widget.initialFen!));
    _history = [_Ply(start)];
    _controller = ChessboardController(game: _gameData());
    _engine = ref.read(engineProvider);
    _evalSub = _engine.evals.listen((eval) {
      if (eval.fen == _pos.fen) setState(() => _eval = eval);
    });
    _analyze();
  }

  @override
  void dispose() {
    _evalSub?.cancel();
    _engine.stop();
    _controller.dispose();
    super.dispose();
  }

  GameData _gameData() => GameData(
        fen: _pos.fen,
        playerSide: PlayerSide.both,
        sideToMove: _pos.turn,
        validMoves: makeLegalMoves(_pos),
        lastMove: _history[_cursor].move,
        kingSquareInCheck: _pos.isCheck ? _pos.board.kingOf(_pos.turn) : null,
      );

  void _analyze() {
    if (_pos.isGameOver) {
      _engine.stop();
    } else {
      _engine.analyze(_pos.fen);
    }
  }

  void _goTo(int index) {
    if (index < 0 || index >= _history.length || index == _cursor) return;
    setState(() {
      _cursor = index;
      _eval = null;
    });
    _controller.updatePosition(_gameData());
    _analyze();
  }

  void _play(Move move) {
    if (!_pos.isLegal(move)) return;
    final normalized = move is NormalMove ? _pos.normalizeMove(move) : move;
    final (next, san) = _pos.makeSan(normalized);
    setState(() {
      _history = [..._history.take(_cursor + 1), _Ply(next, move, san)];
      _cursor++;
      _eval = null;
    });
    _controller.updatePosition(_gameData());
    _analyze();
  }

  void _setPosition(Position position) {
    setState(() {
      _history = [_Ply(position)];
      _cursor = 0;
      _eval = null;
    });
    _controller.updatePosition(_gameData(), animate: false);
    _analyze();
  }

  Future<void> _editFen() async {
    final position = await showDialog<Position>(
      context: context,
      builder: (_) => _FenDialog(initialFen: _pos.fen),
    );
    if (position != null) _setPosition(position);
  }

  @override
  Widget build(BuildContext context) {
    final best = _eval?.best;
    final bestMove = best == null ? null : Move.parse(best.pv.first);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analysis'),
        actions: [
          IconButton(
            tooltip: 'Flip board',
            icon: const Icon(Icons.swap_vert),
            onPressed: () => setState(() => _orientation = _orientation.opposite),
          ),
          IconButton(
            tooltip: 'Set position (FEN)',
            icon: const Icon(Icons.edit_note),
            onPressed: _editFen,
          ),
          IconButton(
            tooltip: 'Reset',
            icon: const Icon(Icons.restart_alt),
            onPressed: () => _setPosition(Chess.initial),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const barWidth = 18.0;
            final boardSize = math.min(
              constraints.maxWidth - barWidth,
              constraints.maxHeight * 0.62,
            );
            return Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    EvalBar(
                      line: best,
                      height: boardSize,
                      width: barWidth,
                      flipped: _orientation == Side.black,
                    ),
                    Chessboard(
                      size: boardSize,
                      controller: _controller,
                      orientation: _orientation,
                      onMove: (move, {viaDragAndDrop}) => _play(move),
                      shapes: {
                        if (bestMove is NormalMove)
                          Arrow(
                            color: const Color(0xAA15781B),
                            orig: bestMove.from,
                            dest: bestMove.to,
                          ),
                      },
                    ),
                  ],
                ),
                _MoveList(
                  history: _history,
                  cursor: _cursor,
                  onSelect: _goTo,
                  onBack: () => _goTo(_cursor - 1),
                  onForward: () => _goTo(_cursor + 1),
                ),
                const Divider(height: 1),
                Expanded(child: _buildEnginePanel()),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildEnginePanel() {
    final theme = Theme.of(context);
    if (_pos.isCheckmate) {
      return Center(child: Text('Checkmate', style: theme.textTheme.titleMedium));
    }
    if (_pos.isGameOver) {
      return Center(child: Text('Draw', style: theme.textTheme.titleMedium));
    }

    return ValueListenableBuilder(
      valueListenable: _engine.status,
      builder: (context, status, _) {
        final message = switch (status) {
          EngineStatus.starting => 'Starting Stockfish…',
          EngineStatus.unavailable =>
            'Stockfish runs on Android and iOS only. Run the app on a phone or emulator.',
          EngineStatus.error => 'Stockfish failed to start.',
          EngineStatus.ready => null,
        };
        if (message != null) {
          return Center(child: Text(message, textAlign: TextAlign.center));
        }

        final eval = _eval;
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                eval == null ? 'Stockfish · thinking…' : 'Stockfish · depth ${eval.depth}',
                style: theme.textTheme.labelMedium,
              ),
            ),
            if (eval != null)
              for (final line in eval.lines)
                _EngineLineTile(
                  line: line,
                  position: _pos,
                  onTap: () {
                    final move = Move.parse(line.pv.first);
                    if (move != null) _play(move);
                  },
                ),
          ],
        );
      },
    );
  }
}

class _EngineLineTile extends StatelessWidget {
  const _EngineLineTile({
    required this.line,
    required this.position,
    required this.onTap,
  });

  final PvLine line;
  final Position position;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final whiteBetter = (line.mate ?? line.cp!) >= 0;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              padding: const EdgeInsets.symmetric(vertical: 2),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: whiteBetter ? const Color(0xFFF0F0F0) : const Color(0xFF404040),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                line.scoreLabel,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: whiteBetter ? Colors.black : Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                pvToSan(position, line.pv),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Formats UCI moves as numbered SAN, e.g. `12... Nf6 13. Bg5 h6`.
String pvToSan(Position start, List<String> pv, {int maxMoves = 12}) {
  final out = StringBuffer();
  var pos = start;
  for (final uci in pv.take(maxMoves)) {
    final move = Move.parse(uci);
    if (move == null || !pos.isLegal(move)) break;
    final normalized = move is NormalMove ? pos.normalizeMove(move) : move;
    if (pos.turn == Side.white) {
      out.write('${pos.fullmoves}. ');
    } else if (identical(pos, start)) {
      out.write('${pos.fullmoves}... ');
    }
    final (next, san) = pos.makeSan(normalized);
    out.write('$san ');
    pos = next;
  }
  return out.toString().trimRight();
}

class _MoveList extends StatelessWidget {
  const _MoveList({
    required this.history,
    required this.cursor,
    required this.onSelect,
    required this.onBack,
    required this.onForward,
  });

  final List<_Ply> history;
  final int cursor;
  final ValueChanged<int> onSelect;
  final VoidCallback onBack;
  final VoidCallback onForward;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: cursor > 0 ? onBack : null,
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(
              children: [
                for (var i = 1; i < history.length; i++)
                  InkWell(
                    onTap: () => onSelect(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      child: Text(
                        _label(i),
                        style: i == cursor
                            ? TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: cursor < history.length - 1 ? onForward : null,
        ),
      ],
    );
  }

  String _label(int i) {
    final before = history[i - 1].position;
    final san = history[i].san!;
    if (before.turn == Side.white) return '${before.fullmoves}. $san';
    if (i == 1) return '${before.fullmoves}... $san';
    return san;
  }
}

class _FenDialog extends StatefulWidget {
  const _FenDialog({required this.initialFen});

  final String initialFen;

  @override
  State<_FenDialog> createState() => _FenDialogState();
}

class _FenDialogState extends State<_FenDialog> {
  late final _text = TextEditingController(text: widget.initialFen);
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final position = Chess.fromSetup(Setup.parseFen(_text.text.trim()));
      Navigator.of(context).pop(position);
    } catch (e) {
      setState(() => _error = 'Invalid or illegal position');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Position (FEN)'),
      content: TextField(
        controller: _text,
        maxLines: 3,
        minLines: 1,
        autofocus: true,
        decoration: InputDecoration(
          errorText: _error,
          suffixIcon: IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy),
            onPressed: () => Clipboard.setData(ClipboardData(text: _text.text)),
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Load')),
      ],
    );
  }
}
