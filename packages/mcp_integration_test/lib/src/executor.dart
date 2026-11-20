import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'command_protocol.dart';
import 'errors.dart';
import 'finder_spec.dart';
import 'snapshot.dart';

/// Executes client commands against a [WidgetTester].
class CommandExecutor {
  CommandExecutor(this.tester, this.binding, this.errors, this.appMain);

  final WidgetTester tester;
  final IntegrationTestWidgetsFlutterBinding binding;
  final ErrorCollector errors;

  /// The app's entry point; `restart` runs it again on a fresh widget tree.
  final FutureOr<void> Function() appMain;

  /// Failed `expect` calls; make the underlying test fail at shutdown.
  final List<String> failedExpectations = [];
  int passedExpectations = 0;

  Future<Object?> run(String method, Map<String, Object?> p) async {
    switch (CommandMethod.byName[method]) {
      case CommandMethod.status:
        return _status();
      case CommandMethod.snapshot:
        return {'nodes': buildSnapshot(tester.binding.rootElement!, maxNodes: _int(p, 'maxNodes') ?? 300)};
      case CommandMethod.find:
        return _find(p);
      case CommandMethod.getText:
        return _getText(p);
      case CommandMethod.tap:
        return _action(p, (f) => tester.tap(f));
      case CommandMethod.longPress:
        return _action(p, (f) => tester.longPress(f));
      case CommandMethod.doubleTap:
        return _action(p, (f) async {
          await tester.tap(f);
          await tester.pump(kDoubleTapMinTime);
          await tester.tap(f);
        });
      case CommandMethod.tapAt:
        return _tapAt(p);
      case CommandMethod.enterText:
        return _enterText(p);
      case CommandMethod.drag:
        return _action(p, (f) => tester.drag(f, Offset(_num(p, 'dx'), _num(p, 'dy'))));
      case CommandMethod.fling:
        return _action(p, (f) => tester.fling(f, Offset(_num(p, 'dx'), _num(p, 'dy')), _num(p, 'speed', 1000)));
      case CommandMethod.scrollUntilVisible:
        return _scrollUntilVisible(p);
      case CommandMethod.pump:
        await tester.pump(Duration(milliseconds: _int(p, 'ms') ?? 0));
        return {};
      case CommandMethod.pumpAndSettle:
        return _settle(timeoutMs: _int(p, 'timeoutMs') ?? 10000, strict: true);
      case CommandMethod.waitFor:
        return _waitFor(p);
      case CommandMethod.expect:
        return _expect(p);
      case CommandMethod.pressBack:
        final completer = Completer<ByteData?>();
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'flutter/navigation',
          const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
          completer.complete,
        );
        final reply = await completer.future;
        await _settle();
        return {'handled': reply == null ? null : const JSONMethodCodec().decodeEnvelope(reply) == true};
      case CommandMethod.sendKey:
        return _sendKey(p);
      case CommandMethod.screenshot:
        return _screenshot(p);
      case CommandMethod.errors:
        final list = errors.all.map((e) => e.toJson()).toList();
        if (p['clear'] == true) errors.clear();
        return {'errors': list};
      case CommandMethod.results:
        return _results();
      case CommandMethod.restart:
        return _restart();
      case CommandMethod.shutdown:
      case null:
        throw ArgumentError('Unknown method "$method"');
    }
  }

  // --- queries ---------------------------------------------------------

  Map<String, Object?> _status() {
    final view = tester.view;
    return {
      'platform': defaultTargetPlatform.name,
      'logicalSize': [view.physicalSize.width / view.devicePixelRatio, view.physicalSize.height / view.devicePixelRatio],
      'devicePixelRatio': view.devicePixelRatio,
      'hasRoot': tester.binding.rootElement != null,
      'expectations': {'passed': passedExpectations, 'failed': failedExpectations.length},
      'appErrors': errors.all.length,
    };
  }

  Map<String, Object?> _find(Map<String, Object?> p) {
    final spec = FinderSpec.fromJson(p['finder']);
    final elements = spec.finder.evaluate().toList();
    return {
      'count': elements.length,
      'matches': elements.take(20).map(_describeElement).toList(),
    };
  }

  Map<String, Object?> _getText(Map<String, Object?> p) {
    final spec = FinderSpec.fromJson(p['finder']);
    final element = _single(spec);
    final texts = <String>[];
    void collect(Element e) {
      final w = e.widget;
      if (w is Text) {
        final t = w.data ?? w.textSpan?.toPlainText();
        if (t != null) texts.add(t);
        return;
      }
      if (w is EditableText) {
        texts.add(_editableText(w));
        return;
      }
      e.visitChildren(collect);
    }

    collect(element);
    return {'texts': texts};
  }

  // --- actions ---------------------------------------------------------

  Future<Map<String, Object?>> _action(Map<String, Object?> p, Future<void> Function(Finder) body) async {
    final spec = FinderSpec.fromJson(p['finder']);
    _single(spec);
    await body(spec.target);
    return {'settled': await _afterAction(p)};
  }

  Future<Map<String, Object?>> _tapAt(Map<String, Object?> p) async {
    await tester.tapAt(Offset(_num(p, 'x'), _num(p, 'y')));
    return {'settled': await _afterAction(p)};
  }

  Future<Map<String, Object?>> _enterText(Map<String, Object?> p) async {
    final spec = FinderSpec.fromJson(p['finder']);
    _single(spec);
    await tester.enterText(spec.target, p['text'] as String? ?? '');
    if (p['submit'] == true) {
      await tester.testTextInput.receiveAction(TextInputAction.done);
    }
    return {'settled': await _afterAction(p)};
  }

  Future<Map<String, Object?>> _scrollUntilVisible(Map<String, Object?> p) async {
    final spec = FinderSpec.fromJson(p['finder']);
    final scrollable = p['scrollable'] == null ? find.byType(Scrollable).first : FinderSpec.fromJson(p['scrollable']).target;
    final delta = Offset(_num(p, 'dx', 0), _num(p, 'dy', _num(p, 'delta', -200)));
    final maxScrolls = _int(p, 'maxScrolls') ?? 50;
    var scrolls = 0;
    while (spec.finder.evaluate().isEmpty) {
      if (scrolls++ >= maxScrolls) {
        throw StateError('${spec.description} not found after $maxScrolls scrolls');
      }
      if (scrollable.evaluate().isEmpty) throw StateError('No Scrollable to scroll');
      await tester.drag(scrollable, delta);
      await _settle(timeoutMs: 1500);
    }
    await Scrollable.ensureVisible(spec.target.evaluate().first);
    return {'scrolls': scrolls, 'settled': await _afterAction(p)};
  }

  Future<Map<String, Object?>> _sendKey(Map<String, Object?> p) async {
    const keys = {
      'enter': LogicalKeyboardKey.enter,
      'tab': LogicalKeyboardKey.tab,
      'escape': LogicalKeyboardKey.escape,
      'backspace': LogicalKeyboardKey.backspace,
      'space': LogicalKeyboardKey.space,
      'arrowUp': LogicalKeyboardKey.arrowUp,
      'arrowDown': LogicalKeyboardKey.arrowDown,
      'arrowLeft': LogicalKeyboardKey.arrowLeft,
      'arrowRight': LogicalKeyboardKey.arrowRight,
    };
    final name = p['key'] as String?;
    final key = keys[name];
    if (key == null) throw ArgumentError('Unknown key "$name". Supported: ${keys.keys.toList()}');
    await tester.sendKeyEvent(key);
    return {'settled': await _afterAction(p)};
  }

  // --- waiting / expectations -----------------------------------------

  Future<Map<String, Object?>> _waitFor(Map<String, Object?> p) async {
    final spec = FinderSpec.fromJson(p['finder']);
    final absent = p['absent'] == true;
    final timeout = Duration(milliseconds: _int(p, 'timeoutMs') ?? 10000);
    final sw = Stopwatch()..start();
    while (true) {
      final found = spec.finder.evaluate().isNotEmpty;
      if (found != absent) return {'elapsedMs': sw.elapsedMilliseconds};
      if (sw.elapsed > timeout) {
        throw TimeoutException(
          'Timed out after ${timeout.inMilliseconds}ms waiting for ${spec.description} to be ${absent ? 'absent' : 'present'}',
        );
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Map<String, Object?> _expect(Map<String, Object?> p) {
    final spec = FinderSpec.fromJson(p['finder']);
    final elements = spec.finder.evaluate().toList();
    final problems = <String>[];
    final count = _int(p, 'count');
    if (count != null && elements.length != count) {
      problems.add('expected $count match(es), found ${elements.length}');
    }
    if (p['exists'] != null && (elements.isNotEmpty != (p['exists'] == true))) {
      problems.add(p['exists'] == true ? 'expected to exist, found none' : 'expected absent, found ${elements.length}');
    }
    if (count == null && p['exists'] == null && p['text'] == null && elements.isEmpty) {
      problems.add('expected to exist, found none');
    }
    final text = p['text'] as String?;
    if (text != null) {
      if (elements.isEmpty) {
        problems.add('cannot check text: no match');
      } else {
        final texts = (_getText({'finder': p['finder']})['texts']! as List).cast<String>();
        if (!texts.contains(text)) problems.add('expected text "$text", found $texts');
      }
    }
    final ok = problems.isEmpty;
    final message = '${spec.description}: ${ok ? 'ok' : problems.join('; ')}';
    if (ok) {
      passedExpectations++;
    } else {
      failedExpectations.add(message);
    }
    return {'ok': ok, 'message': message};
  }

  Map<String, Object?> _results() => {
        'passed': passedExpectations,
        'failed': failedExpectations.length,
        'failures': failedExpectations,
        'appErrors': errors.all.map((e) => e.toJson()).toList(),
      };

  // --- restart ---------------------------------------------------------

  /// Soft restart: unmounts the whole tree (every State, route and controller is
  /// disposed) and runs the app's main again. Expectation counters are kept.
  Future<Map<String, Object?>> _restart() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpWidget(const SizedBox.shrink());
    await appMain();
    // runApp attaches the new root asynchronously, so pump until it settles.
    return {'restarted': true, 'kind': 'soft', ...await _settle(timeoutMs: 5000)};
  }

  // --- screenshot ------------------------------------------------------

  Future<Map<String, Object?>> _screenshot(Map<String, Object?> p) async {
    final maxWidth = _num(p, 'maxWidth', 800);
    final view = tester.view;
    final dpr = view.devicePixelRatio;
    final logical = view.physicalSize / dpr;
    final ratio = (maxWidth / logical.width).clamp(0.1, dpr);

    final renderView = tester.binding.renderViews.first;
    final layer = renderView.debugLayer;
    if (layer is! OffsetLayer) {
      throw StateError('Screenshots need a debug/profile build (render layer unavailable).');
    }
    // The root layer lives in physical pixels (the device pixel ratio is baked
    // into its transform), so capture the whole physical view and scale it to
    // `ratio` relative to the device pixel ratio. Capturing `Offset.zero &
    // logical` zooms the content by `dpr` and crops it.
    final bytes = await tester.runAsync(() async {
      final image = await layer.toImage(Offset.zero & view.physicalSize, pixelRatio: ratio / dpr);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    });
    return {
      'pngBase64': base64Encode(bytes!),
      'width': (logical.width * ratio).round(),
      'height': (logical.height * ratio).round(),
    };
  }

  // --- helpers ---------------------------------------------------------

  Element _single(FinderSpec spec) {
    final all = spec.finder.evaluate().toList();
    if (all.isEmpty) {
      throw StateError('No widget found for ${spec.description}. Use "snapshot" to see what is on screen.');
    }
    if (spec.index >= all.length) {
      throw StateError('index ${spec.index} out of range: only ${all.length} match(es) for ${spec.description}');
    }
    return all[spec.index];
  }

  /// Pumps after an action so the UI reflects it. Never throws on timeout:
  /// apps with endless animations simply don't "settle".
  Future<bool> _afterAction(Map<String, Object?> p) async {
    if (p['settle'] == false) {
      await tester.pump();
      return false;
    }
    return (await _settle(timeoutMs: _int(p, 'settleTimeoutMs') ?? 3000))['settled']! as bool;
  }

  /// Pumps in real time until no frame is scheduled and no animation ticker is
  /// running (two consecutive idle checks), or [timeoutMs] elapses.
  Future<Map<String, Object?>> _settle({int timeoutMs = 3000, bool strict = false}) async {
    final sw = Stopwatch()..start();
    var idle = 0;
    do {
      await tester.pump(const Duration(milliseconds: 50));
      final busy = tester.binding.hasScheduledFrame || tester.binding.transientCallbackCount > 0;
      idle = busy ? 0 : idle + 1;
      if (sw.elapsedMilliseconds > timeoutMs) {
        if (strict) throw TimeoutException('pumpAndSettle timed out after ${timeoutMs}ms (endless animation?)');
        return {'settled': false, 'note': 'still animating after ${timeoutMs}ms'};
      }
    } while (idle < 2);
    return {'settled': true};
  }

  Map<String, Object?> _describeElement(Element e) {
    final w = e.widget;
    final render = e.renderObject;
    String? text;
    if (w is Text) text = w.data ?? w.textSpan?.toPlainText();
    if (w is EditableText) text = _editableText(w);
    return {
      'type': w.runtimeType.toString(),
      if (w.key is ValueKey) 'key': '${(w.key! as ValueKey).value}',
      if (text != null) 'text': text,
      if (render is RenderBox && render.hasSize)
        'rect': [
          for (final v in [...[render.localToGlobal(Offset.zero).dx, render.localToGlobal(Offset.zero).dy], render.size.width, render.size.height])
            double.parse(v.toStringAsFixed(1)),
        ],
    };
  }

  /// Text of an input as reported to the client. Obscured fields (passwords)
  /// are masked, like `snapshot` does: their value must never leave the app.
  static String _editableText(EditableText w) =>
      w.obscureText ? '•' * w.controller.text.length : w.controller.text;

  static int? _int(Map<String, Object?> p, String k) => (p[k] as num?)?.toInt();

  static double _num(Map<String, Object?> p, String k, [double? fallback]) {
    final v = p[k];
    if (v is num) return v.toDouble();
    if (fallback != null) return fallback;
    throw ArgumentError('Missing numeric parameter "$k"');
  }
}
