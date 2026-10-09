import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show PieceKind, Side;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A ready-made board look, some of them textured (wood, marble, …).
class BoardTheme {
  const BoardTheme(this.id, this.label, this.scheme);

  final String id;
  final String label;
  final ChessboardColorScheme scheme;
}

/// Plain white and black squares; black pieces get a white outline by
/// default so they stand out on the black squares.
const blackWhiteThemeId = 'blackWhite';

/// ChessHive's own look and the default: white and golden yellow squares.
/// Black pieces (golden by default) get a dark outline on it.
const goldenThemeId = 'golden';

final boardThemes = [
  BoardTheme(goldenThemeId, 'Golden', _solidScheme(const Color(0xFFFFFDF5), const Color(0xFFF2CC55))),
  BoardTheme('brown', 'Brown', ChessboardColorScheme.brown),
  BoardTheme('green', 'Green', ChessboardColorScheme.green),
  BoardTheme('blue', 'Blue', ChessboardColorScheme.blue),
  BoardTheme('wood', 'Wood', ChessboardColorScheme.wood),
  BoardTheme('wood3', 'Walnut', ChessboardColorScheme.wood3),
  BoardTheme('maple', 'Maple', ChessboardColorScheme.maple),
  BoardTheme('marble', 'Marble', ChessboardColorScheme.marble),
  BoardTheme('blueMarble', 'Blue marble', ChessboardColorScheme.blueMarble),
  BoardTheme('leather', 'Leather', ChessboardColorScheme.leather),
  BoardTheme('metal', 'Metal', ChessboardColorScheme.metal),
  BoardTheme('olive', 'Olive', ChessboardColorScheme.olive),
  BoardTheme('newspaper', 'Newspaper', ChessboardColorScheme.newspaper),
  BoardTheme(blackWhiteThemeId, 'Black & white', _solidScheme(const Color(0xFFFFFFFF), const Color(0xFF000000))),
];

/// The piece styles offered in settings: widely used Lichess sets, and
/// ChessHive's own (all licensed for commercial use; see
/// third_party/chessground/LICENSES.md).
const pieceStyles = [
  (PieceSet.cburnett, 'Classic'),
  (PieceSet.merida, 'Merida'),
  (PieceSet.geo, 'Geo'),
  (PieceSet.ink, 'Ink'),
  (PieceSet.hive, 'Hive'),
  (PieceSet.mpchess, 'Modern'),
  (PieceSet.celtic, 'Celtic'),
  (PieceSet.fantasy, 'Fantasy'),
  (PieceSet.spatial, 'Spatial'),
];

/// Sets drawn in tinted greys (Celtic's slate-blue black pieces): always
/// mapped to neutral black and white, like every other set.
const neutralizedSets = {PieceSet.celtic, PieceSet.fantasy, PieceSet.spatial};

/// How fast pieces glide to their square when a move is played.
enum PieceAnimation {
  instant('Instant', Duration.zero),
  fast('Fast', Duration(milliseconds: 96)),
  moderate('Moderate', Duration(milliseconds: 250)),
  slow('Slow', Duration(milliseconds: 450));

  const PieceAnimation(this.label, this.duration);

  final String label;
  final Duration duration;
}

/// How the board and pieces look. Persisted across launches.
@immutable
class Appearance {
  const Appearance({
    this.boardThemeId = goldenThemeId,
    this.customLight = const Color(0xFFF0D9B6),
    this.customDark = const Color(0xFFB58863),
    this.pieceSet = PieceSet.cburnett,
    this.whitePieces = defaultWhitePieces,
    this.blackPieces = defaultBlackPieces,
    this.moveSounds = true,
    this.showBestMoveArrow = true,
    this.showEvalBar = true,
    this.animation = PieceAnimation.moderate,
    this.whiteOutline,
    this.blackOutline,
    this.outlineWidth = 0,
    this.background = defaultBackground,
  });

  /// [boardThemeId] when the user picked their own square colours.
  static const customThemeId = 'custom';
  static const defaultWhitePieces = Color(0xFFFFFFFF);

  /// Golden yellow: ChessHive's "black" pieces.
  static const defaultBlackPieces = Color(0xFFC99416);

  /// The piece images' own colours: no tinting needed.
  static const untintedWhite = Color(0xFFFFFFFF);
  static const untintedBlack = Color(0xFF000000);

  /// Golden yellow, ChessHive's colour.
  static const defaultBackground = Color(0xFFE8B423);

  /// Ready-made backgrounds offered in settings.
  static const backgroundPresets = [
    defaultBackground,
    Color(0xFF34373C),
    Color(0xFF1F2124),
    Color(0xFF2B3A4A),
    Color(0xFF2E3B2F),
    Color(0xFF4A4D52),
    Color(0xFFECEDEF),
  ];

  final String boardThemeId;
  final Color customLight;
  final Color customDark;
  final PieceSet pieceSet;

  /// Tint of the white pieces' fill; white leaves them unchanged.
  final Color whitePieces;

  /// Tint of the black pieces' fill; black leaves them unchanged.
  final Color blackPieces;

  /// Play a sound for every move made on a board.
  final bool moveSounds;

  /// Draw the engine's best move as an arrow on the analysis board.
  final bool showBestMoveArrow;

  /// Show the evaluation bar under the analysis board (its eye icon
  /// switches this too).
  final bool showEvalBar;

  /// How fast pieces move on the boards.
  final PieceAnimation animation;

  /// The colour of the white / black pieces' lines: the outline and the
  /// drawn details inside (dark on white pieces, light on black ones), and
  /// the ring around them when [outlineWidth] is set. Null: the piece
  /// set's own (black for White, white for Black).
  final Color? whiteOutline;
  final Color? blackOutline;

  /// Thickness of a ring around the pieces, outside them only:
  /// 0 (none) to [maxOutlineWidth].
  final int outlineWidth;

  static const maxOutlineWidth = 10;

  /// Ring thickness per [outlineWidth] step, as a share of the piece image.
  static const _ringStep = 0.006;

  /// The app's background colour.
  final Color background;

  /// The colour of White's / Black's lines (see [whiteOutline]).
  Color get whiteLines => _visible(whiteOutline) ?? untintedBlack;
  Color get blackLines => _visible(blackOutline) ?? untintedWhite;

  /// Ring thickness around White's / Black's pieces, as a share of the
  /// piece image (0: none). Black pieces on the black & white board get a
  /// thin one unless a width is chosen: they'd vanish on the black squares.
  double get whiteRing => outlineWidth * _ringStep;
  double get blackRing =>
      (outlineWidth == 0 && boardThemeId == blackWhiteThemeId ? 4 : outlineWidth) * _ringStep;

  /// Colours the pieces are drawn in, for reading this app's own
  /// screenshots back (see `recognizeBoard`).
  List<Color> get pieceColors => [
        whitePieces,
        blackPieces,
        whiteLines,
        blackLines,
      ];

  static Color? _visible(Color? c) => c == null || c.a == 0 ? null : c;

  bool get isCustomBoard => boardThemeId == customThemeId;

  ChessboardColorScheme get colorScheme {
    if (isCustomBoard) return _solidScheme(customLight, customDark);
    return boardThemes
        .firstWhere((t) => t.id == boardThemeId, orElse: () => boardThemes.first)
        .scheme;
  }

  Appearance copyWith({
    String? boardThemeId,
    Color? customLight,
    Color? customDark,
    PieceSet? pieceSet,
    Color? whitePieces,
    Color? blackPieces,
    bool? moveSounds,
    bool? showBestMoveArrow,
    bool? showEvalBar,
    PieceAnimation? animation,
    Color? Function()? whiteOutline,
    Color? Function()? blackOutline,
    int? outlineWidth,
    Color? background,
  }) {
    return Appearance(
      boardThemeId: boardThemeId ?? this.boardThemeId,
      customLight: customLight ?? this.customLight,
      customDark: customDark ?? this.customDark,
      pieceSet: pieceSet ?? this.pieceSet,
      whitePieces: whitePieces ?? this.whitePieces,
      blackPieces: blackPieces ?? this.blackPieces,
      moveSounds: moveSounds ?? this.moveSounds,
      showBestMoveArrow: showBestMoveArrow ?? this.showBestMoveArrow,
      showEvalBar: showEvalBar ?? this.showEvalBar,
      animation: animation ?? this.animation,
      whiteOutline: whiteOutline == null ? this.whiteOutline : whiteOutline(),
      blackOutline: blackOutline == null ? this.blackOutline : blackOutline(),
      outlineWidth: outlineWidth ?? this.outlineWidth,
      background: background ?? this.background,
    );
  }

  static const _boardThemeKey = 'appearance.boardTheme';
  static const _customLightKey = 'appearance.customLight';
  static const _customDarkKey = 'appearance.customDark';
  static const _pieceSetKey = 'appearance.pieceSet';
  static const _whitePiecesKey = 'appearance.whitePieces';
  static const _blackPiecesKey = 'appearance.blackPieces';
  static const _moveSoundsKey = 'appearance.moveSounds';
  static const _bestMoveArrowKey = 'appearance.bestMoveArrow';
  static const _evalBarKey = 'appearance.evalBar';
  static const _animationKey = 'appearance.animation';
  static const _whiteOutlineKey = 'appearance.whiteOutline';
  static const _blackOutlineKey = 'appearance.blackOutline';
  static const _outlineWidthKey = 'appearance.outlineWidth';
  static const _backgroundKey = 'appearance.background';

  factory Appearance.fromPrefs(SharedPreferences prefs) {
    const defaults = Appearance();
    Color? color(String key) {
      final value = prefs.getInt(key);
      return value == null ? null : Color(value);
    }

    final setName = prefs.getString(_pieceSetKey);
    return Appearance(
      boardThemeId: prefs.getString(_boardThemeKey) ?? defaults.boardThemeId,
      customLight: color(_customLightKey) ?? defaults.customLight,
      customDark: color(_customDarkKey) ?? defaults.customDark,
      pieceSet: PieceSet.values.firstWhere(
        (s) => s.name == setName,
        orElse: () => defaults.pieceSet,
      ),
      whitePieces: color(_whitePiecesKey) ?? defaults.whitePieces,
      blackPieces: color(_blackPiecesKey) ?? defaults.blackPieces,
      moveSounds: prefs.getBool(_moveSoundsKey) ?? defaults.moveSounds,
      showBestMoveArrow: prefs.getBool(_bestMoveArrowKey) ?? defaults.showBestMoveArrow,
      showEvalBar: prefs.getBool(_evalBarKey) ?? defaults.showEvalBar,
      animation: PieceAnimation.values.asNameMap()[prefs.getString(_animationKey)] ?? defaults.animation,
      whiteOutline: color(_whiteOutlineKey),
      blackOutline: color(_blackOutlineKey),
      outlineWidth: (prefs.getInt(_outlineWidthKey) ?? defaults.outlineWidth).clamp(0, maxOutlineWidth),
      background: color(_backgroundKey) ?? defaults.background,
    );
  }

  Future<void> saveTo(SharedPreferences prefs) async {
    await prefs.setString(_boardThemeKey, boardThemeId);
    await prefs.setInt(_customLightKey, customLight.toARGB32());
    await prefs.setInt(_customDarkKey, customDark.toARGB32());
    await prefs.setString(_pieceSetKey, pieceSet.name);
    await prefs.setInt(_whitePiecesKey, whitePieces.toARGB32());
    await prefs.setInt(_blackPiecesKey, blackPieces.toARGB32());
    await prefs.setBool(_moveSoundsKey, moveSounds);
    await prefs.setBool(_bestMoveArrowKey, showBestMoveArrow);
    await prefs.setBool(_evalBarKey, showEvalBar);
    await prefs.setString(_animationKey, animation.name);
    await prefs.setInt(_backgroundKey, background.toARGB32());
    await prefs.setInt(_outlineWidthKey, outlineWidth);
    for (final (key, color) in [(_whiteOutlineKey, whiteOutline), (_blackOutlineKey, blackOutline)]) {
      if (color == null) {
        await prefs.remove(key);
      } else {
        await prefs.setInt(key, color.toARGB32());
      }
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Appearance &&
      other.boardThemeId == boardThemeId &&
      other.customLight == customLight &&
      other.customDark == customDark &&
      other.pieceSet == pieceSet &&
      other.whitePieces == whitePieces &&
      other.blackPieces == blackPieces &&
      other.moveSounds == moveSounds &&
      other.showBestMoveArrow == showBestMoveArrow &&
      other.showEvalBar == showEvalBar &&
      other.animation == animation &&
      other.whiteOutline == whiteOutline &&
      other.blackOutline == blackOutline &&
      other.outlineWidth == outlineWidth &&
      other.background == background;

  @override
  int get hashCode =>
      Object.hash(
        boardThemeId,
        customLight,
        customDark,
        pieceSet,
        whitePieces,
        blackPieces,
        moveSounds,
        showBestMoveArrow,
        showEvalBar,
        animation,
        whiteOutline,
        blackOutline,
        outlineWidth,
        background,
      );
}

ChessboardColorScheme _solidScheme(Color light, Color dark) {
  return ChessboardColorScheme.brown.copyWith(
    lightSquare: light,
    darkSquare: dark,
    background: SolidColorChessboardBackground(lightSquare: light, darkSquare: dark),
    whiteCoordBackground: SolidColorChessboardBackground(
      lightSquare: light,
      darkSquare: dark,
      coordinates: true,
    ),
    blackCoordBackground: SolidColorChessboardBackground(
      lightSquare: light,
      darkSquare: dark,
      coordinates: true,
      orientation: Side.black,
    ),
  );
}

/// Overridden in `main` with the loaded instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

final appearanceProvider = NotifierProvider<AppearanceNotifier, Appearance>(
  AppearanceNotifier.new,
);

class AppearanceNotifier extends Notifier<Appearance> {
  @override
  Appearance build() => Appearance.fromPrefs(ref.watch(sharedPreferencesProvider));

  void setBoardTheme(String id) => _update(state.copyWith(boardThemeId: id));

  /// Switches to a custom board; the colour not given is taken from the
  /// current board so changing one keeps the other.
  void setBoardColors({Color? light, Color? dark}) {
    final current = state.colorScheme;
    _update(state.copyWith(
      boardThemeId: Appearance.customThemeId,
      customLight: light ?? current.lightSquare,
      customDark: dark ?? current.darkSquare,
    ));
  }

  void setPieceSet(PieceSet set) => _update(state.copyWith(pieceSet: set));

  void setPieceColors({Color? white, Color? black}) =>
      _update(state.copyWith(whitePieces: white, blackPieces: black));

  void setMoveSounds(bool on) => _update(state.copyWith(moveSounds: on));

  void setShowBestMoveArrow(bool on) => _update(state.copyWith(showBestMoveArrow: on));

  void setShowEvalBar(bool on) => _update(state.copyWith(showEvalBar: on));

  void setAnimation(PieceAnimation animation) => _update(state.copyWith(animation: animation));

  /// The colour of White's / Black's lines; null restores the set's own.
  void setWhiteOutline(Color? color) => _update(state.copyWith(whiteOutline: () => color));

  void setBlackOutline(Color? color) => _update(state.copyWith(blackOutline: () => color));

  void setOutlineWidth(int width) =>
      _update(state.copyWith(outlineWidth: width.clamp(0, Appearance.maxOutlineWidth)));

  void setBackground(Color color) => _update(state.copyWith(background: color));

  void reset() => _update(const Appearance());

  void _update(Appearance appearance) {
    state = appearance;
    appearance.saveTo(ref.read(sharedPreferencesProvider));
  }
}

/// The piece images to draw, recoloured to the chosen piece and line
/// colours and ringed as chosen.
final pieceAssetsProvider = FutureProvider<PieceAssets>((ref) {
  final (set, white, black, whiteLines, blackLines, whiteRing, blackRing) = ref.watch(
    appearanceProvider.select(
      (a) => (a.pieceSet, a.whitePieces, a.blackPieces, a.whiteLines, a.blackLines, a.whiteRing, a.blackRing),
    ),
  );
  return tintedPieceAssets(
    set,
    white: white,
    black: black,
    whiteLines: whiteLines,
    blackLines: blackLines,
    whiteRing: whiteRing,
    blackRing: blackRing,
  );
});

/// [set]'s pieces recoloured: fills to [white] / [black], lines (outline and
/// inner details) to [whiteLines] / [blackLines], with a ring of the line
/// colour [whiteRing] / [blackRing] thick (a share of the image) outside
/// the piece. The images go in chessground's image cache under their own
/// keys, so the board widgets can use them like any set.
Future<PieceAssets> tintedPieceAssets(
  PieceSet set, {
  required Color white,
  required Color black,
  Color whiteLines = Appearance.untintedBlack,
  Color blackLines = Appearance.untintedWhite,
  double whiteRing = 0,
  double blackRing = 0,
}) async {
  final assets = <PieceKind, AssetImage>{};
  for (final MapEntry(key: kind, value: asset) in set.assets.entries) {
    final isWhite = kind.side == Side.white;
    final fill = isWhite ? white : black;
    final lines = isWhite ? whiteLines : blackLines;
    final ring = isWhite ? whiteRing : blackRing;
    final recolored = neutralizedSets.contains(set) ||
        (isWhite
            ? fill != Appearance.untintedWhite || lines != Appearance.untintedBlack
            : fill != Appearance.untintedBlack || lines != Appearance.untintedWhite);
    if (!recolored && ring <= 0) {
      assets[kind] = asset;
      continue;
    }
    String hex(Color c) => c.toARGB32().toRadixString(16);
    final key = AssetImage(
      '${asset.assetName}#${hex(fill)}#${hex(lines)}#${ring.toStringAsFixed(3)}',
      package: asset.package,
    );
    if (ChessgroundImages.instance.get(key) == null) {
      var image = await ChessgroundImages.instance.load(asset);
      // White pieces are a light fill with dark lines; black pieces the
      // other way round.
      if (recolored) image = await _recolor(image, dark: isWhite ? lines : fill, light: isWhite ? fill : lines);
      if (ring > 0) image = await _ring(image, lines, ring);
      ChessgroundImages.instance.add(key, image);
    }
    assets[kind] = key;
  }
  return assets;
}

/// [source] with a ring of [color] around its shape, [thickness] (a share
/// of the image width) wide, outside it only: the shape is stamped in
/// [color] at offsets around a circle (a cheap dilation), then the piece
/// itself is drawn over it unchanged, at its own size.
Future<ui.Image> _ring(ui.Image source, Color color, double thickness) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final radius = source.width * thickness;
  final stamp = Paint()..colorFilter = ColorFilter.mode(color, BlendMode.srcIn);
  const steps = 24;
  for (var i = 0; i < steps; i++) {
    final angle = 2 * math.pi * i / steps;
    canvas.drawImage(source, Offset(math.cos(angle) * radius, math.sin(angle) * radius), stamp);
  }
  canvas.drawImage(source, Offset.zero, Paint());
  return recorder.endRecording().toImage(source.width, source.height);
}

/// [source] (a piece drawn in black and white and the greys between)
/// mapped so that black becomes [dark] and white becomes [light], greys in
/// between: fill, lines, details and shading all take the new colours.
/// Alpha is left untouched.
Future<ui.Image> _recolor(ui.Image source, {required Color dark, required Color light}) {
  List<double> row(double d, double l) => [(l - d) * 0.299, (l - d) * 0.587, (l - d) * 0.114, 0, d * 255];
  final matrix = <double>[
    ...row(dark.r, light.r),
    ...row(dark.g, light.g),
    ...row(dark.b, light.b),
    0, 0, 0, 1, 0, //
  ];
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImage(
    source,
    Offset.zero,
    Paint()..colorFilter = ColorFilter.matrix(matrix),
  );
  return recorder.endRecording().toImage(source.width, source.height);
}
