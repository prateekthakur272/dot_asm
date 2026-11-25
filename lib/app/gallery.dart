import 'package:dot_asm/app/processor_catalog.dart';

/// Groups the gallery is divided into, in display order.
enum GalleryGroup {
  risc(
    'RISC',
    'Reduced instruction set: few simple, fixed-size instructions; load/store memory access.',
  ),
  cisc(
    'CISC',
    'Complex instruction set: many instructions and addressing modes, variable length.',
  ),
  arm('ARM', 'The ARM family, from classic ARM7 to modern cores.'),
  x86(
    'x86 / x64',
    'Intel and AMD PC processors, from the 8086 to 64-bit x86-64.',
  ),
  educational(
    'Educational',
    'Small designs made for learning how a processor works.',
  ),
  custom('Custom', 'Start from scratch and design your own.');

  const GalleryGroup(this.label, this.blurb);
  final String label;
  final String blurb;
}

/// One card in the processor gallery: a template that can start a project, or a planned processor that is not
/// available yet. Everything shown comes from the template's `.cpu` file (or the planned list), never from code.
class GalleryEntry {
  const GalleryEntry({
    required this.id,
    required this.name,
    required this.vendor,
    required this.year,
    required this.era,
    required this.tags,
    required this.description,
    required this.bits,
    this.template,
  });

  final String id;
  final String name;
  final String vendor;
  final int year;

  /// `legacy` or `modern`.
  final String era;
  final List<String> tags;
  final String description;
  final int bits;

  /// The template to start a project from, or null for a planned entry.
  final ProcessorTemplate? template;

  bool get ready => template != null;
  bool get legacy => era == 'legacy';

  GalleryGroup get group {
    bool has(String t) => tags.any((x) => x.toLowerCase() == t.toLowerCase());
    if (has('Custom')) return GalleryGroup.custom;
    if (has('Educational')) return GalleryGroup.educational;
    if (has('ARM')) return GalleryGroup.arm;
    if (has('x86') || has('x64')) return GalleryGroup.x86;
    if (has('CISC')) return GalleryGroup.cisc;
    if (has('RISC')) return GalleryGroup.risc;
    return GalleryGroup.custom;
  }

  static GalleryEntry fromTemplate(ProcessorTemplate t) {
    final s = t.spec;
    return GalleryEntry(
      id: s.id,
      name: s.name,
      vendor: s.vendor,
      year: s.year,
      era: s.era.isNotEmpty
          ? s.era
          : (s.year > 0 && s.year < 2000 ? 'legacy' : 'modern'),
      tags: s.tags,
      description: s.description,
      bits: s.wordBits,
      template: t,
    );
  }

  static GalleryEntry fromPlanned(PlannedProcessor p) {
    final bits =
        p.tags
            .map((t) => RegExp(r'^(\d+)-bit$').firstMatch(t)?.group(1))
            .whereType<String>()
            .map(int.parse)
            .firstOrNull ??
        0;
    return GalleryEntry(
      id: 'planned-${p.name}',
      name: p.name,
      vendor: p.vendor,
      year: p.year,
      era: p.era,
      tags: p.tags,
      description: p.description,
      bits: bits,
    );
  }
}

/// Display order of tag filters in the gallery.
const preferredTagOrder = [
  'RISC', 'CISC', 'ARM', 'x86', 'x64', 'RISC-V', 'MIPS', 'AVR', 'MOS', //
  '8-bit',
  '16-bit',
  '32-bit',
  '64-bit',
  'Microcontroller',
  'Educational',
  'Open ISA',
  'Custom',
];
