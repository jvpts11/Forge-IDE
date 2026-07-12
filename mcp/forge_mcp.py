#!/usr/bin/env python3
"""Forge MCP server -- drive the Forge IDE programmatically.

Forge exposes a scriptable transport: `Forge.exe serve` opens the window once and reads one
command per line from stdin. This MCP server wraps that transport as tools an MCP client (or an
AI agent) can call: type text, press keys, click, run commands, open/save files, use the command
palette and find bar, read the editor state, and capture a screenshot of the current frame.

It is part of Forge itself -- a remote-control / automation API, the way an editor exposes a
scripting interface -- and doubles as the harness for developing and testing the IDE.

Run as an MCP server:      python forge_mcp.py
Drive a quick self-test:   python forge_mcp.py selftest
Point at a specific build: set FORGE_EXE=C:\\path\\to\\Forge.exe
"""

import os
import sys
import subprocess
import tempfile
from pathlib import Path

from PIL import Image as PILImage

_HERE = Path(__file__).resolve().parent
_ROOT = _HERE.parent                                   # the Forge-IDE project root
_FORGE = os.environ.get("FORGE_EXE", str(_ROOT / "build-output" / "Forge.exe"))

_proc = None


def _forge():
    """Lazily start (or restart) the Forge serve subprocess, rooted at the project so src/ resolves.

    Binary pipes (not text mode): Python's text-mode line buffering breaks pipe writes on Windows.
    """
    global _proc
    if _proc is None or _proc.poll() is not None:
        _proc = subprocess.Popen(
            [_FORGE, "serve"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, cwd=str(_ROOT),
        )
        _proc.stdout.readline()   # consume "forge-serve ready"
    return _proc


def _send(command: str) -> str:
    """Send one command line to Forge and return its single-line acknowledgement."""
    p = _forge()
    p.stdin.write((command + "\n").encode("utf-8", "replace"))
    p.stdin.flush()
    return p.stdout.readline().decode("utf-8", "replace").strip()


def _shot_png() -> str:
    """Render the current frame to a PPM, convert to PNG, and return the PNG path."""
    ppm = os.path.join(tempfile.gettempdir(), "forge_mcp_frame.ppm")
    png = os.path.join(tempfile.gettempdir(), "forge_mcp_frame.png")
    _send("shot " + ppm)
    PILImage.open(ppm).convert("RGB").save(png, "PNG")
    return png


# --- MCP server (only imported when actually serving, so selftest needs no MCP install) ---

def _build_server():
    from mcp.server.fastmcp import FastMCP, Image

    mcp = FastMCP("forge")

    @mcp.tool()
    def type_text(text: str) -> str:
        """Type text into the active editor (or the open overlay's query)."""
        return _send("type " + text)

    @mcp.tool()
    def press(key: str) -> str:
        """Press a named key: enter, backspace, tab, esc, delete, left, right, up, down, home, end,
        pageup, pagedown."""
        return _send("key " + key)

    @mcp.tool()
    def click(x: int, y: int) -> str:
        """Left-click at pixel (x, y): a tab activates it, a tree directory expands/collapses, a tree
        file opens, and the editor pane places the caret."""
        return _send(f"click {x} {y}")

    @mcp.tool()
    def run_command(command_id: str) -> str:
        """Run a Forge command by id, e.g. file.new, edit.undo, edit.redo, edit.selectAll,
        edit.duplicateLine, file.save."""
        return _send("cmd " + command_id)

    @mcp.tool()
    def open_file(path: str) -> str:
        """Open a file (path relative to the project root) in a new tab."""
        return _send("open " + path)

    @mcp.tool()
    def save() -> str:
        """Save the active document to disk."""
        return _send("save")

    @mcp.tool()
    def palette(query: str) -> str:
        """Open the command palette and type a query (then press('enter') to run the top match)."""
        return _send("palette " + query)

    @mcp.tool()
    def find(query: str) -> str:
        """Open the find bar, search for a query, and jump to the first match."""
        return _send("find " + query)

    @mcp.tool()
    def escape() -> str:
        """Close any open overlay (palette / find)."""
        return _send("esc")

    @mcp.tool()
    def state() -> str:
        """Read the editor state: active file, caret line/col, line count, open-tab count, dirty flag."""
        return _send("state")

    @mcp.tool()
    def screenshot() -> Image:
        """Render the current Forge frame and return it as a PNG image."""
        return Image(path=_shot_png())

    return mcp


def _selftest():
    print(_send("state"))
    print(_send("type // hello from the Forge MCP self-test"))
    print(_send("key enter"))
    print(_send("palette save"))
    print("png:", _shot_png())
    print(_send("esc"))
    print(_send("state"))
    _send("quit")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "selftest":
        _selftest()
    else:
        _build_server().run()
