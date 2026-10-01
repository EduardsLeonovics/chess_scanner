import 'package:chess_scanner/src/diagnostics/crash_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('records errors and keeps them across launches', () {
    CrashLog(prefs).record(StateError('boom'), StackTrace.current, source: 'test');
    final reloaded = CrashLog(prefs);
    expect(reloaded.reports.single.error, contains('boom'));
    expect(reloaded.reports.single.source, 'test');
    expect(reloaded.unprompted, 1);
  });

  test('a repeating error is one report', () {
    final log = CrashLog(prefs);
    final stack = StackTrace.current;
    for (var i = 0; i < 5; i++) {
      log.record(StateError('every frame'), stack);
    }
    expect(log.reports, hasLength(1));
  });

  test('keeps only the latest reports', () {
    final log = CrashLog(prefs);
    for (var i = 0; i < CrashLog.maxReports + 3; i++) {
      log.record(StateError('error $i'), null);
    }
    expect(log.reports, hasLength(CrashLog.maxReports));
    expect(log.reports.last.error, contains('error ${CrashLog.maxReports + 2}'));
  });

  test('asks about each crash only once', () {
    final log = CrashLog(prefs)..record(StateError('a'), null);
    log.markPrompted();
    expect(CrashLog(prefs).unprompted, 0);
    log.record(StateError('b'), null);
    expect(CrashLog(prefs).unprompted, 1);
  });

  test('clear removes everything', () {
    final log = CrashLog(prefs)..record(StateError('a'), null);
    log.clear();
    expect(CrashLog(prefs).reports, isEmpty);
    expect(CrashLog(prefs).unprompted, 0);
  });
}
