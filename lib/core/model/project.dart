import 'package:dot_asm/core/dsl/dsl.dart';

/// Which processor a project uses: a `.cpu` file inside the project folder.
///
/// [ProcessorRef.builtin] only exists for project files written by earlier versions (`processor builtin <id>`); the app
/// copies that template into the project's `cpu/` folder when it opens such a project.
class ProcessorRef {
  const ProcessorRef.builtin(this.value) : builtin = true;
  const ProcessorRef.file(this.value) : builtin = false;

  /// True for a legacy template id, false for a path relative to the project folder.
  final bool builtin;
  final String value;

  @override
  bool operator ==(Object other) =>
      other is ProcessorRef && other.builtin == builtin && other.value == value;

  @override
  int get hashCode => Object.hash(builtin, value);

  @override
  String toString() => builtin ? 'builtin $value' : 'file $value';
}

/// Everything stored in a project's `project.dotasm`.
class ProjectConfig {
  const ProjectConfig({
    required this.name,
    required this.processor,
    this.source = 'main.s',
    required this.created,
    required this.updated,
    this.speed = 'fast',
    this.breakpoints = const [],
    this.panel = 'overview',
  });

  final String name;
  final ProcessorRef processor;

  /// The assembly file, relative to the project folder.
  final String source;
  final DateTime created;
  final DateTime updated;

  /// `slow`, `medium` or `fast`.
  final String speed;

  /// 1-based source lines with a breakpoint.
  final List<int> breakpoints;

  /// The tab shown in the processor panel.
  final String panel;

  ProjectConfig copyWith({
    String? name,
    ProcessorRef? processor,
    String? source,
    DateTime? updated,
    String? speed,
    List<int>? breakpoints,
    String? panel,
  }) => ProjectConfig(
    name: name ?? this.name,
    processor: processor ?? this.processor,
    source: source ?? this.source,
    created: created,
    updated: updated ?? this.updated,
    speed: speed ?? this.speed,
    breakpoints: breakpoints ?? this.breakpoints,
    panel: panel ?? this.panel,
  );
}

/// A project on disk: a folder holding `project.dotasm`, the source file and a `cpu/` folder with its own processors.
class Project {
  const Project({required this.path, required this.config});

  /// Absolute path of the project folder. It identifies the project.
  final String path;
  final ProjectConfig config;

  String get id => path;
  String get name => config.name;
  ProcessorRef get processor => config.processor;
  DateTime get updatedAt => config.updated;

  Project withConfig(ProjectConfig c) => Project(path: path, config: c);
}

/// The text format of `project.dotasm`:
///
/// ```
/// project "Demo" {
///   processor builtin arm32          # or: processor file "cpu/my-cpu.cpu"
///   source "main.s"
///   created "2026-11-25T12:00:00.000"
///   updated "2026-11-25T12:30:00.000"
///   speed fast
///   breakpoints 12 20
///   panel registers
/// }
/// ```
class ProjectDsl {
  const ProjectDsl._();

  static const fileName = 'project.dotasm';

  static ProjectConfig parse(String text) {
    final nodes = DslParser(text).parse();
    final projects = nodes.where((n) => n.keyword == 'project').toList();
    if (projects.isEmpty) {
      throw DslError(1, "Expected a 'project \"name\" { ... }' block");
    }
    if (projects.length > 1) {
      throw DslError(projects[1].line, 'A file describes one project');
    }
    for (final n in nodes) {
      if (n.keyword != 'project') {
        throw DslError(
          n.line,
          "Unexpected '${n.keyword}' outside the project block",
        );
      }
    }
    final p = projects.single;
    if (!p.hasBlock) {
      throw DslError(
        p.line,
        'The project needs a block: project "name" { ... }',
      );
    }

    var name = p.arg(0) ?? 'Untitled';
    ProcessorRef? processor;
    var source = 'main.s';
    DateTime? created;
    DateTime? updated;
    var speed = 'fast';
    final breakpoints = <int>[];
    var panel = 'overview';

    String need(DslNode n, int i, String what) {
      final v = n.arg(i);
      if (v == null) throw DslError(n.line, "'${n.keyword}' needs $what");
      return v;
    }

    for (final n in p.children) {
      switch (n.keyword) {
        case 'name':
          name = need(n, 0, 'a name');
        case 'processor':
          // `processor "cpu/x.cpu"`. Older files wrote `processor file "..."` or `processor builtin <id>`.
          final first = need(
            n,
            0,
            'the path of the processor file, for example "cpu/my-cpu.cpu"',
          );
          if (n.args.length == 1) {
            processor = ProcessorRef.file(first);
          } else {
            final value = need(n, 1, 'a path');
            processor = switch (first) {
              'builtin' => ProcessorRef.builtin(value),
              'file' => ProcessorRef.file(value),
              _ => throw DslError(
                n.line,
                "Write the processor as: processor \"cpu/my-cpu.cpu\"",
              ),
            };
          }
        case 'source':
          source = need(n, 0, 'a file name');
        case 'created':
          created = DateTime.tryParse(need(n, 0, 'a date'));
          if (created == null) {
            throw DslError(n.line, "'created' is not a valid date");
          }
        case 'updated':
          updated = DateTime.tryParse(need(n, 0, 'a date'));
          if (updated == null) {
            throw DslError(n.line, "'updated' is not a valid date");
          }
        case 'speed':
          speed = need(n, 0, 'slow, medium or fast');
          if (!const ['slow', 'medium', 'fast'].contains(speed)) {
            throw DslError(n.line, "Speed must be slow, medium or fast");
          }
        case 'breakpoints':
          for (final a in n.argTexts) {
            final v = int.tryParse(a.replaceAll(',', ''));
            if (v == null || v < 1) {
              throw DslError(
                n.line,
                "A breakpoint is a line number, found '$a'",
              );
            }
            breakpoints.add(v);
          }
        case 'panel':
          panel = need(n, 0, 'a tab name');
        default:
          throw DslError(
            n.line,
            "Unknown statement '${n.keyword}' in the project (processor, source, created, updated, speed, breakpoints, panel)",
          );
      }
    }
    if (processor == null) {
      throw DslError(
        p.line,
        "The project needs a 'processor builtin <id>' or 'processor file \"<path>\"' line",
      );
    }
    final now = DateTime.now();
    return ProjectConfig(
      name: name,
      processor: processor,
      source: source,
      created: created ?? now,
      updated: updated ?? created ?? now,
      speed: speed,
      breakpoints: breakpoints,
      panel: panel,
    );
  }

  static String write(ProjectConfig c) {
    final b = StringBuffer()
      ..writeln(
        '# dot ASM project. This file is read when the project is opened.',
      )
      ..writeln('project ${dslQuote(c.name)} {')
      ..writeln(
        c.processor.builtin
            ? '  processor builtin ${dslWord(c.processor.value)}'
            : '  processor ${dslQuote(c.processor.value)}',
      )
      ..writeln('  source ${dslQuote(c.source)}')
      ..writeln('  created ${dslQuote(c.created.toIso8601String())}')
      ..writeln('  updated ${dslQuote(c.updated.toIso8601String())}')
      ..writeln('  speed ${c.speed}');
    if (c.breakpoints.isNotEmpty) {
      b.writeln('  breakpoints ${(c.breakpoints.toList()..sort()).join(' ')}');
    }
    b
      ..writeln('  panel ${c.panel}')
      ..writeln('}');
    return b.toString();
  }
}
