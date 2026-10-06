import 'package:audioplayers/audioplayers.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/appearance.dart';

/// Board sounds; [correct] is the chime for a solved puzzle.
enum MoveSound { move, capture, castle, check, correct }

/// Which sound [move] makes when played from [before]. Check wins over
/// capture and castling, like on most chess sites.
MoveSound soundFor(Position before, Move move) {
  final after = before.play(move);
  if (after.isCheck) return MoveSound.check;
  if (move is NormalMove) {
    final mover = before.board.pieceAt(move.from);
    final target = before.board.pieceAt(move.to);
    if (mover?.role == Role.king && target?.color == mover?.color) return MoveSound.castle;
    if (mover?.role == Role.king && (move.from.file - move.to.file).abs() > 1) {
      return MoveSound.castle;
    }
    if (isCapture(before, move)) return MoveSound.capture;
  }
  return MoveSound.move;
}

/// Whether [move] takes a piece, including en passant.
bool isCapture(Position position, Move move) {
  if (move is! NormalMove) return false;
  final target = position.board.pieceAt(move.to);
  if (target != null) return target.color != position.turn;
  final mover = position.board.pieceAt(move.from);
  return mover?.role == Role.pawn && move.from.file != move.to.file;
}

final moveSoundsProvider = Provider<MoveSounds>((ref) {
  final sounds = MoveSounds()..load();
  ref.onDispose(sounds.dispose);
  return sounds;
});

/// Plays the board sounds from `assets/sounds/` (made by `tool/make_sounds.py`).
class MoveSounds {
  /// Short game sound effects: mix with whatever else is playing (never
  /// pause the user's music) and stay quiet when the phone is on silent.
  static final _effects = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.game,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  );

  /// Players kept per sound, so quick moves can overlap.
  static const _voices = 3;

  /// A fixed set of preloaded players per sound, reused round-robin.
  /// (AudioPool never returns low-latency players to the pool, so it made a
  /// new player on every move: lag that grew into a leak and a crash.)
  final _players = <MoveSound, List<AudioPlayer>>{};
  final _next = <MoveSound, int>{};
  bool _disposed = false;

  Future<void> load() async {
    for (final sound in MoveSound.values) {
      final players = <AudioPlayer>[];
      try {
        for (var i = 0; i < _voices; i++) {
          final player = AudioPlayer();
          players.add(player);
          await player.setPlayerMode(PlayerMode.lowLatency);
          await player.setAudioContext(_effects);
          await player.setReleaseMode(ReleaseMode.stop);
          await player.setSource(AssetSource('sounds/${sound.name}.wav'));
        }
        _players[sound] = players;
        if (_disposed) break;
      } catch (e) {
        debugPrint('Could not load ${sound.name} sound: $e');
        for (final player in players) {
          player.dispose();
        }
      }
    }
    if (_disposed) dispose();
  }

  void play(MoveSound sound) {
    final players = _players[sound];
    if (players == null || players.isEmpty) return;
    final index = _next[sound] ?? 0;
    _next[sound] = (index + 1) % players.length;
    final player = players[index];
    // stop() rewinds; on Android it also frees the old stream so resume()
    // starts the sound again instead of doing nothing.
    player.stop().then((_) => player.resume()).catchError((Object e) {
      debugPrint('Could not play ${sound.name} sound: $e');
    });
  }

  void dispose() {
    _disposed = true;
    for (final players in _players.values) {
      for (final player in players) {
        player.dispose();
      }
    }
    _players.clear();
  }
}

/// Plays the sound for [move] from [before] if move sounds are switched on.
void playMoveSound(WidgetRef ref, Position before, Move move) {
  if (!ref.read(appearanceProvider).moveSounds) return;
  ref.read(moveSoundsProvider).play(soundFor(before, move));
}

/// Plays the chime for a solved puzzle, if sounds are switched on.
void playCorrectSound(WidgetRef ref) {
  if (!ref.read(appearanceProvider).moveSounds) return;
  ref.read(moveSoundsProvider).play(MoveSound.correct);
}
