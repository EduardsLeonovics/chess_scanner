import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analysis/analysis_page.dart';
import '../diagnostics/crash_log.dart';
import '../openings/openings_page.dart';
import '../puzzles/puzzle_store.dart';
import '../puzzles/puzzles_page.dart';
import '../share/position_link.dart';
import '../skills/skills_page.dart';
import 'books_icon.dart';

/// The app's top level: four sections switched from a plain bottom bar of
/// grey icons with small labels (scan, puzzles, openings, skills).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

/// The tab on screen: 0 analysis, 1 puzzles, 2 openings, 3 skills.
final homeTabProvider = NotifierProvider<HomeTab, int>(HomeTab.new);

class HomeTab extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

class _HomeShellState extends ConsumerState<HomeShell> {
  StreamSubscription<Uri>? _links;

  @override
  void initState() {
    super.initState();
    _links = listenForPositionLinks(
      onLink: (position) {
        ref.read(homeTabProvider.notifier).select(0);
        ref.read(pendingPositionProvider.notifier).open(position);
      },
      onInvalid: () {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That link doesn\'t contain a valid chess position.')),
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _offerCrashReport();
      // Finish analyzing games a previous session didn't get through.
      ref.read(puzzleGeneratorProvider.notifier).resume();
    });
  }

  @override
  void dispose() {
    _links?.cancel();
    super.dispose();
  }

  /// After a crash, asks once whether to send the report.
  Future<void> _offerCrashReport() async {
    final log = ref.read(crashLogProvider);
    if (log.unprompted == 0 || !mounted) return;
    log.markPrompted();
    final send = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.bug_report_outlined),
        title: const Text('Something went wrong'),
        content: const Text(
          'ChessGeek ran into a problem last time. Sending the crash report helps '
          'fix it. You can read it before sending; it contains no personal data '
          'beyond what\'s in the error itself.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send report')),
        ],
      ),
    );
    if (send == true && mounted) await log.share(origin: shareOrigin(context));
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(homeTabProvider);
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: const [
          AnalysisPage(),
          PuzzlesPage(),
          OpeningsPage(),
          SkillsPage(),
        ],
      ),
      bottomNavigationBar: _NavBar(
        index: index,
        onSelect: ref.read(homeTabProvider.notifier).select,
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  static const _background = Colors.white;
  static const _border = Color(0xFFE6E8EB);
  static const _selectedFill = Color(0xFFEEF0F3);
  static const _selectedIcon = Color(0xFF29313B);
  static const _icon = Color(0xFF8A919B);

  @override
  Widget build(BuildContext context) {
    final items = <(String, Widget Function(Color))>[
      ('Scan', (c) => Icon(Icons.photo_camera_outlined, color: c, size: 24)),
      ('Puzzles', (c) => Icon(Icons.extension_outlined, color: c, size: 24)),
      ('Openings', (c) => BooksIcon(color: c, size: 24)),
      ('Skills', (c) => Icon(Icons.analytics_outlined, color: c, size: 24)),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: _background,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: Semantics(
                      button: true,
                      selected: i == index,
                      label: items[i].$1,
                      excludeSemantics: true,
                      child: InkResponse(
                        onTap: () => onSelect(i),
                        radius: 32,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 52,
                              height: 30,
                              decoration: BoxDecoration(
                                color: i == index ? _selectedFill : _background,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: items[i].$2(i == index ? _selectedIcon : _icon),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              items[i].$1,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.2,
                                fontWeight: i == index ? FontWeight.w600 : FontWeight.w500,
                                color: i == index ? _selectedIcon : _icon,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
