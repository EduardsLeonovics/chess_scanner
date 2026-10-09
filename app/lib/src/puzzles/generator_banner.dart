import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'puzzle_store.dart';

/// A short note while games are analyzed, or how the last run ended. No
/// background or game counter: the notification has the details. "Hide"
/// removes it until the next run.
class GeneratorBanner extends ConsumerWidget {
  const GeneratorBanner({super.key, required this.state});

  final GeneratorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(generatorBannerHiddenProvider)) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final generator = ref.read(puzzleGeneratorProvider.notifier);
    final problem = state.warning && !state.running;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: problem ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
    );
    final compact = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(0, 32),
      textStyle: theme.textTheme.labelMedium,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              state.running
                  ? 'Analyzing games in the background. This will take some time.'
                  : state.message ?? '',
              style: small,
            ),
          ),
          if (state.running)
            TextButton(style: compact, onPressed: generator.cancel, child: const Text('Stop')),
          TextButton(
            style: compact,
            onPressed: state.running
                ? ref.read(generatorBannerHiddenProvider.notifier).hide
                : generator.dismiss,
            child: const Text('Hide'),
          ),
        ],
      ),
    );
  }
}
