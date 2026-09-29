import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/analysis/analysis_page.dart';

void main() {
  runApp(const ProviderScope(child: ChessScannerApp()));
}

class ChessScannerApp extends StatelessWidget {
  const ChessScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chess Scanner',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF15781B),
          brightness: Brightness.dark,
        ),
      ),
      home: const AnalysisPage(),
    );
  }
}
