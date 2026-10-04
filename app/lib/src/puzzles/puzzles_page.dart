import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../accounts/accounts.dart';
import '../settings/settings_page.dart';
import 'puzzle.dart';
import 'generator_banner.dart';
import 'puzzle_board.dart';
import 'puzzle_store.dart';

/// Puzzles made from the user's own games.
class PuzzlesPage extends ConsumerStatefulWidget {
  const PuzzlesPage({super.key});

  @override
  ConsumerState<PuzzlesPage> createState() => _PuzzlesPageState();
}

class _PuzzlesPageState extends ConsumerState<PuzzlesPage> {
  String? _currentId;

  /// The big "load new games" button, offered when the tab is opened until
  /// the user closes it or loads; then not again until the app restarts.
  bool _offerLoad = false;
  bool _declined = false;
  bool _visible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = Visibility.of(context);
    if (visible && !_visible && !_declined) _offerLoad = true;
    _visible = visible;
  }

  void _skip() => setState(() {
        _offerLoad = false;
        _declined = true;
      });

  List<Puzzle> _visiblePuzzles(PuzzleLibrary library, Set<PuzzleCategory> categories) => [
        for (final p in library.puzzles)
          if (categories.contains(p.category)) p,
      ];

  /// The puzzle on screen: the chosen one, else the first unsolved one.
  Puzzle? _current(List<Puzzle> visible) {
    if (visible.isEmpty) return null;
    for (final p in visible) {
      if (p.id == _currentId) return p;
    }
    return visible.firstWhere(
      (p) => p.result == PuzzleResult.unsolved,
      orElse: () => visible.first,
    );
  }

  void _next(List<Puzzle> visible, Puzzle current) {
    final start = visible.indexWhere((p) => p.id == current.id);
    // Next unsolved puzzle after this one, wrapping; else simply the next.
    for (var i = 1; i <= visible.length; i++) {
      final p = visible[(start + i) % visible.length];
      if (p.result == PuzzleResult.unsolved && p.id != current.id) {
        setState(() => _currentId = p.id);
        return;
      }
    }
    setState(() => _currentId = visible[(start + 1) % visible.length].id);
  }

  void _load() {
    _skip();
    ref.read(puzzleGeneratorProvider.notifier).run();
  }

  Future<void> _pickCategories() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _CategorySheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider);
    final library = ref.watch(puzzleLibraryProvider);
    final categories = ref.watch(puzzleCategoriesProvider);
    final generator = ref.watch(puzzleGeneratorProvider);
    final visible = _visiblePuzzles(library, categories);
    final current = _current(visible);
    final showLoadButton = _offerLoad && accounts.any && !generator.running;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Puzzles'),
        actions: [
          TextButton.icon(
            onPressed: _pickCategories,
            icon: const Icon(Icons.filter_list),
            label: const Text('Categories'),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(settingsRoute()),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (generator.message != null) GeneratorBanner(state: generator),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: current == null
                        ? _EmptyState(
                            connected: accounts.any,
                            hasPuzzles: library.puzzles.isNotEmpty,
                            noCategories: categories.isEmpty,
                            running: generator.running,
                            onLoad: _load,
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) => SingleChildScrollView(
                              child: PuzzleBoard(
                                key: ValueKey(current.id),
                                puzzle: current,
                                boardSize: math.min(
                                  constraints.maxWidth,
                                  constraints.maxHeight * 0.72,
                                ),
                                onNext: () => _next(visible, current),
                              ),
                            ),
                          ),
                  ),
                  if (showLoadButton)
                    Positioned.fill(
                      child: _LoadOverlay(
                        onLoad: _load,
                        onSkip: _skip,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The centred magnifying glass shown when the tab opens. The X beside it,
/// or tapping anywhere else, skips it and goes straight to the puzzles.
class _LoadOverlay extends StatelessWidget {
  const _LoadOverlay({required this.onLoad, required this.onSkip});

  final VoidCallback onLoad;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onSkip,
      child: ColoredBox(
        color: const Color(0x8C000000),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 124,
                child: Stack(
                  children: [
                    Center(
                      child: Semantics(
                        button: true,
                        label: 'Load new games',
                        excludeSemantics: true,
                        child: SizedBox.square(
                          dimension: 96,
                          child: IconButton.filled(
                            onPressed: onLoad,
                            iconSize: 48,
                            icon: const Icon(Icons.search),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      child: IconButton.filledTonal(
                        tooltip: 'Not now',
                        onPressed: onSkip,
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text('Load new games', style: theme.textTheme.titleMedium?.copyWith(color: Colors.white)),
              const SizedBox(height: 4),
              Text(
                'Tap anywhere else to keep solving',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pick any mix of categories, or all of them.
class _CategorySheet extends ConsumerWidget {
  const _CategorySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(puzzleCategoriesProvider);
    final notifier = ref.read(puzzleCategoriesProvider.notifier);
    final all = selected.length == PuzzleCategory.values.length;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Categories', style: Theme.of(context).textTheme.titleLarge),
          ),
          CheckboxListTile(
            title: const Text('All'),
            tristate: true,
            value: all ? true : (selected.isEmpty ? false : null),
            onChanged: (_) => notifier.set(all ? {} : PuzzleCategory.values.toSet()),
          ),
          const Divider(height: 1),
          for (final category in PuzzleCategory.values)
            CheckboxListTile(
              title: Text(category.label),
              value: selected.contains(category),
              onChanged: (on) => notifier.set(
                on! ? {...selected, category} : ({...selected}..remove(category)),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.connected,
    required this.hasPuzzles,
    required this.noCategories,
    required this.running,
    required this.onLoad,
  });

  final bool connected;
  final bool hasPuzzles;
  final bool noCategories;
  final bool running;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (String text, Widget? action) = switch ((connected, hasPuzzles, running)) {
      _ when noCategories => ('Pick at least one category to see puzzles.', null),
      (_, _, true) when !hasPuzzles => ('Puzzles will appear here as your games are analyzed.', null),
      (_, true, _) => ('No puzzles in these categories yet.', null),
      (false, _, _) => (
          'Connect your Lichess or Chess.com account to turn the moments you '
              'missed in your own games into puzzles.',
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(settingsRoute()),
            icon: const Icon(Icons.link),
            label: const Text('Connect an account'),
          ),
        ),
      (true, false, _) => (
          'Load your games to find missed mates, only moves and pieces you could have captured.',
          FilledButton.icon(
            onPressed: onLoad,
            icon: const Icon(Icons.search),
            label: const Text('Load my games'),
          ),
        ),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.extension_outlined, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
            if (action != null) ...[const SizedBox(height: 20), action],
          ],
        ),
      ),
    );
  }
}
