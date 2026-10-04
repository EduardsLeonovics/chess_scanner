import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analysis/analysis_page.dart' show pvToSan;
import '../engine/engine_service.dart';
import '../puzzles/puzzle_finder.dart' show scoreOf;
import '../settings/appearance.dart';
import '../skills/opening_book.dart';
import '../sound/move_sounds.dart';
import 'repertoire.dart';

/// Engine results for opening positions, kept while the app runs so
/// revisiting a position is instant.
final openingAnalysisProvider = Provider<OpeningAnalysis>(
  (ref) => OpeningAnalysis(ref.watch(engineProvider)),
);

class OpeningAnalysis {
  OpeningAnalysis(this._engine);

  final EngineService _engine;
  final _cache = <String, Future<EngineEval>>{};

  /// Depth for the position on screen and its prepared lines.
  static const lineDepth = 16;

  /// Depth for judging the user's moves.
  static const judgeDepth = 14;

  Future<EngineEval> evaluate(String fen, int depth) {
    final key = '$depth|$fen';
    return _cache[key] ??= _engine.evaluate(fen, depth: depth, urgent: true).catchError((Object e) {
      _cache.remove(key);
      throw e;
    });
  }
}

/// How bad one of the user's moves was, by centipawns lost.
enum Verdict {
  good('Good', 0),
  inaccuracy('Inaccuracy', 50),
  mistake('Mistake', 100),
  blunder('Blunder', 200);

  const Verdict(this.label, this.minLoss);

  final String label;
  final int minLoss;

  static Verdict of(int loss) => values.lastWhere((v) => loss >= v.minLoss);
}

const _green = Color(0xCC15A33B);
const _red = Color(0xCCD32F2F);

/// Plies of a prepared line: the user's reply and five more moves each.
const _linePlies = 11;

/// Walks the user's games in one opening on a board: opponents' most
/// common moves in green, the user's weak moves in red, and an engine line
/// prepared against each opponent move.
class OpeningStudyPage extends ConsumerStatefulWidget {
  const OpeningStudyPage({super.key, required this.family, required this.side});

  final OpeningFamily family;
  final Side side;

  @override
  ConsumerState<OpeningStudyPage> createState() => _OpeningStudyPageState();
}

class _OpeningStudyPageState extends ConsumerState<OpeningStudyPage> {
  late final OpeningTree _tree = OpeningTree(widget.family.games);
  late final ChessboardController _controller;
  final List<(Position, Move?)> _history = [(Chess.initial, null)];

  /// Bumped on navigation so a line being played through stops.
  int _generation = 0;

  /// Your-move verdicts per position, computed once.
  final _judgements = <String, Future<_Judged>>{};

  Future<_Judged> _judgementFor(Position pos) =>
      _judgements[OpeningTree.keyOf(pos)] ??= _judge(ref, pos, _tree.at(pos), _side);

  Position get _pos => _history.last.$1;
  Side get _side => widget.side;

  @override
  void initState() {
    super.initState();
    _controller = ChessboardController(game: _gameData());
  }

  @override
  void dispose() {
    _generation++;
    _controller.dispose();
    super.dispose();
  }

  GameData _gameData() => GameData(
        fen: _pos.fen,
        playerSide: PlayerSide.both,
        sideToMove: _pos.turn,
        validMoves: makeLegalMoves(_pos),
        lastMove: _history.last.$2,
        kingSquareInCheck: _pos.isCheck ? _pos.board.kingOf(_pos.turn) : null,
      );

  Move? _parse(Position pos, String uci) {
    final move = Move.parse(uci);
    if (move == null || !pos.isLegal(move)) return null;
    return move is NormalMove ? pos.normalizeMove(move) : move;
  }

  void _play(Move raw) {
    if (!_pos.isLegal(raw)) return;
    final move = raw is NormalMove ? _pos.normalizeMove(raw) : raw;
    playMoveSound(ref, _pos, move);
    setState(() => _history.add((_pos.play(move), move)));
    _controller.updatePosition(_gameData());
  }

  void _back() {
    if (_history.length < 2) return;
    _generation++;
    setState(_history.removeLast);
    _controller.updatePosition(_gameData(), animate: false);
  }

  void _restart() {
    _generation++;
    setState(() => _history.removeRange(1, _history.length));
    _controller.updatePosition(_gameData(), animate: false);
  }

  /// Plays [line] (UCI) on the board one move at a time.
  Future<void> _playThrough(List<String> line) async {
    final generation = ++_generation;
    for (final uci in line) {
      final move = _parse(_pos, uci);
      if (move == null) return;
      _play(move);
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted || generation != _generation) return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final appearance = ref.watch(appearanceProvider);
    final pieceAssets = ref.watch(pieceAssetsProvider).value ?? appearance.pieceSet.assets;
    final book = ref.watch(openingBookProvider).value;
    final node = _tree.at(_pos);
    final opponentToMove = _pos.turn != _side;
    final name = book?.nameOfGame(_history.map((h) => h.$1));
    final judged = opponentToMove || _pos.isGameOver ? null : _judgementFor(_pos);

    return Scaffold(
      appBar: AppBar(title: Text(widget.family.name)),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final boardSize = constraints.maxWidth.clamp(0.0, constraints.maxHeight * 0.55);
            return Column(
              children: [
                _ArrowsBoard(
                  size: boardSize,
                  controller: _controller,
                  orientation: _side,
                  settings: ChessboardSettings(
                    colorScheme: appearance.colorScheme,
                    pieceAssets: pieceAssets,
                  ),
                  node: node,
                  judged: judged,
                  onMove: _play,
                ),
                _NavBar(
                  name: name,
                  moves: _history.skip(1).map((h) => h.$2!).toList(),
                  onBack: _history.length > 1 ? _back : null,
                  onRestart: _history.length > 1 ? _restart : null,
                ),
                const Divider(height: 1),
                Expanded(
                  child: _pos.isGameOver
                      ? const Center(child: Text('Game over'))
                      : opponentToMove
                          ? _OpponentMoves(
                              position: _pos,
                              node: node,
                              side: _side,
                              onPlay: _play,
                              onPlayLine: _playThrough,
                            )
                          : _YourMoves(
                              position: _pos,
                              judged: judged!,
                              onPlay: _play,
                              onPlayLine: _playThrough,
                            ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The board with this position's arrows: green for opponents' common
/// moves (thicker = more often) or for the best move, red for weak moves of yours.
class _ArrowsBoard extends StatelessWidget {
  const _ArrowsBoard({
    required this.size,
    required this.controller,
    required this.orientation,
    required this.settings,
    required this.node,
    required this.judged,
    required this.onMove,
  });

  final double size;
  final ChessboardController controller;
  final Side orientation;
  final ChessboardSettings settings;
  final TreeNode? node;

  /// Set when it's the user's move; null when the opponent is to move.
  final Future<_Judged>? judged;
  final ValueChanged<Move> onMove;

  @override
  Widget build(BuildContext context) {
    Widget board(Set<Shape> shapes) => Chessboard(
          size: size,
          controller: controller,
          orientation: orientation,
          settings: settings,
          onMove: (move, {viaDragAndDrop}) => onMove(move),
          shapes: shapes,
        );

    Arrow? arrow(String uci, Color color, double scale) {
      final move = Move.parse(uci);
      return move is NormalMove ? Arrow(color: color, orig: move.from, dest: move.to, scale: scale) : null;
    }

    final judged = this.judged;
    if (judged == null) {
      final ranked = node?.ranked ?? const [];
      final total = node?.total ?? 1;
      return board({
        // chessground allows arrow scales up to 1.0.
        for (final e in ranked.take(4)) ?arrow(e.key, _green, 0.45 + 0.55 * e.value / total),
      });
    }

    // Your move: red for your weak moves here, green for the best one.
    return FutureBuilder(
      future: judged,
      builder: (context, snapshot) {
        final judged = snapshot.data;
        return board({
          if (judged != null) ...{
            for (final j in judged.moves)
              if (j.verdict != Verdict.good) ?arrow(j.uci, _red, 0.9),
            if (judged.recommended case final best?) ?arrow(best, _green, 1.0),
          },
        });
      },
    );
  }
}

typedef _JudgedMove = ({String uci, int count, Verdict verdict, int loss, List<String> line});

/// The user's moves at a position, each judged against the engine's best.
class _Judged {
  const _Judged({this.bestUci, this.bestLine = const [], this.moves = const []});

  final String? bestUci;
  final List<String> bestLine;
  final List<_JudgedMove> moves;

  /// Your own most-played move if it's good (stick with your repertoire),
  /// otherwise the engine's best move.
  _JudgedMove? get yourGoodMove {
    for (final m in moves) {
      if (m.verdict == Verdict.good) return m;
    }
    return null;
  }

  String? get recommended => yourGoodMove?.uci ?? bestUci;
  List<String> get recommendedLine => yourGoodMove?.line ?? bestLine;
}

Future<_Judged> _judge(WidgetRef ref, Position pos, TreeNode? node, Side side) async {
  final analysis = ref.read(openingAnalysisProvider);
  final eval = await analysis.evaluate(pos.fen, OpeningAnalysis.lineDepth);
  final best = eval.best;
  if (best == null || best.pv.isEmpty) return const _Judged();
  final bestScore = scoreOf(best, side);
  final moves = <_JudgedMove>[];
  for (final e in node?.ranked ?? const <MapEntry<String, int>>[]) {
    final move = Move.parse(e.key);
    if (move == null || !pos.isLegal(move)) continue;
    final after = pos.play(move);
    int score;
    var reply = const <String>[];
    if (after.isCheckmate) {
      score = 100000;
    } else if (after.isGameOver) {
      score = 0;
    } else {
      final line = (await analysis.evaluate(after.fen, OpeningAnalysis.judgeDepth)).best;
      if (line == null) continue;
      score = scoreOf(line, side);
      reply = line.pv;
    }
    final loss = (bestScore - score).clamp(0, 100000);
    // Never call the engine's own choice anything but good.
    final isBest = _sameMove(pos, e.key, best.pv.first);
    moves.add((
      uci: e.key,
      count: e.value,
      verdict: isBest ? Verdict.good : Verdict.of(loss),
      loss: loss,
      line: [e.key, ...reply].take(_linePlies).toList(),
    ));
  }
  return _Judged(bestUci: best.pv.first, bestLine: best.pv.take(_linePlies).toList(), moves: moves);
}

bool _sameMove(Position pos, String a, String b) {
  Move? norm(String uci) {
    final m = Move.parse(uci);
    if (m == null || !pos.isLegal(m)) return null;
    return m is NormalMove ? pos.normalizeMove(m) : m;
  }

  return norm(a) != null && norm(a) == norm(b);
}

String _san(Position pos, String uci) {
  final move = Move.parse(uci);
  if (move == null || !pos.isLegal(move)) return uci;
  return pos.makeSan(move is NormalMove ? pos.normalizeMove(move) : move).$2;
}

/// Opponent to move: their moves in your games, each with a line prepared
/// for your reply.
class _OpponentMoves extends ConsumerWidget {
  const _OpponentMoves({
    required this.position,
    required this.node,
    required this.side,
    required this.onPlay,
    required this.onPlayLine,
  });

  final Position position;
  final TreeNode? node;
  final Side side;
  final ValueChanged<Move> onPlay;
  final ValueChanged<List<String>> onPlayLine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ranked = node?.ranked ?? const [];
    if (ranked.isEmpty) {
      return _BestLine(position: position, side: side, intro: 'None of your games reached this position.', onPlayLine: onPlayLine);
    }
    final total = node!.total;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text('Your opponents played', style: theme.textTheme.titleSmall),
        ),
        for (final e in ranked)
          _PreparedReply(
            position: position,
            uci: e.key,
            count: e.value,
            share: e.value / total,
            side: side,
            onPlay: onPlay,
            onPlayLine: onPlayLine,
          ),
      ],
    );
  }
}

/// One opponent move and the engine's best 5–6 move answer to it.
class _PreparedReply extends ConsumerWidget {
  const _PreparedReply({
    required this.position,
    required this.uci,
    required this.count,
    required this.share,
    required this.side,
    required this.onPlay,
    required this.onPlayLine,
  });

  final Position position;
  final String uci;
  final int count;
  final double share;
  final Side side;
  final ValueChanged<Move> onPlay;
  final ValueChanged<List<String>> onPlayLine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final move = Move.parse(uci);
    if (move == null || !position.isLegal(move)) return const SizedBox.shrink();
    final after = position.play(move is NormalMove ? position.normalizeMove(move) : move);
    return InkWell(
      onTap: () => onPlay(move),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 10, height: 10, decoration: const BoxDecoration(color: _green, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(pvToSan(position, [uci]), style: theme.textTheme.titleMedium),
                const Spacer(),
                Text('$count× · ${(share * 100).round()}%', style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 4),
            if (after.isGameOver)
              const SizedBox.shrink()
            else
              FutureBuilder(
                future: ref.read(openingAnalysisProvider).evaluate(after.fen, OpeningAnalysis.lineDepth),
                builder: (context, snapshot) {
                  final best = snapshot.data?.best;
                  if (best == null) {
                    return Text(
                      snapshot.hasError ? 'Engine unavailable' : 'Preparing your line…',
                      style: theme.textTheme.bodySmall,
                    );
                  }
                  final line = best.pv.take(_linePlies).toList();
                  return Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: 'Your line: ', style: theme.textTheme.bodySmall),
                            TextSpan(text: pvToSan(after, line), style: theme.textTheme.bodyMedium),
                          ]),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Play this line',
                        icon: const Icon(Icons.play_circle_outline),
                        onPressed: () => onPlayLine([uci, ...line]),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Your move: the moves you played here with how good they were, and the best line.
class _YourMoves extends StatelessWidget {
  const _YourMoves({
    required this.position,
    required this.judged,
    required this.onPlay,
    required this.onPlayLine,
  });

  final Position position;
  final Future<_Judged> judged;
  final ValueChanged<Move> onPlay;
  final ValueChanged<List<String>> onPlayLine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder(
      future: judged,
      builder: (context, snapshot) {
        final judged = snapshot.data;
        if (judged == null) {
          return Center(
            child: Text(snapshot.hasError ? 'Engine unavailable' : 'Analyzing your moves…'),
          );
        }
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            if (judged.recommended case final rec?)
              ListTile(
                leading: const Icon(Icons.star, color: _green),
                title: Text(
                  judged.yourGoodMove != null
                      ? 'Keep playing ${_san(position, rec)}'
                      : 'Play ${_san(position, rec)} instead',
                ),
                subtitle: Text(
                  [
                    pvToSan(position, judged.recommendedLine),
                    if (judged.yourGoodMove != null &&
                        judged.bestUci != null &&
                        !_sameMove(position, rec, judged.bestUci!))
                      "Engine's top choice: ${_san(position, judged.bestUci!)}",
                  ].join('\n'),
                ),
                trailing: IconButton(
                  tooltip: 'Play this line',
                  icon: const Icon(Icons.play_circle_outline),
                  onPressed: () => onPlayLine(judged.recommendedLine),
                ),
              ),
            if (judged.moves.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('You played', style: theme.textTheme.titleSmall),
              )
            else
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('None of your games reached this position.'),
              ),
            for (final m in judged.moves)
              ListTile(
                leading: Icon(
                  m.verdict == Verdict.good ? Icons.check_circle_outline : Icons.error_outline,
                  color: m.verdict == Verdict.good ? _green : _red,
                ),
                title: Text(_san(position, m.uci)),
                subtitle: Text(
                  m.verdict == Verdict.good
                      ? 'Good move'
                      : '${m.verdict.label}: loses ${(m.loss / 100).toStringAsFixed(1)} pawns',
                ),
                trailing: Text('${m.count}×', style: theme.textTheme.bodySmall),
                onTap: () {
                  final move = Move.parse(m.uci);
                  if (move != null) onPlay(move);
                },
              ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

/// Beyond your games: just the engine's best line from here.
class _BestLine extends ConsumerWidget {
  const _BestLine({required this.position, required this.side, required this.intro, required this.onPlayLine});

  final Position position;
  final Side side;
  final String intro;
  final ValueChanged<List<String>> onPlayLine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref.read(openingAnalysisProvider).evaluate(position.fen, OpeningAnalysis.lineDepth),
      builder: (context, snapshot) {
        final best = snapshot.data?.best;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(intro),
            const SizedBox(height: 8),
            if (best == null)
              Text(snapshot.hasError ? 'Engine unavailable' : 'Analyzing…')
            else
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.star, color: _green),
                title: const Text('Best line'),
                subtitle: Text(pvToSan(position, best.pv.take(_linePlies).toList())),
                trailing: IconButton(
                  tooltip: 'Play this line',
                  icon: const Icon(Icons.play_circle_outline),
                  onPressed: () => onPlayLine(best.pv.take(_linePlies).toList()),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Opening name, the moves so far, and back / restart.
class _NavBar extends StatelessWidget {
  const _NavBar({required this.name, required this.moves, required this.onBack, required this.onRestart});

  final String? name;
  final List<Move> moves;
  final VoidCallback? onBack;
  final VoidCallback? onRestart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final san = pvToSan(Chess.initial, [for (final m in moves) m.uci], maxMoves: moves.length);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name ?? 'Starting position', style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (san.isNotEmpty)
                  Text(san, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(tooltip: 'Back to the start', icon: const Icon(Icons.first_page), onPressed: onRestart),
          IconButton(tooltip: 'Back one move', icon: const Icon(Icons.chevron_left), onPressed: onBack),
        ],
      ),
    );
  }
}
