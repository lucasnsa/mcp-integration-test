import 'package:flutter/material.dart';

/// Flat, paint-ordered list of the visible, meaningful widgets on screen.
///
/// This is what an LLM "sees": for each node, its type, key, text, bounds and
/// whether it can be tapped.
List<Map<String, Object?>> buildSnapshot(Element root, {int maxNodes = 300}) {
  final nodes = <Map<String, Object?>>[];

  void visit(Element element, int depth) {
    if (nodes.length >= maxNodes) return;
    final widget = element.widget;
    if (widget is Offstage && widget.offstage) return;
    if (widget is Visibility && !widget.visible && !widget.maintainState) return;

    final node = _describe(element, widget);
    if (node != null) nodes.add(node);

    // Text builds a RichText below it; don't report the same text twice.
    if (widget is Text) return;
    element.visitChildren((c) => visit(c, depth + 1));
  }

  visit(root, 0);
  return nodes;
}

Map<String, Object?>? _describe(Element element, Widget widget) {
  String? text;
  var type = widget.runtimeType.toString();
  var tappable = false;
  bool? enabled;
  Object? value;

  if (widget is Text) {
    text = widget.data ?? widget.textSpan?.toPlainText();
    tappable = _insideTappable(element);
  } else if (widget is EditableText) {
    type = 'EditableText';
    text = widget.obscureText ? '•' * widget.controller.text.length : widget.controller.text;
    tappable = true;
  } else if (widget is ButtonStyleButton) {
    tappable = true;
    enabled = widget.enabled;
  } else if (widget is IconButton) {
    tappable = true;
    enabled = widget.onPressed != null;
  } else if (widget is FloatingActionButton) {
    tappable = true;
    enabled = widget.onPressed != null;
  } else if (widget is Checkbox) {
    tappable = true;
    value = widget.value;
    enabled = widget.onChanged != null;
  } else if (widget is Switch) {
    tappable = true;
    value = widget.value;
    enabled = widget.onChanged != null;
  } else if (widget is Slider) {
    value = widget.value;
    enabled = widget.onChanged != null;
  } else if (widget is ListTile) {
    tappable = widget.onTap != null;
  } else if (widget is Icon) {
    text = widget.semanticLabel;
    value = widget.icon?.codePoint;
  } else if (widget is Image) {
    text = widget.semanticLabel;
  } else if (widget is Tooltip) {
    text = widget.message;
  } else {
    return null;
  }

  final key = widget.key;
  final render = element.renderObject;
  List<double>? rect;
  if (render is RenderBox && render.attached && render.hasSize) {
    final o = render.localToGlobal(Offset.zero);
    rect = [o.dx, o.dy, render.size.width, render.size.height]
        .map((v) => double.parse(v.toStringAsFixed(1)))
        .toList();
  }
  return {
    'type': type,
    if (key is ValueKey) 'key': '${key.value}',
    if (text != null) 'text': text,
    if (value != null) 'value': value,
    if (enabled != null) 'enabled': enabled,
    if (tappable) 'tappable': true,
    if (rect != null) 'rect': rect, // [left, top, width, height] in logical px
  };
}

bool _insideTappable(Element element) {
  var found = false;
  var steps = 0;
  element.visitAncestorElements((a) {
    final w = a.widget;
    if (w is ButtonStyleButton ||
        w is IconButton ||
        (w is InkResponse && w.onTap != null) ||
        (w is GestureDetector && w.onTap != null) ||
        (w is ListTile && w.onTap != null)) {
      found = true;
      return false;
    }
    return ++steps < 10;
  });
  return found;
}
