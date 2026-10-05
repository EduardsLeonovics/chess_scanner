import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'community_models.dart';
import 'community_repository.dart';
import 'feed_list.dart';
import 'post_card.dart';

/// A user's profile: name, follower counts, a follow button (or, on your
/// own, sign out and account deletion), and their posts.
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

enum _AccountAction { signOut, delete }

class _ProfilePageState extends ConsumerState<ProfilePage> {
  CommunityProfile? _profile;
  bool? _following;
  bool _busy = false;
  String? _error;

  CommunityRepository get _repo => ref.read(communityProvider)!;
  bool get _mine => _repo.user?.id == widget.userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await _repo.profile(widget.userId);
      final following = _mine ? null : await _repo.isFollowing(widget.userId);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _following = following;
        _error = null;
      });
    } on CommunityException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _toggleFollow() async {
    final following = _following;
    if (following == null || _busy) return;
    setState(() => _busy = true);
    final ok = await runCommunityAction(
      context,
      () => following ? _repo.unfollow(widget.userId) : _repo.follow(widget.userId),
    );
    if (ok) await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _account(_AccountAction action) async {
    final navigator = Navigator.of(context);
    switch (action) {
      case _AccountAction.signOut:
        if (await runCommunityAction(context, _repo.signOut)) navigator.pop();
      case _AccountAction.delete:
        final sure = await confirm(
          context,
          title: 'Delete your account?',
          message: 'Your profile, posts, comments and follows are deleted for good. '
              'Your puzzles and games on this phone stay.',
          action: 'Delete account',
        );
        if (!sure || !mounted) return;
        if (await runCommunityAction(context, _repo.deleteAccount, done: 'Your account is deleted.')) {
          navigator.pop();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(
        title: Text(profile == null ? 'Profile' : '@${profile.username}'),
        actions: [
          if (_mine)
            PopupMenuButton<_AccountAction>(
              onSelected: _account,
              itemBuilder: (context) => const [
                PopupMenuItem(value: _AccountAction.signOut, child: Text('Sign out')),
                PopupMenuItem(value: _AccountAction.delete, child: Text('Delete account')),
              ],
            ),
        ],
      ),
      body: _error != null && profile == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  TextButton(onPressed: _load, child: const Text('Try again')),
                ],
              ),
            )
          : FeedList(
              load: (before) => _repo.postsBy(widget.userId, before: before),
              emptyMessage: _mine ? 'Share a scanned position or one of your puzzles to post it here.' : 'No posts yet.',
              header: _header(context, profile),
            ),
    );
  }

  Widget _header(BuildContext context, CommunityProfile? profile) {
    final theme = Theme.of(context);
    if (profile == null) {
      return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    }
    Widget count(int n, String label) => Text.rich(TextSpan(children: [
          TextSpan(text: '$n', style: const TextStyle(fontWeight: FontWeight.bold)),
          TextSpan(text: ' $label', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        ]));
    final following = _following;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(username: profile.username, radius: 32),
              const Spacer(),
              if (following != null)
                following
                    ? OutlinedButton(onPressed: _busy ? null : _toggleFollow, child: const Text('Following'))
                    : FilledButton(onPressed: _busy ? null : _toggleFollow, child: const Text('Follow')),
            ],
          ),
          const SizedBox(height: 12),
          Text('@${profile.username}', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          if (profile.bio.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(profile.bio),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            children: [
              count(profile.following, 'Following'),
              count(profile.followers, profile.followers == 1 ? 'Follower' : 'Followers'),
              count(profile.posts, profile.posts == 1 ? 'Post' : 'Posts'),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
        ],
      ),
    );
  }
}
