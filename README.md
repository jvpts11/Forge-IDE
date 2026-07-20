<!-- Forge — the IDE for LDP3, written in LDP3. -->

# Forge

**The IDE for [LDP3](https://github.com/jvpts11/LDP3), written in LDP3.**

Forge is the first flagship application of the LDP3 language: a native, from-scratch
IDE — editor, navigation, git, build/run, integrated terminals, and a debugger client —
built entirely in LDP3, rendered on the GPU through the `ldp3-opengl` stack. It is how
LDP3 proves it can carry real, GUI-heavy systems software, not just command-line programs.

Mascot and identity are shared with the language: **Flamo**, the amber flame, on the
deep brand ground. Forge's own icon is a hammer striking an anvil.

## Status — a working native graphical IDE

Forge opens a native GL window and runs a full editing session today. `ldp3 build`
compiles all of `src/` into one program; `build.ps1` builds it and runs the headless
engine self-check (**over 400 checks**, the exact count printed by `Forge.exe test`).

What works today (see [`docs/DESIGN.md`](docs/DESIGN.md) for the module map):

- **Editing** — line-based buffer; full caret/selection model; **multi-cursor** (add
  caret above/below, add-next-occurrence, column select); snapshot undo/redo; word- and
  line-wise motion/deletion; smart Home/End; auto-indent, block indent/dedent, comment
  toggle; duplicate/move/sort/join lines; extract-variable; bracket matching + auto-close;
  find/replace and **find/replace across files**; folding, bookmarks, word wrap.
- **Files & project** — a real-filesystem project tree, tabs, open/save/new/rename/delete,
  session restore, recent projects, and external-change detection.
- **Navigation** — go-to-definition (into the bundled stdlib too), find references, an
  outline/structure panel, breadcrumbs, go-to-symbol, workspace symbol search, quick-open,
  go-to-line, back/forward history, and a fuzzy command palette.
- **Language intelligence** — LDP3 syntax highlighting, autocomplete (keywords, buffer and
  project symbols, import paths), hover, **live diagnostics** (the `ldp3` compiler runs on
  the unsaved buffer, debounced), quick-fixes, `ldp3 explain`, and workspace-wide rename.
- **Git** — status with gutter change bars, commit, push, branch list + checkout, and a
  side-by-side / unified diff view.
- **Build / run / terminal** — build (diagnostics become a navigable Problems list), run,
  run-tests, and multiple **integrated terminals** (cmd or PowerShell, renamable tabs). Each
  runs its shell behind a real pseudo-console (ConPTY), so colours, cursor movement, history
  and tab-completion work as they do in a real console.
- **Debugger** — a Debug Adapter Protocol client with gutter breakpoints, step over/in/out,
  call stack and variables. `ldp3 build --debug` emits DWARF and the client drives `lldb-dap`;
  source-line breakpoints bind and locals are shown (verified end to end). It needs `lldb-dap`
  present with its `python311` runtime, which the installer bundles.
- **UI** — light/dark themes (persisted), split editor over a shared document, a minimap,
  resizable panels, font zoom, and context menus.

## Architecture

Forge is a clean MVC engine with two interchangeable view backends over the same
`Controller`/`Workbench`:

```
                +------------------ Forge (LDP3) ------------------+
   ldp3     <-- |  navigation   editor engine   build/run runner   |
   git      <-- |  file tree    terminals       debugger (DAP)     |
                |         GpuScreen (GPU view)  /  ScreenRenderer   |
                +--------------------+-----------------------------+
                     glyph atlas     |   2D batch renderer
                   (GDI Consolas)    |     (ldp3-opengl)
                +--------------------+-----------------------------+
                |     native GL window + input  (Win32 via FFI)     |
                +--------------------------------------------------+
                                     FFI (extern)
```

The **editor engine** (`editor/`, `view/`, `syntax/`, `app/`, `input/`, `io/`) is
decoupled from graphics, so it is unit-tested headless without a window. The **graphics
layer** (`gfx/`) is a second view backend: a pixel-space quad batcher (`Batch2D`), a glyph
atlas (`Font`), the frame composer (`GpuScreen`), and the window + event loop (`GuiApp`).

## Ecosystem

Forge builds on sibling LDP3 projects:

| Dependency     | Role                                              | State          |
|----------------|---------------------------------------------------|----------------|
| `LDP3`         | the language, compiler (`ldp3c`), driver (`ldp3`) | in progress    |
| `ldp3-opengl`  | pluggable modern-GL (3.3 core) rendering library  | in use         |

Diagnostics and build/run shell out to the `ldp3` driver; git features shell out to `git`;
the debugger drives `lldb-dap`. Forge locates the toolchain on `PATH` or in a sibling
`../LDP3` checkout.

## Building

Forge is a normal LDP3 project. With the `ldp3` toolchain available:

```
./build.ps1        # ldp3 build + bundle reference docs + run the headless self-test
```

`build.ps1` finds the driver on `PATH`, then the sibling `../LDP3` dev build (override with
`-Ldp3 <path>`). It targets Windows x86-64 today; other targets follow the language.

---

Created by João Victor Pereira Tavares.
