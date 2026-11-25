import 'dart:io';

import 'package:dot_asm/app/processor_catalog.dart';
import 'package:dot_asm/core/sim/spec/processor_spec.dart';

/// The `.cpu` files in `assets/templates`, sorted by name.
List<File> templateFiles() =>
    Directory('assets/templates')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.cpu'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

/// Loads the templates the way the app does at startup (it reads the same files from the asset bundle).
void loadTemplates() =>
    TemplateCatalog.setTexts(templateFiles().map((f) => f.readAsStringSync()));

ProcessorSpec template(String id) => TemplateCatalog.byId(id)!.spec;
