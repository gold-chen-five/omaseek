"""One whole answer from an agent's print mode, with stdin closed (codex waits
on it otherwise) and the CLI tied to this process, so a stopped answer does not
leave an agent running and billing."""

import ctypes
import os
import signal
import subprocess
import sys

from .config import TIMEOUT, WORK_DIR, emit
from .outcome import chat_outcome


def chat_env(agent):
    env = dict(os.environ)
    for key in agent.get("launch_env_unset", []):
        env.pop(key, None)
    return env


def die_with_parent():
    """In the agent's child, before exec: take SIGTERM when this script dies.

    The panel stops an answer by stopping this process, and a stopped answer
    must not keep an agent CLI running — and billing — in the background. The
    kernel delivers it however this script ends, SIGKILL included, which no
    handler here could promise."""
    try:
        ctypes.CDLL(None, use_errno=True).prctl(1, signal.SIGTERM)   # PR_SET_PDEATHSIG
    except (OSError, AttributeError):
        pass


def run_chat_outcome(agent, prompt):
    """One whole answer, as a payload. Never exits, so --stream can wrap it."""
    os.makedirs(WORK_DIR, exist_ok=True)
    last = os.path.join(WORK_DIR, f"{agent['id']}.last")
    # A stale file from an earlier answer would be read as this one's.
    if os.path.exists(last):
        os.remove(last)
    command = [part.replace("{last}", last) for part in agent["chat"]] + [prompt]
    try:
        done = subprocess.run(
            command, cwd=WORK_DIR, env=chat_env(agent),
            # Closed stdin: given the panel's, `codex exec` waits on it and never answers.
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=TIMEOUT,
            preexec_fn=die_with_parent,
        )
    except FileNotFoundError:
        return {"ok": False, "error": "agent", "message": f"{agent['id']} is not installed"}
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "agent",
                "message": f"{agent['name']} did not answer within {TIMEOUT}s"}
    text = done.stdout.strip()
    if "{last}" in "".join(agent["chat"]):
        try:
            with open(last, encoding="utf-8") as handle:
                text = handle.read().strip()
        except OSError:
            pass
    return chat_outcome(agent, done.returncode, done.stdout, done.stderr, text)


def run_chat(agent, prompt):
    outcome = run_chat_outcome(agent, prompt)
    if not outcome["ok"]:
        emit(outcome)
        sys.exit(0)
    return outcome["text"]
