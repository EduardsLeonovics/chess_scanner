import 'dart:io' as io;

import 'package:chess_scanner/src/privacy/usage_stats.dart';
import 'package:chess_scanner/src/settings/appearance.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ProviderContainer> open(Map<String, Object> saved) async {
    SharedPreferences.setMockInitialValues(saved);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    return container;
  }

  group('statistics consent', () {
    test('off until the user turns it on', () async {
      final container = await open({});
      expect(container.read(usageSharingProvider), isFalse);
      container.read(usageStatsProvider).track(UsageEvent.appOpen);
      expect(container.read(sharedPreferencesProvider).getString('usage.pending'), isNull);

      container.read(usageSharingProvider.notifier).set(true);
      container.read(usageStatsProvider).track(UsageEvent.appOpen);
      expect(container.read(sharedPreferencesProvider).getString('usage.pending'), isNotNull);
    });

    test('nobody is opted in by the old switch', () async {
      expect((await open({'usage.sharingOff': false})).read(usageSharingProvider), isFalse);
      expect((await open({'usage.sharingOff': true})).read(usageSharingProvider), isFalse);
    });
  });

  test('usage events match what the server accepts', () {
    final schema = io.File('../backend/supabase/schema.sql').readAsStringSync();
    final known = RegExp(r'known constant text\[\] := array\[([^\]]*)\]').firstMatch(schema)!;
    final server = RegExp(r"'([a-z_]+)'").allMatches(known.group(1)!).map((m) => m.group(1)).toSet();
    expect({for (final e in UsageEvent.values) e.id}, server);
  });
}
