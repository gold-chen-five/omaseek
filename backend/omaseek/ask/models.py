"""Which model an agent is given, and the models it offers: from its own CLI,
its cache, or — for Crush — cut to the providers its crush.json names."""

import json
import os
import re
import subprocess

from .outcome import ANSI


# Only these CLIs expose a non-interactive model catalogue. Codex keeps the
# catalogue it receives from the service in models_cache.json.
MODEL_COMMANDS = {
    "opencode": ["opencode", "models"],
    "cursor-agent": ["cursor-agent", "models"],
    "copilot": ["copilot", "help", "config"],
    # Every model of every provider Crush knows — 1,600-odd — so the rows are
    # kept to the providers configured in its crush.json (crush_providers).
    "crush": ["crush", "models"],
}


MODEL_CACHE_AGENTS = ("codex",)


def chosen_model(payload, config, agent):
    if "model" in payload:
        value = payload.get("model")
    elif agent["id"] in MODEL_COMMANDS or agent["id"] in MODEL_CACHE_AGENTS:
        models = config.get("chat_models")
        value = models.get(agent["id"]) if isinstance(models, dict) else ""
    else:
        value = ""
    if not isinstance(value, str):
        return ""
    value = value.strip()
    return "" if re.search(r"[\x00-\x1f\x7f]", value) else value


def crush_providers():
    """The providers Crush has set up, by name, from its crush.json files: the
    data one its own sign-in writes, and the hand-written config one. Only the
    keys are read — the values hold tokens."""
    data = os.environ.get("XDG_DATA_HOME") or os.path.join(os.environ["HOME"], ".local", "share")
    config = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.environ["HOME"], ".config")
    names = []
    for path in (os.path.join(data, "crush", "crush.json"), os.path.join(config, "crush", "crush.json")):
        try:
            with open(path, encoding="utf-8") as handle:
                providers = json.load(handle).get("providers")
        except (OSError, ValueError, AttributeError):
            continue
        if isinstance(providers, dict):
            names.extend(name for name in providers if name not in names)
    return names


def parse_model_list(agent_id, text, providers=None):
    """Read only model rows, never banners, help prose or log lines."""
    text = ANSI.sub("", text)
    if agent_id == "crush":
        rows = re.findall(r"^([\w.-]+)/(\S+)$", text, re.M)
        allowed = set(providers or [])
        candidates = [f"{provider}/{model}" for provider, model in rows if provider in allowed]
    elif agent_id == "copilot":
        section = re.search(r"(?ms)^  `model`:.*?(?=^  `|\Z)", text)
        candidates = re.findall(r'^\s+- "([^"\s]+)"\s*$', section[0] if section else "", re.M)
    elif agent_id == "opencode":
        candidates = re.findall(r"^([\w.-]+/[^\s]+)$", text, re.M)
    else:
        # Cursor prints `id - display name`, optionally with a current marker.
        candidates = re.findall(r"^\s*([\w][\w./:+-]*)\s+-\s+\S.*$", text, re.M)
    return list(dict.fromkeys(candidates))


def list_models(agent):
    agent_id = agent["id"]
    if agent_id == "codex":
        home = os.environ.get("CODEX_HOME") or os.path.join(os.environ["HOME"], ".codex")
        try:
            with open(os.path.join(home, "models_cache.json"), encoding="utf-8") as handle:
                cache = json.load(handle)
            rows = cache.get("models", []) if isinstance(cache, dict) else []
            models = [row["slug"] for row in rows if isinstance(row, dict)
                      and isinstance(row.get("slug"), str) and row["slug"]
                      and row.get("visibility", "list") == "list"] if isinstance(rows, list) else []
        except (OSError, ValueError):
            models = []
        return {"ok": True, "agent": agent_id, "models": list(dict.fromkeys(models)),
                "message": "" if models else "open Codex once to refresh its model list; using default"}
    if agent_id not in MODEL_COMMANDS:
        return {"ok": True, "agent": agent_id, "models": [],
                "message": "this CLI does not expose a model list; using default"}
    try:
        done = subprocess.run(MODEL_COMMANDS[agent_id], stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.SubprocessError):
        return {"ok": False, "agent": agent_id, "models": [], "message": "model lookup unavailable"}
    providers = crush_providers() if agent_id == "crush" else None
    models = parse_model_list(agent_id, done.stdout, providers) if done.returncode == 0 else []
    message = "" if models else "model lookup unavailable; using default"
    if agent_id == "crush" and not providers:
        message = "set up a provider in Crush first; using its default"
    return {"ok": done.returncode == 0, "agent": agent_id, "models": models, "message": message}


def with_model(agent, model):
    """All supported CLIs accept --model, before the prompt-consuming flags.

    Keep the trailing prompt flag / -- in place: the chat appends its prompt,
    and the draft launcher removes that flag before starting an empty editor.
    Login/setup commands keep their own model-selection flow.
    """
    if not model:
        return agent
    selected = dict(agent)
    for kind in ("chat", "stream", "launch"):
        if kind not in agent:
            continue
        if kind == "launch" and agent.get("launch_model") is False:
            continue
        command = list(agent[kind])
        at = 2 if command[1] in ("exec", "run", "chat") else 1
        command[at:at] = ["--model", model]
        selected[kind] = command
    return selected
