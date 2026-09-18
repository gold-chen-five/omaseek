"""What an agent is asked: a chat turn with the conversation so far in the
prompt, since print mode remembers nothing, or a translation and nothing else."""

def build_prompt(question, history):
    """The whole conversation, since a print-mode process remembers nothing."""
    lines = [
        "You are answering inside a small desktop search panel. Be direct and",
        "reasonably brief; use plain Markdown (paragraphs, lists, code) and no",
        "tables. Search the web when the question needs current facts.",
        "",
    ]
    # The last few turns are plenty of context and keep the argument short.
    history = history[-8:]
    if history:
        lines.append("Conversation so far:")
        for turn in history:
            role = "User" if turn.get("role") == "user" else "Assistant"
            lines.append(f"{role}: {turn.get('text', '')}")
        lines.append("")
    lines.append(f"User: {question}")
    return "\n".join(lines)


# The languages the panel translates into, by the code its setting stores. Mirrored
# as TRANSLATE_LANGUAGES in src/lib/translate.mjs; change both. The name is how
# the prompt says it, so zh-TW is not left for the agent to guess at.
TRANSLATE_LANGUAGES = {
    "zh-TW": "Traditional Chinese (as written in Taiwan)",
    "zh-CN": "Simplified Chinese",
    "en": "English",
    "ja": "Japanese",
    "ko": "Korean",
    "fr": "French",
    "de": "German",
    "es": "Spanish",
    "it": "Italian",
    "pt": "Portuguese",
    "ru": "Russian",
    "vi": "Vietnamese",
    "th": "Thai",
}


DEFAULT_TRANSLATE_TARGET = "zh-TW"


def translate_target(value):
    """A code from the table, or the default: the prompt names a language it knows."""
    code = str(value or "").strip()
    return code if code in TRANSLATE_LANGUAGES else DEFAULT_TRANSLATE_TARGET


def build_translation_prompt(text, target):
    """A translation and nothing else — no panel preamble, no conversation. Text
    already in the target language goes the other way, into English (or, when
    English is the target, into Traditional Chinese), so one key serves both."""
    language = TRANSLATE_LANGUAGES[translate_target(target)]
    other = "Traditional Chinese (as written in Taiwan)" if translate_target(target) == "en" else "English"
    return "\n".join([
        f"Translate the text below into {language}.",
        f"If it is already in {language}, translate it into {other} instead.",
        "Reply with the translation only: no notes, no quotation marks, no",
        "romanisation, no explanation. Keep line breaks, lists and code as they are.",
        "",
        "Text:",
        text,
    ])


def without_web(agent):
    """A translation needs no web search, and a tool call only slows it down:
    the chat spelling with Claude's WebSearch and WebFetch left out."""
    chat = [part for part in agent["chat"] if part not in ("--allowedTools", "WebSearch", "WebFetch")]
    selected = dict(agent)
    selected["chat"] = chat
    return selected
