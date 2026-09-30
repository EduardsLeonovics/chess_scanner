import 'package:chess_scanner/src/settings/appearance.dart';
import 'package:chessground/chessground.dart';
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

  test('offers textured board themes and five piece styles', () {
    expect(
      boardThemes.where((t) => t.scheme.background is ImageChessboardBackground),
      isNotEmpty,
    );
    expect(pieceStyles, hasLength(5));
  });
}
