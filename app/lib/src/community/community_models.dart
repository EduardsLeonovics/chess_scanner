import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

/// A position posted to the community feed, to be solved.
@immutable
class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.authorId,
    required this.authorUsername,
    required this.body,
    required this.fen,
    required this.solution,
    required this.bestScore,
    required this.createdAt,
    this.lastMove,
    this.commentCount = 0,
    this.authorAvatarUrl,
  });

  final int id;
  final String authorId;
  final String authorUsername;

  /// The author's profile picture, if they set one.
  final String? authorAvatarUrl;

  /// The author's text, up to [PostDraft.maxBody] characters.
  final String body;

  /// Position before [lastMove]; the solver plays the side to move after it.
  final String fen;

  /// The move leading into the puzzle, shown first, in UCI.
  final String? lastMove;

  /// UCI moves, the solver's first: solver, reply, solver, …
  final List<String> solution;

  /// Engine score of the solution for the solver, in centipawns (mates
  /// as ±100000-ish, see `scoreOf`). Equally good moves are accepted.
  final int bestScore;
  final DateTime createdAt;
  final int commentCount;

  /// The side the solver plays.
  Side get solverSide {
    final side = Setup.parseFen(fen).turn;
    return lastMove == null ? side : side.opposite;
  }

  factory CommunityPost.fromJson(Map<String, dynamic> json) => CommunityPost(
        id: json['id'] as int,
        authorId: json['author_id'] as String,
        authorUsername: json['author_username'] as String,
        body: json['body'] as String? ?? '',
        fen: json['fen'] as String,
        lastMove: json['last_move'] as String?,
        solution: (json['solution'] as List<dynamic>).cast<String>(),
        bestScore: json['best_score'] as int,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        commentCount: json['comment_count'] as int? ?? 0,
        authorAvatarUrl: json['author_avatar_url'] as String?,
      );
}

/// A post being written: the puzzle plus the text, before it has an id.
@immutable
class PostDraft {
  const PostDraft({
    required this.fen,
    required this.solution,
    required this.bestScore,
    this.lastMove,
    this.body = '',
  });

  static const maxBody = 280;

  final String fen;
  final String? lastMove;
  final List<String> solution;
  final int bestScore;
  final String body;

  PostDraft withBody(String body) => PostDraft(
        fen: fen,
        lastMove: lastMove,
        solution: solution,
        bestScore: bestScore,
        body: body,
      );

  Map<String, dynamic> toJson(String authorId) => {
        'author_id': authorId,
        'body': body.trim(),
        'fen': fen,
        'last_move': lastMove,
        'solution': solution,
        'best_score': bestScore,
      };
}

@immutable
class PostComment {
  const PostComment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorUsername,
    required this.body,
    required this.createdAt,
    this.authorAvatarUrl,
  });

  static const maxBody = 500;

  final String? authorAvatarUrl;

  final int id;
  final int postId;
  final String authorId;
  final String authorUsername;
  final String body;
  final DateTime createdAt;

  factory PostComment.fromJson(Map<String, dynamic> json) => PostComment(
        id: json['id'] as int,
        postId: json['post_id'] as int,
        authorId: json['author_id'] as String,
        authorUsername: json['author_username'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        authorAvatarUrl: json['author_avatar_url'] as String?,
      );
}

/// A user's public profile with follower counts.
@immutable
class CommunityProfile {
  const CommunityProfile({
    required this.id,
    required this.username,
    required this.bio,
    required this.followers,
    required this.following,
    required this.posts,
    this.avatarUrl,
  });

  final String id;
  final String? avatarUrl;
  final String username;
  final String bio;
  final int followers;
  final int following;
  final int posts;

  factory CommunityProfile.fromJson(Map<String, dynamic> json) => CommunityProfile(
        id: json['id'] as String,
        username: json['username'] as String,
        bio: json['bio'] as String? ?? '',
        followers: json['followers'] as int? ?? 0,
        following: json['following'] as int? ?? 0,
        posts: json['posts'] as int? ?? 0,
        avatarUrl: json['avatar_url'] as String?,
      );
}

/// Usernames: 3–20 letters, digits or underscores (as the database checks).
final usernamePattern = RegExp(r'^[A-Za-z0-9_]{3,20}$');

/// "now", "5m", "3h", "2d", or a date for older posts, like a feed shows.
String timeAgo(DateTime time, DateTime now) {
  final age = now.difference(time);
  if (age.inMinutes < 1) return 'now';
  if (age.inHours < 1) return '${age.inMinutes}m';
  if (age.inDays < 1) return '${age.inHours}h';
  if (age.inDays < 7) return '${age.inDays}d';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final date = '${months[time.month - 1]} ${time.day}';
  return time.year == now.year ? date : '$date, ${time.year}';
}
