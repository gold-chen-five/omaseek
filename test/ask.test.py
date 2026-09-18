#!/usr/bin/env python3
"""bin/ask's Crush spellings, in-process: nothing here runs an agent."""

import importlib.machinery
import importlib.util
import json
import os
import pathlib
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


def load_ask():
    loader = importlib.machinery.SourceFileLoader("omaseek_ask", str(ROOT / "bin" / "ask"))
    spec = importlib.util.spec_from_loader("omaseek_ask", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


# What crush v0.95.0 printed on stderr, exit 1, with a ChatGPT allowance spent.
CRUSH_OUT_OF_QUOTA = """

   ERROR

  Agent processing failed: failed to start agent processing stream: retry error: too many requests: The usage limit
  has been reached.
"""


class CrushTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ask = load_ask()
        cls.crush = next(agent for agent in cls.ask.AGENTS if agent["id"] == "crush")

    def test_crush_asks_through_run_and_hands_off_as_omarchy_agent_does(self):
        self.assertEqual(self.crush["name"], "Crush")
        self.assertEqual(self.crush["chat"], ["crush", "run", "-q"])
        self.assertEqual(self.crush["launch"], ["crush", "--yolo"])
        self.assertNotIn("stream", self.crush, "crush run prints its reply whole")

    def test_a_chosen_model_reaches_run_but_never_the_interactive_command(self):
        picked = self.ask.with_model(self.crush, "openai/gpt-5.6-luna")
        self.assertEqual(picked["chat"], ["crush", "run", "--model", "openai/gpt-5.6-luna", "-q"])
        self.assertEqual(picked["launch"], ["crush", "--yolo"], "interactive crush refuses --model")
        codex = next(agent for agent in self.ask.AGENTS if agent["id"] == "codex")
        self.assertIn("--model", self.ask.with_model(codex, "gpt-5")["launch"], "the others still get it")

    def test_the_model_list_keeps_only_configured_providers(self):
        text = "aihubmix/DeepSeek-V3\nopenai/gpt-5.6-sol\nopenai/gpt-6-astra\nanthropic/claude-x\nnot a row\n"
        self.assertEqual(self.ask.parse_model_list("crush", text, ["openai"]),
                         ["openai/gpt-5.6-sol", "openai/gpt-6-astra"])
        self.assertEqual(self.ask.parse_model_list("crush", text, []), [], "none configured, none offered")

    def test_providers_are_read_from_both_crush_files_by_name_only(self):
        with tempfile.TemporaryDirectory() as home:
            data = pathlib.Path(home, "data", "crush")
            config = pathlib.Path(home, "config", "crush")
            data.mkdir(parents=True)
            config.mkdir(parents=True)
            (data / "crush.json").write_text(json.dumps({"providers": {"openai": {"oauth": {"token": "secret"}}}}))
            (config / "crush.json").write_text(json.dumps({"providers": {"anthropic": {}, "openai": {}}}))
            saved = {key: os.environ.get(key) for key in ("XDG_DATA_HOME", "XDG_CONFIG_HOME")}
            os.environ["XDG_DATA_HOME"] = str(pathlib.Path(home, "data"))
            os.environ["XDG_CONFIG_HOME"] = str(pathlib.Path(home, "config"))
            try:
                self.assertEqual(self.ask.crush_providers(), ["openai", "anthropic"])
            finally:
                for key, value in saved.items():
                    if value is None:
                        os.environ.pop(key, None)
                    else:
                        os.environ[key] = value

    def test_a_wrapped_crush_error_is_one_sentence_and_read_as_out_of_allowance(self):
        outcome = self.ask.chat_outcome(self.crush, 1, "", CRUSH_OUT_OF_QUOTA, "")
        self.assertEqual(outcome["error"], "quota")
        self.assertEqual(outcome["message"],
                         "Crush: Agent processing failed: failed to start agent processing stream: "
                         "retry error: too many requests: The usage limit has been reached.")
        self.assertNotIn("login", outcome, "signing in again fixes nothing")

    def test_signing_in_opens_crush_itself_rather_than_charm_hyper(self):
        self.assertEqual(self.ask.fix_command(self.crush, "login"), ["crush"])


class TranslateTests(unittest.TestCase):
    """--translate's prompt and agent, in-process: nothing here runs an agent."""

    @classmethod
    def setUpClass(cls):
        cls.ask = load_ask()

    def test_the_prompt_names_the_target_and_asks_for_the_translation_alone(self):
        prompt = self.ask.build_translation_prompt("ownership", "zh-TW")
        self.assertIn("into Traditional Chinese (as written in Taiwan)", prompt)
        self.assertIn("translate it into English instead", prompt)
        self.assertIn("Reply with the translation only", prompt)
        self.assertTrue(prompt.endswith("Text:\nownership"))
        self.assertNotIn("desktop search panel", prompt, "no panel preamble, no conversation")

    def test_english_as_the_target_turns_back_into_traditional_chinese(self):
        prompt = self.ask.build_translation_prompt("所有權", "en")
        self.assertIn("into English.", prompt)
        self.assertIn("into Traditional Chinese (as written in Taiwan) instead", prompt)

    def test_an_unknown_target_is_the_default_rather_than_a_guess(self):
        self.assertEqual(self.ask.translate_target("klingon"), "zh-TW")
        self.assertEqual(self.ask.translate_target("ja"), "ja")

    def test_a_translation_asks_claude_without_its_web_tools(self):
        claude = next(agent for agent in self.ask.AGENTS if agent["id"] == "claude")
        chat = self.ask.without_web(claude)["chat"]
        self.assertNotIn("WebSearch", chat)
        self.assertNotIn("--allowedTools", chat)
        self.assertIn("WebSearch", claude["chat"], "and Ask keeps them")


if __name__ == "__main__":
    unittest.main()
