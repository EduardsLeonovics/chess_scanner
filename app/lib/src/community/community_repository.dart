import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'community_config.dart';
import 'community_models.dart';

/// A failed community action, with a message fit to show the user.
class CommunityException implements Exception {
  const CommunityException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The community backend, or null when this build has none (see
/// [CommunityConfig]).
final communityProvider = Provider<CommunityRepository?>(
  (ref) => CommunityConfig.ready ? CommunityRepository(Supabase.instance.client) : null,
);

/// The signed-in user, null when signed out or without a community.
final communityUserProvider = StreamProvider<User?>((ref) {
  final repo = ref.watch(communityProvider);
  if (repo == null) return Stream.value(null);
  return repo.userChanges;
});

/// Accounts, posts, comments and follows, stored in Supabase (schema in
/// `backend/supabase/schema.sql`). Every call throws [CommunityException]
/// with a readable message on failure.
class CommunityRepository {
  CommunityRepository(this._client);

  final SupabaseClient _client;

  static const pageSize = 20;

  User? get user => _client.auth.currentUser;

  /// The current user, then every change (sign in, sign out, …).
  Stream<User?> get userChanges async* {
    yield user;
    yield* _client.auth.onAuthStateChange.map((state) => state.session?.user);
  }

  /// Fires when the user opened a password-reset link: the app should ask
  /// for a new password (see [setPassword]).
  Stream<void> get passwordRecovery =>
      _client.auth.onAuthStateChange.where((s) => s.event == AuthChangeEvent.passwordRecovery);

  String get _uid {
    final id = user?.id;
    if (id == null) throw const CommunityException('Sign in first.');
    return id;
  }

  Future<T> _call<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on CommunityException {
      rethrow;
    } on AuthException catch (e) {
      throw CommunityException(_authMessage(e));
    } on PostgrestException catch (e) {
      throw CommunityException(_dbMessage(e));
    } on TimeoutException {
      throw const CommunityException('The server took too long. Try again.');
    } catch (e) {
      // Usually no connection (SocketException / ClientException).
      throw const CommunityException('Couldn\'t reach ChessGeek. Check your connection.');
    }
  }

  // -------------------------------------------------------------------------
  // Accounts

  /// Creates an account. Returns true when signed in right away, false when
  /// the user must first confirm their email.
  Future<bool> signUp({required String email, required String password, required String username}) =>
      _call(() async {
        if (!usernamePattern.hasMatch(username)) {
          throw const CommunityException('Usernames are 3–20 letters, digits or _.');
        }
        final free = await _client.rpc<bool>('username_available', params: {'name': username});
        if (!free) throw const CommunityException('That username is taken.');
        final response = await _client.auth.signUp(
          email: email.trim(),
          password: password,
          data: {'username': username},
          emailRedirectTo: CommunityConfig.authRedirect,
        );
        return response.session != null;
      });

  /// Signs in with an email or a username ([login] without an `@`).
  Future<void> signIn({required String login, required String password}) => _call(() async {
        var email = login.trim();
        if (!email.contains('@')) {
          if (!usernamePattern.hasMatch(email)) {
            throw const CommunityException('Wrong username or password.');
          }
          final found = await _client.rpc<String?>(
            'email_for_sign_in',
            params: {'name': email, 'password': password},
          );
          if (found == null) throw const CommunityException('Wrong username or password.');
          email = found;
        }
        await _client.auth.signInWithPassword(email: email, password: password);
      });

  Future<void> signOut() => _call(() => _client.auth.signOut());

  Future<void> sendPasswordReset(String email) => _call(
        () => _client.auth.resetPasswordForEmail(email.trim(), redirectTo: CommunityConfig.authRedirect),
      );

  Future<void> setPassword(String password) =>
      _call(() => _client.auth.updateUser(UserAttributes(password: password)));

  /// Deletes the account with all its posts, comments and follows.
  Future<void> deleteAccount() => _call(() async {
        // The picture is in public storage, which deleting the account
        // doesn't touch. Best effort: there may be none.
        try {
          await _client.storage.from('avatars').remove(['$_uid/avatar.jpg']);
        } catch (_) {}
        await _client.rpc<void>('delete_account');
        await _client.auth.signOut();
      });

  // -------------------------------------------------------------------------
  // Posts

  /// Newest posts first, older than [before] (for paging). [following]
  /// limits them to people the user follows, and the user's own.
  Future<List<CommunityPost>> feed({bool following = false, DateTime? before}) => _call(() async {
        var query = _client.from('feed_posts').select();
        if (following) {
          query = query.inFilter('author_id', [_uid, ...await _followingIds()]);
        }
        if (before != null) query = query.lt('created_at', before.toUtc().toIso8601String());
        final rows = await query.order('created_at', ascending: false).limit(pageSize);
        return rows.map(CommunityPost.fromJson).toList();
      });

  Future<List<CommunityPost>> postsBy(String userId, {DateTime? before}) => _call(() async {
        var query = _client.from('feed_posts').select().eq('author_id', userId);
        if (before != null) query = query.lt('created_at', before.toUtc().toIso8601String());
        final rows = await query.order('created_at', ascending: false).limit(pageSize);
        return rows.map(CommunityPost.fromJson).toList();
      });

  Future<CommunityPost> createPost(PostDraft draft) => _call(() async {
        final row = await _client.from('posts').insert(draft.toJson(_uid)).select('id').single();
        final post = await _client.from('feed_posts').select().eq('id', row['id'] as int).single();
        return CommunityPost.fromJson(post);
      });

  Future<void> deletePost(int id) => _call(() => _client.from('posts').delete().eq('id', id));

  // -------------------------------------------------------------------------
  // Comments

  Future<List<PostComment>> comments(int postId) => _call(() async {
        final rows = await _client
            .from('post_comments')
            .select()
            .eq('post_id', postId)
            .order('created_at')
            .limit(500);
        return rows.map(PostComment.fromJson).toList();
      });

  Future<void> addComment(int postId, String body) => _call(
        () => _client.from('comments').insert({'post_id': postId, 'author_id': _uid, 'body': body.trim()}),
      );

  Future<void> deleteComment(int id) => _call(() => _client.from('comments').delete().eq('id', id));

  // -------------------------------------------------------------------------
  // Profiles and follows

  Future<CommunityProfile> profile(String userId) => _call(() async {
        final row = await _client.from('profile_stats').select().eq('id', userId).single();
        return CommunityProfile.fromJson(row);
      });

  Future<bool> isFollowing(String userId) => _call(() async {
        final row = await _client
            .from('follows')
            .select('followee_id')
            .eq('follower_id', _uid)
            .eq('followee_id', userId)
            .maybeSingle();
        return row != null;
      });

  Future<void> follow(String userId) =>
      _call(() => _client.from('follows').upsert({'follower_id': _uid, 'followee_id': userId}));

  Future<void> unfollow(String userId) => _call(
        () => _client.from('follows').delete().eq('follower_id', _uid).eq('followee_id', userId),
      );

  Future<List<String>> _followingIds() async {
    final rows = await _client.from('follows').select('followee_id').eq('follower_id', _uid);
    return [for (final row in rows) row['followee_id'] as String];
  }

  // -------------------------------------------------------------------------
  // Profile pictures

  /// Uploads [jpeg] as the user's picture and returns its URL.
  Future<String> setAvatar(Uint8List jpeg) => _call(() async {
        final uid = _uid;
        final path = '$uid/avatar.jpg';
        await _client.storage.from('avatars').uploadBinary(
              path,
              jpeg,
              fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
            );
        // A new URL each time, so caches don't keep showing the old picture.
        final url = '${_client.storage.from('avatars').getPublicUrl(path)}'
            '?v=${DateTime.now().millisecondsSinceEpoch}';
        await _client.from('profiles').update({'avatar_url': url}).eq('id', uid);
        return url;
      });

  Future<void> removeAvatar() => _call(() async {
        final uid = _uid;
        await _client.from('profiles').update({'avatar_url': null}).eq('id', uid);
        await _client.storage.from('avatars').remove(['$uid/avatar.jpg']);
      });

  // -------------------------------------------------------------------------
  // Post alerts ("notify me when they post")

  Future<bool> hasPostAlerts(String userId) => _call(() async {
        final row = await _client
            .from('post_alerts')
            .select('author_id')
            .eq('subscriber_id', _uid)
            .eq('author_id', userId)
            .maybeSingle();
        return row != null;
      });

  Future<void> setPostAlerts(String userId, bool on) => _call(() async {
        if (on) {
          await _client.from('post_alerts').upsert({'subscriber_id': _uid, 'author_id': userId});
        } else {
          await _client.from('post_alerts').delete().eq('subscriber_id', _uid).eq('author_id', userId);
        }
      });

  /// Posts by the people the user turned alerts on for, newest first,
  /// older than [before] (for paging) and, with [since], newer than that.
  Future<List<CommunityPost>> alertPosts({DateTime? before, DateTime? since}) => _call(() async {
        final rows = await _client.from('post_alerts').select('author_id').eq('subscriber_id', _uid);
        final authors = [for (final row in rows) row['author_id'] as String];
        if (authors.isEmpty) return const <CommunityPost>[];
        var query = _client.from('feed_posts').select().inFilter('author_id', authors);
        if (before != null) query = query.lt('created_at', before.toUtc().toIso8601String());
        if (since != null) query = query.gt('created_at', since.toUtc().toIso8601String());
        final posts = await query.order('created_at', ascending: false).limit(pageSize);
        return posts.map(CommunityPost.fromJson).toList();
      });

  // -------------------------------------------------------------------------
  // Safety

  /// Hides [userId]'s posts and comments from the user, and unfollows them.
  Future<void> block(String userId) => _call(() async {
        await _client.from('blocks').upsert({'blocker_id': _uid, 'blocked_id': userId});
        await _client.from('follows').delete().eq('follower_id', _uid).eq('followee_id', userId);
      });

  Future<void> report({int? postId, int? commentId, required String reason}) => _call(
        () => _client.from('reports').insert({
          'reporter_id': _uid,
          'post_id': postId,
          'comment_id': commentId,
          'reason': reason,
        }),
      );
}

String _authMessage(AuthException e) {
  final code = e.code;
  return switch (code) {
    'invalid_credentials' => 'Wrong email or password.',
    'email_not_confirmed' => 'Confirm your email first: open the link we sent you.',
    'user_already_exists' || 'email_exists' => 'An account with that email already exists.',
    'weak_password' => 'Choose a longer password (at least 6 characters).',
    'over_email_send_rate_limit' || 'over_request_rate_limit' => 'Too many tries. Wait a minute.',
    'same_password' => 'That is already your password.',
    _ => e.message,
  };
}

String _dbMessage(PostgrestException e) => switch (e.code) {
      '23505' => 'That already exists.',
      '23514' => 'That is too long or not allowed.',
      'PGRST116' => 'That post or profile no longer exists.',
      '42501' => 'You can\'t do that.',
      'P0001' when e.message.contains('too_many_attempts') => 'Too many wrong passwords. Wait 15 minutes.',
      _ => 'Something went wrong on the server (${e.code ?? e.message}).',
    };
