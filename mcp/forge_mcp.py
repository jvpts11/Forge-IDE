#!/usr/bin/env python3
"""Forge MCP server -- drive the Forge IDE programmatically.

Forge exposes a scriptable transport: `Forge.exe serve` opens the window once and reads one
command per line from stdin. This MCP server wraps that transport as tools an MCP client (or an
AI agent) can call.

It is part of Forge itself -- a remote-control / automation API, the way an editor exposes a
scripting interface -- and doubles as the harness for developing and testing the IDE.

CAPABILITIES. An agent driving your editor can change files, run git and start processes, so what
it may touch is your decision rather than the agent's. Permissions live in
~/.forge/mcp-permissions.txt as `category = on|off`, written with defaults the first time this
server runs, so they can be reviewed and edited like any other setting:

    edit       type, press keys, click -- change the buffer
    files      open and save files
    git        status, diff, commit, log
    build      build, run, run tests
    debug      breakpoints, start/step/stop
    terminal   the integrated terminal
    inspect    read-only: editor state, tool windows, screenshots
    settings   read and change preferences
    plugins    list and install plugins
    shell      run an ARBITRARY shell command -- off by default

`shell` is off by default because it is the only one that is unbounded; every other category is
limited to something Forge already does. A tool whose category is off returns a refusal naming
that category, so the agent can ask for it rather than failing opaquely.

Run as an MCP server:      python forge_mcp.py
Drive a quick self-test:   python forge_mcp.py selftest
Show the permissions:      python forge_mcp.py perms
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

# --- capabilities -------------------------------------------------------------------------------

_PERM_FILE = Path(os.path.expanduser("~")) / ".forge" / "mcp-permissions.txt"

# shell is opt-in: every other category is bounded by something Forge itself does, while shell is
# not bounded by anything.
_DEFAULT_PERMS = {
    "edit": True,
    "files": True,
    "git": True,
    "build": True,
    "debug": True,
    "terminal": True,
    "inspect": True,
    "settings": True,
    "plugins": True,
    "shell": False,
}

_PERM_HELP = """# What the Forge MCP server may do. `category = on` or `off`; edit, then restart the server.
#
#   edit       type, press keys, click -- change the buffer
#   files      open and save files
#   git        status, diff, commit, log
#   build      build, run, run tests
#   debug      breakpoints, start/step/stop
#   terminal   the integrated terminal
#   inspect    read-only: editor state, tool windows, screenshots
#   settings   read and change preferences
#   plugins    list and install plugins
#   shell      run an ARBITRARY shell command -- off by default, since it is unbounded
"""


def _write_default_perms() -> None:
    _PERM_FILE.parent.mkdir(parents=True, exist_ok=True)
    lines = [_PERM_HELP]
    for name, allowed in _DEFAULT_PERMS.items():
        lines.append(f"{name} = {'on' if allowed else 'off'}")
    _PERM_FILE.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _perms() -> dict:
    """Current permissions, seeding the file with defaults on first run.

    Unknown keys are ignored and missing ones keep their default, so an older or hand-edited file
    never leaves the server unable to start.
    """
    if not _PERM_FILE.exists():
        _write_default_perms()
    out = dict(_DEFAULT_PERMS)
    try:
        for raw in _PERM_FILE.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            if key in out:
                out[key] = value.strip().lower() in ("on", "true", "yes", "1")
    except OSError:
        pass                                   # unreadable: fall back to the defaults
    return out


def _denied(category: str) -> str:
    return (f"refused: the '{category}' capability is off for the Forge MCP server. "
            f"Turn it on in {_PERM_FILE} and restart the server.")


def _allowed(category: str) -> bool:
    return _perms().get(category, False)


# --- transport ----------------------------------------------------------------------------------

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


def _guard(category: str, command: str) -> str:
    """Send a command only when its capability is on."""
    if not _allowed(category):
        return _denied(category)
    return _send(command)


def _dump(category: str, command: str) -> str:
    """Run a command, then read the output panel back -- for tools whose answer is a list."""
    if not _allowed(category):
        return _denied(category)
    _send(command)
    return _send("outdump")


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

    # --- editing -------------------------------------------------------------------------------

    @mcp.tool()
    def type_text(text: str) -> str:
        """Type text into the focused editor."""
        return _guard("edit", "type " + text)

    @mcp.tool()
    def press(key: str) -> str:
        """Press a key: enter, esc, tab, backspace, up/down/left/right, or ctrl+<letter>."""
        return _guard("edit", "key " + key)

    @mcp.tool()
    def click(x: int, y: int) -> str:
        """Click at window coordinates."""
        return _guard("edit", f"click {x} {y}")

    @mcp.tool()
    def run_command(command_id: str) -> str:
        """Run a registered command by id (edit.format, view.split, git.status, ...)."""
        return _guard("edit", "cmd " + command_id)

    @mcp.tool()
    def palette(query: str) -> str:
        """Open the command palette and filter it; press('enter') runs the top match."""
        return _guard("edit", "palette " + query)

    @mcp.tool()
    def find(query: str) -> str:
        """Find text in the active document and jump to the first match."""
        return _guard("edit", "find " + query)

    @mcp.tool()
    def escape() -> str:
        """Close whatever overlay is open."""
        return _guard("edit", "esc")

    # --- files ---------------------------------------------------------------------------------

    @mcp.tool()
    def open_file(path: str) -> str:
        """Open a file in a tab."""
        return _guard("files", "open " + path)

    @mcp.tool()
    def save() -> str:
        """Save the active document to disk."""
        return _guard("files", "save")

    # --- git -----------------------------------------------------------------------------------

    @mcp.tool()
    def git_status() -> str:
        """Working-tree status, as the Source Control panel shows it."""
        return _dump("git", "cmd git.status")

    @mcp.tool()
    def git_diff() -> str:
        """Diff of the active file."""
        return _dump("git", "cmd git.diff")

    @mcp.tool()
    def git_log() -> str:
        """Recent commit history."""
        return _dump("git", "cmd git.log")

    # --- build and tests -----------------------------------------------------------------------

    @mcp.tool()
    def build() -> str:
        """Build the project; diagnostics land in the Problems list."""
        return _guard("build", "build")

    @mcp.tool()
    def run_project() -> str:
        """Run the project."""
        return _guard("build", "cmd run.program")

    @mcp.tool()
    def run_tests() -> str:
        """Run the project's tests; reports pass/fail per test."""
        return _dump("build", "cmd view.tests")

    @mcp.tool()
    def problems() -> str:
        """The current diagnostics."""
        return _dump("inspect", "cmd view.problems")

    # --- debugging -----------------------------------------------------------------------------

    @mcp.tool()
    def breakpoint_at(line: int) -> str:
        """Toggle a breakpoint on a line of the active file."""
        return _guard("debug", f"bp {line}")

    @mcp.tool()
    def debug_start() -> str:
        """Build with debug info and start (or continue) the debugger."""
        return _guard("debug", "debug")

    @mcp.tool()
    def debug_step() -> str:
        """Step over."""
        return _guard("debug", "dbgstep")

    @mcp.tool()
    def debug_stop() -> str:
        """Stop the debugger."""
        return _guard("debug", "dbgstop")

    @mcp.tool()
    def debug_state() -> str:
        """Where the debugger is stopped, with the call stack and variables."""
        return _guard("debug", "dbgstate")

    # --- terminal ------------------------------------------------------------------------------

    @mcp.tool()
    def terminal_send(text: str) -> str:
        """Type a line into the integrated terminal and run it."""
        return _guard("terminal", "term " + text)

    @mcp.tool()
    def terminal_output() -> str:
        """The terminal's recent output."""
        return _guard("terminal", "termdump")

    # --- inspection (read-only) ----------------------------------------------------------------

    @mcp.tool()
    def state() -> str:
        """Editor state: active file, caret line/col, line count, open tabs, dirty flag."""
        return _guard("inspect", "state")

    @mcp.tool()
    def symbols(query: str = "") -> str:
        """Symbols in the workspace, optionally filtered."""
        return _dump("inspect", "symbols " + query)

    @mcp.tool()
    def regions() -> str:
        """LDP3 regions declared in the project (the Regions tool window)."""
        return _dump("inspect", "cmd view.regions")

    @mcp.tool()
    def bundles() -> str:
        """The project's bundles and their dependencies."""
        return _dump("inspect", "cmd view.bundles")

    @mcp.tool()
    def persistents() -> str:
        """Persistent declarations in the project."""
        return _dump("inspect", "cmd view.persistents")

    @mcp.tool()
    def screenshot() -> Image:
        """A picture of the current frame."""
        if not _allowed("inspect"):
            raise RuntimeError(_denied("inspect"))
        return Image(path=_shot_png())

    # --- settings and plugins ------------------------------------------------------------------

    @mcp.tool()
    def settings_open() -> str:
        """Open the settings panel."""
        return _guard("settings", "settings")

    @mcp.tool()
    def plugins_list() -> str:
        """Installed plugins."""
        return _dump("plugins", "cmd plugins.list")

    # --- unbounded -----------------------------------------------------------------------------

    @mcp.tool()
    def run_shell(command: str) -> str:
        """Run an arbitrary shell command in the project directory. Off unless enabled."""
        return _guard("shell", "run " + command)

    @mcp.tool()
    def capabilities() -> str:
        """What this server is currently allowed to do, and where to change it."""
        rows = [f"{name:9} {'on' if allowed else 'off'}" for name, allowed in _perms().items()]
        return "\n".join(rows) + f"\n\nedit {_PERM_FILE} and restart to change these"

    return mcp


def _selftest() -> int:
    """Drive a few commands without needing an MCP client installed."""
    print("permissions file:", _PERM_FILE)
    for name, allowed in _perms().items():
        print(f"  {name:9} {'on' if allowed else 'off'}")
    print("state:", _send("state"))
    print("guarded (shell, off by default):", _guard("shell", "run echo hi"))
    print("guarded (inspect, on):", _guard("inspect", "state"))
    png = _shot_png()
    print("screenshot:", png, os.path.getsize(png), "bytes")
    _send("quit")
    return 0


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "selftest":
        raise SystemExit(_selftest())
    if len(sys.argv) > 1 and sys.argv[1] == "perms":
        print(_PERM_FILE)
        for name, allowed in _perms().items():
            print(f"  {name:9} {'on' if allowed else 'off'}")
        raise SystemExit(0)
    _build_server().run()
