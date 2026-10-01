import 'package:audioplayers/audioplayers.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/appearance.dart';

enum MoveSound { move, capture, castle, check }

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

  final _pools = <MoveSound, AudioPool>{};

  Future<void> load() async {
    for (final sound in MoveSound.values) {
      try {
        _pools[sound] = await AudioPool.create(
          source: AssetSource('sounds/${sound.name}.wav'),
          minPlayers: 2,
          maxPlayers: 4,
          playerMode: PlayerMode.lowLatency,
          audioContext: _effects,
        );
      } catch (e) {
        debugPrint('Could not load ${sound.name} sound: $e');
      }
    }
  }

  void play(MoveSound sound) => _pools[sound]?.start();

  void dispose() {
    for (final pool in _pools.values) {
      pool.dispose();
    }
  }
}

/// Plays the sound for [move] from [before] if move sounds are switched on.
void playMoveSound(WidgetRef ref, Position before, Move move) {
  if (!ref.read(appearanceProvider).moveSounds) return;
  ref.read(moveSoundsProvider).play(soundFor(before, move));
}
