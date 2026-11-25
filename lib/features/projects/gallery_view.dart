import 'package:flutter/material.dart';
import 'package:dot_asm/components/empty_state.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/app/gallery.dart';
import 'package:dot_asm/app/processor_catalog.dart';
import 'package:dot_asm/components/buttons.dart';
import 'package:dot_asm/components/inputs.dart';
import 'package:dot_asm/components/modifiers.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/theme/icons.dart';
import 'package:dot_asm/theme/theme.dart';

/// The processor gallery: famous processors grouped by family and filterable by tag and era.
class GalleryView extends StatefulWidget {
  const GalleryView({super.key, required this.state});
  final AppState state;

  @override
  State<GalleryView> createState() => _GalleryViewState();
}

class _GalleryViewState extends State<GalleryView> {
  String _tag = '';
  String _era = ''; // '', legacy, modern
  String _query = '';

  AppState get state => widget.state;

  List<GalleryEntry> get _all => [
    for (final t in TemplateCatalog.templates) GalleryEntry.fromTemplate(t),
    for (final pl in PlannedCatalog.entries) GalleryEntry.fromPlanned(pl),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final all = _all;

    final tagSet = <String>{for (final e in all) ...e.tags};
    final tags = [
      ...preferredTagOrder.where(tagSet.contains),
      ...(tagSet.difference(preferredTagOrder.toSet()).toList()..sort()),
    ];

    final q = _query.trim().toLowerCase();
    final shown = [
      for (final e in all)
        if ((_tag.isEmpty || e.tags.contains(_tag)) &&
            (_era.isEmpty || e.era == _era) &&
            (q.isEmpty ||
                '${e.name} ${e.vendor} ${e.tags.join(' ')} ${e.description}'
                    .toLowerCase()
                    .contains(q)))
          e,
    ];

    final ready = all.where((e) => e.ready).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
          decoration: BoxDecoration(
            color: p.panel,
            border: Border(bottom: BorderSide(color: p.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.collections_bookmark_outlined, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const T(
                          'Processor gallery',
                          size: 14,
                          weight: FontWeight.w700,
                        ),
                        T(
                          '$ready runnable processors · pick one to start a project, or customise a copy',
                          size: 11,
                          color: p.muted,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: BoundTextField(
                      value: _query,
                      height: 30,
                      hint: 'Search processors…',
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconBtn(
                    icon: AppIcons.close,
                    tooltip: 'Close',
                    size: 30,
                    onClick: state.closeGallery,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _Pills(
                    label: 'Era',
                    options: const [
                      ('', 'All'),
                      ('legacy', 'Legacy'),
                      ('modern', 'Modern'),
                    ],
                    value: _era,
                    onChanged: (v) => setState(() => _era = v),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _Pills(
                label: 'Category',
                options: [('', 'All'), for (final t in tags) (t, t)],
                value: _tag,
                onChanged: (v) => setState(() => _tag = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? const Center(
                  child: EmptyState(
                    art: EmptyArt.search,
                    title: 'No processors match these filters',
                    subtitle:
                        'Clear the era or category, or change the search.',
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(18),
                  physics: const ClampingScrollPhysics(),
                  children: [
                    for (final g in GalleryGroup.values)
                      if (shown.any((e) => e.group == g)) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            T(
                              g.label.toUpperCase(),
                              size: 11,
                              weight: FontWeight.w700,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: T(
                                g.blurb,
                                size: 11,
                                color: p.muted,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final e in shown.where((e) => e.group == g))
                              _EntryCard(state: state, entry: e),
                          ],
                        ),
                        const SizedBox(height: 26),
                      ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _Pills extends StatelessWidget {
  const _Pills({
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final List<(String, String)> options;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Expanded(
      flex: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 62,
              child: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: T(
                  label,
                  size: 10.5,
                  color: p.muted,
                  weight: FontWeight.w600,
                ),
              ),
            ),
            Flexible(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final o in options)
                    HoverBuilder(
                      cursor: SystemMouseCursors.click,
                      onTap: () => onChanged(o.$1),
                      builder: (context, hovered) {
                        final sel = o.$1 == value;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: sel
                                ? p.accent
                                : (hovered ? p.hover : p.field),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: sel ? p.accent : p.border,
                            ),
                          ),
                          child: T(
                            o.$2,
                            size: 11,
                            weight: FontWeight.w600,
                            color: sel ? p.onAccent : p.muted,
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.state, required this.entry});
  final AppState state;
  final GalleryEntry entry;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final e = entry;
    final spec = e.template?.spec;
    final dim = !e.ready;
    final facts = [
      if (e.year > 0) '${e.year}',
      if (e.vendor.isNotEmpty) e.vendor,
      if (spec != null)
        '${spec.registerFile?.count ?? spec.registerCount} registers · ${spec.instructions.length} instructions',
    ].join('  ·  ');

    return Opacity(
      opacity: dim ? 0.62 : 1,
      child: Container(
        width: 336,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.panel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: p.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: p.field,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: p.border),
                  ),
                  alignment: Alignment.center,
                  child: T(
                    '${e.bits}',
                    size: 12,
                    weight: FontWeight.w800,
                    color: p.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      T(e.name, size: 13, weight: FontWeight.w700, maxLines: 1),
                      if (facts.isNotEmpty)
                        T(facts, size: 10.5, color: p.muted, maxLines: 1),
                    ],
                  ),
                ),
                _Badge(
                  e.ready ? (e.legacy ? 'Legacy' : 'Modern') : 'Planned',
                  e.ready ? (e.legacy ? p.warn : p.ok) : p.muted,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [for (final t in e.tags) _Tag(t)],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: T(
                e.description,
                size: 11.5,
                color: p.muted,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 10),
            if (e.ready)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Btn(
                    label: 'Use template',
                    icon: AppIcons.play,
                    primary: true,
                    height: 28,
                    fontSize: 11.5,
                    onClick: () =>
                        state.modal = ModalNewProject(templateId: e.id),
                  ),
                  Btn(
                    label: 'Customise',
                    icon: AppIcons.edit,
                    height: 28,
                    fontSize: 11.5,
                    onClick: () => state.customiseTemplate(e.template!),
                  ),
                ],
              )
            else
              T(
                'On the roadmap: not simulated yet',
                size: 11,
                color: p.muted,
                italic: true,
              ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.14),
      borderRadius: BorderRadius.circular(4),
    ),
    child: T(label, size: 10, weight: FontWeight.w700, color: color),
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: p.field,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
      ),
      child: T(label, size: 10, weight: FontWeight.w600, color: p.muted),
    );
  }
}
