/// Facts about the app shown to users (About screen, crash reports).
abstract final class AppInfo {
  static const name = 'ChessHive';

  /// Where the GPL source code is published. The GPL requires users to be
  /// able to get it, so this repository must be public before release.
  static const sourceUrl = 'https://github.com/EduardsLeonovics/chesshive';

  /// The privacy policy (share_site/privacy/). Its #delete section
  /// is the account-deletion page Google Play asks for.
  static const privacyUrl = 'https://chesshive.app/privacy/';

  /// The terms of use (share_site/terms/), accepted when creating
  /// an account.
  static const termsUrl = 'https://chesshive.app/terms/';

  /// Where crash reports and support questions should go (forwarded by
  /// Cloudflare Email Routing).
  static const supportEmail = 'support@chesshive.app';

  static const legalese =
      'Copyright (C) 2026 Eduards Leonovics.\n\n'
      'ChessHive is free software under the GNU General Public License v3. '
      'You may redistribute and modify it under its terms. The source code is at '
      '$sourceUrl.\n\n'
      'Uses Stockfish, the open-source chess engine (GPLv3). '
      'Not affiliated with or endorsed by Lichess or Chess.com.';
}
