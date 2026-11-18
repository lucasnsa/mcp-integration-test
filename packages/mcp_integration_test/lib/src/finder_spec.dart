import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a [Finder] from a JSON description.
///
/// Every given criterion must match the same widget (logical AND).
///
/// ```json
/// {"text": "Login"}
/// {"key": "submit"}
/// {"type": "TextField", "within": {"key": "form"}, "index": 1}
/// ```
class FinderSpec {
  FinderSpec._(this.finder, this.index, this.description);

  /// Matches every candidate; use [target] to pick one.
  final Finder finder;
  final int index;
  final String description;

  /// The single finder the action should operate on.
  Finder get target => finder.at(index);

  static const _known = {
    'text', 'textContaining', 'key', 'type', 'tooltip', 'semanticsLabel',
    'within', 'index', 'includeOffstage',
  };

  factory FinderSpec.fromJson(Object? json) {
    if (json is! Map) {
      throw ArgumentError('"finder" must be an object, e.g. {"text": "Login"}');
    }
    final unknown = json.keys.where((k) => !_known.contains(k)).toList();
    if (unknown.isNotEmpty) {
      throw ArgumentError('Unknown finder field(s) $unknown. Supported: ${_known.toList()}');
    }
    final index = (json['index'] as num?)?.toInt() ?? 0;
    final offstage = json['includeOffstage'] == true;

    final checks = <bool Function(Widget)>[];
    final desc = <String>[];
    void add(String d, bool Function(Widget) c) {
      desc.add(d);
      checks.add(c);
    }

    final text = json['text'];
    if (text != null) add('text == "$text"', (w) => _textOf(w) == text);
    final contains = json['textContaining'];
    if (contains != null) {
      add('text contains "$contains"', (w) => _textOf(w)?.contains('$contains') ?? false);
    }
    final key = json['key'];
    if (key != null) {
      add('key == "$key"', (w) {
        final k = w.key;
        return k is ValueKey && '${k.value}' == '$key';
      });
    }
    final type = json['type'];
    if (type != null) add('type == $type', (w) => w.runtimeType.toString() == type);
    final tooltip = json['tooltip'];
    if (tooltip != null) add('tooltip == "$tooltip"', (w) => w is Tooltip && w.message == tooltip);
    final label = json['semanticsLabel'];
    if (label != null) {
      add('semantics label == "$label"', (w) => w is Semantics && w.properties.label == label);
    }
    if (checks.isEmpty) {
      throw ArgumentError('Finder needs at least one of text, textContaining, key, type, tooltip, semanticsLabel');
    }

    Finder base = find.byElementPredicate(
      (e) => checks.every((c) => c(e.widget)),
      skipOffstage: !offstage,
    );
    var description = desc.join(' && ');
    final within = json['within'];
    if (within != null) {
      final parent = FinderSpec.fromJson(within);
      base = find.descendant(of: parent.target, matching: base, skipOffstage: !offstage);
      description = '$description within [${parent.description}]';
    }
    return FinderSpec._(base, index, '$description (index $index)');
  }

  static String? _textOf(Widget w) {
    if (w is Text) return w.data ?? w.textSpan?.toPlainText();
    if (w is EditableText) return w.controller.text;
    return null;
  }
}
