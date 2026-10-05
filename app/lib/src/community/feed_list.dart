import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'community_models.dart';
import 'community_repository.dart';
import 'post_card.dart';

/// Bumped when posts change (posted, deleted, someone blocked), so open
/// feeds reload.
final feedRevisionProvider = NotifierProvider<FeedRevision, int>(FeedRevision.new);

class FeedRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// Loads a page of posts older than `before` (null: the newest).
typedef PostLoader = Future<List<CommunityPost>> Function(DateTime? before);

/// An endless list of posts, newest first: pull down to refresh, more load
/// near the end. [header] goes above the first post (e.g. a profile).
class FeedList extends ConsumerStatefulWidget {
  const FeedList({super.key, required this.load, required this.emptyMessage, this.header});

  final PostLoader load;
  final String emptyMessage;
  final Widget? header;

  @override
  ConsumerState<FeedList> createState() => _FeedListState();
}

class _FeedListState extends ConsumerState<FeedList> {
  final _posts = <CommunityPost>[];
  bool _loading = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _refresh() async {
    setState(() {
      _posts.clear();
      _done = false;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _done) return;
    setState(() => _loading = true);
    try {
      final page = await widget.load(_posts.isEmpty ? null : _posts.last.createdAt);
      if (!mounted) return;
      setState(() {
        _posts.addAll(page);
        _done = page.length < CommunityRepository.pageSize;
        _error = null;
      });
    } on CommunityException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(feedRevisionProvider, (_, _) => _refresh());
    final header = widget.header;
    final extra = header == null ? 0 : 1;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: extra + _posts.length + 1,
        separatorBuilder: (context, i) => i < extra ? const SizedBox.shrink() : const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i < extra) return header!;
          final index = i - extra;
          if (index < _posts.length) {
            if (index >= _posts.length - 3 && _error == null) WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
            final post = _posts[index];
            return PostCard(key: ValueKey(post.id), post: post);
          }
          return _footer(context);
        },
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(_error!, textAlign: TextAlign.center),
            TextButton(onPressed: _loadMore, child: const Text('Try again')),
          ],
        ),
      );
    }
    if (_posts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Text(widget.emptyMessage, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
      );
    }
    return const SizedBox(height: 32);
  }
}
