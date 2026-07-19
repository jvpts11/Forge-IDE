# Forge — design & architecture

This is the design home for Forge, the LDP3 IDE. It records *how* Forge is built and *in
what order* it came together. Forge is now a working native graphical IDE; this document
describes its architecture and the path that got there.

## Where Forge sits in the master sequence

The LDP3 project follows a strict order: finish the language, then the stdlib, then the
toolchain, then an audit-and-optimize pass, and only then real software — of which Forge
is the first. Forge does not jump that queue. What *can* proceed earlier is the work that
is genuinely "finishing the language": exercising the FFI against real C libraries, which
is how we discover and close the FFI's rough edges (structs by value, function-pointer
callbacks, output-pointer parameters, opaque handles).

## The prerequisite chain (built bottom-up)

Forge is a text editor before it is anything else, and a text editor needs a window and a
2D canvas — not a GPU compute API. It was built bottom-up along this chain; every step
below is now in place:

1. **Prove the FFI.** Bind one small, real C library end to end (e.g. a compression or
   hashing lib) and drive it from LDP3. Goal: confirm `extern cdecl/stdcall/fastcall`,
   struct passing, callbacks, and pointer/array marshaling all work, and file bugs where
   they don't. No graphics yet.
2. **Windowing + input.** Create an OS window and receive keyboard/mouse/resize events.
   Two options: bind a cross-platform lib (GLFW or SDL) via FFI, or go native per OS
   (Win32 / X11 / Wayland / Cocoa). GLFW-via-FFI is the pragmatic first pick — one small
   C API, cross-platform, battle-tested.
3. **`ldp3-opengl`.** A pluggable LDP3 library wrapping a modern-but-simple GL profile:
   clear, textured quads, a batched 2D renderer (rects, lines, glyph quads). This is the
   whole rendering need for an editor. Legacy GL is fine here; `ldp3-vulkan` is a separate
   later library for the game-grade flagships, not a Forge dependency.
4. **Text rendering.** Rasterize glyphs and lay out lines. Either FreeType via FFI (the
   proven path) or a pure-LDP3 rasterizer over a bundled font. Cache glyphs in a texture
   atlas; `ldp3-opengl` draws them.
5. **UI toolkit.** Pure LDP3 over steps 2–4: a retained or immediate-mode widget layer
   with layout, focus, scrolling, and the dockable tool-window frame. No external
   dependency — this is the part that makes Forge *Forge*.
6. **Editor core.** A gap-buffer or rope text model, multiple cursors, selection,
   undo/redo, viewport/scrolling, and incremental re-highlighting. Pure LDP3.
7. **IDE features.** Everything above the editor: the LSP client, the build/run runner,
   the file tree, the integrated terminal, and the LDP3-native tool windows.

Each step is shippable on its own and unblocks the next; nothing above step 3 needs a
GPU feature beyond textured 2D quads.

## Architecture (top of the chain)

```
                +------------------ Forge (LDP3) ------------------+
   ldp3-lsp <-- |  LSP client   editor core   build runner        |
   ldp3c/ldp3<--|  file tree    terminal      tool windows         |
                |            UI toolkit  (pure LDP3)                |
                +--------------------+-----------------------------+
                       text layout   |   2D renderer
                     (Freetype/pure) |  (ldp3-opengl)
                +--------------------+-----------------------------+
                |          windowing + input (GLFW via FFI)        |
                +--------------------------------------------------+
                                     FFI (extern)
```

Pieces we already have and reuse:

- **Lexer** — the LDP3 compiler's own lexer drives syntax highlighting, so the editor and
  the language agree on tokens by construction.
- **`ldp3-lsp`** — the language server (shipped in the LDP3 repo) gives diagnostics,
  hover, go-to-definition, and quick-fixes over stdio.
- **`ldp3` driver** — `ldp3 build` / `ldp3 run` and process spawning give the build and
  run integration; the console shows the real toolchain output.
- **stdlib** — `Files`, `String`/`string`, collections, `Regex`, threads/async for
  background indexing and compilation.

## LDP3-native differentiators

These tool windows exist because no other language has the features behind them:

- **Regions & Memory** — live regions and arenas with usage bars, ownership annotations
  (`unique` / `movable` / `partitionable`), and a leak view fed by the compiler's flow
  analysis. LDP3 is manual-memory with compile-time ownership; Forge makes that visible.
- **Bundles** — the `.ldb` dependency graph, transitive closure, and ABI fingerprints,
  with reattach/reimport state for the managed-runtime features.
- **Persistents / lifecycle** — inspect persistent objects and lifecycle hooks at runtime.

## Milestones (all reached)

| #  | Milestone                          | Proves                                             |
|----|------------------------------------|----------------------------------------------------|
| M0 | FFI against a real C lib           | the FFI is production-usable                        |
| M1 | Window + a cleared frame           | windowing/input via FFI                             |
| M2 | A triangle, then a textured quad   | `ldp3-opengl` batched 2D                            |
| M3 | A line of text on screen           | glyph rasterization + atlas                         |
| M4 | Editable buffer with a cursor      | editor core + UI toolkit                            |
| M5 | LDP3 syntax highlighting           | lexer integration                                   |
| M6 | ldp3-lsp diagnostics + quick-fix   | LSP client                                          |
| M7 | Build & run from the IDE           | `ldp3` driver integration                           |
| M8 | Tool windows (Project/Regions/…)   | the docked IDE frame + native views                 |

## Non-goals for v1

Remote development, a plugin marketplace, multi-language support, a visual designer, and
`ldp3-vulkan`. Forge v1 is a fast, native, single-language editor that makes LDP3 a joy to
write — and proves the language can build a real GUI application.

## Progress

**Editor engine — built and headless-tested, multi-file LDP3 under `src/`.** The heart of
the IDE was built first, decoupled from graphics so it is unit-testable without a window.
Every module is its own `.ldp3` file in a namespaced package; `ldp3 build` (via `ldp3.toml`)
compiles them into one program, and `build.ps1` runs the self-check (**over 400 checks**;
the exact count is printed by `Forge.exe test`). Running `Forge.exe` also opens the IDE — tab bar,
project tree, editor pane, and status bar — rendered from live state.

Layered as a clean MVC:

- **Model — `editor/`**
  - **`TextBuffer`** — a line-based text model (one String per line): insertChar, splitLine
    (Enter), backspace, multi-line getRange/deleteRange/insertText, whole-line set/insert/
    remove, load/serialize.
  - **`Editor`** — a caret over a TextBuffer: type/enter/backspace/delete-forward; arrow,
    word, smart-Home/End, and document moves (each with a select variant); selection with
    anchor; **clipboard** (copy/cut/paste, multi-line); **line ops** (duplicate/delete/
    move/indent/dedent); **snapshot-based undo/redo**; and plain-text **find/replace**.
  - **`Search`** — line-oriented plain-text search (findAll/next/prev/count, case folding)
    with a `Match` sentinel so callers never touch a nullable; also drives find/replace.
  - **`Brackets`** — bracket matching by depth scan; the Editor uses it for auto-close pairs
    (typeWithPairs) and match highlighting (matchingBracket).
  - **`Snapshot` / `Clipboard`** — small value/holder classes for undo and cut-paste.
- **View — `view/` + `syntax/`**
  - **`Viewport`** — a cell-based scrolling window: keep-caret-visible with a scrolloff
    margin, paging, clamping.
  - **`syntax.Highlighter`** — a small LDP3 tokenizer that tiles a line into coloured Spans
    (keyword/ident/number/string/char/comment/punct).
  - **`TextRenderer`** — paints the visible state into text rows (line-number gutter +
    horizontal clipping), a status bar, and an ANSI-coloured variant for a real terminal.
  - **`ScreenRenderer`** — composes a whole IDE frame (tab bar + project tree + editor pane +
    status bar) from live Workbench + FileTree state.
- **Controller, application & input — `app/` + `input/`**
  - **`Controller`** — the per-document brain: owns Document + Editor + Viewport +
    Highlighter, keeps the viewport following the caret, tracks the dirty flag, and exposes a
    flat command + render-query surface for any front-end.
  - **`DocumentManager`** — the open documents (tabs): one Controller per document, active
    switching, open/open-file(de-dup)/close, titles.
  - **`Command` / `CommandRegistry`** — the command set + a fuzzy palette (subsequence match,
    ranked) — the Ctrl+Shift+P foundation; selecting yields an id.
  - **`Workbench`** — the application root a shell instantiates: owns the DocumentManager,
    CommandRegistry and KeyMap; feeds keys to the active editor and runs palette commands.
  - **`input.Key` / `input.KeyMap`** — a decoded key model and all editor key bindings in
    one place (Shift = extend selection, Ctrl = word/document scope, Alt = line moves,
    Ctrl+C/X/V/Z/Y/A/D shortcuts).
  - **`app.Demo`** — builds a Workbench, loads Forge's own src/ as the tree, and prints one
    composed IDE frame so `Forge.exe` demonstrates the whole pipeline end to end.
- **`io.Document`** — open/save a file (Files.readLines/writeLines) with a modified flag;
  **`io.FileTree`** — the lazy project explorer (dirs-first, expand/collapse) over the real
  filesystem; **`test/`** — the `Asserts` harness + `CoreTests` suite.

Found and fixed stdlib/language gaps on the way: `ArrayList.insertAt` (LDP3 repo); confirmed
the reserved-word set (`on`, `step`) and the nullable/no-narrowing model shape the API design
(sentinel returns over nullable pointers).

**Graphics layer — built and verified (`src/gfx/`).** Forge is now a real graphical IDE
rendered entirely on the GPU by LDP3, on top of `ldp3-opengl`. It is a second view backend
over the same `Controller`/`Workbench` (the editor engine is unchanged), reusing the `KeyMap`
for input. Slices L1–L2 (in `ldp3-opengl`: a GDI-rasterized Consolas glyph atlas, a keyboard
event queue, RGBA texture upload) and G1–G8:

- **`gfx.Batch2D`** — a pixel-space orthographic quad batcher (pos + uv + colour + texFlag),
  one `glDrawArrays` per frame; a single shader draws solid rects and tints glyph coverage.
- **`gfx.Font`** — the uploaded atlas + metrics; draws text/spans with no per-glyph allocation.
- **`gfx.GpuScreen`** — composes the whole IDE frame: tab bar, project tree panel, and the
  editor pane (gutter, line numbers, per-token syntax colours, current-line band, selection,
  caret), all from live state.
- **`gfx.GuiApp`** — opens a native GL 4.6 window and runs the frame loop: pump OS events →
  translate to `input.Key` → drive the `Workbench` → draw. `Forge.exe` opens the window;
  `Forge.exe shot` renders one frame to a PPM for offscreen verification; `Forge.exe test`
  runs the headless engine checks.

Each slice was verified by reading the frame back from the GPU (`glReadPixels` → PPM → PNG).
Live mouse and OS-keyboard input are wired and verified interactively.

**Next:** live-window polish (tab/tree clicks, scrollbar, minimap, save/open), then the
LDP3-native tool windows (Regions & Memory, Bundles) and the LSP/build-runner integration —
and, per the product vision, a render-preview window and build/run panel, evolving toward a
lightweight multi-language IDE.
