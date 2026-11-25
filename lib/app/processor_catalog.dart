import 'package:flutter/services.dart' show AssetBundle, AssetManifest;
import 'package:dot_asm/core/dsl/dsl.dart';
import 'package:dot_asm/core/logging/log.dart';
import 'package:dot_asm/core/sim/dsl/processor_dsl.dart';
import 'package:dot_asm/core/sim/spec/processor_spec.dart';

/// A processor template: a `.cpu` file shipped with the app. Creating a project copies the file into the project, so
/// the app never needs to know a processor by name: it only reads the file.
class ProcessorTemplate {
  const ProcessorTemplate({required this.spec, required this.text});

  /// The parsed definition (for listing and filtering).
  final ProcessorSpec spec;

  /// The file's text, copied verbatim into projects.
  final String text;

  String get id => spec.id;
}

/// The templates found in `assets/templates/*.cpu`. Add a template by dropping a `.cpu` file there: nothing in the code
/// lists them.
class TemplateCatalog {
  TemplateCatalog._();

  static const folder = 'assets/templates/';

  static List<ProcessorTemplate> templates = const [];

  /// Discovers and parses every template in the asset bundle.
  static Future<void> load(AssetBundle bundle) async {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    final keys =
        manifest
            .listAssets()
            .where((k) => k.startsWith(folder) && k.endsWith('.cpu'))
            .toList()
          ..sort();
    final texts = <String>[];
    for (final key in keys) {
      try {
        texts.add(await bundle.loadString(key));
      } catch (e, st) {
        Log.error('catalog', 'Cannot read template $key', e, st);
      }
    }
    setTexts(texts);
  }

  /// Parses template texts (also used by tests, which read the files directly).
  static void setTexts(Iterable<String> texts) {
    final out = <ProcessorTemplate>[];
    for (final text in texts) {
      try {
        final spec = ProcessorDsl.parse(text, builtin: true);
        final problems = spec.validate();
        if (problems.isNotEmpty) {
          Log.warning(
            'catalog',
            'Template ${spec.id} has problems: ${problems.join('; ')}',
          );
        }
        out.add(ProcessorTemplate(spec: spec, text: text));
      } on DslError catch (e) {
        Log.error('catalog', 'Cannot read a template: $e');
      } catch (e, st) {
        Log.error('catalog', 'Cannot read a template', e, st);
      }
    }
    templates = out;
  }

  static ProcessorTemplate? byId(String id) =>
      templates.where((t) => t.id == id).firstOrNull;

  /// The template meant as a starting point for a new design: the first one tagged "Custom".
  static ProcessorTemplate? get blank =>
      templates
          .where((t) => t.spec.tags.any((x) => x.toLowerCase() == 'custom'))
          .firstOrNull ??
      templates.firstOrNull;
}

/// A processor that is listed in the gallery but cannot be simulated yet, read from `assets/gallery/planned.dotasm`.
class PlannedProcessor {
  const PlannedProcessor({
    required this.name,
    required this.vendor,
    required this.year,
    required this.era,
    required this.tags,
    required this.description,
  });

  final String name;
  final String vendor;
  final int year;
  final String era;
  final List<String> tags;
  final String description;

  static const asset = 'assets/gallery/planned.dotasm';

  static List<PlannedProcessor> parse(String text) {
    final out = <PlannedProcessor>[];
    for (final n in DslParser(text).parse()) {
      if (n.keyword != 'planned') continue;
      out.add(
        PlannedProcessor(
          name: n.arg(0) ?? 'Unnamed',
          vendor: n.child('vendor')?.arg(0) ?? '',
          year: int.tryParse(n.child('year')?.arg(0) ?? '') ?? 0,
          era: n.child('era')?.arg(0) ?? '',
          tags: n.child('tags')?.argTexts ?? const [],
          description: n.child('describe')?.arg(0) ?? '',
        ),
      );
    }
    return out;
  }
}

/// The planned processors, loaded at startup.
class PlannedCatalog {
  PlannedCatalog._();

  static List<PlannedProcessor> entries = const [];

  static Future<void> load(AssetBundle bundle) async {
    try {
      entries = PlannedProcessor.parse(
        await bundle.loadString(PlannedProcessor.asset),
      );
    } catch (e, st) {
      Log.warning('catalog', 'Cannot read the planned processors', e, st);
    }
  }
}
