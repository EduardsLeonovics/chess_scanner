import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../backup/library_backup.dart';
import '../puzzles/puzzle_store.dart';
import 'community_models.dart';
import 'community_repository.dart';
import 'feed_list.dart';
import 'post_card.dart';
import 'report_sheet.dart';

/// [bytes] as a square 256-pixel JPEG for a profile picture (centre crop),
/// or null if it isn't an image. Runs in an isolate (see [compute]).
Uint8List? avatarJpeg(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final image = img.bakeOrientation(decoded);
  final side = image.width < image.height ? image.width : image.height;
  final square = img.copyCrop(
    image,
    x: (image.width - side) ~/ 2,
    y: (image.height - side) ~/ 2,
    width: side,
    height: side,
  );
  return img.encodeJpg(img.copyResize(square, width: 256, height: 256), quality: 85);
}

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

  /// "Notify me when they post"; null on your own profile.
  bool? _alerts;

  /// Whether the user blocked this person; null on your own profile.
  bool? _blocked;
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
      final blocked = _mine ? null : await _repo.isBlocked(widget.userId);
      bool? alerts;
      if (!_mine) {
        try {
          alerts = await _repo.hasPostAlerts(widget.userId);
        } on CommunityException {
          // No alerts table yet (server not updated): just hide the bell.
        }
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _following = following;
        _alerts = alerts;
        _blocked = blocked;
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

  Future<void> _toggleAlerts() async {
    final on = _alerts;
    if (on == null || _busy) return;
    setState(() => _busy = true);
    final ok = await runCommunityAction(
      context,
      () => _repo.setPostAlerts(widget.userId, !on),
      done: on
          ? 'You won\'t be notified about @${_profile?.username}\'s posts.'
          : 'You\'ll see @${_profile?.username}\'s new posts under the bell in Community.',
    );
    if (!mounted) return;
    setState(() {
      if (ok) _alerts = !on;
      _busy = false;
    });
  }

  Future<void> _changePicture() async {
    final remove = _profile?.avatarUrl != null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            if (remove)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove picture'),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'remove') {
      setState(() => _busy = true);
      if (await runCommunityAction(context, _repo.removeAvatar, done: 'Picture removed.')) {
        ref.read(feedRevisionProvider.notifier).bump();
        await _load();
      }
      if (mounted) setState(() => _busy = false);
      return;
    }
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Couldn\'t open the picture: $e')));
      }
      return;
    }
    if (file == null || !mounted) return;
    setState(() => _busy = true);
    final bytes = await file.readAsBytes();
    final jpeg = await compute(avatarJpeg, bytes);
    if (!mounted) return;
    if (jpeg == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That picture couldn\'t be read.')));
      setState(() => _busy = false);
      return;
    }
    if (await runCommunityAction(context, () => _repo.setAvatar(jpeg), done: 'Profile picture updated.')) {
      ref.read(feedRevisionProvider.notifier).bump();
      await _load();
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Signing out removes the games from the phone, which a run analyzing
  /// them can't have.
  bool _notWhileLoadingGames() {
    if (!ref.read(puzzleGeneratorProvider).running) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Stop loading your games first (Puzzles tab).')),
    );
    return false;
  }

  Future<void> _account(_AccountAction action) async {
    final navigator = Navigator.of(context);
    switch (action) {
      case _AccountAction.signOut:
        final backup = ref.read(libraryBackupProvider.notifier);
        if (!_notWhileLoadingGames()) return;
        var signedOut = false;
        if (!await runCommunityAction(context, () async => signedOut = await backup.signOut())) return;
        if (!signedOut) {
          if (!mounted) return;
          final sure = await confirm(
            context,
            title: 'Sign out anyway?',
            message: 'Your latest games and puzzles couldn\'t be saved to your account '
                '(no connection?). Signing out removes them from this phone.',
            action: 'Sign out',
          );
          if (!sure || !mounted) return;
          signedOut = await runCommunityAction(context, () => backup.signOut(force: true));
        }
        if (signedOut) navigator.pop();
      case _AccountAction.delete:
        if (!_notWhileLoadingGames()) return;
        final sure = await confirm(
          context,
          title: 'Delete your account?',
          message: 'Your profile, posts, comments, follows and saved games and puzzles '
              'are deleted for good, also from this phone.',
          action: 'Delete account',
        );
        if (!sure || !mounted) return;
        final backup = ref.read(libraryBackupProvider.notifier);
        if (await runCommunityAction(context, backup.deleteAccount, done: 'Your account is deleted.')) {
          navigator.pop();
        }
    }
  }

  Future<void> _other(_OtherAction action) async {
    final username = _profile?.username ?? '';
    switch (action) {
      case _OtherAction.report:
        await reportContent(context, ref, userId: widget.userId, username: username);
      case _OtherAction.block:
        await blockUser(context, ref, widget.userId, username);
      case _OtherAction.unblock:
        await runCommunityAction(context, () => _repo.unblock(widget.userId), done: '@$username is unblocked.');
        ref.read(feedRevisionProvider.notifier).bump();
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final blocked = _blocked;
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
            )
          else if (profile != null)
            PopupMenuButton<_OtherAction>(
              tooltip: 'More',
              onSelected: _other,
              itemBuilder: (context) => [
                PopupMenuItem(value: _OtherAction.report, child: Text('Report @${profile.username}')),
                if (blocked == true)
                  PopupMenuItem(value: _OtherAction.unblock, child: Text('Unblock @${profile.username}'))
                else
                  PopupMenuItem(value: _OtherAction.block, child: Text('Block @${profile.username}')),
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
              if (_mine)
                Tooltip(
                  message: 'Change profile picture',
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _busy ? null : _changePicture,
                    child: Stack(
                      children: [
                        UserAvatar(username: profile.username, avatarUrl: profile.avatarUrl, radius: 32),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: theme.colorScheme.primary,
                            child: _busy
                                ? SizedBox.square(
                                    dimension: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: theme.colorScheme.onPrimary,
                                    ),
                                  )
                                : Icon(Icons.photo_camera, size: 14, color: theme.colorScheme.onPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                UserAvatar(username: profile.username, avatarUrl: profile.avatarUrl, radius: 32),
              const Spacer(),
              if (_alerts case final alerts?)
                IconButton(
                  tooltip: alerts ? 'Stop notifying me' : 'Notify me when they post',
                  isSelected: alerts,
                  onPressed: _busy ? null : _toggleAlerts,
                  icon: const Icon(Icons.notifications_none),
                  selectedIcon: const Icon(Icons.notifications_active),
                ),
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

enum _OtherAction { report, block, unblock }
