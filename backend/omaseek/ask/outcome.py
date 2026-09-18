"""What a finished run amounts to: the answer, or why there is none — signed
out, out of allowance, unconfigured, or failed — read from short, non-log lines
only, since some CLIs log whole catalogues to stderr."""

import re


# What a signed-out CLI says. Claude: "Not logged in · Please run /login";
# the rest name the token, the key, or the status code.
SIGNED_OUT = re.compile(
    r"not logged in|please run /login|login required|not authenticated|"
    r"unauthori[sz]ed|authentication (failed|required|error)|invalid api key|"
    r"no api key|api key (is )?(missing|not set)|please (sign|log) in|\b401\b",
    re.IGNORECASE,
)


# Signed in but out of allowance: logging in again fixes nothing.
OUT_OF_QUOTA = re.compile(
    r"usage limit|rate limit|quota|out of credit|insufficient (credit|balance|funds)|"
    r"upgrade to (plus|pro)|\b429\b",
    re.IGNORECASE,
)


# Installed and signed in, but unconfigured (no provider, model or auth method).
# Matched only against a short whole output, so an answer that merely mentions
# API keys is still an answer.
NOT_CONFIGURED = re.compile(
    r"no (inference )?provider configured|no model (is )?(configured|selected)|"
    r"please set an auth method|run '[a-z][\w-]* (model|config|configure)'",
    re.IGNORECASE,
)


UNCONFIGURED_MAX = 400


# A structured log line. These carry whole HTTP bodies; never diagnose from them.
LOG_LINE = re.compile(r"^\d{4}-\d\d-\d\dT[\d:.]+Z?\s+(TRACE|DEBUG|INFO|WARN|ERROR)\b")


ANSI = re.compile(r"\x1b\[[0-9;]*m")


def diagnosis(*streams):
    """The last few human-facing lines of a failed run.

    Long lines are dropped along with log lines: an agent talking to a person
    writes a sentence, not a 47KB JSON body.
    """
    lines = []
    for stream in streams:
        for line in ANSI.sub("", stream or "").splitlines():
            line = line.strip()
            if not line or len(line) > 400 or LOG_LINE.match(line):
                continue
            lines.append(re.sub(r"^(ERROR|error|Error):\s*", "", line))
    # The same complaint is often printed twice; the tail is what matters.
    unique = []
    for line in lines[-6:]:
        if line not in unique:
            unique.append(line)
    return unique


def chat_outcome(agent, returncode, out, err, text):
    """What a finished run amounts to: the answer, or why there is none.

    Pure, and the only place a failure is classified, so the streamed and the
    whole-answer paths can never come to different conclusions about the same
    run. What goes in matters: `out` is passed only when it is something a
    person wrote — Codex logs a 47KB model catalogue there, and diagnosing from
    it once reported a signed-in CLI as signed out.
    """
    if returncode != 0:
        said = diagnosis(out, err)
        if agent.get("wrapped_errors"):
            # One complaint wrapped across lines under a bare ERROR heading:
            # its last line alone ("has been reached.") says nothing.
            words = " ".join(line for line in said if line.upper() != "ERROR")
            said = [words] if words else []
        joined = "\n".join(said)
        if OUT_OF_QUOTA.search(joined):
            return {"ok": False, "error": "quota", "message": f"{agent['name']}: {said[-1]}"}
        if SIGNED_OUT.search(joined):
            return {"ok": False, "error": "auth", "login": True, "fix": "login",
                    "message": f"{agent['name']} is signed out — opening its sign-in"}
        # gemini reports missing auth on stderr, with a non-zero exit.
        if NOT_CONFIGURED.search(joined):
            return {"ok": False, "error": "config", "login": True, "fix": "setup",
                    "message": f"{agent['name']}: {said[-1]}"}
        if not text:
            return {"ok": False, "error": "agent",
                    "message": f"{agent['name']}: {said[-1] if said else f'exit {returncode}'}"}
    if not text:
        return {"ok": False, "error": "agent", "message": f"{agent['name']} returned nothing"}
    # Setup instructions on stdout are not an answer.
    if len(text) <= UNCONFIGURED_MAX and NOT_CONFIGURED.search(text):
        return {"ok": False, "error": "config", "login": True, "fix": "setup",
                "message": f"{agent['name']}: {' '.join(text.split())}"}
    return {"ok": True, "text": text}
