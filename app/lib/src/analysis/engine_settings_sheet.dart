import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/engine_settings.dart';

Future<void> showEngineSettings(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const EngineSettingsSheet(),
    );

/// Lines, search limit, threads and memory for live analysis. Changes
/// apply (and restart the analysis) right away.
class EngineSettingsSheet extends ConsumerWidget {
  const EngineSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(engineSettingsProvider);
    final notifier = ref.read(engineSettingsProvider.notifier);
    void set(EngineSettings s) => notifier.set(s);
    final theme = Theme.of(context);
    final maxThreads = EngineSettings.maxThreads;

    Widget heading(String text, [String? value]) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Row(
            children: [
              Text(text, style: theme.textTheme.titleSmall),
              const Spacer(),
              if (value != null) Text(value, style: theme.textTheme.bodyMedium),
            ],
          ),
        );

    const dense = ButtonStyle(
      visualDensity: VisualDensity(horizontal: -2, vertical: -2),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Engine settings', style: theme.textTheme.titleLarge),
            heading('Lines shown'),
            SegmentedButton<int>(
              style: dense,
              showSelectedIcon: false,
              segments: [
                for (var n = 1; n <= EngineSettings.maxLines; n++) ButtonSegment(value: n, label: Text('$n')),
              ],
              selected: {settings.lines},
              onSelectionChanged: (s) => set(settings.copyWith(lines: s.first)),
            ),
            heading('Think until'),
            SegmentedButton<SearchLimit>(
              style: dense,
              showSelectedIcon: false,
              segments: [
                for (final limit in SearchLimit.values) ButtonSegment(value: limit, label: Text(limit.label)),
              ],
              selected: {settings.limit},
              onSelectionChanged: (s) => set(settings.copyWith(limit: s.first)),
            ),
            switch (settings.limit) {
              SearchLimit.depth => _SliderRow(
                  label: 'Depth ${settings.depth}',
                  value: settings.depth,
                  min: EngineSettings.minDepth,
                  max: EngineSettings.maxDepth,
                  onChanged: (v) => set(settings.copyWith(depth: v)),
                ),
              SearchLimit.time => _SliderRow(
                  label: '${settings.seconds} s per position',
                  value: settings.seconds,
                  min: EngineSettings.minSeconds,
                  max: EngineSettings.maxSeconds,
                  onChanged: (v) => set(settings.copyWith(seconds: v)),
                ),
              SearchLimit.unlimited => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Keeps thinking until you move. Game analysis for puzzles waits while '
                    'this board is open.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            },
            heading('Threads', '${settings.threads} of $maxThreads cores'),
            if (maxThreads > 1)
              _SliderRow(
                value: settings.threads,
                min: 1,
                max: maxThreads,
                onChanged: (v) => set(settings.copyWith(threads: v)),
              ),
            heading('Memory (hash)'),
            SegmentedButton<int>(
              style: dense,
              showSelectedIcon: false,
              segments: [
                for (final mb in EngineSettings.hashSizes) ButtonSegment(value: mb, label: Text('$mb MB')),
              ],
              selected: {settings.hashMb},
              onSelectionChanged: (s) => set(settings.copyWith(hashMb: s.first)),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: notifier.reset,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset to defaults'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String? label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (label != null) SizedBox(width: 132, child: Text(label!)),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            label: '$value',
            onChanged: (v) {
              if (v.round() != value) onChanged(v.round());
            },
          ),
        ),
      ],
    );
  }
}
