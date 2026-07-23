# Forge — graphics layer design

**Date:** 2026-07-12
**Status:** approved (verbal), spec under review
**Scope:** put the finished headless editor engine on screen — a real OpenGL window with
GDI-rasterized text, keyboard input, and mouse — by adding a GPU *view backend* over the
existing `Controller`/`Workbench`, plus the enabling additions to the shared `ldp3-opengl`
library. No change to the editor engine (Model/Controller/Workbench stay as-is; 229 headless
checks remain green).

## 1. Principle

The engine already separates model from view: `Controller` exposes render queries (visible
line, per-token spans, caret screen position, selection) and `Workbench.handleKey` consumes
`input.Key` events. The terminal path (`TextRenderer`/`ScreenRenderer`) is one view backend.
The graphics layer is a **second view backend** reading the *same* queries and drawing them on
the GPU. The `KeyMap` is reused verbatim — OS key events are translated to `input.Key` and fed
to the same `Workbench`.

```
  [ Model / Controller / Workbench ]     ← unchanged
        │  render-queries + handleKey
        ├──► TextRenderer / ScreenRenderer      (text backend, exists)
        └──► GpuScreen + Batch2D + Font         (GPU backend, NEW)
                  │
             ldp3-opengl (shared lib)  ← + keyboard events, + GDI font, + RGBA upload
```

Two repos change: **`ldp3-opengl`** gains general-purpose capabilities (keyboard input, GDI
font rasterization, RGBA texture upload) that benefit any consumer and do not break the
existing Pool_balls consumer; **`Forge-IDE`** gains a `gfx/` package and a `GuiApp` main loop.

## 2. Additions to `ldp3-opengl` (shared library)

The library today gives a real movable GL 4.6 window (`GlWindow.open/pump/swap/isOpen/width/
height`), shader compile/link (`Shader.fromSource`), typed VAO/VBO helpers, `GlMat4.ortho`
(2D), blending enums, and `Gl.readPixelsRgb` readback. It lacks keyboard text input and any
font/text support. We add:

### 2.1 Keyboard events on `GlWindow`
`pump()` already calls `TranslateMessage`, so `WM_CHAR` is generated but discarded. Add a small
event queue and decode, alongside the existing `WM_MOUSEWHEEL` branch:
- `WM_CHAR` (`0x0102`) — `wParam` at `MSG+16` is a UTF-16 code unit → a typed character.
- `WM_KEYDOWN` (`0x0100`) / `WM_KEYUP` (`0x0101`) — `wParam` = virtual-key; `lParam` bit 30 =
  auto-repeat flag.
New surface on `GlWindow`:
- an `InputEvent` value: `{ int kind (CHAR|KEYDOWN); int codepoint; int vk; boolean repeat; }`.
- `hasEvent() returns boolean`, `nextEvent() returns InputEvent` (drains the queue front).
- `modCtrl()/modShift()/modAlt() returns boolean` via `GetAsyncKeyState(VK_CONTROL/SHIFT/MENU)`.
The queue is a fixed-capacity ring on the window (same style as the `scrollDelta` accumulator).

### 2.2 GDI font rasterization
New class (e.g. `gltext.GdiFont`) binding gdi32 (already linked): `CreateFontW`,
`CreateCompatibleDC`, `CreateDIBSection`, `SelectObject`, `SetTextColor`, `SetBkMode`,
`TextOutW`, `GetTextExtentPoint32W`, `DeleteObject`, `DeleteDC`.
- `rasterizeAscii(String fontName, int pixelHeight) returns FontAtlas` — creates a memory DC +
  32-bit DIB, selects the monospace font, measures the cell (fixed advance for a monospace
  face), draws printable ASCII 32..126 into a grid, reads the DIB bits into an **RGBA** buffer
  where each glyph is white with alpha = coverage (so the shader tints per-token color).
- `FontAtlas` carries: `byte[] rgba`, `int atlasW/atlasH`, `int cols`, `int cellW/cellH`,
  `int ascent`, and `uv(char) returns float[4]` (u0,v0,u1,v1).
Reuses the proven LockBits→scan0→row-pack pattern already used for image textures.

### 2.3 RGBA texture upload
`Gl.uploadRGBA(byte[] pixels, int w, int h) returns int` — allocate a `Memory` buffer, write
the bytes, `glTexImage2D(..., GL_RGBA, GL_UNSIGNED_BYTE, ptr)`, nearest filtering, clamp. Used
to upload the font atlas (and later any procedural texture).

## 3. Additions to `Forge-IDE` (`gfx/` package + app loop)

### 3.1 `gfx/Batch2D` — orthographic quad batcher
Pixel-space 2D drawing. `begin(int screenW, int screenH)` sets an `ortho` projection;
`rect(x,y,w,h, r,g,b,a)` and `glyph(x,y, u0,v0,u1,v1, r,g,b,a)` append quads (pos + uv + color)
to a growing CPU array; `flush()` uploads once and issues **one** `glDrawArrays` with alpha
blending. A single shader samples the atlas; the atlas includes one fully-opaque white texel so
`rect()` is a glyph draw with white UV — no shader branch, one draw call for the whole frame.

### 3.2 `gfx/Font`
Wraps the uploaded atlas texture id + `FontAtlas` metrics. `uv(char)`, `cellW()`, `cellH()`,
`ascent()`. Monospace ⇒ pixel position of column *c* row *r* is `(gutter + c*cellW, r*cellH)`.

### 3.3 `gfx/GpuScreen` — the GPU counterpart of `ScreenRenderer`
Given the `Workbench` (and optional `FileTree`), draws one frame with `Batch2D` + `Font`:
gutter background + line numbers; each visible line's text with **per-token colors** from
`Highlighter` spans; current-line highlight band; selection rectangles; the caret rectangle
(from `caretScreenRow/Col`); the tab bar (`DocumentManager.title`s, active emphasized); and the
file-tree panel (`FileTree.visible` + `rowLabel`). A `Theme` holds the Flamo palette (amber
`#eab464` on deep teal) and per-`Tok` colors, matching the VS Code extension and installer.

### 3.4 `app/GuiApp` — the main loop
- `run()`: `GlWindow.open("Forge", 1100, 720, 4, 6)` → load atlas (Consolas ~16px) via
  `GdiFont` + `Gl.uploadRGBA` → build `Batch2D`, `Font`, `GpuScreen`, `Workbench`. Loop while
  `isOpen()`: `pump()`; drain `nextEvent()`s → translate to `input.Key` → `Workbench.handleKey`;
  re-`glViewport` if `width()/height()` changed; clear; `GpuScreen.draw(wb)`; `swap()`.
- `shot(path)`: same setup, render one frame, `readPixelsRgb` → write PPM (flipped Y) for
  offscreen verification.

### 3.5 Input translation (OS → `input.Key`)
- `WM_CHAR`, codepoint ≥ 32 and ≠ 127 → `Key.ch((char)cp)` (typed text; auto-pairs handled by
  the editor).
- `WM_KEYDOWN` → map VK to `KeyCode`: `VK_LEFT/RIGHT/UP/DOWN`, `VK_BACK`→BACKSPACE,
  `VK_RETURN`→ENTER, `VK_DELETE`→DELETE, `VK_TAB`→TAB, `VK_HOME/END`, `VK_PRIOR/NEXT`→PAGE_UP/
  DOWN, plus `VK_A..Z` when Ctrl is held (shortcuts). Modifier flags from `modCtrl/Shift/Alt`.
This is exactly the CHAR-vs-special split the existing `KeyMap` expects, so no editor change.

## 4. Verification

- **Offscreen (me):** `Forge.exe shot frame.ppm` renders one frame; the PPM is converted to PNG
  and viewed to confirm each slice before hand-off. Deterministic monospace layout makes visual
  diffs meaningful.
- **Live (João):** `Forge.exe` opens the interactive window; João confirms real typing/editing.

The library's "shot" still opens a real (briefly visible) window and reads the default
framebuffer — no true FBO offscreen exists yet; that's acceptable (the env has a real GPU). A
true FBO path is out of scope here.

## 5. Slice plan (each = a visible, committable artifact)

**Library prep (`ldp3-opengl`):**
- **L1** — gdi32 font bindings + `GdiFont.rasterizeAscii`; dump the atlas to a PPM to confirm
  glyphs rasterize correctly.
- **L2** — `GlWindow` keyboard event queue (WM_CHAR + WM_KEYDOWN + modifiers) + `Gl.uploadRGBA`.

**Forge `gfx/`:**
- **G1** — open a window, clear to the Forge background, swap → a solid colored window.
- **G2** — `Batch2D` + `Font`: draw one line of text on screen.
- **G3** — `GpuScreen` draws the whole active document: visible lines + gutter + line numbers.
- **G4** — per-token syntax colors + current-line highlight.
- **G5** — caret rectangle + selection highlight + scrolling (viewport follows the caret).
- **G6** — wire keyboard input → `Workbench` → **live editing** (type, arrows, edit, undo).
- **G7** — tab bar + file-tree panel (full IDE layout).
- **G8** — mouse (click to place caret, wheel to scroll) + window-resize handling.

After G6 there is a usable graphical code editor; G7–G8 complete the IDE frame.

## 6. Testing & non-goals

- Editor-engine logic keeps its headless `CoreTests` (unchanged, 229 checks).
- The graphics layer is verified visually per slice (offscreen PPM/PNG + live window); it has no
  unit tests of its own beyond a "renders without GL error" smoke path, because it is inherently
  visual.
- **Non-goals (this spec):** true FBO offscreen, PNG-in-LDP3 encoding, font ligatures/kerning
  (monospace ASCII first; Unicode/UTF-8 glyphs later), the LSP client, the build/run runner, and
  the Regions/Bundles tool windows — all follow after a usable editor window exists.

## 7. Risks

- **GDI DIB metrics / color order.** Mitigated by reusing the existing GDI+ LockBits pattern and
  verifying L1's atlas PPM before anything depends on it.
- **WM_CHAR vs Ctrl-combos double-firing.** Windows sends a control-char WM_CHAR for Ctrl+letter;
  we take text from WM_CHAR only for codepoints ≥ 32 and route shortcuts through WM_KEYDOWN, so
  Ctrl combos never insert stray characters.
- **User's installed toolchain is stale** (missing `ArrayList.insertAt`, committed in `e553b27`).
  Orthogonal to this design: the graphics work builds with the current dev toolchain; the
  installed `ldp3` will be refreshed separately so `ldp3 build` works for the user.
