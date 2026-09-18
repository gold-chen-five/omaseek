"""Where bin/ask keeps things, and its one-object output: the config file it
shares with the panel, the working directory agents run in, the payload it is
handed, and emit/fail, which always exit 0 with a JSON object."""

import json
import os
import sys


# The plugin's bin/, where agent-draft lives: four levels up from this file
# (backend/omaseek/ask/config.py), through any symlink the plugin is installed by.
BIN_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))), "bin")

CONFIG_PATH = os.path.join(
    os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.environ["HOME"], ".config"),
    "omaseek", "config.json",
)


# The chat runs somewhere with no project in it: an agent started in $HOME
# or a repo would read that directory's instructions into a web question.
WORK_DIR = os.path.join(
    os.environ.get("XDG_CACHE_HOME") or os.path.join(os.environ["HOME"], ".cache"),
    "omaseek", "ask",
)


TIMEOUT = 180           # an agent that has said nothing by now is stuck, not thinking


LAUNCHERS = ("terminal", "tmux", "herdr")


def emit(obj):
    json.dump(obj, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    # Flushed every time: a streamed delta held in the buffer until exit would
    # defeat the whole point of streaming it.
    sys.stdout.flush()


def fail(error, message):
    emit({"ok": False, "error": error, "message": message})
    sys.exit(0)


def read_config():
    try:
        with open(CONFIG_PATH, encoding="utf-8") as handle:
            config = json.load(handle)
    except (OSError, ValueError):
        return {}
    return config if isinstance(config, dict) else {}


def read_payload(argv):
    """The JSON payload: --json '<object>', or stdin."""
    if "--json" in argv:
        at = argv.index("--json")
        if at + 1 >= len(argv):
            fail("usage", "--json needs a value")
        raw = argv[at + 1]
        del argv[at:at + 2]
    else:
        raw = sys.stdin.read() if not sys.stdin.isatty() else ""
    if not raw.strip():
        return {}
    try:
        payload = json.loads(raw)
    except ValueError:
        fail("usage", "stdin is not valid JSON")
    return payload if isinstance(payload, dict) else {}
