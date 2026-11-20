import 'dart:async';

/// Autosave like the website's queueSave/persistItem: typing waits 350 ms before saving, and the saves
/// for one item run one after another, so an older PATCH can never land after a newer one.
class SaveQueue {
  SaveQueue({this.delay = const Duration(milliseconds: 350)});

  final Duration delay;
  final _waiting = <String, ({Timer timer, void Function() run})>{};
  final _chains = <String, Future<void>>{};

  /// Schedules save() for key. With immediate, it runs now instead of after the delay.
  void queue(String key, Future<void> Function() save,
      {bool immediate = false, required void Function(Object error) onError}) {
    _waiting.remove(key)?.timer.cancel();
    void run() => _run(key, save, onError);
    if (immediate) {
      run();
    } else {
      _waiting[key] = (timer: Timer(delay, run), run: run);
    }
  }

  void _run(String key, Future<void> Function() save, void Function(Object error) onError) {
    _waiting.remove(key)?.timer.cancel();
    final previous = _chains[key] ?? Future<void>.value();
    late final Future<void> operation;
    operation = previous.then((_) => save()).catchError(onError).whenComplete(() {
      if (identical(_chains[key], operation)) _chains.remove(key);
    });
    _chains[key] = operation;
  }

  /// Runs every waiting save now and waits for all of them, e.g. before signing out.
  Future<void> flush() async {
    for (final waiting in _waiting.values.toList()) {
      waiting.run();
    }
    await Future.wait(_chains.values.toList());
  }

  void dispose() {
    for (final waiting in _waiting.values) {
      waiting.timer.cancel();
    }
    _waiting.clear();
  }
}
