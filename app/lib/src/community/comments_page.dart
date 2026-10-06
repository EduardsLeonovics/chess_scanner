import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'community_models.dart';
import 'community_repository.dart';
import 'post_card.dart';
import 'report_sheet.dart';

/// A post with its comments, and a box to add one.
class CommentsPage extends ConsumerStatefulWidget {
  const CommentsPage({super.key, required this.post});

  final CommunityPost post;

  @override
  ConsumerState<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends ConsumerState<CommentsPage> {
  final _text = TextEditingController();
  List<PostComment>? _comments;
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final comments = await ref.read(communityProvider)!.comments(widget.post.id);
      if (!mounted) return;
      setState(() {
        _comments = comments;
        _error = null;
      });
    } on CommunityException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    final sent = await runCommunityAction(
      context,
      () => ref.read(communityProvider)!.addComment(widget.post.id, body),
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (sent) {
      _text.clear();
      FocusScope.of(context).unfocus();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final comments = _comments;
    return Scaffold(
      appBar: AppBar(title: const Text('Post')),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  PostCard(post: widget.post, showComments: false),
                  const Divider(height: 1),
                  if (_error != null)
                    Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center))
                  else if (comments == null)
                    const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                  else if (comments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('No comments yet. Say what you think of the puzzle!',
                          textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                    )
                  else
                    for (final comment in comments)
                      _CommentTile(comment: comment, postAuthorId: widget.post.authorId, onChanged: _load),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: PostComment.maxBody,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Add a comment',
                        border: InputBorder.none,
                        counterText: '',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Send',
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _CommentAction { delete, report, block }

class _CommentTile extends ConsumerWidget {
  const _CommentTile({required this.comment, required this.postAuthorId, required this.onChanged});

  final PostComment comment;

  /// Whoever wrote the post: they can remove any comment under it.
  final String postAuthorId;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final me = ref.watch(communityProvider)?.user?.id;
    final mine = me == comment.authorId;
    final canDelete = mine || me == postAuthorId;
    return ListTile(
      leading: UserAvatar(
        username: comment.authorUsername,
        avatarUrl: comment.authorAvatarUrl,
        radius: 16,
        onTap: () => openProfile(context, comment.authorId),
      ),
      title: Text.rich(TextSpan(children: [
        TextSpan(text: '@${comment.authorUsername}', style: const TextStyle(fontWeight: FontWeight.bold)),
        TextSpan(
          text: ' · ${timeAgo(comment.createdAt, DateTime.now())}',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ])),
      subtitle: Text(comment.body, style: theme.textTheme.bodyMedium),
      trailing: PopupMenuButton<_CommentAction>(
        tooltip: 'More',
        iconSize: 18,
        onSelected: (action) async {
          switch (action) {
            case _CommentAction.delete:
              if (await runCommunityAction(
                context,
                () => ref.read(communityProvider)!.deleteComment(comment.id),
              )) {
                onChanged();
              }
            case _CommentAction.report:
              if (await reportContent(
                context,
                ref,
                commentId: comment.id,
                userId: comment.authorId,
                username: comment.authorUsername,
              )) {
                onChanged();
              }
            case _CommentAction.block:
              if (await blockUser(context, ref, comment.authorId, comment.authorUsername)) onChanged();
          }
        },
        itemBuilder: (context) => [
          if (canDelete) const PopupMenuItem(value: _CommentAction.delete, child: Text('Delete comment')),
          if (!mine) ...[
            const PopupMenuItem(value: _CommentAction.report, child: Text('Report comment')),
            PopupMenuItem(value: _CommentAction.block, child: Text('Block @${comment.authorUsername}')),
          ],
        ],
      ),
    );
  }
}
