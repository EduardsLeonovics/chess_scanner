import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../share/share_link.dart';
import 'comments_page.dart';
import 'community_models.dart';
import 'community_repository.dart';
import 'feed_list.dart';
import 'feed_puzzle.dart';
import 'profile_page.dart';

/// One post in the feed: author, text, the puzzle to solve, and actions.
class PostCard extends ConsumerWidget {
  const PostCard({super.key, required this.post, this.showComments = true});

  final CommunityPost post;

  /// False on the post's own comments page.
  final bool showComments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    // The author sits above the post, so the text and the board get the
    // full width and stay centred.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(
                  username: post.authorUsername,
                  avatarUrl: post.authorAvatarUrl,
                  radius: 16,
                  onTap: () => openProfile(context, post.authorId),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: InkWell(
                    onTap: () => openProfile(context, post.authorId),
                    child: Text(
                      '@${post.authorUsername}',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                Text(
                  ' · ${timeAgo(post.createdAt, now)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const Spacer(),
                _PostMenu(post: post),
              ],
            ),
            if (post.body.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(post.body, style: theme.textTheme.bodyMedium),
              )
            else
              const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: FeedPuzzle(post: post, size: constraints.maxWidth),
            ),
            Row(
              children: [
                if (showComments)
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => CommentsPage(post: post)),
                    ),
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: Text(post.commentCount == 0 ? 'Comment' : '${post.commentCount}'),
                  ),
                const Spacer(),
                Builder(
                  builder: (buttonContext) => IconButton(
                    tooltip: 'Share a link',
                    icon: const Icon(Icons.share_outlined, size: 20),
                    onPressed: () => sharePositionLink(_puzzleFen(post), buttonContext),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The puzzle position itself (after the lead-in move), for links.
String _puzzleFen(CommunityPost post) {
  final pos = Chess.fromSetup(Setup.parseFen(post.fen));
  final lead = post.lastMove == null ? null : Move.parse(post.lastMove!);
  return lead != null && pos.isLegal(lead) ? pos.play(lead).fen : pos.fen;
}

/// A round avatar: the user's picture, or else the username's first letter
/// in a colour of its own.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.username, this.avatarUrl, this.radius = 20, this.onTap});

  final String username;
  final String? avatarUrl;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hue = (username.toLowerCase().codeUnits.fold(0, (h, c) => h * 31 + c) % 360).toDouble();
    final url = avatarUrl;
    return GestureDetector(
      onTap: onTap,
      child: CircleAvatar(
        radius: radius,
        backgroundColor: HSLColor.fromAHSL(1, hue, 0.45, 0.4).toColor(),
        // Decoded at the size shown, not the size uploaded.
        foregroundImage: url == null
            ? null
            : ResizeImage.resizeIfNeeded(
                (radius * 2 * MediaQuery.devicePixelRatioOf(context)).ceil(),
                null,
                NetworkImage(url),
              ),
        // The letter shows while the picture loads, or if it fails to.
        onForegroundImageError: url == null ? null : (_, _) {},
        child: Text(
          username.isEmpty ? '?' : username[0].toUpperCase(),
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: radius * 0.9),
        ),
      ),
    );
  }
}

void openProfile(BuildContext context, String userId) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfilePage(userId: userId)));
}

enum _PostAction { delete, report, block }

class _PostMenu extends ConsumerWidget {
  const _PostMenu({required this.post});

  final CommunityPost post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(communityProvider)?.user?.id == post.authorId;
    return PopupMenuButton<_PostAction>(
      tooltip: 'More',
      iconSize: 18,
      padding: EdgeInsets.zero,
      onSelected: (action) => switch (action) {
        _PostAction.delete => _delete(context, ref),
        _PostAction.report => reportContent(context, ref, postId: post.id),
        _PostAction.block => blockUser(context, ref, post.authorId, post.authorUsername),
      },
      itemBuilder: (context) => [
        if (mine)
          const PopupMenuItem(value: _PostAction.delete, child: Text('Delete post'))
        else ...[
          const PopupMenuItem(value: _PostAction.report, child: Text('Report post')),
          PopupMenuItem(value: _PostAction.block, child: Text('Block @${post.authorUsername}')),
        ],
      ],
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final sure = await confirm(context, title: 'Delete this post?', action: 'Delete');
    if (!sure || !context.mounted) return;
    await runCommunityAction(context, () => ref.read(communityProvider)!.deletePost(post.id),
        done: 'Post deleted.');
    ref.read(feedRevisionProvider.notifier).bump();
  }
}

/// Asks why, then reports a post or comment to the project owner.
Future<void> reportContent(BuildContext context, WidgetRef ref, {int? postId, int? commentId}) async {
  const reasons = ['Spam', 'Abusive or hateful', 'Inappropriate', 'Something else'];
  final reason = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Why are you reporting this?'),
      children: [
        for (final r in reasons)
          SimpleDialogOption(onPressed: () => Navigator.pop(context, r), child: Text(r)),
      ],
    ),
  );
  if (reason == null || !context.mounted) return;
  await runCommunityAction(
    context,
    () => ref.read(communityProvider)!.report(postId: postId, commentId: commentId, reason: reason),
    done: 'Thanks, we\'ll take a look.',
  );
}

Future<void> blockUser(BuildContext context, WidgetRef ref, String userId, String username) async {
  final sure = await confirm(
    context,
    title: 'Block @$username?',
    message: 'You won\'t see their posts or comments any more, and you\'ll stop following them.',
    action: 'Block',
  );
  if (!sure || !context.mounted) return;
  await runCommunityAction(context, () => ref.read(communityProvider)!.block(userId),
      done: '@$username is blocked.');
  ref.read(feedRevisionProvider.notifier).bump();
}

Future<bool> confirm(BuildContext context, {required String title, String? message, required String action}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
      ],
    ),
  );
  return result == true;
}

/// Runs [action], showing [done] or the error in a snack bar. True on success.
Future<bool> runCommunityAction(BuildContext context, Future<void> Function() action, {String? done}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
    return true;
  } on CommunityException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
}
