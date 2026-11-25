/// A small, line-oriented block language shared by processor files (`*.cpu`) and project files (`project.dotasm`).
///
/// ```
/// # comment                      (also // comment)
/// keyword arg "quoted arg" 0x10  # one statement per line
/// block name {                   # a statement that ends with { opens a block
///   child 1
/// }
/// text """                       # a multi-line string (common indentation is removed)
///   any text
/// """
/// ```
///
/// A few block keywords are *raw*: their body is kept as text instead of being parsed as statements (the
/// instruction semantics in `exec { ... }`, the expansion lines of a pseudo-instruction).
library;

class DslError implements Exception {
  DslError(this.line, this.message, {this.column = 0});

  /// 1-based line, 0 when unknown.
  final int line;
  final int column;
  final String message;

  @override
  String toString() => line > 0 ? 'line $line: $message' : message;
}

/// One argument of a statement.
class DslArg {
  const DslArg(this.text, {this.quoted = false});
  final String text;
  final bool quoted;

  @override
  String toString() => text;
}

/// `keyword args... [{ children }]`
class DslNode {
  DslNode(this.keyword, this.args, this.line);
  final String keyword;
  final List<DslArg> args;
  final int line;
  final List<DslNode> children = [];

  /// Body of a raw block (null for ordinary statements).
  String? raw;
  bool hasBlock = false;

  List<String> get argTexts => [for (final a in args) a.text];

  String? arg(int i) => i < args.length ? args[i].text : null;

  DslNode? child(String keyword) {
    for (final c in children) {
      if (c.keyword == keyword) return c;
    }
    return null;
  }

  Iterable<DslNode> childrenOf(String keyword) =>
      children.where((c) => c.keyword == keyword);
}

enum RawMode {
  /// Ends at the brace that balances the opening one (instruction semantics).
  braces,

  /// Ends at the first line that is only `}` (lists of assembly lines).
  lines,
}

class DslParser {
  DslParser(this.source, {this.rawBlocks = const {}});

  final String source;

  /// Keyword → how its block body is read.
  final Map<String, RawMode> rawBlocks;

  late final List<String> _lines = source.split(RegExp(r'\r?\n'));
  int _i = 0;

  List<DslNode> parse() {
    final out = <DslNode>[];
    while (_i < _lines.length) {
      final n = _statement();
      if (n == null) continue;
      if (n.keyword == '}') {
        throw DslError(n.line, "Unexpected '}' with no block to close");
      }
      out.add(n);
      if (n.hasBlock && n.raw == null) _children(n);
    }
    return out;
  }

  void _children(DslNode parent) {
    while (true) {
      if (_i >= _lines.length) {
        throw DslError(
          parent.line,
          "The block '${parent.keyword}' is never closed (missing '}')",
        );
      }
      final n = _statement();
      if (n == null) continue;
      if (n.keyword == '}') return;
      parent.children.add(n);
      if (n.hasBlock && n.raw == null) _children(n);
    }
  }

  /// Reads the next non-empty statement; returns null for blank/comment lines.
  DslNode? _statement() {
    final lineNo = _i + 1;
    final tokens = _tokenize(lineNo);
    if (tokens == null) return null;
    var opens = false;
    if (tokens.isNotEmpty && tokens.last.text == '{' && !tokens.last.quoted) {
      opens = true;
      tokens.removeLast();
    }
    if (tokens.isEmpty) {
      if (opens) {
        throw DslError(lineNo, "'{' must follow a statement on the same line");
      }
      return null;
    }
    // A lone "}" closes a block; "} something" is not allowed.
    if (tokens.first.text == '}' && !tokens.first.quoted) {
      if (tokens.length > 1) {
        throw DslError(lineNo, "Nothing may follow '}' on the same line");
      }
      return DslNode('}', const [], lineNo);
    }
    final node = DslNode(tokens.first.text, tokens.sublist(1), lineNo);
    node.hasBlock = opens;
    if (opens) {
      final mode = rawBlocks[node.keyword];
      if (mode != null) node.raw = _rawBody(node, mode);
    }
    return node;
  }

  String _rawBody(DslNode node, RawMode mode) {
    final body = <String>[];
    var depth = 1;
    while (_i < _lines.length) {
      final line = _lines[_i];
      _i++;
      if (mode == RawMode.lines) {
        if (line.trim() == '}') return _dedent(body);
        body.add(line);
        continue;
      }
      // Count braces outside strings.
      var cut = -1;
      var inStr = false;
      for (var k = 0; k < line.length; k++) {
        final c = line[k];
        if (inStr) {
          if (c == r'\') {
            k++;
          } else if (c == '"') {
            inStr = false;
          }
          continue;
        }
        if (c == '"') {
          inStr = true;
        } else if (c == '{') {
          depth++;
        } else if (c == '}') {
          depth--;
          if (depth == 0) {
            cut = k;
            break;
          }
        }
      }
      if (cut >= 0) {
        final before = line.substring(0, cut);
        if (before.trim().isNotEmpty) body.add(before);
        return _dedent(body);
      }
      body.add(line);
    }
    throw DslError(
      node.line,
      "The block '${node.keyword}' is never closed (missing '}')",
    );
  }

  static String _dedent(List<String> lines) {
    // Drop leading/trailing blank lines, remove the common indentation.
    var a = 0;
    var b = lines.length;
    while (a < b && lines[a].trim().isEmpty) {
      a++;
    }
    while (b > a && lines[b - 1].trim().isEmpty) {
      b--;
    }
    final body = lines.sublist(a, b);
    var common = -1;
    for (final l in body) {
      if (l.trim().isEmpty) continue;
      final ind = l.length - l.trimLeft().length;
      if (common < 0 || ind < common) common = ind;
    }
    if (common <= 0) return body.join('\n');
    return body
        .map((l) => l.length >= common ? l.substring(common) : l.trimLeft())
        .join('\n');
  }

  /// Splits the current line into tokens and advances. Returns null for an empty line.
  List<DslArg>? _tokenize(int lineNo) {
    var line = _lines[_i];
    _i++;
    final out = <DslArg>[];
    var p = 0;
    while (true) {
      while (p < line.length && (line[p] == ' ' || line[p] == '\t')) {
        p++;
      }
      if (p >= line.length) break;
      final c = line[p];
      if (c == '#' || (c == '/' && p + 1 < line.length && line[p + 1] == '/')) {
        break;
      }
      if (c == '"') {
        if (line.startsWith('"""', p)) {
          // Multi-line string: runs to the next """ (possibly on a later line).
          final start = p + 3;
          final buf = <String>[];
          var rest = line.substring(start);
          while (true) {
            final end = rest.indexOf('"""');
            if (end >= 0) {
              buf.add(rest.substring(0, end));
              line = rest.substring(end + 3);
              p = 0;
              break;
            }
            buf.add(rest);
            if (_i >= _lines.length) {
              throw DslError(lineNo, 'A """ string is never closed');
            }
            rest = _lines[_i];
            _i++;
          }
          // Drop the line break right after the opening """.
          if (buf.isNotEmpty && buf.first.trim().isEmpty) buf.removeAt(0);
          if (buf.isNotEmpty && buf.last.trim().isEmpty) buf.removeLast();
          out.add(DslArg(_dedent(buf), quoted: true));
          continue;
        }
        final sb = StringBuffer();
        p++;
        var closed = false;
        while (p < line.length) {
          final d = line[p];
          if (d == r'\' && p + 1 < line.length) {
            final e = line[p + 1];
            sb.write(switch (e) {
              'n' => '\n',
              't' => '\t',
              _ => e,
            });
            p += 2;
          } else if (d == '"') {
            closed = true;
            p++;
            break;
          } else {
            sb.write(d);
            p++;
          }
        }
        if (!closed) {
          throw DslError(
            lineNo,
            'A "string" is not closed on this line',
            column: p,
          );
        }
        out.add(DslArg(sb.toString(), quoted: true));
        continue;
      }
      final start = p;
      while (p < line.length && line[p] != ' ' && line[p] != '\t') {
        // A comment may directly follow a token.
        if (line[p] == '#') break;
        if (line[p] == '/' && p + 1 < line.length && line[p + 1] == '/') break;
        p++;
      }
      out.add(DslArg(line.substring(start, p)));
    }
    return out.isEmpty ? null : out;
  }
}

/// Quotes [s] for writing, using a multi-line string when it contains line breaks.
String dslQuote(String s, {String indent = ''}) {
  if (s.contains('\n') && !s.contains('"""')) {
    final body = s
        .split('\n')
        .map((l) => l.isEmpty ? '' : '$indent  $l')
        .join('\n');
    return '"""\n$body\n$indent"""';
  }
  final esc = s
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\t', r'\t');
  return '"$esc"';
}

/// A bare word when [s] is a plain token, otherwise quoted.
String dslWord(String s) {
  if (s.isNotEmpty && !RegExp(r'[\s"#{}]|//').hasMatch(s)) return s;
  return dslQuote(s);
}
