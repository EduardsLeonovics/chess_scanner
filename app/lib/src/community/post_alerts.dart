import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/appearance.dart' show sharedPreferencesProvider;
import 'community_repository.dart';
import 'feed_list.dart';

/// New posts from the people the user asked to be notified about (the bell
/// on their profile), since the user last opened [PostAlertsPage]. Checked
/// when the Community tab opens and every few minutes while the app runs.
final unseenPostAlertsProvider = AsyncNotifierProvider<UnseenPostAlerts, int>(UnseenPostAlerts.new);

class UnseenPostAlerts extends AsyncNotifier<int> {
  static const _seenKey = 'community.alertsSeen';
  static const _interval = Duration(minutes: 3);

  @override
  Future<int> build() async {
    final repo = ref.watch(communityProvider);
    final user = ref.watch(communityUserProvider).value;
    if (repo == null || user == null) return 0;
    final timer = Timer.periodic(_interval, (_) => refresh());
    ref.onDispose(timer.cancel);
    return _count(repo);
  }

  Future<int> _count(CommunityRepository repo) async {
    final seen = _seen;
    if (seen == null) {
      // First run: start counting from now rather than flagging old posts.
      _markSeen();
      return 0;
    }
    try {
      return (await repo.alertPosts(since: seen)).length;
    } on CommunityException {
      return state.value ?? 0;
    }
  }

  DateTime? get _seen {
    final ms = ref.read(sharedPreferencesProvider).getInt(_seenKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  void _markSeen() =>
      ref.read(sharedPreferencesProvider).setInt(_seenKey, DateTime.now().millisecondsSinceEpoch);

  Future<void> refresh() async {
    final repo = ref.read(communityProvider);
    if (repo == null || repo.user == null) return;
    final count = await _count(repo);
    if (ref.mounted) state = AsyncData(count);
  }

  /// The user looked at the alerts: nothing is new any more.
  void markSeen() {
    _markSeen();
    state = const AsyncData(0);
  }
}

/// The bell in the Community app bar, with the number of new posts.
class PostAlertsButton extends ConsumerWidget {
  const PostAlertsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unseen = ref.watch(unseenPostAlertsProvider).value ?? 0;
    return IconButton(
      tooltip: unseen == 0 ? 'Notifications' : '$unseen new post${unseen == 1 ? '' : 's'}',
      icon: Badge(
        isLabelVisible: unseen > 0,
        label: Text(unseen > 20 ? '20+' : '$unseen'),
        child: Icon(unseen > 0 ? Icons.notifications_active : Icons.notifications_outlined),
      ),
      onPressed: () {
        ref.read(unseenPostAlertsProvider.notifier).markSeen();
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PostAlertsPage()));
      },
    );
  }
}

/// Posts by everyone the user turned notifications on for.
class PostAlertsPage extends ConsumerWidget {
  const PostAlertsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(communityProvider)!;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: FeedList(
        load: (before) => repo.alertPosts(before: before),
        emptyMessage: 'Nothing here yet. Open someone\'s profile and tap the bell to be '
            'notified whenever they post.',
      ),
    );
  }
}
