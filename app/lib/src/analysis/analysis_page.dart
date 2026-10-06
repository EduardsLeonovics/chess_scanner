import 'dart:async';
import 'dart:math' as math;

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/board_setup.dart';
import '../capture/image_capture.dart';
import '../community/post_puzzle.dart';
import '../community/share_choice.dart';
import '../engine/engine_service.dart';
import '../engine/engine_settings.dart';
import '../engine/uci.dart';
import '../recognition/board_recognizer.dart';
import '../settings/appearance.dart';
import '../settings/settings_page.dart';
import '../share/position_link.dart';
import '../sound/move_sounds.dart';
import 'engine_settings_sheet.dart';
import 'eval_bar.dart';

/// A position in the move history and the move that led to it.
class _Ply {
  const _Ply(this.position, [this.move]);

  final Position position;
  final Move? move;
}

class AnalysisPage extends ConsumerStatefulWidget {
  const AnalysisPage({
    super.key,
    this.initialFen,
    this.initialMoves = const [],
    this.orientation,
    this.title,
  });

  /// Starting position, e.g. from board recognition. Defaults to the
  /// standard starting position.
  final String? initialFen;

  /// A line from [initialFen] (UCI) to step through with the arrows, e.g. a
  /// puzzle's solution. The board starts before its first move.
  final List<String> initialMoves;

  /// Board side at the bottom; White by default.
  final Side? orientation;

  /// Set when opened on its own (e.g. from a puzzle): shows a back button
  /// and this title instead of the scan button.
  final String? title;

  @override
  ConsumerState<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends ConsumerState<AnalysisPage> with WidgetsBindingObserver {
  late final EngineService _engine;
  late final ChessboardController _controller;
  StreamSubscription<EngineEval>? _evalSub;

  late List<_Ply> _history;
  int _cursor = 0;
  Side _orientation = Side.white;
  EngineEval? _eval;

  /// Board editing: on while the user fixes a (recognized) position.
  bool _editing = false;
  Pieces _editPieces = const {};
  Side _editTurn = Side.white;

  /// Piece placed by tapping a square while editing; null erases.
  Piece? _brush = Piece.whitePawn;

  bool _recognizing = false;

  /// False while another tab is showing; the engine is then left free for
  /// background work such as puzzle generation.
  bool _visible = true;

  /// False while the app is in the background (home screen, screen off).
  bool _foreground = true;

  Position get _pos => _history[_cursor].position;

  @override
  void initState() {
    super.initState();
    final start = widget.initialFen == null
        ? Chess.initial
        : Chess.fromSetup(Setup.parseFen(widget.initialFen!));
    _history = [_Ply(start)];
    Position pos = start;
    for (final uci in widget.initialMoves) {
      final move = Move.parse(uci);
      if (move == null || !pos.isLegal(move)) break;
      final normalized = move is NormalMove ? pos.normalizeMove(move) : move;
      pos = pos.play(normalized);
      _history.add(_Ply(pos, normalized));
    }
    _orientation = widget.orientation ?? Side.white;
    _controller = ChessboardController(game: _gameData());
    _engine = ref.read(engineProvider);
    WidgetsBinding.instance.addObserver(this);
    _evalSub = _engine.evals.listen((eval) {
      if (eval.fen == _pos.fen) setState(() => _eval = eval);
    });
    _analyze();
    // A link that arrived before this page was built.
    final pending = widget.title == null ? ref.read(pendingPositionProvider) : null;
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openLinked(pending));
    }
  }

  void _openLinked(Position position) {
    ref.read(pendingPositionProvider.notifier).clear();
    if (_editing) setState(() => _editing = false);
    _orientation = position.turn;
    _setPosition(position);
    _showMessage('Opened the shared position.');
  }

  /// Post the position to the community, or share a link to it.
  Future<void> _share(BuildContext buttonContext) {
    final position = _pos;
    return showShareChoice(
      buttonContext,
      ref,
      linkFen: position.fen,
      makeDraft: () => draftFromPosition(position, _engine),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = Visibility.of(context);
    if (visible == _visible) return;
    _visible = visible;
    if (_editing) return;
    if (visible) {
      _analyze();
    } else {
      _engine.stop();
    }
  }

  /// Live analysis runs until stopped, so stop it while the app is in the
  /// background: the hidden tab check above doesn't notice that.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Inactive is still on screen (notification shade, a system dialog).
    final foreground = state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (_editing) return;
    _analyze();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    if (!_visible || !_foreground || _pos.isGameOver) {
      _engine.stop();
    } else {
      _engine.analyze(_pos.fen);
    }
  }

  void _play(Move move) {
    if (!_pos.isLegal(move)) return;
    final normalized = move is NormalMove ? _pos.normalizeMove(move) : move;
    playMoveSound(ref, _pos, normalized);
    final next = _pos.play(normalized);
    setState(() {
      _history = [..._history.take(_cursor + 1), _Ply(next, move)];
      _cursor++;
      _eval = null;
    });
    _controller.updatePosition(_gameData());
    _analyze();
  }

  /// Shows the position [index] plies into the history.
  void _goTo(int index) {
    if (index < 0 || index >= _history.length || index == _cursor) return;
    setState(() {
      _cursor = index;
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _scan() async {
    final bytes = await captureBoardImage(context);
    if (bytes == null || !mounted) return;
    setState(() => _recognizing = true);
    final RecognizedBoard result;
    try {
      result = await recognizeBoard(bytes);
    } on RecognitionException catch (e) {
      if (mounted) _showMessage(e.message);
      return;
    } finally {
      if (mounted) setState(() => _recognizing = false);
    }
    if (!mounted) return;

    _orientation = result.blackAtBottom ? Side.black : Side.white;
    // White to move unless that's impossible (Black already in check).
    for (final turn in [Side.white, Side.black]) {
      try {
        _setPosition(positionFromBoard(result.board, turn));
        if (_editing) setState(() => _editing = false);
        _showMessage('Position loaded. Tap the pencil to fix any wrong pieces.');
        return;
      } on PositionSetupException {
        // Try the other side, then fall back to the editor.
      }
    }
    _startEditing(pieces: {for (final (sq, piece) in result.board.pieces) sq: piece});
    try {
      positionFromBoard(result.board, Side.white);
    } on PositionSetupException catch (e) {
      _showMessage('${describeSetupError(e)}. Fix the board, then tap ✓.');
    }
  }

  void _startEditing({Pieces? pieces}) {
    _engine.stop();
    setState(() {
      _editing = true;
      _editPieces = pieces ?? {for (final (sq, piece) in _pos.board.pieces) sq: piece};
      _editTurn = pieces == null ? _pos.turn : Side.white;
      _eval = null;
    });
  }

  void _finishEditing() {
    var board = Board.empty;
    for (final MapEntry(key: square, value: piece) in _editPieces.entries) {
      board = board.setPieceAt(square, piece);
    }
    try {
      final position = positionFromBoard(board, _editTurn);
      setState(() => _editing = false);
      _setPosition(position);
    } on PositionSetupException catch (e) {
      _showMessage(describeSetupError(e));
    }
  }

  void _cancelEditing() {
    setState(() => _editing = false);
    _analyze();
  }

  void _editSquare(Square square) {
    final brush = _brush;
    setState(() {
      _editPieces = {..._editPieces}..remove(square);
      if (brush != null) _editPieces[square] = brush;
    });
  }

  /// Reverses the coordinates (a↔h, 1↔8, see [rotateBoard]) and flips the
  /// view with them, so the pieces stay where they are on screen. If the
  /// result isn't a legal position, opens it in the editor to be fixed.
  void _rotate() {
    _orientation = _orientation.opposite;
    if (_editing) {
      setState(() => _editPieces = rotatePieces(_editPieces));
      return;
    }
    final board = rotateBoard(_pos.board);
    try {
      _setPosition(positionFromBoard(board, _pos.turn));
    } on PositionSetupException catch (e) {
      _startEditing(pieces: {for (final (sq, piece) in board.pieces) sq: piece});
      _showMessage('${describeSetupError(e)}. Fix the board, then tap ✓.');
    }
  }

  void _setTurn(Side turn) {
    if (_editing) {
      setState(() => _editTurn = turn);
      return;
    }
    if (turn == _pos.turn) return;
    try {
      _setPosition(withTurn(_pos, turn));
    } on PositionSetupException catch (e) {
      _showMessage(describeSetupError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.title == null) {
      ref.listen(pendingPositionProvider, (_, position) {
        if (position != null) _openLinked(position);
      });
    }
    final best = _editing ? null : _eval?.best;
    final bestMove = best == null ? null : Move.parse(best.pv.first);
    final appearance = ref.watch(appearanceProvider);
    final pieceAssets = ref.watch(pieceAssetsProvider).value ?? appearance.pieceSet.assets;
    final boardSettings = ChessboardSettings(
      colorScheme: appearance.colorScheme,
      pieceAssets: pieceAssets,
    );

    return Scaffold(
      appBar: AppBar(
        title: widget.title == null ? null : Text(widget.title!),
        leading: widget.title != null
            ? null
            : IconButton(
                tooltip: 'Scan a position',
                icon: const Icon(Icons.photo_camera_outlined),
                onPressed: _recognizing ? null : _scan,
              ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(settingsRoute()),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                const barWidth = 26.0;
                final boardSize = math.max(
                  0.0,
                  math.min(
                    constraints.maxWidth - barWidth,
                    constraints.maxHeight * 0.62,
                  ),
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
                        if (_editing)
                          ChessboardEditor(
                            size: boardSize,
                            orientation: _orientation,
                            pieces: _editPieces,
                            pointerMode: EditorPointerMode.edit,
                            settings: boardSettings,
                            onEditedSquare: _editSquare,
                          )
                        else
                          Chessboard(
                            size: boardSize,
                            controller: _controller,
                            orientation: _orientation,
                            settings: boardSettings,
                            onMove: (move, {viaDragAndDrop}) => _play(move),
                            shapes: {
                              if (bestMove is NormalMove && appearance.showBestMoveArrow)
                                Arrow(
                                  color: const Color(0xAA15781B),
                                  orig: bestMove.from,
                                  dest: bestMove.to,
                                ),
                            },
                          ),
                      ],
                    ),
                    if (_editing)
                      _PiecePalette(
                        selected: _brush,
                        pieceAssets: pieceAssets,
                        onSelect: (piece) => setState(() => _brush = piece),
                        onClear: () => setState(() => _editPieces = const {}),
                      ),
                    _BoardControls(
                      turn: _editing ? _editTurn : _pos.turn,
                      onTurn: _setTurn,
                      side: _orientation,
                      onSide: (side) => setState(() => _orientation = side),
                      editing: _editing,
                      onEdit: _startEditing,
                      onDone: _finishEditing,
                      onCancel: _cancelEditing,
                      onShare: _share,
                      onRotate: _rotate,
                    ),
                    if (!_editing && _history.length > 1)
                      _MoveNavigation(
                        cursor: _cursor,
                        length: _history.length,
                        moveLabel: _cursor == 0 ? 'Start' : _sanAt(_cursor),
                        onGoTo: _goTo,
                      ),
                    const Divider(height: 1),
                    Expanded(
                      child: _editing
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'Pick a piece, then tap squares to place it. '
                                  'Tap ✓ to analyze.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : _buildEnginePanel(),
                    ),
                  ],
                );
              },
            ),
            if (_recognizing)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x99000000),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Reading the board…'),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The move that led to ply [index], numbered, e.g. "12... Nf6".
  String _sanAt(int index) {
    final before = _history[index - 1].position;
    final move = _history[index].move;
    if (move == null || !before.isLegal(move)) return '';
    final (_, san) = before.makeSan(move);
    return '${before.fullmoves}${before.turn == Side.white ? '.' : '...'} $san';
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
        final settings = ref.watch(engineSettingsProvider);
        final settingsNotifier = ref.read(engineSettingsProvider.notifier);
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Row(
                children: [
                  Text(
                    eval == null ? 'Stockfish · thinking…' : 'Stockfish · depth ${eval.depth}',
                    style: theme.textTheme.labelMedium,
                  ),
                  IconButton(
                    tooltip: 'Engine settings',
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.tune),
                    onPressed: () => showEngineSettings(context),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: settings.showLines ? 'Hide lines' : 'Show lines',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(settings.showLines ? Icons.unfold_less : Icons.unfold_more),
                    onPressed: () => settingsNotifier.set(settings.copyWith(showLines: !settings.showLines)),
                  ),
                ],
              ),
            ),
            if (eval != null && settings.showLines)
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

/// Share, then "Move" (side to move) and "Side" (board perspective)
/// toggles, plus the edit / done / cancel buttons.
class _BoardControls extends StatelessWidget {
  const _BoardControls({
    required this.turn,
    required this.onTurn,
    required this.side,
    required this.onSide,
    required this.editing,
    required this.onEdit,
    required this.onDone,
    required this.onCancel,
    required this.onShare,
    required this.onRotate,
  });

  final Side turn;
  final ValueChanged<Side> onTurn;
  final Side side;
  final ValueChanged<Side> onSide;
  final bool editing;
  final VoidCallback onEdit;
  final VoidCallback onDone;
  final VoidCallback onCancel;

  /// Gets the share button's context, to anchor the share sheet.
  final ValueChanged<BuildContext> onShare;

  /// Reverses the board's coordinates, see [_AnalysisPageState._rotate].
  final VoidCallback onRotate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
      child: Row(
        children: [
          if (!editing)
            Builder(
              builder: (buttonContext) => IconButton(
                tooltip: 'Share position',
                icon: const Icon(Icons.share_outlined),
                onPressed: () => onShare(buttonContext),
              ),
            )
          else
            const SizedBox(width: 8),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  _SideToggle(label: 'Move', value: turn, onChanged: onTurn),
                  const SizedBox(width: 16),
                  _SideToggle(label: 'Side', value: side, onChanged: onSide),
                  const SizedBox(width: 12),
                  _RotateSwitch(onRotate: onRotate),
                ],
              ),
            ),
          ),
          if (editing) ...[
            IconButton(
              tooltip: 'Cancel',
              icon: const Icon(Icons.close),
              onPressed: onCancel,
            ),
            IconButton.filled(
              tooltip: 'Done',
              icon: const Icon(Icons.check),
              onPressed: onDone,
            ),
          ] else
            IconButton(
              tooltip: 'Edit board',
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
        ],
      ),
    );
  }
}

/// First / back / forward / last through the move history, with the move
/// just played.
class _MoveNavigation extends StatelessWidget {
  const _MoveNavigation({
    required this.cursor,
    required this.length,
    required this.moveLabel,
    required this.onGoTo,
  });

  final int cursor;
  final int length;
  final String moveLabel;
  final ValueChanged<int> onGoTo;

  @override
  Widget build(BuildContext context) {
    final atStart = cursor == 0;
    final atEnd = cursor == length - 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'First position',
            icon: const Icon(Icons.first_page),
            onPressed: atStart ? null : () => onGoTo(0),
          ),
          IconButton(
            tooltip: 'Previous move',
            icon: const Icon(Icons.chevron_left),
            onPressed: atStart ? null : () => onGoTo(cursor - 1),
          ),
          Expanded(
            child: Text(
              moveLabel,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          IconButton(
            tooltip: 'Next move',
            icon: const Icon(Icons.chevron_right),
            onPressed: atEnd ? null : () => onGoTo(cursor + 1),
          ),
          IconButton(
            tooltip: 'Last position',
            icon: const Icon(Icons.last_page),
            onPressed: atEnd ? null : () => onGoTo(length - 1),
          ),
        ],
      ),
    );
  }
}

/// "Label: White | Black" as a compact segmented toggle.
class _SideToggle extends StatelessWidget {
  const _SideToggle({required this.label, required this.value, required this.onChanged});

  final String label;
  final Side value;
  final ValueChanged<Side> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$label:', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(width: 8),
        SegmentedButton<Side>(
          segments: const [
            ButtonSegment(value: Side.white, label: Text('White')),
            ButtonSegment(value: Side.black, label: Text('Black')),
          ],
          selected: {value},
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity(horizontal: -4, vertical: -2),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
          ),
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ],
    );
  }
}

/// "Rotate": a small two-light vertical switch. Each tap reverses the
/// coordinates (a-file to h-file, rank 1 to rank 8) while the pieces stay
/// put on screen; the lit half shows whether the board is as scanned or
/// turned.
class _RotateSwitch extends StatefulWidget {
  const _RotateSwitch({required this.onRotate});

  final VoidCallback onRotate;

  @override
  State<_RotateSwitch> createState() => _RotateSwitchState();
}

class _RotateSwitchState extends State<_RotateSwitch> {
  bool _turned = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget light(bool lit, BorderRadius radius) => AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 22,
          height: 13,
          decoration: BoxDecoration(
            color: lit ? scheme.primary : scheme.surfaceContainerHighest,
            borderRadius: radius,
          ),
        );
    return Semantics(
      button: true,
      toggled: _turned,
      label: 'Rotate board',
      excludeSemantics: true,
      child: Tooltip(
        message: 'Rotate: swap a↔h and 1↔8, pieces stay where they are',
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() => _turned = !_turned);
            widget.onRotate();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                Text('Rotate', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outline),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      light(!_turned, const BorderRadius.vertical(top: Radius.circular(5))),
                      const SizedBox(height: 2),
                      light(_turned, const BorderRadius.vertical(bottom: Radius.circular(5))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pieces to place while editing, an eraser, and a clear-board button.
class _PiecePalette extends StatelessWidget {
  const _PiecePalette({
    required this.selected,
    required this.pieceAssets,
    required this.onSelect,
    required this.onClear,
  });

  final Piece? selected;
  final PieceAssets pieceAssets;
  final ValueChanged<Piece?> onSelect;
  final VoidCallback onClear;

  static const _roles = [Role.king, Role.queen, Role.rook, Role.bishop, Role.knight, Role.pawn];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget cell({required bool isSelected, required String tooltip, required Widget child, required VoidCallback onTap}) {
      return Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 40,
            height: 40,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: isSelected ? scheme.primaryContainer : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: child,
          ),
        ),
      );
    }

    Widget pieceRow(Side side) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final role in _roles)
              cell(
                isSelected: selected == Piece(color: side, role: role),
                tooltip: '${side.name} ${role.name}',
                onTap: () => onSelect(Piece(color: side, role: role)),
                child: PieceWidget(
                  piece: Piece(color: side, role: role),
                  size: 34,
                  pieceAssets: pieceAssets,
                ),
              ),
            side == Side.white
                ? cell(
                    isSelected: selected == null,
                    tooltip: 'Erase',
                    onTap: () => onSelect(null),
                    child: const Icon(Icons.backspace_outlined),
                  )
                : cell(
                    isSelected: false,
                    tooltip: 'Clear board',
                    onTap: onClear,
                    child: const Icon(Icons.delete_outline),
                  ),
          ],
        );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: [pieceRow(Side.white), pieceRow(Side.black)]),
    );
  }
}
