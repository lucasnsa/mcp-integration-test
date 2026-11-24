/// A tool call made during a recorded session, replayable as test code.
final class RecordedStep {
  RecordedStep(this.tool, Map<String, Object?> args, {this.failure})
    : args = Map.unmodifiable(args);

  /// Tool name, e.g. `tap`, `enterEnv`, `app_restart`.
  final String tool;

  /// Arguments the tool was called with (without `shot` / `shotImage`).
  final Map<String, Object?> args;

  /// Set when an `expect` did not hold while recording; exported as a comment.
  final String? failure;

  Map<String, Object?> toJson() => {
    'tool': tool,
    'args': args,
    if (failure != null) 'failure': failure,
  };
}

/// Tools whose successful calls are recorded.
const recordableTools = {
  'tap',
  'longPress',
  'doubleTap',
  'tapAt',
  'enterText',
  'enterEnv',
  'drag',
  'fling',
  'scrollUntilVisible',
  'pressBack',
  'sendKey',
  'pump',
  'pumpAndSettle',
  'waitFor',
  'expect',
  'app_restart',
};

/// Collects the steps of a session between `recording_start` and
/// `recording_stop`. Steps are kept after stopping so they can be exported.
final class SessionRecorder {
  final _steps = <RecordedStep>[];
  bool _recording = false;

  bool get isRecording => _recording;

  List<RecordedStep> get steps => List.unmodifiable(_steps);

  /// Clears previous steps and starts recording.
  void start() {
    _steps.clear();
    _recording = true;
  }

  void stop() => _recording = false;

  /// Adds a step when recording and [tool] is replayable; ignored otherwise.
  void record(String tool, Map<String, Object?> args, {String? failure}) {
    if (!_recording || !recordableTools.contains(tool)) {
      return;
    }
    _steps.add(RecordedStep(tool, _deepCopy(args), failure: failure));
  }

  static Map<String, Object?> _deepCopy(Map<String, Object?> map) => {
    for (final MapEntry(:key, :value) in map.entries)
      key: value is Map ? _deepCopy(value.cast<String, Object?>()) : value,
  };
}
