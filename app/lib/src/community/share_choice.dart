import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../share/share_link.dart';
import 'auth_page.dart';
import 'community_models.dart';
import 'community_repository.dart';
import 'compose_post_page.dart';
import 'post_puzzle.dart';

/// "Share": post the position to the ChessGeek community feed (with your
/// own text), or send a link through any app as before.
///
/// [linkFen] is the position the link opens; [makeDraft] builds the post's
/// puzzle (it may ask the engine, so it only runs when posting). Throws
/// nothing: problems show in a snack bar.
Future<void> showShareChoice(
  BuildContext buttonContext,
  WidgetRef ref, {
  required String linkFen,
  required Future<PostDraft> Function() makeDraft,
}) async {
  final community = ref.read(communityProvider) != null;
  final choice = await showModalBottomSheet<_Share>(
    context: buttonContext,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.forum_outlined),
            title: const Text('Post to the ChessGeek community'),
            subtitle: Text(community
                ? 'Write something about it; others solve it in their feed'
                : 'The community isn\'t available in this version'),
            enabled: community,
            onTap: () => Navigator.pop(context, _Share.community),
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Share a link'),
            subtitle: const Text('Send it through any app; opens in ChessGeek'),
            onTap: () => Navigator.pop(context, _Share.link),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (!buttonContext.mounted) return;
  switch (choice) {
    case null:
      return;
    case _Share.link:
      await sharePositionLink(linkFen, buttonContext);
    case _Share.community:
      await _postToCommunity(buttonContext, ref, makeDraft);
  }
}

enum _Share { community, link }

Future<void> _postToCommunity(
  BuildContext context,
  WidgetRef ref,
  Future<PostDraft> Function() makeDraft,
) async {
  if (!await ensureSignedIn(context, ref) || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Expanded(child: Text('Working out the solution…')),
        ],
      ),
    ),
  );
  PostDraft? draft;
  try {
    draft = await makeDraft();
  } on PostPuzzleException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } finally {
    navigator.pop();
  }
  if (draft == null) return;
  await navigator.push(MaterialPageRoute<bool>(builder: (_) => ComposePostPage(draft: draft!)));
}
