"""bin/ask's commands: --agents, --models, --login, --launch, --translate,
and a chat turn, whole or streamed."""

import sys

from .agents import installed_agents, omarchy_default, resolve_agent
from .config import emit, fail, read_config, read_payload
from .handoff import chosen_launcher, hand_off, launch_terminal, login_line, shell_line
from .models import chosen_effort, chosen_model, list_models, with_effort, with_model
from .prompts import build_prompt, build_translation_prompt, translate_target, without_web
from .run import run_chat, run_chat_outcome
from .stream import stream_chat


def translate(payload, config, available):
    """--translate: one translation through its own agent, model and effort. The panel
    names both; from the command line they fall back to Settings → Translate,
    whose agent 'same' means the one Ask uses."""
    text = str(payload.get("text") or "").strip()
    if not text:
        fail("usage", "--translate needs text")
    target = translate_target(payload.get("target") or config.get("translate_language"))
    chosen = str(config.get("translate_agent") or "same")
    requested = payload.get("agent") or (config.get("chat_agent") if chosen == "same" else chosen) or "default"
    agent, _is_default = resolve_agent(requested, available)
    if "model" in payload:
        model = chosen_model(payload, config, agent)
    else:
        models = config.get("translate_models")
        model = chosen_model({"model": models.get(agent["id"], "") if isinstance(models, dict) else ""},
                             config, agent)
    effort = chosen_effort(payload, config, agent, "translate_efforts")
    agent = with_effort(with_model(without_web(agent), model), effort)
    outcome = run_chat_outcome(agent, build_translation_prompt(text, target))
    if outcome.get("ok"):
        outcome.update({"agent": agent["id"], "model": model, "target": target})
    emit(outcome)


def main():
    argv = sys.argv[1:]
    config = read_config()
    available = installed_agents()

    if argv and argv[0] == "--agents":
        default_id = omarchy_default()
        emit({
            "ok": True,
            "agents": [{"id": a["id"], "name": a["name"]} for a in available],
            "default": default_id if any(a["id"] == default_id for a in available)
                       else (available[0]["id"] if available else ""),
            "configured": bool(default_id),
        })
        return

    payload = read_payload(argv)
    if argv and argv[0] == "--translate":
        translate(payload, config, available)
        return
    requested = payload.get("agent") or config.get("chat_agent") or "default"
    agent, _is_default = resolve_agent(requested, available)
    if argv and argv[0] == "--models":
        emit(list_models(agent))
        return
    model = chosen_model(payload, config, agent)
    agent = with_effort(with_model(agent, model), chosen_effort(payload, config, agent))

    if argv and argv[0] == "--login":
        launcher = chosen_launcher(payload, config)
        hand_off(launcher, agent, login_line(agent, str(payload.get("prompt") or "").strip(),
                                             str(payload.get("fix") or "login")))
        emit({"ok": True, "login": agent["id"], "launcher": launcher})
        return

    if argv and argv[0] == "--launch":
        prompt = str(payload.get("prompt") or "").strip()
        if not prompt:
            fail("usage", "--launch needs a prompt")
        launcher = chosen_launcher(payload, config)
        if launcher == "terminal":
            launch_terminal(agent, prompt)
        else:
            hand_off(launcher, agent, shell_line(agent, prompt))
        emit({"ok": True, "launched": agent["id"], "launcher": launcher})
        return

    streaming = bool(argv) and argv[0] == "--stream"
    if argv and not streaming:
        fail("usage", f"unknown argument {argv[0]!r}")

    question = str(payload.get("question") or "").strip()
    if not question:
        fail("usage", "no question given")
    history = payload.get("history") if isinstance(payload.get("history"), list) else []
    prompt = build_prompt(question, history)

    if not streaming:
        emit({"ok": True, "text": run_chat(agent, prompt), "agent": agent["id"], "model": model})
        return

    # An agent with no streaming spelling still ends in one done event, so the
    # panel reads one protocol whichever agent answered.
    outcome = stream_chat(agent, prompt) if agent.get("stream") else run_chat_outcome(agent, prompt)
    done = {"event": "done"}
    done.update(outcome)
    if outcome.get("ok"):
        done["agent"] = agent["id"]
        done["model"] = model
    emit(done)
