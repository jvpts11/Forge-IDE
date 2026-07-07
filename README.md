<!-- Forge — the IDE for LDP3, written in LDP3. -->

# Forge

**The IDE for [LDP3](https://github.com/jvpts11/LDP3), written in LDP3.**

Forge is the first flagship application of the LDP3 language: a native, from-scratch
IDE — editor, language server client, build runner, debugger, and memory inspector —
built entirely in LDP3 on top of a pluggable graphics stack. It is how LDP3 proves it
can carry real, GUI-heavy systems software, not just command-line programs.

Mascot and identity are shared with the language: **Flamo**, the amber flame, on the
deep teal ground.

## Status — design phase

Forge is **not being built yet**. Its home exists so the design and roadmap have a
place to live. Construction is gated behind the LDP3 master sequence:

> finish the language → stdlib → toolchain → audit & optimize → **real software (Forge)**

and behind Forge's own prerequisite chain (see [`docs/DESIGN.md`](docs/DESIGN.md)):

```
prove FFI  →  windowing + input  →  ldp3-opengl  →  text rendering  →  UI toolkit  →  editor core  →  IDE
```

The first concrete graphics milestone is **not Vulkan** — it is proving the LDP3 FFI
against a real C library, then a windowing layer and **ldp3-opengl** (a 2D canvas is all
a text editor needs). `ldp3-vulkan` is a later, separate effort for the game-grade
flagships.

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
| `ldp3-opengl`  | pluggable 2D/GL rendering library                 | not started    |
| windowing lib  | native window + input (GLFW/SDL via FFI, or OS)   | not started    |

## Building (eventually)

Forge is a normal LDP3 project — `ldp3 build` / `ldp3 run`. It runs on every platform
the language targets (Windows and Linux x86-64 today; ARM64 / macOS later).

---

Created by João Victor Pereira Tavares. Private during bring-up.
