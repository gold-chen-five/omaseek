"""A reply as it is written: the agent's streaming print mode, its events
turned into delta and done lines. Display only — the answer that is saved is
the one in the done event."""

import json
import os
import subprocess
import threading

from .config import TIMEOUT, WORK_DIR, emit
from .outcome import chat_outcome
from .run import chat_env, die_with_parent


def message_text(message):
    """The text blocks of one assistant message, joined."""
    parts = []
    for block in message.get("content") or []:
        if isinstance(block, dict) and block.get("type") == "text":
            parts.append(block.get("text") or "")
    return "".join(parts)


def claude_event(state, event):
    """One `claude -p --output-format stream-json` event -> (shown, settled).

    `shown` is text to display now; `settled` is the answer the CLI itself
    settled on, and only that is saved. `state` remembers whether token deltas
    have been seen: with --include-partial-messages the finished message
    arrives as well, and taking both would show the answer twice.
    """
    kind = event.get("type")
    if kind == "stream_event":
        inner = event.get("event") or {}
        if inner.get("type") == "content_block_delta":
            delta = inner.get("delta") or {}
            if delta.get("type") == "text_delta":
                state["partial"] = True
                return delta.get("text") or "", None
        return "", None
    if kind == "assistant" and not state.get("partial"):
        return message_text(event.get("message") or {}), None
    if kind == "result":
        return "", str(event.get("result") or "")
    return "", None


STREAM_PARSERS = {"claude": claude_event}


def stream_chat(agent, prompt):
    """The agent's streaming print mode, its events turned into ours as they
    arrive. Display only: the answer that is saved is the one in the final
    payload, so a delta this misreads can never corrupt it."""
    os.makedirs(WORK_DIR, exist_ok=True)
    parse = STREAM_PARSERS[agent["stream_format"]]
    try:
        process = subprocess.Popen(
            list(agent["stream"]) + [prompt], cwd=WORK_DIR, env=chat_env(agent),
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, preexec_fn=die_with_parent,
        )
    except FileNotFoundError:
        return {"ok": False, "error": "agent", "message": f"{agent['id']} is not installed"}

    # stderr is drained in a thread and kept whole: diagnosis() wants all of it,
    # and a pipe left unread fills and deadlocks the run.
    errors = []
    reader = threading.Thread(target=lambda: errors.append(process.stderr.read()), daemon=True)
    reader.start()

    # A watchdog, not subprocess.run's timeout: nothing here waits on the
    # process, it waits on the next line.
    overdue = []
    watchdog = threading.Timer(TIMEOUT, lambda: (overdue.append(True), process.kill()))
    watchdog.start()

    state = {}
    shown = []
    settled = None
    try:
        for line in process.stdout:
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except ValueError:
                continue                    # narration, not an event
            text, answer = parse(state, event)
            if text:
                shown.append(text)
                emit({"event": "delta", "text": text})
            if answer is not None:
                settled = answer
    finally:
        watchdog.cancel()
        process.stdout.close()
        code = process.wait()
        reader.join(timeout=2)

    if overdue:
        return {"ok": False, "error": "agent",
                "message": f"{agent['name']} did not answer within {TIMEOUT}s"}
    text = (settled if settled is not None else "".join(shown)).strip()
    # stdout held events, not sentences, so only stderr is worth diagnosing.
    return chat_outcome(agent, code, "", "".join(errors), text)
