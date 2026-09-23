"""The agent CLIs bin/ask can drive, and which of them are installed.

Presence is Omarchy's test rather than PATH: Omarchy leaves a mise shim on PATH
for every agent it knows, installed or not."""

import os
import subprocess

from .config import fail


# In omarchy-default-agent's order. `chat` is the print-mode command with the
# prompt appended; `launch` is the interactive one, from omarchy-agent.
# `efforts` are the levels its `effort` flag takes ({} is the level), mirrored
# as EFFORT_CHOICES in src/settings/choices.mjs; change both.
AGENTS = [
    {
        "id": "claude", "name": "Claude Code",
        "chat": ["claude", "-p", "--output-format", "text",
                 "--allowedTools", "WebSearch", "WebFetch", "--"],
        # --include-partial-messages is what actually streams tokens: without it
        # the whole reply still arrives in one `assistant` event at the end.
        "stream": ["claude", "-p", "--output-format", "stream-json",
                   "--include-partial-messages", "--verbose",
                   "--allowedTools", "WebSearch", "WebFetch", "--"],
        "stream_format": "claude",
        "launch": ["claude", "--permission-mode", "auto", "--"],
        "effort": ["--effort", "{}"],
        "efforts": ["low", "medium", "high", "xhigh", "max"],
        "login": ["claude", "auth", "login"],
    },
    {
        "id": "codex", "name": "Codex",
        # exec narrates on stdout too; the final message alone lands in -o.
        "chat": ["codex", "exec", "--skip-git-repo-check", "--color", "never", "-o", "{last}"],
        # No "stream": measured, `codex exec --json` emits no text deltas — the
        # reply arrives whole in one item.completed at the end — so streaming it
        # would buy nothing but tool chatter. It takes the whole-answer path.
        "launch": ["codex", "--approve-for-me", "--"],
        # No flag of its own: -c overrides config.toml for this process only.
        "effort": ["-c", 'model_reasoning_effort="{}"'],
        "efforts": ["low", "medium", "high", "xhigh", "max"],
        "login": ["codex", "login"],
    },
    {
        "id": "crush", "name": "Crush",
        # `run` answers once and exits, never prompting; -q hides its spinner.
        # No "stream": it prints the reply whole when it is done.
        "chat": ["crush", "run", "-q"],
        # As omarchy-agent spells it: --yolo belongs to the interactive command.
        "launch": ["crush", "--yolo"],
        # Only `crush run` takes --model; the interactive command refuses it, so
        # a hand-off opens on Crush's own selected model.
        "launch_model": False,
        # `crush login` alone signs in to Charm Hyper, whatever provider is in
        # use; the TUI walks through choosing one instead, as gemini's does.
        "login": ["crush"],
        # Its errors are boxed and wrapped over several lines.
        "wrapped_errors": True,
    },
    {
        "id": "opencode", "name": "OpenCode",
        "chat": ["opencode", "run"],
        "launch": ["opencode", "--auto", "--prompt"],
        # A variant is the provider's reasoning effort. Only `opencode run`
        # takes --variant, so a hand-off opens on the TUI's own choice.
        "effort": ["--variant", "{}"],
        "efforts": ["minimal", "low", "medium", "high", "max"],
        "launch_effort": False,
        "login": ["opencode", "auth", "login"],
    },
    {
        "id": "gemini", "name": "Gemini",
        "chat": ["gemini", "-p"],
        "launch": ["gemini", "--yolo", "--prompt-interactive"],
        "login": ["gemini"],               # no subcommand: the TUI asks on first start
    },
    {
        "id": "hermes", "name": "Hermes",
        "chat": ["hermes", "chat", "-Q", "-q"],
        "launch": ["hermes", "chat", "--yolo", "--tui", "--query"],
        "launch_env_unset": ["HERMES_SESSION_SOURCE"],
        "login": ["hermes", "login"],
        "setup": ["hermes", "model"],      # signed in but with no provider chosen
        "installer": "omarchy-install-hermes-cli",
    },
    {
        "id": "copilot", "name": "GitHub Copilot",
        "chat": ["copilot", "-p"],
        "launch": ["copilot", "--allow-all", "--interactive"],
        "effort": ["--effort", "{}"],
        "efforts": ["none", "minimal", "low", "medium", "high", "xhigh", "max"],
        "login": ["copilot", "login"],
    },
    {
        "id": "cursor-agent", "name": "Cursor CLI",
        "chat": ["cursor-agent", "-p", "--output-format", "text", "--trust"],
        "launch": ["cursor-agent", "--yolo", "--trust", "agent", "--"],
        "login": ["cursor-agent", "login"],
    },
]


def user_install(agent_id):
    """A binary the user put in ~/.local/bin themselves (a symlink, or anything
    that is not Omarchy's `mise use -g` stub)."""
    path = os.path.join(os.environ["HOME"], ".local", "bin", agent_id)
    if not os.access(path, os.X_OK):
        return False
    if os.path.islink(path):
        return True
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return not any(line.startswith("mise use -g") for line in handle)
    except OSError:
        return False


def quietly(command):
    try:
        return subprocess.run(command, capture_output=True, timeout=10).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def agent_present(agent):
    if agent.get("installer"):
        return quietly([agent["installer"], "--check"])
    return user_install(agent["id"]) or quietly(["mise", "where", agent.get("package", agent["id"])])


def installed_agents():
    return [agent for agent in AGENTS if agent_present(agent)]


def omarchy_default():
    """What `omarchy default agent` was set to, or '' — Omarchy ships unset."""
    try:
        out = subprocess.run(["omarchy-default-agent"], capture_output=True,
                             text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""
    return out


def resolve_agent(requested, available):
    """'default' or an id -> the agent record, and whether it is Omarchy's own default."""
    default_id = omarchy_default()
    if requested in ("", None, "default"):
        for agent in available:
            if agent["id"] == default_id:
                return agent, True
        # Omarchy ships with no default agent; the first installed one stands in.
        if available:
            return available[0], False
        fail("agent", "no supported AI agent is installed — see `omarchy default agent`")
    for agent in available:
        if agent["id"] == requested:
            return agent, agent["id"] == default_id
    fail("agent", f"{requested} is not installed")
