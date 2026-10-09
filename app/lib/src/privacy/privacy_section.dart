import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'usage_stats.dart';

/// Settings → Privacy: the anonymous statistics switch (off until the user
/// turns it on).
class PrivacySection extends ConsumerWidget {
  const PrivacySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Share anonymous usage statistics'),
          subtitle: const Text(
            'Daily totals like "puzzles solved", with no account, device id or location. '
            'Helps decide what to improve.',
          ),
          value: ref.watch(usageSharingProvider),
          onChanged: ref.read(usageSharingProvider.notifier).set,
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            'Photos you scan and the games you analyze stay on this phone. The app never '
            'collects your location or contacts.',
          ),
        ),
      ],
    );
  }
}
