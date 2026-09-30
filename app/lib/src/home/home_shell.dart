import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analysis/analysis_page.dart';
import 'books_icon.dart';

/// The app's top level: four sections switched from a plain bottom bar of
/// grey icons (camera, puzzles, library, analysis).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          AnalysisPage(),
          // Puzzles, library and analysis come later.
          _BlankSection(),
          _BlankSection(),
          _BlankSection(),
        ],
      ),
      bottomNavigationBar: _NavBar(
        index: _index,
        onSelect: (i) => setState(() => _index = i),
      ),
    );
  }
}

class _BlankSection extends StatelessWidget {
  const _BlankSection();

  @override
  Widget build(BuildContext context) {
    return const AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: ColoredBox(color: Colors.white, child: SizedBox.expand()),
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
      ('Scan', (c) => Icon(Icons.photo_camera_outlined, color: c, size: 26)),
      ('Puzzles', (c) => Icon(Icons.extension_outlined, color: c, size: 26)),
      ('Library', (c) => BooksIcon(color: c, size: 26)),
      ('Analysis', (c) => Icon(Icons.analytics_outlined, color: c, size: 26)),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: _background,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: Tooltip(
                    message: items[i].$1,
                    child: Semantics(
                      button: true,
                      selected: i == index,
                      label: items[i].$1,
                      excludeSemantics: true,
                      child: InkResponse(
                        onTap: () => onSelect(i),
                        radius: 32,
                        child: Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 56,
                            height: 40,
                            decoration: BoxDecoration(
                              color: i == index ? _selectedFill : _background,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: items[i].$2(i == index ? _selectedIcon : _icon),
                          ),
                        ),
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
