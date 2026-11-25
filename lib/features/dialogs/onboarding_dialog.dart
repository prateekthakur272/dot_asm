import 'package:flutter/material.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/components/buttons.dart';
import 'package:dot_asm/components/layout.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/platform/platform.dart';
import 'package:dot_asm/theme/theme.dart';
import 'package:dot_asm/utils/app_config.dart';

/// The welcome tour shown the first time the app starts (and from Help ▸ Welcome tour): what the app is, how a
/// project works, what to watch while a program runs, and where to go next.
class OnboardingDialog extends StatefulWidget {
  const OnboardingDialog({super.key, required this.state});
  final AppState state;

  @override
  State<OnboardingDialog> createState() => _OnboardingDialogState();
}

class _OnboardingDialogState extends State<OnboardingDialog> {
  int _step = 0;
  static const int _steps = 5;

  void _close() => widget.state.modal = null;

  void _next() {
    if (_step < _steps - 1) {
      setState(() => _step++);
    } else {
      _close();
    }
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final last = _step == _steps - 1;
    return ModalScaffold(
      title: switch (_step) {
        0 => 'Welcome to ${AppConfig.NAME}',
        1 => 'Projects are folders',
        2 => 'Run it and watch',
        3 => 'Real processors, or your own',
        _ => 'You are ready',
      },
      width: 660,
      onClose: _close,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 380,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, a) =>
                  FadeTransition(opacity: a, child: child),
              child: KeyedSubtree(
                key: ValueKey(_step),
                child: switch (_step) {
                  0 => const _Welcome(),
                  1 => const _ProjectsStep(),
                  2 => const _RunStep(),
                  3 => const _ProcessorsStep(),
                  _ => _ReadyStep(state: widget.state),
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.only(top: 14),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: p.border.withOpacity(0.7))),
            ),
            child: Row(
              children: [
                if (!last)
                  Btn(label: 'Skip', height: 32, fontSize: 12, onClick: _close)
                else
                  const SizedBox(width: 56),
                const Spacer(),
                for (var i = 0; i < _steps; i++) ...[
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: i == _step ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _step ? p.accent : p.border,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  if (i < _steps - 1) const SizedBox(width: 5),
                ],
                const Spacer(),
                if (_step > 0) ...[
                  Btn(label: 'Back', height: 32, fontSize: 12, onClick: _back),
                  const SizedBox(width: 8),
                ],
                Btn(
                  label: last ? 'Done' : 'Continue',
                  icon: last
                      ? Icons.check_rounded
                      : Icons.arrow_forward_rounded,
                  primary: true,
                  height: 32,
                  fontSize: 12,
                  onClick: _next,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------

/// A heading and a paragraph.
class _Lead extends StatelessWidget {
  const _Lead(this.title, this.body);
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        T(title, size: 18, weight: FontWeight.w700),
        const SizedBox(height: 6),
        T(body, size: 12.5, color: p.muted, overflow: TextOverflow.visible),
      ],
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget pillar(IconData icon, String title, String body) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.field,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: p.accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: p.accent),
            ),
            const SizedBox(height: 12),
            T(title, size: 13, weight: FontWeight.w700),
            const SizedBox(height: 4),
            T(body, size: 11.5, color: p.muted, overflow: TextOverflow.visible),
          ],
        ),
      ),
    );
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [p.accent.withOpacity(0.08), p.field],
            ),
            border: Border.all(color: p.border),
          ),
          child: Row(
            children: [
              Image.asset(
                'assets/icons/app_icon.png',
                width: 64,
                height: 64,
                filterQuality: FilterQuality.high,
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: _Lead(
                  'Learn how a processor really works',
                  'Write assembly, run it on a simulated CPU, and watch every register, flag and memory cell change '
                      'as you step through it.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            pillar(
              Icons.code_rounded,
              'Write',
              'An editor that knows the processor: highlighting, suggestions and error marks.',
            ),
            const SizedBox(width: 10),
            pillar(
              Icons.visibility_outlined,
              'Watch',
              'Registers, memory, the decoded instruction and a trace you can rewind.',
            ),
            const SizedBox(width: 10),
            pillar(
              Icons.developer_board_rounded,
              'Build',
              'Start from RISC-V, ARM, x86 or a 6502, or design a CPU of your own.',
            ),
          ],
        ),
      ],
    );
  }
}

class _ProjectsStep extends StatelessWidget {
  const _ProjectsStep();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget file(
      int depth,
      IconData icon,
      String name,
      String note, {
      Color? c,
    }) => Padding(
      padding: EdgeInsets.only(left: depth * 20.0, bottom: 7),
      child: Row(
        children: [
          Icon(icon, size: 15, color: c ?? p.muted),
          const SizedBox(width: 8),
          MonoText(name, size: 12, weight: FontWeight.w600),
          const SizedBox(width: 10),
          Flexible(child: T(note, size: 11, color: p.muted, maxLines: 1)),
        ],
      ),
    );
    Widget point(String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          T(title, size: 12.5, weight: FontWeight.w700),
          const SizedBox(height: 2),
          T(body, size: 11.5, color: p.muted, overflow: TextOverflow.visible),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Lead(
          'Everything about a project is a plain file',
          'A project is a folder you choose. Keep it in git, move it, share it.',
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 11,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: p.field,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: p.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      file(
                        0,
                        Icons.folder_rounded,
                        'MyProject/',
                        '',
                        c: p.warn,
                      ),
                      file(
                        1,
                        Icons.settings_outlined,
                        'project.dotasm',
                        'settings',
                      ),
                      file(
                        1,
                        Icons.code_rounded,
                        'main.s',
                        'your assembly',
                        c: p.accent,
                      ),
                      file(1, Icons.folder_rounded, 'cpu/', '', c: p.warn),
                      file(
                        2,
                        Icons.memory_rounded,
                        'rv32i.cpu',
                        'the processor',
                        c: p.ok,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    point(
                      'You choose where it lives',
                      'Pick any folder when you create a project, or open one that already has a project.dotasm.',
                    ),
                    point(
                      'The processor is a text file',
                      'Creating a project copies a processor into cpu/. From then on it is yours to read and change.',
                    ),
                    point(
                      'No hidden database',
                      'The app only remembers where your projects are.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RunStep extends StatelessWidget {
  const _RunStep();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final mac = Platform.isMac;
    Widget btn(IconData icon, String label, {Color? color, String? key}) =>
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: (color ?? p.field).withOpacity(color == null ? 1 : 0.14),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: p.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color ?? p.text),
              const SizedBox(width: 5),
              T(
                label,
                size: 11.5,
                weight: FontWeight.w700,
                color: color ?? p.text,
              ),
              if (key != null) ...[
                const SizedBox(width: 7),
                MonoText(key, size: 10, color: p.muted),
              ],
            ],
          ),
        );
    Widget tab(IconData icon, String title, String body) => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.field,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: p.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                T(title, size: 12, weight: FontWeight.w700),
                const SizedBox(height: 1),
                T(
                  body,
                  size: 11,
                  color: p.muted,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Lead(
          'Step through a program, one instruction at a time',
          'Run it, or step and watch exactly what each instruction does. Made a mistake? Step back to undo it.',
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            btn(Icons.play_arrow_rounded, 'Run', color: p.ok, key: 'F5'),
            btn(Icons.skip_next_rounded, 'Step', key: 'F10'),
            btn(Icons.skip_previous_rounded, 'Step back', key: '⇧F10'),
            btn(Icons.restart_alt_rounded, 'Reset'),
            btn(
              Icons.build_circle_outlined,
              'Assemble',
              key: mac ? '⌘⇧B' : 'Ctrl+⇧B',
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 3.6,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              tab(
                Icons.space_dashboard_outlined,
                'Overview',
                'The next instruction and how the last one flowed through the CPU',
              ),
              tab(
                Icons.developer_board_rounded,
                'Registers',
                'Every value, with the changes highlighted. Click one to edit it',
              ),
              tab(
                Icons.grid_view_rounded,
                'Memory',
                'A hex dump with reads and writes marked',
              ),
              tab(
                Icons.list_alt_rounded,
                'Disassembly',
                'The assembled program. Click a row for a breakpoint',
              ),
              tab(
                Icons.account_tree_outlined,
                'Decode',
                'The instruction bits, coloured by operand',
              ),
              tab(
                Icons.history_rounded,
                'Trace',
                'Everything that ran. Click an entry to rewind to it',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProcessorsStep extends StatelessWidget {
  const _ProcessorsStep();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget chip(String t, {bool accent = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent ? p.accent.withOpacity(0.1) : p.field,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent ? p.accent.withOpacity(0.5) : p.border,
        ),
      ),
      child: T(t, size: 11.5, weight: FontWeight.w600),
    );
    Widget line(String a, String b, [Color? c]) => Row(
      children: [
        MonoText(a, size: 11.5, weight: FontWeight.w700, color: p.accent),
        const SizedBox(width: 8),
        Flexible(child: MonoText(b, size: 11.5, color: c ?? p.text)),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Lead(
          'Learn on a real architecture',
          'The processor gallery is grouped by family and era. Every processor is a readable file, so you can see how '
              'its instructions are encoded and what they do.',
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            chip('RISC-V RV32I'),
            chip('MIPS32'),
            chip('ARM (A32)'),
            chip('x86'),
            chip('x86-64'),
            chip('MOS 6502'),
            chip('Atmel AVR'),
            chip('Tiny-16', accent: true),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: p.field,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.data_object_rounded, size: 14, color: p.muted),
                  const SizedBox(width: 6),
                  T('tiny16.cpu', size: 11, color: p.muted),
                ],
              ),
              const SizedBox(height: 10),
              line('instruction', 'add "rd, rs1, rs2" {'),
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    line('match', '0xf007 0x0'),
                    line('operand', 'rd reg [11:9]'),
                    line('exec', '{ rd = rs1 + rs2; }', p.ok),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              MonoText('}', size: 11.5, color: p.text),
            ],
          ),
        ),
        const SizedBox(height: 12),
        T(
          'Change an instruction, or add one, in the processor builder.',
          size: 12,
          color: p.muted,
        ),
      ],
    );
  }
}

class _ReadyStep extends StatelessWidget {
  const _ReadyStep({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final mod = Platform.isMac ? '⌘' : 'Ctrl+';
    Widget key(String k, String what) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 58),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.field,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: p.border),
            ),
            child: MonoText(k, size: 11, weight: FontWeight.w700),
          ),
          const SizedBox(width: 10),
          T(what, size: 12, color: p.muted),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Lead(
          'Start with a project',
          'A starter program is ready in every processor, so you can press Run straight away.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Btn(
              label: 'New project',
              icon: Icons.add_rounded,
              primary: true,
              height: 36,
              fontSize: 12.5,
              onClick: () => state.modal = const ModalNewProject(),
            ),
            Btn(
              label: 'Browse processors',
              icon: Icons.collections_bookmark_outlined,
              height: 36,
              fontSize: 12.5,
              onClick: () {
                state.modal = null;
                state.openGallery();
              },
            ),
            Btn(
              label: 'Open a project…',
              icon: Icons.folder_open_rounded,
              height: 36,
              fontSize: 12.5,
              onClick: () {
                state.modal = null;
                state.openProjectFromPicker();
              },
            ),
          ],
        ),
        const SizedBox(height: 20),
        T('USEFUL KEYS', size: 10.5, weight: FontWeight.w700, color: p.muted),
        const SizedBox(height: 8),
        key('${mod}K', 'Command palette: search for anything'),
        key('F5', 'Run or pause'),
        key('F10', 'Step one instruction'),
        key('⇧F10', 'Step back'),
        const Spacer(),
        T(
          'You can open this tour again from Help ▸ Welcome tour.',
          size: 11,
          color: p.muted,
        ),
      ],
    );
  }
}
