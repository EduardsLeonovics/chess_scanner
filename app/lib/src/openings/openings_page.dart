import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../accounts/accounts.dart';
import '../community/community_repository.dart';
import '../accounts/game_sources.dart' show GameSpeed;
import '../home/speed_filter.dart';
import '../puzzles/generator_banner.dart';
import '../puzzles/puzzle_store.dart';
import '../settings/appearance.dart';
import '../settings/settings_page.dart';
import '../ads/ad_banner.dart';
import '../skills/opening_book.dart';
import 'opening_study_page.dart';
import 'repertoire.dart';

/// The opening study: pick White or Black, then one of your openings.
class OpeningsPage extends ConsumerStatefulWidget {
  const OpeningsPage({super.key});

  @override
  ConsumerState<OpeningsPage> createState() => _OpeningsPageState();
}

class _OpeningsPageState extends ConsumerState<OpeningsPage> {
  Side? _side;

  /// The families for the last inputs: grouping replays every game's
  /// opening moves, and this page rebuilds whenever the library changes.
  (Object, GameSpeed?, Side, OpeningBook)? _familiesFor;
  List<OpeningFamily>? _families;

  List<OpeningFamily> _familiesOf(
    Map<String, RepertoireGame> all,
    GameSpeed? speed,
    List<RepertoireGame> games,
    Side side,
    OpeningBook book,
  ) {
    final key = _familiesFor;
    final cached = _families;
    if (cached != null &&
        key != null &&
        identical(key.$1, all) &&
        key.$2 == speed &&
        key.$3 == side &&
        identical(key.$4, book)) {
      return cached;
    }
    _familiesFor = (all, speed, side, book);
    return _families = OpeningFamily.group(games, side, book);
  }

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(accountsProvider).any && ref.watch(signedInProvider);
    final library = ref.watch(puzzleLibraryProvider);
    final generator = ref.watch(puzzleGeneratorProvider);
    final book = ref.watch(openingBookProvider);
    final all = library.openingGames.values;
    final speed = ref.watch(speedFilterProvider);
    final games = filterBySpeed(speed, all, (g) => g.speed);
    final side = _side;

    return Scaffold(
      appBar: AppBar(
        leading: side == null
            ? null
            : IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _side = null),
              ),
        title: Text(side == null ? 'Openings' : 'Openings as ${side == Side.white ? 'White' : 'Black'}'),
        actions: [
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
            SpeedFilterBar(available: {for (final g in all) ?g.speed}),
            Expanded(
              child: games.isEmpty
                  ? _Empty(
                      connected: connected,
                      running: generator.running,
                      onLoad: () => ref.read(puzzleGeneratorProvider.notifier).run(),
                    )
                  : switch (book) {
                      AsyncData(value: final book) => side == null
                          ? _SideChooser(games: games, onPick: (s) => setState(() => _side = s))
                          : _FamilyList(families: _familiesOf(library.openingGames, speed, games, side, book), side: side),
                      AsyncError() => const Center(child: Text('The opening database couldn\'t be loaded.')),
                      _ => const Center(child: CircularProgressIndicator()),
                    },
            ),
            const AdBanner(),
          ],
        ),
      ),
    );
  }
}

/// The two big choices: openings as White, openings as Black.
class _SideChooser extends ConsumerWidget {
  const _SideChooser({required this.games, required this.onPick});

  final List<RepertoireGame> games;
  final ValueChanged<Side> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);
    final assets = ref.watch(pieceAssetsProvider).value ?? appearance.pieceSet.assets;
    final theme = Theme.of(context);

    Widget card(Side side) {
      final count = games.where((g) => g.side == side).length;
      final name = side == Side.white ? 'White' : 'Black';
      return Expanded(
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: count == 0 ? null : () => onPick(side),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PieceWidget(piece: Piece(color: side, role: Role.king), size: 72, pieceAssets: assets),
                  const SizedBox(height: 12),
                  Text('Openings as $name', style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  Text('$count game${count == 1 ? '' : 's'}', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Study the openings you actually play: what your opponents answer most, '
          'where you went wrong, and the best line to play next time.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Row(children: [card(Side.white), const SizedBox(width: 12), card(Side.black)]),
      ],
    );
  }
}

/// The user's openings for one side, most played first.
class _FamilyList extends StatelessWidget {
  const _FamilyList({required this.families, required this.side});

  final List<OpeningFamily> families;
  final Side side;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = families.fold(0, (n, f) => n + f.games.length);
    if (total == 0) {
      return const Center(child: Text('No games with this colour yet.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: families.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
      itemBuilder: (context, i) {
        final family = families[i];
        final share = family.games.length / total;
        return ListTile(
          title: Text(family.name),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: share,
                      minHeight: 6,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${family.games.length} game${family.games.length == 1 ? '' : 's'} · ${(share * 100).round()}%',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => OpeningStudyPage(family: family, side: side),
          )),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.connected, required this.running, required this.onLoad});

  final bool connected;
  final bool running;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (String text, Widget? action) = running
        ? ('Your openings appear here as your games are analyzed.', null)
        : connected
            ? (
                'Load your games to study the openings you play most.',
                FilledButton.icon(onPressed: onLoad, icon: const Icon(Icons.search), label: const Text('Load my games')),
              )
            : (
                'Sign in to ChessGeek and connect your Lichess or Chess.com account to '
                    'study your openings.',
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(settingsRoute()),
                  icon: const Icon(Icons.link),
                  label: const Text('Connect an account'),
                ),
              );
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
            if (action != null) ...[const SizedBox(height: 20), action],
          ],
        ),
      ),
    );
  }
}
