import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'puzzle_store.dart';

/// The download / analysis progress line, or how the last run ended.
class GeneratorBanner extends ConsumerWidget {
  const GeneratorBanner({super.key, required this.state});

  final GeneratorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final generator = ref.read(puzzleGeneratorProvider.notifier);
    final progress = state.total == 0 ? null : state.done / state.total;
    return Material(
      color: state.warning && !state.running
          ? theme.colorScheme.errorContainer
          : theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      state.message ?? '',
                      if (state.running && state.found > 0) '${state.found} found',
                    ].join(' · '),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: state.warning && !state.running
                          ? theme.colorScheme.onErrorContainer
                          : null,
                    ),
                  ),
                ),
                if (state.running)
                  TextButton(onPressed: generator.cancel, child: const Text('Stop'))
                else
                  IconButton(
                    tooltip: 'Dismiss',
                    icon: const Icon(Icons.close),
                    onPressed: generator.dismiss,
                  ),
              ],
            ),
            if (state.running) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(right: 12, bottom: 4),
                child: LinearProgressIndicator(value: progress),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
