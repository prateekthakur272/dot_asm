import 'dart:convert' as convert;

final class Json {
  const Json._();

  static dynamic parse(String? source) {
    if (source == null || source.trim().isEmpty) return null;
    try {
      return convert.jsonDecode(source);
    } catch (_) {
      return null;
    }
  }

  static String encode(dynamic value, {bool pretty = false}) {
    if (pretty) {
      return const convert.JsonEncoder.withIndent('  ').convert(value);
    }
    return convert.jsonEncode(value);
  }

  static Map<String, dynamic>? obj(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), val));
    }
    return null;
  }

  static List<dynamic>? list(dynamic v) => v is List ? v : null;
}
