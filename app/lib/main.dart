import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app_info.dart';
import 'src/diagnostics/crash_log.dart';
import 'src/home/home_shell.dart';
import 'src/settings/appearance.dart';

Future<void> main() async {
  CrashLog? crashLog;
  // Errors that escape everything else (async gaps) land in this zone.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    crashLog = CrashLog(prefs)..install();
    LicenseRegistry.addLicense(() => Stream.fromIterable(const [
          LicenseEntryWithLineBreaks([AppInfo.name], AppInfo.legalese),
          LicenseEntryWithLineBreaks(
            ['Impact Sounds by Kenney'],
            'Board sounds are built from "Impact Sounds" by Kenney (www.kenney.nl), '
                'released under Creative Commons Zero (CC0 1.0).',
          ),
          LicenseEntryWithLineBreaks(
            ['lichess-org/chess-openings'],
            'Opening names and theory from the Lichess chess-openings data set '
                '(github.com/lichess-org/chess-openings), released under CC0 1.0.',
          ),
        ]));
    runApp(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        crashLogProvider.overrideWithValue(crashLog!),
      ],
      child: const ChessGeekApp(),
    ));
  }, (error, stack) {
    crashLog?.record(error, stack, source: 'async');
    if (kDebugMode) debugPrint('Uncaught: $error\n$stack');
  });
}

class ChessGeekApp extends StatelessWidget {
  const ChessGeekApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppInfo.name,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF15781B),
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeShell(),
    );
  }
}
