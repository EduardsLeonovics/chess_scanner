import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'consent.dart';
import 'usage_stats.dart';

/// Settings → Privacy: the anonymous statistics switch, and a way back into
/// Google's consent message where the law requires one.
class PrivacySection extends ConsumerWidget {
  const PrivacySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final privacy = ref.watch(privacyProvider);
    final sharing = ref.watch(usageSharingProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Share anonymous usage statistics'),
          subtitle: Text(
            privacy.statsConsent
                ? 'Daily totals like "puzzles solved", with no account, device id or location. '
                    'Helps decide what to improve.'
                : 'Off until you allow measurement in Privacy choices below.',
          ),
          value: sharing && privacy.statsConsent,
          onChanged: privacy.statsConsent ? ref.read(usageSharingProvider.notifier).set : null,
        ),
        if (privacy.privacyOptionsRequired)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy choices'),
            subtitle: const Text('Change what you agreed to for ads and statistics'),
            onTap: () => ref.read(privacyProvider.notifier).showPrivacyOptions(),
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
