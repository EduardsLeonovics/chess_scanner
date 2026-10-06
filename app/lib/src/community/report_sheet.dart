import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'community_models.dart';
import 'community_repository.dart';
import 'feed_list.dart';
import 'post_card.dart';

/// Reports a post, a comment or (with only [userId]) a profile: asks what's
/// wrong, then sends it to the moderators. Offers to block [username] at the
/// same time. True when the report was sent.
Future<bool> reportContent(
  BuildContext context,
  WidgetRef ref, {
  int? postId,
  int? commentId,
  required String userId,
  required String username,
}) async {
  final what = postId != null
      ? 'post'
      : commentId != null
          ? 'comment'
          : 'profile';
  final choice = await showModalBottomSheet<_ReportChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _ReportSheet(what: what, username: username),
  );
  if (choice == null || !context.mounted) return false;
  final repo = ref.read(communityProvider)!;
  final sent = await runCommunityAction(
    context,
    () async {
      await repo.report(
        postId: postId,
        commentId: commentId,
        userId: postId == null && commentId == null ? userId : null,
        category: choice.category,
        details: choice.details,
      );
      if (choice.block) await repo.block(userId);
    },
    done: choice.block
        ? 'Thanks for reporting. @$username is blocked.'
        : 'Thanks for reporting. Our moderators will review it.',
  );
  if (sent && choice.block) ref.read(feedRevisionProvider.notifier).bump();
  return sent;
}

typedef _ReportChoice = ({ReportCategory category, String details, bool block});

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.what, required this.username});

  /// "post", "comment" or "profile".
  final String what;
  final String username;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  ReportCategory? _category;
  final _details = TextEditingController();
  bool _block = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  bool get _canSend =>
      _category != null && (_category != ReportCategory.other || _details.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = _category;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Report this ${widget.what}', style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'What is wrong with it? Reports are private: @${widget.username} won\'t know who sent it.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            RadioGroup<ReportCategory>(
              groupValue: category,
              onChanged: (c) => setState(() => _category = c),
              child: Column(
                children: [
                  for (final c in ReportCategory.values)
                    RadioListTile<ReportCategory>(
                      value: c,
                      title: Text(c.label),
                      subtitle: Text(c.hint),
                      dense: true,
                    ),
                ],
              ),
            ),
            if (category == ReportCategory.childSafety || category == ReportCategory.selfHarm)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
                child: Text(
                  'If someone is in immediate danger, contact your local emergency services first.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: TextField(
                controller: _details,
                maxLength: 500,
                maxLines: 3,
                minLines: 1,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: category == ReportCategory.other ? 'What is wrong?' : 'Details (optional)',
                ),
              ),
            ),
            CheckboxListTile(
              value: _block,
              onChanged: (v) => setState(() => _block = v ?? false),
              title: Text('Also block @${widget.username}'),
              subtitle: const Text('Neither of you will see the other\'s posts or comments.'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: FilledButton(
                onPressed: _canSend
                    ? () => Navigator.pop<_ReportChoice>(
                          context,
                          (category: category!, details: _details.text, block: _block),
                        )
                    : null,
                child: const Text('Send report'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
