"""Handing a draft or a sign-in to the agent's interactive CLI, in a terminal,
a tmux window or a herdr tab. The draft goes in unsent, through agent-draft."""

import json
import os
import shlex
import shutil
import subprocess
import tempfile

from .config import BIN_DIR, LAUNCHERS, fail


def interactive_command(agent, prompt):
    # Startup prompt flags submit immediately. Start with an empty editor,
    # then let the PTY helper deliver a bracketed paste without Enter.
    command = list(agent["launch"])
    if command[-1] in ("--", "--prompt", "--prompt-interactive", "--query", "--interactive"):
        command.pop()
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8",
                                     prefix="omaseek-draft-", delete=False) as draft:
        draft.write(prompt)
    helper = os.path.join(BIN_DIR, "agent-draft")
    return [helper, draft.name, "--"] + command


def env_prefix(agent):
    """`env -u KEY` for the variables the interactive spelling must not see."""
    unset = agent.get("launch_env_unset", [])
    return ["env"] + ["-u" + key for key in unset] if unset else []


def shell_line(agent, prompt):
    """The interactive command as one shell string, for tmux and herdr."""
    return shlex.join(env_prefix(agent) + interactive_command(agent, prompt))


def fix_command(agent, fix):
    """Signed out -> its sign-in; unconfigured -> its setup, where it has one."""
    if fix == "setup" and agent.get("setup"):
        return agent["setup"]
    return agent["login"]


def login_line(agent, prompt, fix="login"):
    """Fix the agent, then exec into it with an editable draft. `;` not `&&`, so a
    failed sign-in still leaves the agent on screen saying why."""
    line = shlex.join(env_prefix(agent) + fix_command(agent, fix))
    if prompt:
        line += "; exec " + shell_line(agent, prompt)
    return line


def open_terminal(command, env_unset=()):
    """A plain terminal window running `command` — the same class as the
    user's own terminal, so their window rules dress it the same way."""
    launcher = ["setsid", "uwsm-app", "--", "xdg-terminal-exec", "-e"]
    for key in env_unset:
        launcher = ["env", "-u", key] + launcher   # before the launcher: xdg-terminal-exec passes it on
    subprocess.Popen(launcher + list(command), start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def launch_terminal(agent, prompt):
    open_terminal(interactive_command(agent, prompt), agent.get("launch_env_unset", []))


def launch_tmux(agent, line):
    session = "Work"                       # the one omarchy-launch-terminal-tmux attaches to
    has = subprocess.run(["tmux", "has-session", "-t", session], capture_output=True)
    if has.returncode != 0:
        subprocess.run(["tmux", "new-session", "-d", "-s", session], check=False)
    subprocess.run(["tmux", "new-window", "-t", session, "-n", agent["id"], line], check=False)
    clients = subprocess.run(["tmux", "list-clients", "-t", session],
                             capture_output=True, text=True).stdout.strip()
    if not clients:
        subprocess.Popen(["omarchy-launch-terminal-tmux"], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def launch_herdr(agent, line):
    created = subprocess.run(
        ["herdr", "tab", "create", "--label", agent["name"], "--focus"],
        capture_output=True, text=True, timeout=15,
    )
    try:
        result = json.loads(created.stdout)["result"]
        pane = result["root_pane"]["pane_id"]
    except (ValueError, KeyError, TypeError):
        detail = created.stderr.strip() or created.stdout.strip() or "no answer from the herdr server"
        fail("launcher", f"herdr could not open a tab: {detail}")
    subprocess.run(["herdr", "pane", "run", pane, line],
                   capture_output=True, timeout=15)
    # A bare `herdr` process is a client attached to the session; the server
    # runs with arguments. No client means the tab opened somewhere invisible.
    clients = subprocess.run(["pgrep", "-x", "-f", "herdr"], capture_output=True)
    if clients.returncode != 0:
        subprocess.Popen(["omarchy-launch-terminal-herdr"], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def hand_off(launcher, agent, line):
    """Open one shell line where this user keeps their terminals."""
    if launcher == "tmux":
        launch_tmux(agent, line)
    elif launcher == "herdr":
        launch_herdr(agent, line)
    else:
        # -l: the compositor's PATH may lack mise's shims.
        open_terminal(["bash", "-lc", line])


def chosen_launcher(payload, config):
    launcher = payload.get("launcher") or config.get("launcher") or "terminal"
    if launcher not in LAUNCHERS:
        fail("usage", f"unknown launcher {launcher!r}")
    if launcher != "terminal" and shutil.which(launcher) is None:
        fail("launcher", f"{launcher} is not installed")
    return launcher
