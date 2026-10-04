import 'dart:async';

import 'package:chess_scanner/src/engine/engine_service.dart';
import 'package:chess_scanner/src/engine/engine_settings.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

const _fen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';

/// Answers every `go` with one info line and a bestmove, unless [silent].
class _FakeProcess implements EngineProcess {
  final _out = StreamController<String>();
  final sent = <String>[];
  bool silent = false;
  bool disposed = false;

  @override
  Stream<String> get stdout => _out.stream;

  @override
  void send(String command) {
    if (disposed) throw StateError('gone');
    sent.add(command);
    if (command.startsWith('go') && !silent) {
      scheduleMicrotask(() {
        _out.add('info depth 5 multipv 1 score cp 30 pv e7e5');
        _out.add('bestmove e7e5');
      });
    }
  }

  void exit() => _out.close();

  @override
  void dispose() => disposed = true;
}

_FakeProcess _add(List<_FakeProcess> all, _FakeProcess p) {
  all.add(p);
  return p;
}

void main() {
  test('evaluate returns the final lines', () async {
    final process = _FakeProcess();
    final engine = EngineService(launcher: () async => process);
    await engine.start();
    final eval = await engine.evaluate(_fen, depth: 5);
    expect(eval.best!.cp, -30); // Black to move: White's point of view.
    engine.dispose();
  });

  test('a dying engine fails the running search and is restarted', () async {
    final processes = <_FakeProcess>[];
    final engine = EngineService(launcher: () async => _add(processes, _FakeProcess()));
    await engine.start();
    processes.first.silent = true;
    final pending = engine.evaluate(_fen, depth: 5);
    await Future<void>.delayed(Duration.zero);
    processes.first.exit();
    await expectLater(pending, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    expect(processes, hasLength(2));
    expect(engine.status.value, EngineStatus.ready);
    final eval = await engine.evaluate(_fen, depth: 5);
    expect(eval.best, isNotNull);
    engine.dispose();
  });

  test('a silent engine is stopped, then treated as dead', () {
    fakeAsync((async) {
      final processes = <_FakeProcess>[];
      final engine = EngineService(
        launcher: () async => _add(processes, _FakeProcess()..silent = true),
        stallTimeout: const Duration(seconds: 10),
      );
      engine.start();
      async.flushMicrotasks();
      Object? error;
      engine.evaluate(_fen, depth: 5).catchError((Object e) {
        error = e;
        return const EngineEval(fen: '', lines: []);
      });
      async.elapse(const Duration(seconds: 11));
      expect(processes.first.sent.last, 'stop');
      expect(error, isNull);
      async.elapse(const Duration(seconds: 10));
      expect(error, isA<StateError>());
      expect(processes.first.disposed, isTrue);
      expect(processes, hasLength(2));
      engine.dispose();
    });
  });

  test('live analysis follows the settings, and new threads apply before the next search', () async {
    final process = _FakeProcess();
    final engine = EngineService(
      settings: const EngineSettings(lines: 2, limit: SearchLimit.time, seconds: 5, threads: 1),
      launcher: () async => process,
    );
    await engine.start();
    engine.analyze(_fen);
    await Future<void>.delayed(Duration.zero);
    expect(process.sent, containsAllInOrder(['setoption name MultiPV value 2', 'go movetime 5000']));

    engine.configure(const EngineSettings(lines: 4, limit: SearchLimit.unlimited, threads: 2));
    await Future<void>.delayed(Duration.zero);
    final after = process.sent.skip(process.sent.lastIndexOf('go movetime 5000') + 1).toList();
    expect(after, containsAllInOrder([
      'setoption name Threads value 2',
      'setoption name MultiPV value 4',
      'position fen $_fen',
      'go infinite',
    ]));
    engine.dispose();
  });

  test('gives up after too many restarts', () async {
    var launches = 0;
    late _FakeProcess last;
    final engine = EngineService(launcher: () async {
      launches++;
      return last = _FakeProcess()..silent = true;
    });
    await engine.start();
    for (var i = 0; i <= EngineService.maxRestarts; i++) {
      final pending = engine.evaluate(_fen, depth: 5);
      await Future<void>.delayed(Duration.zero);
      last.exit();
      await expectLater(pending, throwsStateError);
      await Future<void>.delayed(Duration.zero);
    }
    expect(launches, EngineService.maxRestarts + 1);
    expect(engine.status.value, EngineStatus.error);
    await expectLater(engine.evaluate(_fen, depth: 5), throwsStateError);
    engine.dispose();
  });
}
