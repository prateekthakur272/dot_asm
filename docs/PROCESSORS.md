# Processor and project files

Everything about a project lives in its own folder, in readable text files:

```
MyProject/
  project.dotasm      the project's configuration
  main.s              your assembly source
  cpu/
    my-cpu.cpu        the project's own processors (one file each)
```

The app data directory (`~/.dotasm`) holds only app settings and a list of where your projects are.

**The app does not contain any processor.** A processor is a `.cpu` file; the app reads the project's file and sets up
the registers, memory map, assembler, decoder and simulator from what it says. Creating a project copies a *template*
(or the blank starting point) into the project's `cpu/` folder, and from then on the project owns its copy.

Both file types use one small block language: one statement per line, `{ }` blocks, `"strings"`, `"""multi-line
strings"""`, and `#` or `//` comments.

## `project.dotasm`

```
project "Demo" {
  processor builtin arm32          # a built-in id, or:  processor file "cpu/my-cpu.cpu"
  source "main.s"
  created "2026-11-25T12:00:00.000"
  updated "2026-11-25T12:30:00.000"
  speed fast                       # slow | medium | fast
  breakpoints 12 20                # source lines
  panel registers                  # the tab shown in the processor panel
}
```

## `*.cpu`: a processor

```
processor tiny16 "Tiny-16" {
  arch custom
  vendor "me"
  year 2026
  era modern                        # legacy | modern (default: before 2000 is legacy)
  tags RISC Educational 16-bit      # gallery filters: RISC CISC ARM x86 x64 8-bit ...
  describe "A small 16-bit RISC for learning."

  word 16 little                    # address/word size in bits, byte order
  fetch 16                          # default instruction size in bits
  aligned                           # fault on misaligned loads and stores

  registers r count 8 width 16 {    # r0..r7
    zero 0                          # r0 always reads 0
    alias zero=0 ra=6 sp=7
  }
  register ACC width 8 "accumulator"   # an extra single register
  flags N Z C V
  init sp=0x7ffe
  reset 0x0
  comments "#" ";" "//"
  pipeline IF ID EX MEM WB

  memory {
    text  at 0x0000 size 0x2000 perms rx role text
    data  at 0x4000 size 0x2000 perms rw role data
    stack at 0x7000 size 0x1000 perms rw role stack
  }

  instruction add "rd, rs1, rs2" {
    size 16
    match 0xF007 0x0000             # mask and value: the bits that identify it
    operand rd  reg [11:9]
    operand rs1 reg [8:6]
    operand rs2 reg [5:3]
    cycles 1
    describe "rd = rs1 + rs2"
    exec {
      rd = rs1 + rs2;
    }
  }

  pseudo "li rd, imm" {
    when "imm >= -256 && imm <= 255" {
      li rd, imm
    }
    otherwise {
      lui rd, ((imm) + 32) >> 6
      addi rd, rd, (imm) - ((((imm) + 32) >> 6) << 6)
    }
  }

  sample """
    li r1, 5
    halt
  """
}
```

Other statements: `hexprefix "$"` (6502-style hex), `wordbytes N` (size of `.word`), `rewrite "regex" "replacement"`
(operand text rewrites such as `[ebx-4]` to `[ebx+-4]`), `conditions field [31:28] default 14 { eq 0 when Z ... }`
(ARM-style conditional execution), and inside an instruction `base N` (pc-relative base), `conditional`.

Mistakes are reported with the line number and, for a misspelled statement, a suggestion
(`line 12: Unknown statement 'regsters' (did you mean 'registers'?)`).

### Instructions

* `match mask value`: the instruction is chosen when `word & mask == value`; the most specific match wins.
* `operand name kind field`: `kind` is `reg` (register file index), `imm` (number or expression) or `pcrel` (a label
  becomes a distance from the instruction; a plain number is used as the offset).
* Field syntax: `[hi:lo]` ranges separated by commas (most significant first), `s` prefix = signed, `<<n` = implicit
  shift, `+n` = register offset (AVR `[7:4]+16` reaches r16..r31).

### Semantics (`exec`)

A tiny language with no loops or I/O, so opening someone else's processor never runs arbitrary code:

* Names: operands, registers and their aliases, flags, `pc` (this instruction), `next` (the following one), locals.
* Writing `pc` branches. Memory: `mem8[a]`, `mem16[a]`, `mem32[a]`, `mem64[a]`.
* Operators `+ - * / % & | ^ ~ ! << >> == != < > <= >= && || ?:` (comparisons are signed; `>>` is logical).
* Functions: `sext zext sra ltu geu gtu leu divu remu mulh mulhu rol ror bit bits abs min max lo hi lo8 hi8`.
* Statements: `x = expr;`, `if (c) { ... } else { ... }`, `halt();`, `trap("msg");`,
  `out("int"|"uint"|"hex"|"char"|"str", v);`.

## Templates

Templates are ordinary `.cpu` files in `assets/templates/`. The app finds them by listing that folder in its asset
bundle, so **adding a template means adding a file**: no code lists them. The gallery's filters, groups and cards come
from each file's `vendor`, `year`, `era`, `tags` and `describe`. A template tagged `Custom` is the blank starting point
for "New processor". Processors that are only planned (not simulated yet) are listed in
`assets/gallery/planned.dotasm`.

* **New project:** copies the chosen template to `<project>/cpu/<id>.cpu`, sets the project's `processor` to that
  file, and starts the source from the template's `sample`.
* **Customise / Add to this project:** copies the template file into the open project (with a fresh id if the id is
  taken) and opens it in the builder.
* **New processor:** a draft from the blank template; saving writes `<project>/cpu/<id>.cpu`.
* **The builder belongs to a project.** It is offered only while a project is open, and edits that project's `cpu/` files.
* **Import** accepts `.cpu` text (and the JSON files of older versions) into the open project. **Export** writes `<id>.cpu`.

Projects from earlier versions are converted in place the first time the app starts, and a project that named a
template (`processor builtin <id>`) gets that template's file copied into its `cpu/` folder.

## Adding a template

1. Drop `assets/templates/<id>.cpu` in place (give it `vendor`, `year`, `tags`, `describe` and a `sample` program that
   prints something and halts).
2. That is all. `test/gallery_test.dart` checks that it is valid, categorised, that its sample assembles and runs to a
   halt, that every instruction decodes, and that nothing in `lib/` mentions processors by name;
   `test/dsl_test.dart` checks it survives a round trip through the writer. Add a `test/sim/<id>_test.dart` with known
   machine words for real encodings.
