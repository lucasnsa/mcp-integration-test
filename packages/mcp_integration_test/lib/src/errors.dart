import 'package:flutter/foundation.dart';

/// One distinct error raised by the app (deduplicated by kind + summary).
class AppError {
  AppError({
    required this.kind,
    required this.summary,
    required this.library,
    required this.context,
    required this.stack,
    required this.afterCommand,
  });

  /// `overflow` (RenderFlex/RenderBox overflow) or `exception`.
  final String kind;
  final String summary;
  final String? library;
  final String? context;
  final List<String> stack;

  /// Command that was running (or had just run) when the error was reported.
  final String afterCommand;
  int count = 1;

  Map<String, Object?> toJson() => {
        'kind': kind,
        'summary': summary,
        if (library != null) 'library': library,
        if (context != null) 'context': context,
        'count': count,
        'afterCommand': afterCommand,
        if (stack.isNotEmpty) 'stack': stack,
      };
}

/// Records every [FlutterErrorDetails] (overflows, build/layout/paint
/// exceptions, errors thrown in gesture callbacks, uncaught errors that the
/// test zone forwards) and still forwards them to the original handler so the
/// test binding keeps working.
class ErrorCollector {
  final List<AppError> all = [];
  int _reported = 0;
  FlutterExceptionHandler? _previous;

  /// Set by the session loop so errors can be attributed to a command.
  String currentCommand = '(between commands)';

  void install() {
    _previous = FlutterError.onError;
    FlutterError.onError = (details) {
      _record(details);
      _previous?.call(details);
    };
  }

  /// Must run before the test ends: flutter_test checks the handler was restored.
  void uninstall() => FlutterError.onError = _previous;

  void _record(FlutterErrorDetails d) {
    final text = d.exceptionAsString();
    final summary = text.split('\n').first.trim();
    final kind = text.contains('overflowed') ? 'overflow' : 'exception';
    for (final e in all) {
      if (e.kind == kind && e.summary == summary) {
        e.count++;
        return;
      }
    }
    final stack = d.stack == null
        ? <String>[]
        : FlutterError.demangleStackTrace(d.stack!)
            .toString()
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .take(8)
            .toList();
    all.add(AppError(
      kind: kind,
      summary: summary,
      library: d.library,
      context: d.context?.toDescription(),
      stack: stack,
      afterCommand: currentCommand,
    ));
  }

  /// Errors first seen since the previous call.
  List<Map<String, Object?>> takeNew() {
    final fresh = all.sublist(_reported).map((e) => e.toJson()).toList();
    _reported = all.length;
    return fresh;
  }

  void clear() {
    all.clear();
    _reported = 0;
  }
}
