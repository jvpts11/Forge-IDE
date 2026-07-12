# Forge MCP server

Drive the Forge IDE programmatically over the [Model Context Protocol](https://modelcontextprotocol.io).
It is a remote-control / automation API for Forge — the way a mature editor exposes a scripting
interface — and doubles as the harness used to develop and test the IDE.

## How it works

Forge ships a scriptable transport: **`Forge.exe serve`** opens the window once and reads one command
per line from stdin, driving the editor and acknowledging each on stdout. `forge_mcp.py` wraps that
transport as MCP tools.

```
MCP client  ⇄  forge_mcp.py  ⇄  Forge.exe serve  (window + GL 4.6)
                (stdin/stdout line protocol)
```

## Tools

| Tool | What it does |
|------|--------------|
| `type_text(text)`      | Type text into the active editor (or the open overlay's query) |
| `press(key)`           | Press a named key: `enter`, `backspace`, `tab`, `esc`, `delete`, `left`/`right`/`up`/`down`, `home`, `end`, `pageup`, `pagedown` |
| `click(x, y)`          | Left-click a pixel — a tab activates it, a tree dir expands, a tree file opens, the editor places the caret |
| `run_command(id)`      | Run a command by id (`file.new`, `edit.undo`, `edit.selectAll`, …) |
| `open_file(path)`      | Open a file (relative to the project root) in a new tab |
| `save()`               | Save the active document |
| `palette(query)`       | Open the command palette and type a query (then `press("enter")`) |
| `find(query)`          | Open the find bar and jump to the first match |
| `escape()`             | Close any open overlay |
| `state()`              | Active file, caret line/col, line/tab count, dirty flag |
| `screenshot()`         | Render the current frame and return it as a PNG image |

## Run it

Prereqs: a built `Forge.exe` (`ldp3 build` in the repo root), Python 3.10+, and `pip install mcp pillow`.

```bash
python mcp/forge_mcp.py            # run as an MCP stdio server
python mcp/forge_mcp.py selftest   # drive a quick scripted session (prints a PNG path)
```

Point at a specific build with `FORGE_EXE=C:\path\to\Forge.exe`.

## Register with an MCP client

Claude Code / Claude Desktop (`claude_desktop_config.json` or `.mcp.json`):

```json
{
  "mcpServers": {
    "forge": {
      "command": "python",
      "args": ["C:/Users/jvpts/Documents/GitHub/Forge-IDE/mcp/forge_mcp.py"]
    }
  }
}
```

## Notes

- The serve process flushes stdout after every reply (`fflush`), and the Python side uses binary pipes,
  so replies arrive immediately rather than being stuck in the CRT's pipe buffer.
- One Forge window is spawned lazily on the first tool call and reused; it is rebuilt if it exits.
