/// A tiny expression and statement language used for instruction semantics (`exec`) in processor specs, and for
/// operand expressions in the assembler.
///
/// It is deliberately small and side-effect free: no loops, no I/O, no imports, so a spec that is imported from a
/// stranger can never run arbitrary code. Everything is a Dart `int` (64 bit); the word size of the processor decides
/// how values are masked on write and how signed operations behave.
///
/// Grammar:
/// ```
/// program := stmt*
/// stmt    := 'if' '(' expr ')' block ('else' (block | ifstmt))?
///          | lvalue '=' expr ';'
///          | call ';'
/// lvalue  := NAME | NAME '[' expr ']'            // register/flag/local, or mem8/16/32/64[addr]
/// expr    := cond ? expr : expr | binary | unary | NUMBER | NAME | NAME '[' expr ']' | call | '(' expr ')'
/// ```
library;

class ExprError implements Exception {
  ExprError(this.message);
  final String message;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------------------------------------------
// AST

sealed class Expr {
  const Expr();
}

class NumExpr extends Expr {
  const NumExpr(this.value);
  final int value;
}

class StrExpr extends Expr {
  const StrExpr(this.value);
  final String value;
}

class NameExpr extends Expr {
  const NameExpr(this.name);
  final String name;
}

class IndexExpr extends Expr {
  const IndexExpr(this.base, this.index);
  final String base;
  final Expr index;
}

class UnaryExpr extends Expr {
  const UnaryExpr(this.op, this.operand);
  final String op;
  final Expr operand;
}

class BinaryExpr extends Expr {
  const BinaryExpr(this.op, this.left, this.right);
  final String op;
  final Expr left;
  final Expr right;
}

class CondExpr extends Expr {
  const CondExpr(this.cond, this.then, this.otherwise);
  final Expr cond;
  final Expr then;
  final Expr otherwise;
}

class CallExpr extends Expr {
  const CallExpr(this.fn, this.args);
  final String fn;
  final List<Expr> args;
}

sealed class Stmt {
  const Stmt();
}

class AssignStmt extends Stmt {
  const AssignStmt(this.target, this.value);

  /// A [NameExpr] or [IndexExpr].
  final Expr target;
  final Expr value;
}

class IfStmt extends Stmt {
  const IfStmt(this.cond, this.then, this.otherwise);
  final Expr cond;
  final List<Stmt> then;
  final List<Stmt> otherwise;
}

class CallStmt extends Stmt {
  const CallStmt(this.call);
  final CallExpr call;
}

// ---------------------------------------------------------------------------------------------------------------
// Lexer

enum _T { num, ident, str, punct, end }

class _Tok {
  const _Tok(this.type, this.text, this.pos, [this.num = 0]);
  final _T type;
  final String text;
  final int pos;
  final int num;
}

final _tokenRe = RegExp(
  r'''\s+|(0[xX][0-9a-fA-F_]+|0[bB][01_]+|\d[\d_]*)|([A-Za-z_.$][A-Za-z0-9_.$]*)|"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)')|(<<|>>|<=|>=|==|!=|&&|\|\||[-+*/%&|^~!<>=?:;,(){}\[\]])''',
);

List<_Tok> _lex(String src) {
  final out = <_Tok>[];
  var i = 0;
  while (i < src.length) {
    final m = _tokenRe.matchAsPrefix(src, i);
    if (m == null) {
      throw ExprError("Unexpected character '${src[i]}' at column ${i + 1}");
    }
    if (m.group(1) != null) {
      final t = m.group(1)!.replaceAll('_', '');
      // Hex and binary may use all 64 bits (0xffffffffffffffff is -1).
      final v = t.startsWith('0x') || t.startsWith('0X')
          ? BigInt.tryParse(t.substring(2), radix: 16)?.toSigned(64).toInt()
          : t.startsWith('0b') || t.startsWith('0B')
          ? BigInt.tryParse(t.substring(2), radix: 2)?.toSigned(64).toInt()
          : int.tryParse(t);
      if (v == null) {
        throw ExprError("Bad number '${m.group(1)}' at column ${i + 1}");
      }
      out.add(_Tok(_T.num, t, i, v));
    } else if (m.group(2) != null) {
      out.add(_Tok(_T.ident, m.group(2)!, i));
    } else if (m.group(3) != null) {
      out.add(_Tok(_T.str, _unescape(m.group(3)!), i));
    } else if (m.group(4) != null) {
      final s = _unescape(m.group(4)!.substring(0, m.group(4)!.length - 1));
      out.add(_Tok(_T.num, s, i, s.isEmpty ? 0 : s.codeUnitAt(0)));
    } else if (m.group(5) != null) {
      out.add(_Tok(_T.punct, m.group(5)!, i));
    }
    i = m.end;
  }
  out.add(_Tok(_T.end, '', src.length));
  return out;
}

String _unescape(String s) => s
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\t', '\t')
    .replaceAll(r'\r', '\r')
    .replaceAll(r'\0', '\u0000')
    .replaceAll(r'\"', '"')
    .replaceAll(r"\'", "'")
    .replaceAll(r'\\', '\\');

// ---------------------------------------------------------------------------------------------------------------
// Parser

/// Parses a single expression.
Expr parseExpression(String src) {
  final p = _Parser(_lex(src));
  final e = p.expr();
  p.expectEnd();
  return e;
}

/// Parses a statement list (the `exec` of an instruction).
List<Stmt> parseProgram(String src) {
  final p = _Parser(_lex(src));
  final out = <Stmt>[];
  while (!p.atEnd) {
    out.add(p.stmt());
  }
  return out;
}

class _Parser {
  _Parser(this.t);
  final List<_Tok> t;
  int i = 0;

  _Tok get cur => t[i];
  bool get atEnd => cur.type == _T.end;

  bool _is(String p) => cur.type == _T.punct && cur.text == p;

  bool _accept(String p) {
    if (_is(p)) {
      i++;
      return true;
    }
    return false;
  }

  void _expect(String p) {
    if (!_accept(p)) {
      throw ExprError(
        "Expected '$p' at column ${cur.pos + 1}${atEnd ? '' : " but found '${cur.text}'"}",
      );
    }
  }

  void expectEnd() {
    if (!atEnd) {
      throw ExprError("Unexpected '${cur.text}' at column ${cur.pos + 1}");
    }
  }

  List<Stmt> _block() {
    _expect('{');
    final out = <Stmt>[];
    while (!_is('}')) {
      if (atEnd) throw ExprError("Missing '}'");
      out.add(stmt());
    }
    _expect('}');
    return out;
  }

  Stmt stmt() {
    if (cur.type == _T.ident && cur.text == 'if') {
      i++;
      _expect('(');
      final c = expr();
      _expect(')');
      final then = _block();
      var otherwise = <Stmt>[];
      if (cur.type == _T.ident && cur.text == 'else') {
        i++;
        if (cur.type == _T.ident && cur.text == 'if') {
          otherwise = [stmt()];
        } else {
          otherwise = _block();
        }
      }
      return IfStmt(c, then, otherwise);
    }
    if (cur.type != _T.ident) {
      throw ExprError("Expected a statement at column ${cur.pos + 1}");
    }
    final name = cur.text;
    final start = i;
    i++;
    if (_is('(')) {
      i = start;
      final c = _primary();
      _expect(';');
      if (c is! CallExpr) {
        throw ExprError("Expected a call at column ${t[start].pos + 1}");
      }
      return CallStmt(c);
    }
    Expr target = NameExpr(name);
    if (_accept('[')) {
      final idx = expr();
      _expect(']');
      target = IndexExpr(name, idx);
    }
    _expect('=');
    final v = expr();
    _expect(';');
    return AssignStmt(target, v);
  }

  Expr expr() => _cond();

  Expr _cond() {
    final c = _bin(0);
    if (_accept('?')) {
      final a = _cond();
      _expect(':');
      final b = _cond();
      return CondExpr(c, a, b);
    }
    return c;
  }

  static const _levels = <List<String>>[
    ['||'],
    ['&&'],
    ['|'],
    ['^'],
    ['&'],
    ['==', '!='],
    ['<', '>', '<=', '>='],
    ['<<', '>>'],
    ['+', '-'],
    ['*', '/', '%'],
  ];

  Expr _bin(int level) {
    if (level >= _levels.length) return _unary();
    var left = _bin(level + 1);
    while (cur.type == _T.punct && _levels[level].contains(cur.text)) {
      final op = cur.text;
      i++;
      left = BinaryExpr(op, left, _bin(level + 1));
    }
    return left;
  }

  Expr _unary() {
    if (cur.type == _T.punct &&
        (cur.text == '-' ||
            cur.text == '~' ||
            cur.text == '!' ||
            cur.text == '+')) {
      final op = cur.text;
      i++;
      final e = _unary();
      return op == '+' ? e : UnaryExpr(op, e);
    }
    return _primary();
  }

  Expr _primary() {
    final c = cur;
    switch (c.type) {
      case _T.num:
        i++;
        return NumExpr(c.num);
      case _T.str:
        i++;
        return StrExpr(c.text);
      case _T.ident:
        i++;
        if (_accept('(')) {
          final args = <Expr>[];
          if (!_is(')')) {
            do {
              args.add(expr());
            } while (_accept(','));
          }
          _expect(')');
          return CallExpr(c.text, args);
        }
        if (_accept('[')) {
          final idx = expr();
          _expect(']');
          return IndexExpr(c.text, idx);
        }
        return NameExpr(c.text);
      case _T.punct:
        if (c.text == '(') {
          i++;
          final e = expr();
          _expect(')');
          return e;
        }
      case _T.end:
        break;
    }
    throw ExprError(
      atEnd
          ? 'Unexpected end of expression'
          : "Unexpected '${c.text}' at column ${c.pos + 1}",
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Static helpers

/// Every name read by [e] (not function names).
void collectReads(Expr e, Set<String> out) {
  switch (e) {
    case NumExpr() || StrExpr():
      break;
    case NameExpr(:final name):
      out.add(name);
    case IndexExpr(:final index):
      collectReads(index, out);
    case UnaryExpr(:final operand):
      collectReads(operand, out);
    case BinaryExpr(:final left, :final right):
      collectReads(left, out);
      collectReads(right, out);
    case CondExpr(:final cond, :final then, :final otherwise):
      collectReads(cond, out);
      collectReads(then, out);
      collectReads(otherwise, out);
    case CallExpr(:final args):
      for (final a in args) {
        collectReads(a, out);
      }
  }
}

/// Names a statement list reads and the names it assigns, in program order.
({List<String> reads, List<String> writes}) analyze(List<Stmt> prog) {
  final reads = <String>[];
  final writes = <String>[];
  void expr(Expr e) {
    final s = <String>{};
    collectReads(e, s);
    reads.addAll(s);
  }

  void walk(List<Stmt> l) {
    for (final s in l) {
      switch (s) {
        case AssignStmt(:final target, :final value):
          expr(value);
          if (target is NameExpr) {
            writes.add(target.name);
          } else if (target is IndexExpr) {
            expr(target.index);
            writes.add(target.base);
          }
        case IfStmt(:final cond, :final then, :final otherwise):
          expr(cond);
          walk(then);
          walk(otherwise);
        case CallStmt(:final call):
          expr(call);
      }
    }
  }

  walk(prog);
  return (reads: reads, writes: writes);
}

/// Memory access names: `mem8`, `mem16`, `mem32`, `mem64` → access size in bytes.
int? memSize(String name) => switch (name) {
  'mem8' => 1,
  'mem16' => 2,
  'mem32' => 4,
  'mem64' => 8,
  _ => null,
};

// ---------------------------------------------------------------------------------------------------------------
// Interpreter

/// What the interpreter needs from the machine (or from the assembler's symbol table).
abstract interface class ExprEnv {
  int read(String name);
  void write(String name, int value);
  int load(int size, int addr);
  void store(int size, int addr, int value);

  /// Statement calls such as `halt()`, `trap("msg")`, `out("int", x)`. Arguments are `int` or `String`.
  void call(String fn, List<Object> args);
}

class Interp {
  Interp(this.env, this.bits)
    : mask = bits >= 64 ? -1 : (1 << bits) - 1,
      _signBit = bits >= 64 ? 1 << 63 : 1 << (bits - 1);

  final ExprEnv env;
  final int bits;
  final int mask;
  final int _signBit;

  int _sx(int v) {
    if (bits >= 64) return v;
    v &= mask;
    return (v & _signBit) != 0 ? v - (1 << bits) : v;
  }

  int _ux(int v) => v & mask;

  static bool _ltuRaw(int a, int b) => (a ^ (1 << 63)) < (b ^ (1 << 63));

  void exec(List<Stmt> prog) {
    for (final s in prog) {
      switch (s) {
        case AssignStmt(:final target, :final value):
          final v = eval(value);
          if (target is NameExpr) {
            env.write(target.name, v);
          } else if (target is IndexExpr) {
            final size = memSize(target.base);
            if (size == null) {
              throw ExprError(
                "'${target.base}[...]' cannot be assigned (use mem8/16/32/64)",
              );
            }
            env.store(size, _ux(eval(target.index)), v);
          }
        case IfStmt(:final cond, :final then, :final otherwise):
          exec(eval(cond) != 0 ? then : otherwise);
        case CallStmt(:final call):
          env.call(call.fn, [
            for (final a in call.args) a is StrExpr ? a.value : eval(a),
          ]);
      }
    }
  }

  int eval(Expr e) {
    switch (e) {
      case NumExpr(:final value):
        return value;
      case StrExpr():
        throw ExprError('A string cannot be used as a number');
      case NameExpr(:final name):
        return env.read(name);
      case IndexExpr(:final base, :final index):
        final size = memSize(base);
        if (size == null) {
          throw ExprError(
            "Unknown memory access '$base[...]' (use mem8/16/32/64)",
          );
        }
        return env.load(size, _ux(eval(index)));
      case UnaryExpr(:final op, :final operand):
        final v = eval(operand);
        return switch (op) {
          '-' => -v,
          '~' => ~v,
          _ => _ux(v) == 0 ? 1 : 0,
        };
      case CondExpr(:final cond, :final then, :final otherwise):
        return eval(cond) != 0 ? eval(then) : eval(otherwise);
      case BinaryExpr(:final op, :final left, :final right):
        if (op == '&&') return eval(left) != 0 && eval(right) != 0 ? 1 : 0;
        if (op == '||') return eval(left) != 0 || eval(right) != 0 ? 1 : 0;
        return _binary(op, eval(left), eval(right));
      case CallExpr(:final fn, :final args):
        return _function(fn, [for (final a in args) eval(a)]);
    }
  }

  int _binary(String op, int a, int b) {
    switch (op) {
      case '+':
        return a + b;
      case '-':
        return a - b;
      case '*':
        return a * b;
      case '/':
        if (_ux(b) == 0) throw ExprError('Division by zero');
        return _sx(a) ~/ _sx(b);
      case '%':
        if (_ux(b) == 0) throw ExprError('Division by zero');
        return _sx(a).remainder(_sx(b));
      case '&':
        return a & b;
      case '|':
        return a | b;
      case '^':
        return a ^ b;
      case '<<':
        _checkShift(b);
        return a << b;
      case '>>':
        _checkShift(b);
        return bits >= 64 ? a >>> b : _ux(a) >>> b;
      case '==':
        return _ux(a) == _ux(b) ? 1 : 0;
      case '!=':
        return _ux(a) != _ux(b) ? 1 : 0;
      case '<':
        return _sx(a) < _sx(b) ? 1 : 0;
      case '>':
        return _sx(a) > _sx(b) ? 1 : 0;
      case '<=':
        return _sx(a) <= _sx(b) ? 1 : 0;
      case '>=':
        return _sx(a) >= _sx(b) ? 1 : 0;
    }
    throw ExprError("Unknown operator '$op'");
  }

  void _checkShift(int n) {
    if (n < 0) throw ExprError('Negative shift amount');
  }

  int _arity(String fn, List<int> a, int n) {
    if (a.length != n) {
      throw ExprError("$fn() takes $n argument${n == 1 ? '' : 's'}");
    }
    return n;
  }

  int _function(String fn, List<int> a) {
    switch (fn) {
      case 'sext':
        _arity(fn, a, 2);
        return _sextBits(a[0], a[1]);
      case 'zext':
        _arity(fn, a, 2);
        return a[1] >= 64 ? a[0] : a[0] & ((1 << a[1]) - 1);
      case 'sra':
        _arity(fn, a, 2);
        _checkShift(a[1]);
        return _sx(a[0]) >> a[1];
      case 'ltu':
        _arity(fn, a, 2);
        return _ltuRaw(_ux(a[0]), _ux(a[1])) ? 1 : 0;
      case 'geu':
        _arity(fn, a, 2);
        return _ltuRaw(_ux(a[0]), _ux(a[1])) ? 0 : 1;
      case 'gtu':
        _arity(fn, a, 2);
        return _ltuRaw(_ux(a[1]), _ux(a[0])) ? 1 : 0;
      case 'leu':
        _arity(fn, a, 2);
        return _ltuRaw(_ux(a[1]), _ux(a[0])) ? 0 : 1;
      case 'divu':
        _arity(fn, a, 2);
        if (_ux(a[1]) == 0) throw ExprError('Division by zero');
        return (BigInt.from(_ux(a[0])).toUnsigned(64) ~/
                BigInt.from(_ux(a[1])).toUnsigned(64))
            .toInt();
      case 'remu':
        _arity(fn, a, 2);
        if (_ux(a[1]) == 0) throw ExprError('Division by zero');
        return (BigInt.from(_ux(a[0]))
                .toUnsigned(64)
                .remainder(BigInt.from(_ux(a[1])).toUnsigned(64)))
            .toInt();
      case 'mulh':
        _arity(fn, a, 2);
        return ((BigInt.from(_sx(a[0])) * BigInt.from(_sx(a[1]))) >> bits)
            .toInt();
      case 'mulhu':
        _arity(fn, a, 2);
        return ((BigInt.from(_ux(a[0])).toUnsigned(64) *
                    BigInt.from(_ux(a[1])).toUnsigned(64)) >>
                bits)
            .toInt();
      case 'rol':
        _arity(fn, a, 2);
        final n = a[1] % bits;
        return _ux((_ux(a[0]) << n) | (_ux(a[0]) >>> (bits - n)));
      case 'ror':
        _arity(fn, a, 2);
        final n = a[1] % bits;
        return _ux((_ux(a[0]) >>> n) | (_ux(a[0]) << (bits - n)));
      case 'bit':
        _arity(fn, a, 2);
        return (a[0] >>> a[1]) & 1;
      case 'bits':
        _arity(fn, a, 3);
        final w = a[1] - a[2] + 1;
        return (a[0] >>> a[2]) & (w >= 64 ? -1 : (1 << w) - 1);
      case 'abs':
        _arity(fn, a, 1);
        return _sx(a[0]).abs();
      case 'min':
        _arity(fn, a, 2);
        return _sx(a[0]) < _sx(a[1]) ? a[0] : a[1];
      case 'max':
        _arity(fn, a, 2);
        return _sx(a[0]) > _sx(a[1]) ? a[0] : a[1];
      // Assembler helpers for upper/lower immediates (the lui/addi split).
      case 'lo8':
        _arity(fn, a, 1);
        return a[0] & 255;
      case 'hi8':
        _arity(fn, a, 1);
        return (a[0] >> 8) & 255;
      case 'hi':
        _arity(fn, a, 1);
        return ((a[0] + 0x800) >> 12) & 0xFFFFF;
      case 'lo':
        _arity(fn, a, 1);
        return _sextBits(a[0] & 0xFFF, 12);
    }
    throw ExprError("Unknown function '$fn()'");
  }

  static int _sextBits(int v, int n) {
    if (n >= 64) return v;
    v &= (1 << n) - 1;
    return (v & (1 << (n - 1))) != 0 ? v - (1 << n) : v;
  }
}

/// Function names usable in expressions (for validation).
const exprFunctions = {
  'sext',
  'zext',
  'sra',
  'ltu',
  'geu',
  'gtu',
  'leu',
  'divu',
  'remu',
  'mulh',
  'mulhu',
  'rol',
  'ror',
  'bit',
  'bits',
  'abs', 'min', 'max', 'hi', 'lo', 'lo8', 'hi8', //
};

/// Statement-only calls (for validation).
const stmtFunctions = {'halt', 'trap', 'out'};
