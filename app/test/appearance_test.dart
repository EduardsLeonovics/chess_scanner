import 'package:chess_scanner/src/settings/appearance.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show PieceKind;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults to the brown board and classic pieces', () async {
    SharedPreferences.setMockInitialValues({});
    final appearance = Appearance.fromPrefs(await SharedPreferences.getInstance());
    expect(appearance, const Appearance());
    expect(appearance.colorScheme, ChessboardColorScheme.brown);
    expect(appearance.pieceSet, PieceSet.cburnett);
  });

  test('round-trips through preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const custom = Appearance(
      boardThemeId: Appearance.customThemeId,
      customLight: Color(0xFFEEEED2),
      customDark: Color(0xFF769656),
      pieceSet: PieceSet.merida,
      whitePieces: Color(0xFFFFE0B2),
      blackPieces: Color(0xFF1E2A38),
      showBestMoveArrow: false,
      showEvalBar: false,
      blackOutline: Color(0xFFFF0000),
    );
    await custom.saveTo(prefs);
    expect(Appearance.fromPrefs(prefs), custom);
  });

  test('a custom board uses the chosen square colours', () {
    const appearance = Appearance(
      boardThemeId: Appearance.customThemeId,
      customLight: Color(0xFFEEEED2),
      customDark: Color(0xFF769656),
    );
    expect(appearance.colorScheme.lightSquare, const Color(0xFFEEEED2));
    expect(appearance.colorScheme.darkSquare, const Color(0xFF769656));
  });

  test('offers textured board themes and six piece styles', () {
    expect(
      boardThemes.where((t) => t.scheme.background is ImageChessboardBackground),
      isNotEmpty,
    );
    expect(pieceStyles, hasLength(6));
  });

  test('the black & white board outlines black pieces in white unless turned off', () {
    const plain = Appearance();
    expect(plain.effectiveBlackOutline, isNull);
    const bw = Appearance(boardThemeId: blackWhiteThemeId);
    expect(bw.colorScheme.lightSquare, const Color(0xFFFFFFFF));
    expect(bw.colorScheme.darkSquare, const Color(0xFF000000));
    expect(bw.effectiveBlackOutline, const Color(0xFFFFFFFF));
    expect(bw.effectiveWhiteOutline, isNull);
    final off = bw.copyWith(blackOutline: () => Appearance.noOutline);
    expect(off.effectiveBlackOutline, isNull);
    final red = bw.copyWith(blackOutline: () => const Color(0xFFFF0000));
    expect(red.effectiveBlackOutline, const Color(0xFFFF0000));
  });

  test('a cleared outline is not saved', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await const Appearance(whiteOutline: Color(0xFF00FF00)).saveTo(prefs);
    await const Appearance().saveTo(prefs);
    expect(Appearance.fromPrefs(prefs).whiteOutline, isNull);
  });

  testWidgets('outlined pieces are drawn under their own image keys', (tester) async {
    final assets = await tester.runAsync(() => tintedPieceAssets(
          PieceSet.cburnett,
          white: Appearance.defaultWhitePieces,
          black: Appearance.defaultBlackPieces,
          blackOutline: const Color(0xFFFFFFFF),
        ));
    final blackKing = assets![PieceKind.blackKing]!;
    expect(blackKing.assetName, endsWith('#ffffffff'));
    expect(ChessgroundImages.instance.get(blackKing), isNotNull);
    expect(assets[PieceKind.whiteKing], PieceSet.cburnett.assets[PieceKind.whiteKing], reason: 'untouched');
  });
}
