import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_page.dart';
import 'community_repository.dart';
import 'feed_list.dart';
import 'post_card.dart';

/// The Community tab: a feed of puzzles posted by ChessGeek users, solved
/// right in the feed. "For you" has everyone's posts, "Following" the
/// people you follow. Signed out, it invites you to join.
class CommunityPage extends ConsumerStatefulWidget {
  const CommunityPage({super.key});

  @override
  ConsumerState<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends ConsumerState<CommunityPage> {
  StreamSubscription<void>? _recovery;

  @override
  void initState() {
    super.initState();
    // A password-reset link signs the user in: ask for the new password.
    _recovery = ref.read(communityProvider)?.passwordRecovery.listen((_) => _askNewPassword());
  }

  @override
  void dispose() {
    _recovery?.cancel();
    super.dispose();
  }

  Future<void> _askNewPassword() async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set a new password'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New password', helperText: 'At least 6 characters.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (password == null || !mounted) return;
    await runCommunityAction(
      context,
      () => ref.read(communityProvider)!.setPassword(password),
      done: 'Password changed.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(communityProvider);
    if (repo == null) {
      return const _Message(
        icon: Icons.cloud_off_outlined,
        title: 'Community unavailable',
        text: 'This version of ChessGeek isn\'t connected to the community server.',
      );
    }
    final user = ref.watch(communityUserProvider);
    return switch (user) {
      AsyncData(value: final user?) => _Feed(userId: user.id),
      AsyncData() => const _Welcome(),
      AsyncError() => const _Welcome(),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}

class _Feed extends ConsumerWidget {
  const _Feed({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(communityProvider)!;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Community'),
          actions: [
            IconButton(
              tooltip: 'Your profile',
              icon: const Icon(Icons.account_circle_outlined),
              onPressed: () => openProfile(context, userId),
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'For you'), Tab(text: 'Following')]),
        ),
        body: TabBarView(
          children: [
            FeedList(
              load: (before) => repo.feed(before: before),
              emptyMessage: 'No posts yet. Be the first: share a scanned position or one of '
                  'your puzzles and choose "Post to the ChessGeek community".',
            ),
            FeedList(
              load: (before) => repo.feed(following: true, before: before),
              emptyMessage: 'Posts from people you follow show up here. Tap a name in '
                  '"For you" to open their profile and follow them.',
            ),
          ],
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void open(bool create) => Navigator.of(context).push(
          MaterialPageRoute<bool>(builder: (_) => AuthPage(createAccount: create)),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Community')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('Join the ChessGeek community', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'Solve puzzles other players post, share positions from your own games and '
                'scans, comment, and follow people.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: () => open(true), child: const Text('Create account')),
              TextButton(onPressed: () => open(false), child: const Text('I have an account')),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Community')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48),
              const SizedBox(height: 16),
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(text, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
