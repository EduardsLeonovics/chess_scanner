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

const boardThemes = [
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
];

/// The piece styles offered in settings: widely used Lichess sets.
const pieceStyles = [
  (PieceSet.cburnett, 'Classic'),
  (PieceSet.merida, 'Merida'),
  (PieceSet.alpha, 'Alpha'),
  (PieceSet.california, 'California'),
  (PieceSet.staunty, 'Staunty'),
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
  });

  /// [boardThemeId] when the user picked their own square colours.
  static const customThemeId = 'custom';
  static const defaultWhitePieces = Color(0xFFFFFFFF);
  static const defaultBlackPieces = Color(0xFF000000);

  final String boardThemeId;
  final Color customLight;
  final Color customDark;
  final PieceSet pieceSet;

  /// Tint of the white pieces' fill; white leaves them unchanged.
  final Color whitePieces;

  /// Tint of the black pieces' fill; black leaves them unchanged.
  final Color blackPieces;

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
  }) {
    return Appearance(
      boardThemeId: boardThemeId ?? this.boardThemeId,
      customLight: customLight ?? this.customLight,
      customDark: customDark ?? this.customDark,
      pieceSet: pieceSet ?? this.pieceSet,
      whitePieces: whitePieces ?? this.whitePieces,
      blackPieces: blackPieces ?? this.blackPieces,
    );
  }

  static const _boardThemeKey = 'appearance.boardTheme';
  static const _customLightKey = 'appearance.customLight';
  static const _customDarkKey = 'appearance.customDark';
  static const _pieceSetKey = 'appearance.pieceSet';
  static const _whitePiecesKey = 'appearance.whitePieces';
  static const _blackPiecesKey = 'appearance.blackPieces';

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
    );
  }

  Future<void> saveTo(SharedPreferences prefs) async {
    await prefs.setString(_boardThemeKey, boardThemeId);
    await prefs.setInt(_customLightKey, customLight.toARGB32());
    await prefs.setInt(_customDarkKey, customDark.toARGB32());
    await prefs.setString(_pieceSetKey, pieceSet.name);
    await prefs.setInt(_whitePiecesKey, whitePieces.toARGB32());
    await prefs.setInt(_blackPiecesKey, blackPieces.toARGB32());
  }

  @override
  bool operator ==(Object other) =>
      other is Appearance &&
      other.boardThemeId == boardThemeId &&
      other.customLight == customLight &&
      other.customDark == customDark &&
      other.pieceSet == pieceSet &&
      other.whitePieces == whitePieces &&
      other.blackPieces == blackPieces;

  @override
  int get hashCode =>
      Object.hash(boardThemeId, customLight, customDark, pieceSet, whitePieces, blackPieces);
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

  void reset() => _update(const Appearance());

  void _update(Appearance appearance) {
    state = appearance;
    appearance.saveTo(ref.read(sharedPreferencesProvider));
  }
}

/// The piece images to draw, recoloured to the chosen piece colours.
final pieceAssetsProvider = FutureProvider<PieceAssets>((ref) {
  final (set, white, black) = ref.watch(
    appearanceProvider.select((a) => (a.pieceSet, a.whitePieces, a.blackPieces)),
  );
  return tintedPieceAssets(set, white: white, black: black);
});

/// [set]'s pieces with white fills tinted [white] and black fills tinted
/// [black]. The recoloured images are put in chessground's image cache
/// under their own keys, so the board widgets can use them like any set.
Future<PieceAssets> tintedPieceAssets(
  PieceSet set, {
  required Color white,
  required Color black,
}) async {
  final assets = <PieceKind, AssetImage>{};
  for (final MapEntry(key: kind, value: asset) in set.assets.entries) {
    final color = kind.side == Side.white ? white : black;
    final unchanged = color ==
        (kind.side == Side.white ? Appearance.defaultWhitePieces : Appearance.defaultBlackPieces);
    if (unchanged) {
      assets[kind] = asset;
      continue;
    }
    final key = AssetImage(
      '${asset.assetName}#${color.toARGB32().toRadixString(16)}',
      package: asset.package,
    );
    if (ChessgroundImages.instance.get(key) == null) {
      final source = await ChessgroundImages.instance.load(asset);
      ChessgroundImages.instance.add(key, await _tint(source, color, kind.side));
    }
    assets[kind] = key;
  }
  return assets;
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
