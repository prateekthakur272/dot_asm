import 'package:flutter/foundation.dart';
import 'package:dot_asm/core/sim/spec/processor_spec.dart';

/// A processor being edited in the builder.
///
/// The draft is the processor's JSON itself (the same format that is imported and exported), so every field of the
/// spec is editable and nothing is lost. After each change the JSON is parsed and validated; [problems] is what is
/// still wrong and [spec] is the parsed processor when the structure is sound.
class ProcessorDraft extends ChangeNotifier {
  ProcessorDraft(Map<String, dynamic> json, {this.originalId})
    : json = _deepCopy(json) {
    _evaluate();
  }

  Map<String, dynamic> json;

  /// The id the processor was saved under (null for a brand new one).
  String? originalId;
  bool dirty = false;

  /// Bumped when the JSON is replaced as a whole, so form fields re-read their values.
  int revision = 0;

  ProcessorSpec? _spec;
  List<String> _problems = const [];

  ProcessorSpec? get spec => _spec;
  List<String> get problems => _problems;
  bool get isValid => _problems.isEmpty && _spec != null;

  String get id => '${json['id'] ?? ''}';
  String get name => '${json['name'] ?? ''}';

  static Map<String, dynamic> _deepCopy(Map<String, dynamic> m) => {
    for (final e in m.entries) e.key: _copyValue(e.value),
  };

  static Object? _copyValue(Object? v) {
    if (v is Map) {
      return {for (final e in v.entries) '${e.key}': _copyValue(e.value)};
    }
    if (v is List) return [for (final x in v) _copyValue(x)];
    return v;
  }

  void _evaluate() {
    try {
      final s = ProcessorSpec.fromJson(json);
      _spec = s;
      _problems = s.validate();
    } on SpecFormatError catch (e) {
      _spec = null;
      _problems = e.errors;
    } catch (e) {
      _spec = null;
      _problems = ['$e'];
    }
  }

  /// Applies an edit to the JSON and re-validates.
  void edit(void Function(Map<String, dynamic> json) change) {
    change(json);
    dirty = true;
    _evaluate();
    notifyListeners();
  }

  void set(String key, Object? value) => edit((j) {
    if (value == null ||
        (value is String && value.isEmpty && key != 'name' && key != 'id')) {
      j.remove(key);
    } else {
      j[key] = value;
    }
  });

  /// Replaces the whole JSON (e.g. after editing the raw text).
  void replace(Map<String, dynamic> newJson) {
    json = _deepCopy(newJson);
    revision++;
    dirty = true;
    _evaluate();
    notifyListeners();
  }

  List<Map<String, dynamic>> listOf(String key) {
    final v = json[key];
    if (v is List) return v.whereType<Map<String, dynamic>>().toList();
    return [];
  }

  /// Marks the draft as saved under [id].
  void markSaved(String id) {
    originalId = id;
    dirty = false;
    notifyListeners();
  }
}
