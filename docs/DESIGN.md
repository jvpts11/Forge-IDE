# Forge — design & build plan

This is the design home for Forge, the LDP3 IDE. It records *how* Forge will be built
and *in what order*, so that when the LDP3 master sequence reaches "real software" there
is a plan to execute rather than a blank page. Nothing here is built yet.

## Where Forge sits in the master sequence

The LDP3 project follows a strict order: finish the language, then the stdlib, then the
toolchain, then an audit-and-optimize pass, and only then real software — of which Forge
is the first. Forge does not jump that queue. What *can* proceed earlier is the work that
is genuinely "finishing the language": exercising the FFI against real C libraries, which
is how we discover and close the FFI's rough edges (structs by value, function-pointer
callbacks, output-pointer parameters, opaque handles).

## The prerequisite chain

Forge is a text editor before it is anything else, and a text editor needs a window and a
2D canvas — not a GPU compute API. The chain is therefore deliberately boring at the
bottom and gets interesting only near the top:

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

## Milestones

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
