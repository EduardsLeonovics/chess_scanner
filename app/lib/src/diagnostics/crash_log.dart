import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_info.dart';

/// One uncaught error.
@immutable
class CrashReport {
  const CrashReport({required this.time, required this.source, required this.error, required this.stack});

  final DateTime time;

  /// Where it was caught, e.g. "Flutter framework" or "async".
  final String source;
  final String error;
  final String stack;

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'source': source,
        'error': error,
        'stack': stack,
      };

  factory CrashReport.fromJson(Map<String, dynamic> json) => CrashReport(
        time: DateTime.parse(json['time'] as String),
        source: json['source'] as String,
        error: json['error'] as String,
        stack: json['stack'] as String,
      );
}

final crashLogProvider = Provider<CrashLog>(
  (ref) => throw UnimplementedError('crashLogProvider must be overridden'),
);

/// Catches uncaught errors and keeps the latest few on the device.
///
/// Nothing leaves the phone unless the user chooses to send a report from
/// the prompt after a crash or from Settings.
class CrashLog extends ChangeNotifier {
  CrashLog(this._prefs) {
    try {
      final raw = _prefs.getString(_reportsKey);
      if (raw != null) {
        _reports = [
          for (final json in jsonDecode(raw) as List<dynamic>)
            CrashReport.fromJson(json as Map<String, dynamic>),
        ];
      }
    } catch (_) {
      _reports = [];
    }
  }

  static const _reportsKey = 'crash.reports';
  static const _promptedKey = 'crash.prompted';
  static const maxReports = 10;
  static const _maxStackLength = 6000;

  final SharedPreferences _prefs;
  List<CrashReport> _reports = [];

  /// Newest last.
  List<CrashReport> get reports => List.unmodifiable(_reports);

  /// Reports saved since the user was last asked about them.
  int get unprompted => (_reports.length - (_prefs.getInt(_promptedKey) ?? 0)).clamp(0, maxReports);

  /// Routes Flutter and platform errors here. Call once, before [runApp].
  void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      record(details.exception, details.stack, source: 'Flutter ${details.context ?? 'framework'}');
      previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack, source: 'platform');
      return true;
    };
  }

  void record(Object error, StackTrace? stack, {String source = 'async'}) {
    final text = error.toString();
    var trace = (stack ?? StackTrace.empty).toString();
    if (trace.length > _maxStackLength) trace = '${trace.substring(0, _maxStackLength)}\n…';
    // The same error repeating (e.g. every frame) is one report.
    if (_reports.isNotEmpty && _reports.last.error == text && _reports.last.stack == trace) return;
    _reports = [..._reports, CrashReport(time: DateTime.now(), source: source, error: text, stack: trace)];
    if (_reports.length > maxReports) {
      final dropped = _reports.length - maxReports;
      _reports = _reports.sublist(dropped);
      final prompted = _prefs.getInt(_promptedKey) ?? 0;
      _prefs.setInt(_promptedKey, (prompted - dropped).clamp(0, maxReports));
    }
    _save();
    if (kDebugMode) debugPrint('Crash recorded ($source): $text');
  }

  void markPrompted() {
    _prefs.setInt(_promptedKey, _reports.length);
    notifyListeners();
  }

  void clear() {
    _reports = [];
    _prefs.setInt(_promptedKey, 0);
    _save();
  }

  /// The reports as plain text, with app and device details.
  Future<String> format() async {
    var version = 'unknown';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {}
    final out = StringBuffer()
      ..writeln('${AppInfo.name} crash report')
      ..writeln('App version: $version${kDebugMode ? ' (debug)' : ''}')
      ..writeln('System: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
      ..writeln('Reports: ${_reports.length}');
    for (final (i, r) in _reports.reversed.indexed) {
      out
        ..writeln()
        ..writeln('--- #${i + 1}  ${r.time.toIso8601String()}  [${r.source}]')
        ..writeln(r.error)
        ..writeln(r.stack.trim());
    }
    return out.toString();
  }

  /// Opens the share sheet with the reports. [origin] anchors the sheet on iPad.
  Future<void> share({Rect? origin}) async {
    final email = AppInfo.supportEmail;
    final text = await format();
    await SharePlus.instance.share(ShareParams(
      subject: '${AppInfo.name} crash report',
      text: email == null ? text : 'To: $email\n\n$text',
      sharePositionOrigin: origin,
    ));
  }

  void _save() {
    _prefs.setString(_reportsKey, jsonEncode([for (final r in _reports) r.toJson()]));
    notifyListeners();
  }
}

/// The share sheet's anchor for [context]'s widget (needed on iPad).
Rect? shareOrigin(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  return box == null ? null : box.localToGlobal(Offset.zero) & box.size;
}
