import 'dart:io' as io;

import 'package:chess_scanner/src/privacy/consent.dart';
import 'package:chess_scanner/src/privacy/usage_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('statistics consent', () {
    test('no consent message where the GDPR does not apply', () {
      expect(statsAllowed(gdprApplies: 0, publisherConsent: null), isTrue);
      expect(statsAllowed(gdprApplies: null, publisherConsent: null), isTrue);
    });

    test('under the GDPR it needs storage plus measurement or statistics', () {
      // Purposes 1..10; '1' at index n-1 means purpose n was allowed.
      expect(statsAllowed(gdprApplies: 1, publisherConsent: '1000000100'), isTrue);
      expect(statsAllowed(gdprApplies: 1, publisherConsent: '1000000010'), isTrue);
      expect(statsAllowed(gdprApplies: 1, publisherConsent: '0000000110'), isFalse);
      expect(statsAllowed(gdprApplies: 1, publisherConsent: '1000000000'), isFalse);
      expect(statsAllowed(gdprApplies: 1, publisherConsent: null), isFalse);
      expect(statsAllowed(gdprApplies: 1, publisherConsent: '1'), isFalse);
    });
  });

  test('usage events match what the server accepts', () {
    final schema = io.File('../backend/supabase/schema.sql').readAsStringSync();
    final known = RegExp(r'known constant text\[\] := array\[([^\]]*)\]').firstMatch(schema)!;
    final server = RegExp(r"'([a-z_]+)'").allMatches(known.group(1)!).map((m) => m.group(1)).toSet();
    expect({for (final e in UsageEvent.values) e.id}, server);
  });
}
