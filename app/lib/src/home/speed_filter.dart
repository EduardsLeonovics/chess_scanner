import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../accounts/game_sources.dart';

/// The time control the Skills and Openings pages show; null for all games.
final speedFilterProvider = NotifierProvider<SpeedFilter, GameSpeed?>(SpeedFilter.new);

class SpeedFilter extends Notifier<GameSpeed?> {
  @override
  GameSpeed? build() => null;

  void set(GameSpeed? speed) => state = speed;
}

/// The items of [all] played at the chosen time control. A choice that has
/// no games (e.g. after the data was reset) falls back to all of them.
List<T> filterBySpeed<T>(GameSpeed? chosen, Iterable<T> all, GameSpeed? Function(T) speedOf) {
  final list = all.toList();
  if (chosen == null || !list.any((e) => speedOf(e) == chosen)) return list;
  return [for (final e in list) if (speedOf(e) == chosen) e];
}

/// A row of chips: All, then each time control the user has games in.
/// Hidden when there's nothing to choose between.
class SpeedFilterBar extends ConsumerWidget {
  const SpeedFilterBar({super.key, required this.available});

  /// Time controls that occur in the user's games.
  final Set<GameSpeed> available;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (available.length < 2) return const SizedBox.shrink();
    final chosen = ref.watch(speedFilterProvider);
    final current = available.contains(chosen) ? chosen : null;
    void pick(GameSpeed? speed) => ref.read(speedFilterProvider.notifier).set(speed);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          ChoiceChip(label: const Text('All'), selected: current == null, onSelected: (_) => pick(null)),
          for (final speed in GameSpeed.values)
            if (available.contains(speed)) ...[
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text(speed.label),
                selected: current == speed,
                onSelected: (_) => pick(speed),
              ),
            ],
        ],
      ),
    );
  }
}
