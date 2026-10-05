import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Where the community lives: a Supabase project set up with
/// `backend/supabase/schema.sql`.
///
/// Both values are public by design (the publishable key, called "anon"
/// in older projects, only allows what the database's row-level security
/// allows), so they can ship in the app. Fill them in here, or give them at
/// build time:
/// `flutter build apk --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_KEY=…`
abstract final class CommunityConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://zpbpolhskkiedzdspmje.supabase.co',
  );
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_bxFpAsKUrT7IAH4ttultQQ_Bkt_O7B-',
  );

  /// Where the sign-up confirmation email sends the user back to: the app.
  static const authRedirect = 'chessgeek://login-callback';

  static bool get configured => url.isNotEmpty && publishableKey.isNotEmpty;

  /// Whether [init] connected; false in tests and unconfigured builds, where
  /// the Community tab explains instead.
  static bool ready = false;

  /// Connects to the project, if one is configured. Never throws: without
  /// the community the rest of the app still works.
  static Future<void> init() async {
    if (!configured) return;
    try {
      await Supabase.initialize(url: url, publishableKey: publishableKey);
      ready = true;
    } catch (e) {
      debugPrint('Community unavailable: $e');
    }
  }
}
