import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'community_models.dart';
import 'community_repository.dart';
import 'feed_list.dart';
import 'post_card.dart';

/// Settings entry for community safety, shown while signed in.
class CommunitySafetySection extends ConsumerWidget {
  const CommunitySafetySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(communityUserProvider).value != null;
    if (!signedIn) {
      return const Text('Sign in on the Community tab to post, comment and follow players.');
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.block),
      title: const Text('Blocked accounts'),
      subtitle: const Text('People you blocked, and unblocking them'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const BlockedAccountsPage()),
      ),
    );
  }
}

/// Everyone the user blocked, each with an Unblock button.
class BlockedAccountsPage extends ConsumerStatefulWidget {
  const BlockedAccountsPage({super.key});

  @override
  ConsumerState<BlockedAccountsPage> createState() => _BlockedAccountsPageState();
}

class _BlockedAccountsPageState extends ConsumerState<BlockedAccountsPage> {
  List<BlockedUser>? _blocked;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final blocked = await ref.read(communityProvider)!.blockedUsers();
      if (!mounted) return;
      setState(() {
        _blocked = blocked;
        _error = null;
      });
    } on CommunityException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _unblock(BlockedUser user) async {
    final ok = await runCommunityAction(
      context,
      () => ref.read(communityProvider)!.unblock(user.id),
      done: '@${user.username} is unblocked.',
    );
    if (!ok) return;
    ref.read(feedRevisionProvider.notifier).bump();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _blocked;
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked accounts')),
      body: switch ((blocked, _error)) {
        (null, final String error) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [Text(error), TextButton(onPressed: _load, child: const Text('Try again'))],
            ),
          ),
        (null, _) => const Center(child: CircularProgressIndicator()),
        (final list?, _) when list.isEmpty => const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'You haven\'t blocked anyone. Block someone from the menu on their profile, '
                'post or comment.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        (final list?, _) => ListView(
            children: [
              for (final user in list)
                ListTile(
                  leading: UserAvatar(username: user.username, radius: 18),
                  title: Text('@${user.username}'),
                  trailing: TextButton(onPressed: () => _unblock(user), child: const Text('Unblock')),
                ),
            ],
          ),
      },
    );
  }
}
