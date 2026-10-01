/// Facts about the app shown to users (About screen, crash reports).
abstract final class AppInfo {
  static const name = 'ChessGeek';

  /// Where the GPL source code is published. The GPL requires users to be
  /// able to get it, so this repository must be public before release.
  static const sourceUrl = 'https://github.com/EduardsLeonovics/chess_scanner';

  /// Where crash reports and support questions should go. Set before release;
  /// while null, crash reports are shared without a suggested recipient.
  static const String? supportEmail = null;

  static const legalese =
      'Copyright (C) 2026 Eduards Leonovics.\n\n'
      'ChessGeek is free software under the GNU General Public License v3. '
      'You may redistribute and modify it under its terms. The source code is at '
      '$sourceUrl.\n\n'
      'Uses Stockfish, the open-source chess engine (GPLv3). '
      'Not affiliated with or endorsed by Lichess or Chess.com.';
}
