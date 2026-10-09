import 'package:chess_scanner/src/settings/appearance.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show PieceKind;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults to the golden look: white and yellow board, golden black pieces', () async {
    SharedPreferences.setMockInitialValues({});
    final appearance = Appearance.fromPrefs(await SharedPreferences.getInstance());
    expect(appearance, const Appearance());
    expect(appearance.boardThemeId, goldenThemeId);
    expect(appearance.colorScheme.lightSquare, const Color(0xFFFFFDF5));
    expect(appearance.colorScheme.darkSquare, const Color(0xFFF2CC55));
    expect(appearance.whitePieces, const Color(0xFFFFFFFF));
    expect(appearance.blackPieces, Appearance.defaultBlackPieces);
    expect(appearance.background, Appearance.defaultBackground);
    expect(appearance.blackRing, 0, reason: 'no ring by default: both sides the same size');
    expect(appearance.whiteRing, 0);
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
      animation: PieceAnimation.instant,
      blackOutline: Color(0xFFFF0000),
      outlineWidth: 4,
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

  test('offers textured board themes and the piece styles', () {
    expect(
      boardThemes.where((t) => t.scheme.background is ImageChessboardBackground),
      isNotEmpty,
    );
    expect([for (final (_, label) in pieceStyles) label], [
      'Classic', 'Merida', 'Geo', 'Ink', 'Hive', 'Modern', 'Celtic', 'Fantasy', 'Spatial',
    ]);
  });

  test("lines default to the set's own; a ring only on the black & white board", () {
    const plain = Appearance(boardThemeId: 'brown');
    expect(plain.whiteLines, const Color(0xFF000000));
    expect(plain.blackLines, const Color(0xFFFFFFFF));
    expect(plain.blackRing, 0);
    const bw = Appearance(boardThemeId: blackWhiteThemeId);
    expect(bw.colorScheme.darkSquare, const Color(0xFF000000));
    expect(bw.blackRing, greaterThan(0), reason: 'black pieces would vanish on black squares');
    expect(bw.whiteRing, 0);
    final wide = plain.copyWith(outlineWidth: 5);
    expect(wide.whiteRing, wide.blackRing);
    expect(wide.whiteRing, greaterThan(0));
  });

  test('a cleared outline is not saved', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await const Appearance(whiteOutline: Color(0xFF00FF00)).saveTo(prefs);
    await const Appearance().saveTo(prefs);
    expect(Appearance.fromPrefs(prefs).whiteOutline, isNull);
  });

  testWidgets('recoloured pieces are drawn under their own image keys', (tester) async {
    final assets = await tester.runAsync(() => tintedPieceAssets(
          PieceSet.cburnett,
          white: Appearance.untintedWhite,
          black: const Color(0xFFC99416),
          blackLines: const Color(0xFFFF0000),
        ));
    final blackKing = assets![PieceKind.blackKing]!;
    expect(blackKing.assetName, contains('#ffff0000#'));
    expect(ChessgroundImages.instance.get(blackKing), isNotNull);
    expect(assets[PieceKind.whiteKing], PieceSet.cburnett.assets[PieceKind.whiteKing], reason: 'untouched');
  });

  testWidgets("a black piece's inner details take the line colour, and its size doesn't change", (tester) async {
    await tester.runAsync(() async {
      final original = await ChessgroundImages.instance.load(PieceSet.cburnett.assets[PieceKind.blackKing]!);
      final assets = await tintedPieceAssets(
        PieceSet.cburnett,
        white: Appearance.untintedWhite,
        black: const Color(0xFFC99416),
        blackLines: const Color(0xFFFF0000),
      );
      final recolored = ChessgroundImages.instance.get(assets[PieceKind.blackKing]!)!;
      final before = (await original.toByteData())!.buffer.asUint8List();
      final after = (await recolored.toByteData())!.buffer.asUint8List();
      var whiteBefore = 0, whiteAfter = 0, redAfter = 0;
      var opaqueBefore = 0, opaqueAfter = 0;
      for (var i = 0; i < before.length; i += 4) {
        if (before[i + 3] > 200) opaqueBefore++;
        if (after[i + 3] > 200) opaqueAfter++;
        if (before[i + 3] > 200 && before[i] > 220 && before[i + 1] > 220 && before[i + 2] > 220) whiteBefore++;
        if (after[i + 3] > 200 && after[i] > 220 && after[i + 1] > 220 && after[i + 2] > 220) whiteAfter++;
        if (after[i + 3] > 200 && after[i] > 200 && after[i + 1] < 60 && after[i + 2] < 60) redAfter++;
      }
      expect(whiteBefore, greaterThan(100), reason: 'the black king has white details');
      expect(whiteAfter, 0, reason: 'no white left: the details are red now');
      expect(redAfter, greaterThan(whiteBefore ~/ 2));
      expect(opaqueAfter, opaqueBefore, reason: 'no ring: exactly the same shape');
    });
  });
}
