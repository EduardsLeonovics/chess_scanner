import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../community/community_config.dart';
import '../settings/appearance.dart' show sharedPreferencesProvider;

/// What the anonymous usage statistics count. Only totals per day reach the
/// server (see `record_usage` in backend/supabase/schema.sql): no user or
/// device id, no IP address, no positions or text.
enum UsageEvent {
  appOpen('app_open'),
  scanRead('scan_read'),
  scanFailed('scan_failed'),
  puzzleSolved('puzzle_solved'),
  puzzleFailed('puzzle_failed'),
  gameAnalyzed('game_analyzed'),
  openingStudied('opening_studied'),
  postCreated('post_created'),
  commentCreated('comment_created'),
  positionShared('position_shared');

  const UsageEvent(this.id);

  /// The name stored on the server.
  final String id;
}

/// The user's consent to the statistics (Settings → Privacy): off until
/// they turn it on.
final usageSharingProvider = NotifierProvider<UsageSharing, bool>(UsageSharing.new);

class UsageSharing extends Notifier<bool> {
  static const _key = 'usage.sharingOn';

  /// Before the switch was the consent itself, it could only turn sharing
  /// off; a user who did so stays off, and nobody else is opted in.
  static const _legacyKey = 'usage.sharingOff';

  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    prefs.remove(_legacyKey);
    return prefs.getBool(_key) ?? false;
  }

  void set(bool on) {
    ref.read(sharedPreferencesProvider).setBool(_key, on);
    state = on;
    if (!on) ref.read(usageStatsProvider).discard();
  }
}

final usageStatsProvider = Provider<UsageStats>(UsageStats.new);

/// Counts [UsageEvent]s on the phone and sends the totals now and then.
class UsageStats {
  UsageStats(this._ref);

  final Ref _ref;
  static const _pendingKey = 'usage.pending';
  bool _sending = false;

  bool get _allowed => _ref.read(usageSharingProvider);

  /// Counts [event] once, if the user allows statistics.
  void track(UsageEvent event, [int times = 1]) {
    if (!_allowed) return;
    final pending = _pending()..update(event.id, (n) => n + times, ifAbsent: () => times);
    _ref.read(sharedPreferencesProvider).setString(_pendingKey, jsonEncode(pending));
  }

  /// Sends the counted totals and clears them. Never throws.
  Future<void> flush() async {
    if (_sending || !CommunityConfig.ready) return;
    if (!_allowed) {
      discard();
      return;
    }
    final pending = _pending();
    if (pending.isEmpty) return;
    _sending = true;
    try {
      final info = await PackageInfo.fromPlatform();
      await Supabase.instance.client.rpc<void>('record_usage', params: {
        'events': pending,
        'platform': kIsWeb ? 'web' : Platform.operatingSystem,
        'app_version': info.version,
      });
      // Only what was sent: events counted meanwhile stay pending.
      final now = _pending();
      for (final MapEntry(:key, :value) in pending.entries) {
        final left = (now[key] ?? 0) - value;
        if (left > 0) {
          now[key] = left;
        } else {
          now.remove(key);
        }
      }
      _ref.read(sharedPreferencesProvider).setString(_pendingKey, jsonEncode(now));
    } catch (e) {
      debugPrint('Usage statistics not sent: $e');
    } finally {
      _sending = false;
    }
  }

  /// Forgets counts not sent yet.
  void discard() => _ref.read(sharedPreferencesProvider).remove(_pendingKey);

  Map<String, int> _pending() {
    final raw = _ref.read(sharedPreferencesProvider).getString(_pendingKey);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int));
    } catch (_) {
      return {};
    }
  }
}
