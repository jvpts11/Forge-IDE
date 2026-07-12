<!-- Forge — the IDE for LDP3, written in LDP3. -->

# Forge

**The IDE for [LDP3](https://github.com/jvpts11/LDP3), written in LDP3.**

Forge is the first flagship application of the LDP3 language: a native, from-scratch
IDE — editor, language server client, build runner, debugger, and memory inspector —
built entirely in LDP3 on top of a pluggable graphics stack. It is how LDP3 proves it
can carry real, GUI-heavy systems software, not just command-line programs.

Mascot and identity are shared with the language: **Flamo**, the amber flame, on the
deep teal ground.

## Status — editor engine built (headless), graphics layer next

The **editor engine is implemented and passing** — a complete, well-structured,
multi-file LDP3 codebase built decoupled from graphics so it is unit-testable without a
window. `ldp3 build` compiles all of `src/` into one program; `build.ps1` runs the
headless self-check (**"editor tests: OK (229 checks)"**), and running `Forge.exe` prints
one fully-composed IDE frame — tab bar, project tree, editor pane with a gutter, and
status bar — rendered from live state.

What works today (see [`docs/DESIGN.md`](docs/DESIGN.md) for the module map): a line-based
text buffer; a full caret/editing model (selection, clipboard, undo/redo, word- and
line-wise motion and deletion, smart Home/End, auto-indent, block indent/dedent, line
comment toggle, configurable tab width); plain-text find/replace; bracket matching with
auto-close pairs; a syntax highlighter; a scrolling viewport; a tab/document manager; a
project file tree over the real filesystem; a fuzzy command palette; a key map; a
Workbench application root; and text/screen renderers.

What's left is the **graphics/UI layer**, which needs visual verification: a window +
input layer, the `ldp3-opengl` 2D canvas, glyph rendering, and a UI toolkit — then wiring
the `Workbench` + `ScreenRenderer` onto a real surface. Forge's prerequisite chain:

```
prove FFI  →  windowing + input  →  ldp3-opengl  →  text rendering  →  UI toolkit  →  [editor core ✓]  →  IDE
```

The first graphics milestone is **not Vulkan** — a 2D canvas is all a text editor needs.
`ldp3-vulkan` is a later, separate effort for the game-grade flagships.

## What Forge looks like

An IntelliJ / Visual Studio-class layout — dense, professional, tool windows docked on
every edge — dressed in the LDP3 amber-and-teal identity. It leans into features that
only an LDP3 IDE can have:

- **Regions & Memory** tool window — live view of LDP3 regions, arenas, ownership
  (`unique` / `movable`), and a leak checker driven by the compiler's flow analysis.
- **Bundles** tool window — the `.ldb` dependency graph and ABI fingerprints.
- Editor with LDP3 syntax highlighting (from the compiler's own lexer), inlay hints,
  gutter run icons, and inline diagnostics + quick-fixes from **ldp3-lsp**.
- Build / run driven by the `ldp3` toolchain, with the target and EH model in the
  console (`x86-64, Itanium EH`).

## Ecosystem

Forge depends on sibling LDP3 projects:

| Dependency     | Role                                              | State          |
|----------------|---------------------------------------------------|----------------|
| `LDP3`         | the language, compiler (`ldp3c`), driver (`ldp3`) | in progress    |
| `ldp3-lsp`     | language server (ships in the LDP3 repo)          | exists         |
| `ldp3-opengl`  | pluggable modern-GL (3.3 core) rendering library  | exists, proven |
| windowing lib  | native window + input (GLFW/SDL via FFI, or OS)   | not started    |

## Building (eventually)

Forge is a normal LDP3 project — `ldp3 build` / `ldp3 run`. It runs on every platform
the language targets (Windows and Linux x86-64 today; ARM64 / macOS later).

---

Created by João Victor Pereira Tavares. Private during bring-up.
