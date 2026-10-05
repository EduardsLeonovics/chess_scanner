import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/appearance.dart';
import 'community_models.dart';
import 'community_repository.dart';
import 'feed_list.dart';
import 'post_card.dart';

/// Writing a post: text above the position, like attaching an image to a
/// post on X. Pops with true once posted.
class ComposePostPage extends ConsumerStatefulWidget {
  const ComposePostPage({super.key, required this.draft});

  final PostDraft draft;

  @override
  ConsumerState<ComposePostPage> createState() => _ComposePostPageState();
}

class _ComposePostPageState extends ConsumerState<ComposePostPage> {
  final _text = TextEditingController();
  bool _posting = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    if (_posting) return;
    setState(() => _posting = true);
    final navigator = Navigator.of(context);
    final posted = await runCommunityAction(
      context,
      () => ref.read(communityProvider)!.createPost(widget.draft.withBody(_text.text)),
      done: 'Posted to the community.',
    );
    if (!mounted) return;
    setState(() => _posting = false);
    if (posted) {
      ref.read(feedRevisionProvider.notifier).bump();
      navigator.pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appearance = ref.watch(appearanceProvider);
    final pieceAssets = ref.watch(pieceAssetsProvider).value ?? appearance.pieceSet.assets;
    final draft = widget.draft;
    Position pos = Chess.fromSetup(Setup.parseFen(draft.fen));
    Move? lead = draft.lastMove == null ? null : Move.parse(draft.lastMove!);
    if (lead != null && pos.isLegal(lead)) {
      pos = pos.play(lead);
    } else {
      lead = null;
    }
    final solver = pos.turn;
    final user = ref.watch(communityProvider)?.user;
    final username = user?.userMetadata?['username'] as String? ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('New post'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _posting ? null : _post,
              child: _posting
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Post'),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserAvatar(username: username),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _text,
                    autofocus: true,
                    minLines: 2,
                    maxLines: 8,
                    maxLength: PostDraft.maxBody,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: '${solver == Side.white ? 'White' : 'Black'} to move. What should people find?',
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 52),
              child: LayoutBuilder(
                builder: (context, box) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: StaticChessboard(
                    size: box.maxWidth,
                    orientation: solver,
                    fen: pos.fen,
                    lastMove: lead,
                    settings: StaticChessboardSettings(
                      colorScheme: appearance.colorScheme,
                      pieceAssets: pieceAssets,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(52, 12, 0, 0),
              child: Text(
                draft.solution.length > 1
                    ? 'Solution: a forced mate, ${(draft.solution.length + 1) ~/ 2} moves. '
                        'Others solve it in their feed; equally good moves count too.'
                    : 'Solution: Stockfish\'s best move. Others solve it in their feed; '
                        'equally good moves count too.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
