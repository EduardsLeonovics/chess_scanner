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

final boardThemes = [
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
/// ChessGeek's own (all licensed for commercial use; see
/// third_party/chessground/LICENSES.md).
const pieceStyles = [
  (PieceSet.cburnett, 'Classic'),
  (PieceSet.merida, 'Merida'),
  (PieceSet.chessnut, 'Chessnut'),
  (PieceSet.geo, 'Geo'),
  (PieceSet.ink, 'Ink'),
  (PieceSet.bubble, 'Bubble'),
];

/// How the board and pieces look. Persisted across launches.
@immutable
class Appearance {
  const Appearance({
    this.boardThemeId = 'brown',
    this.customLight = const Color(0xFFF0D9B6),
    this.customDark = const Color(0xFFB58863),
    this.pieceSet = PieceSet.cburnett,
    this.whitePieces = defaultWhitePieces,
    this.blackPieces = defaultBlackPieces,
    this.moveSounds = true,
    this.showBestMoveArrow = true,
    this.whiteOutline,
    this.blackOutline,
    this.background = defaultBackground,
  });

  /// [boardThemeId] when the user picked their own square colours.
  static const customThemeId = 'custom';
  static const defaultWhitePieces = Color(0xFFFFFFFF);
  static const defaultBlackPieces = Color(0xFF000000);

  /// A dark grey, light enough that black pieces off the board (e.g. in
  /// the editor's palette) stand out against it.
  static const defaultBackground = Color(0xFF34373C);

  /// Ready-made backgrounds offered in settings.
  static const backgroundPresets = [
    defaultBackground,
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

  /// A ring drawn around the white / black pieces. Null: the default (none,
  /// or white for black pieces on the [blackWhiteThemeId] board);
  /// [noOutline]: none, even there.
  final Color? whiteOutline;
  final Color? blackOutline;

  static const noOutline = Color(0x00000000);

  /// The app's background colour.
  final Color background;

  Color? get effectiveWhiteOutline => _visible(whiteOutline);

  Color? get effectiveBlackOutline =>
      _visible(blackOutline ?? (boardThemeId == blackWhiteThemeId ? const Color(0xFFFFFFFF) : null));

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
    Color? Function()? whiteOutline,
    Color? Function()? blackOutline,
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
      whiteOutline: whiteOutline == null ? this.whiteOutline : whiteOutline(),
      blackOutline: blackOutline == null ? this.blackOutline : blackOutline(),
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
  static const _whiteOutlineKey = 'appearance.whiteOutline';
  static const _blackOutlineKey = 'appearance.blackOutline';
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
      whiteOutline: color(_whiteOutlineKey),
      blackOutline: color(_blackOutlineKey),
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
    await prefs.setInt(_backgroundKey, background.toARGB32());
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
      other.whiteOutline == whiteOutline &&
      other.blackOutline == blackOutline &&
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
        whiteOutline,
        blackOutline,
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

  /// [Appearance.noOutline] turns an outline off; null restores the default.
  void setWhiteOutline(Color? color) => _update(state.copyWith(whiteOutline: () => color));

  void setBlackOutline(Color? color) => _update(state.copyWith(blackOutline: () => color));

  void setBackground(Color color) => _update(state.copyWith(background: color));

  void reset() => _update(const Appearance());

  void _update(Appearance appearance) {
    state = appearance;
    appearance.saveTo(ref.read(sharedPreferencesProvider));
  }
}

/// The piece images to draw, recoloured to the chosen piece colours and
/// outlined as chosen.
final pieceAssetsProvider = FutureProvider<PieceAssets>((ref) {
  final (set, white, black, whiteOutline, blackOutline) = ref.watch(
    appearanceProvider.select(
      (a) => (a.pieceSet, a.whitePieces, a.blackPieces, a.effectiveWhiteOutline, a.effectiveBlackOutline),
    ),
  );
  return tintedPieceAssets(
    set,
    white: white,
    black: black,
    whiteOutline: whiteOutline,
    blackOutline: blackOutline,
  );
});

/// [set]'s pieces with white fills tinted [white] and black fills tinted
/// [black], ringed with [whiteOutline] / [blackOutline] when given. The
/// recoloured images are put in chessground's image cache under their own
/// keys, so the board widgets can use them like any set.
Future<PieceAssets> tintedPieceAssets(
  PieceSet set, {
  required Color white,
  required Color black,
  Color? whiteOutline,
  Color? blackOutline,
}) async {
  final assets = <PieceKind, AssetImage>{};
  for (final MapEntry(key: kind, value: asset) in set.assets.entries) {
    final isWhite = kind.side == Side.white;
    final color = isWhite ? white : black;
    final outline = isWhite ? whiteOutline : blackOutline;
    final tinted = color != (isWhite ? Appearance.defaultWhitePieces : Appearance.defaultBlackPieces);
    if (!tinted && outline == null) {
      assets[kind] = asset;
      continue;
    }
    String hex(Color c) => c.toARGB32().toRadixString(16);
    final key = AssetImage(
      '${asset.assetName}#${hex(color)}${outline == null ? '' : '#${hex(outline)}'}',
      package: asset.package,
    );
    if (ChessgroundImages.instance.get(key) == null) {
      var image = await ChessgroundImages.instance.load(asset);
      if (tinted) image = await _tint(image, color, kind.side);
      if (outline != null) image = await _outline(image, outline);
      ChessgroundImages.instance.add(key, image);
    }
    assets[kind] = key;
  }
  return assets;
}

/// [source] on top of a ring of [color] around its shape: the shape is
/// stamped in [color] at offsets around a circle (a cheap dilation),
/// then the piece itself is drawn over it.
Future<ui.Image> _outline(ui.Image source, Color color) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final radius = source.width * 0.035;
  final stamp = Paint()..colorFilter = ColorFilter.mode(color, BlendMode.srcIn);
  const steps = 16;
  for (var i = 0; i < steps; i++) {
    final angle = 2 * math.pi * i / steps;
    canvas.drawImage(source, Offset(math.cos(angle) * radius, math.sin(angle) * radius), stamp);
  }
  canvas.drawImage(source, Offset.zero, Paint());
  return recorder.endRecording().toImage(source.width, source.height);
}

Future<ui.Image> _tint(ui.Image source, Color color, Side side) {
  final (r, g, b) = (color.r, color.g, color.b);
  // White pieces: multiply, so the white fill takes the colour and the
  // dark outline stays dark. Black pieces: screen, so the black fill takes
  // the colour and light details stay light. Alpha is left untouched.
  final matrix = side == Side.white
      ? <double>[r, 0, 0, 0, 0, 0, g, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, 1, 0]
      : <double>[
          1 - r, 0, 0, 0, 255 * r, //
          0, 1 - g, 0, 0, 255 * g,
          0, 0, 1 - b, 0, 255 * b,
          0, 0, 0, 1, 0,
        ];
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImage(
    source,
    Offset.zero,
    Paint()..colorFilter = ColorFilter.matrix(matrix),
  );
  return recorder.endRecording().toImage(source.width, source.height);
}
