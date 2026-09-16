import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
DRAFT = runpy.run_path(str(ROOT / 'bin/agent-draft'))
ASK = runpy.run_path(str(ROOT / 'bin/ask'))


class DraftTests(unittest.TestCase):
    def test_model_catalogue_parsers_ignore_banners_and_unrelated_help(self):
        parse = ASK['parse_model_list']
        self.assertEqual(parse('opencode', 'Models:\n\x1b[32mopenai/one\x1b[0m\nlocal/two\nopenai/one\n'),
                         ['openai/one', 'local/two'])
        self.assertEqual(parse('cursor-agent', 'Available models\nsonnet-4 - Sonnet 4\nauto - Auto (current)\n'),
                         ['sonnet-4', 'auto'])
        self.assertEqual(parse('copilot', '  `banner`: frequency\n    - "never"\n'
                              '  `model`: model selection\n    - "model-one"\n    - "model-two"\n'
                              '  `theme`: theme selection\n    - "dark"\n'), ['model-one', 'model-two'])

    def test_model_lookup_failure_does_not_trigger_login_or_chat(self):
        lookup = ASK['list_models']
        for result in (subprocess.CompletedProcess([], 1, '', 'Authentication required'),
                       subprocess.TimeoutExpired('opencode', 15)):
            with patch('subprocess.run') as run:
                if isinstance(result, Exception):
                    run.side_effect = result
                else:
                    run.return_value = result
                response = lookup({'id': 'opencode'})
                self.assertEqual(response['models'], [])
                self.assertFalse(response['ok'])
                self.assertNotIn('login', response)
                self.assertEqual(run.call_count, 1)
                self.assertEqual(run.call_args.kwargs['stdin'], subprocess.DEVNULL)

    def test_codex_model_cache_only_offers_visible_models_and_handles_bad_files(self):
        lookup = ASK['list_models']
        with tempfile.TemporaryDirectory() as directory:
            with patch.dict(os.environ, CODEX_HOME=directory):
                cache = Path(directory) / 'models_cache.json'
                self.assertEqual(lookup({'id': 'codex'})['models'], [])
                cache.write_text('{"models":[{"slug":"visible","visibility":"list"},'
                                 '{"slug":"hidden","visibility":"hide"},{"slug":42},null]}')
                self.assertEqual(lookup({'id': 'codex'})['models'], ['visible'])
                for content in ('not json', 'null', '{"models":null}'):
                    cache.write_text(content)
                    self.assertEqual(lookup({'id': 'codex'})['models'], [])

    def test_model_selection_is_per_resolved_agent_with_payload_override(self):
        choose = ASK['chosen_model']
        config = {'chat_models': {'claude': 'sonnet', 'codex': 'custom-model'}}
        self.assertEqual(choose({}, config, {'id': 'claude'}), '', 'no catalogue means CLI default')
        self.assertEqual(choose({}, config, {'id': 'codex'}), 'custom-model')
        self.assertEqual(choose({}, config, {'id': 'gemini'}), '')
        self.assertEqual(choose({'model': ' opus '}, config, {'id': 'claude'}), 'opus')
        self.assertEqual(choose({'model': ''}, config, {'id': 'claude'}), '')
        for models in (None, [], 'sonnet', {'claude': 42}, {'claude': 'bad\x00id'}):
            self.assertEqual(choose({}, {'chat_models': models}, {'id': 'claude'}), '')

    def test_agent_without_model_catalogue_reports_default_only(self):
        response = ASK['list_models']({'id': 'claude'})
        self.assertTrue(response['ok'])
        self.assertEqual(response['models'], [])
        self.assertIn('using default', response['message'])

    def test_model_reaches_chat_and_unsent_draft_for_every_agent(self):
        for original in ASK['AGENTS']:
            with self.subTest(agent=original['id']):
                model = 'provider/custom-model'
                agent = ASK['with_model'](original, model)
                self.assertNotIn('--model', original['chat'])
                self.assertEqual(agent['login'], original['login'])
                run_chat = ASK['run_chat']
                with tempfile.TemporaryDirectory() as directory:
                    with patch.dict(run_chat.__globals__, WORK_DIR=directory):
                        with patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0, 'answer', '')) as run:
                            self.assertEqual(run_chat(agent, 'question'), 'answer')
                    command = run.call_args.args[0]
                    self.assertEqual(command[command.index('--model') + 1], model)
                    self.assertEqual(command[-1], 'question')
                    self.assertEqual(run.call_args.kwargs['stdin'], subprocess.DEVNULL)
                    if command[-2] in ('-p', '-q', '--'):
                        self.assertLess(command.index('--model'), len(command) - 2)
                command = ASK['interactive_command'](agent, 'draft text')
                try:
                    self.assertEqual(command[command.index('--model') + 1], model)
                    self.assertEqual(Path(command[1]).read_text(), 'draft text')
                    self.assertNotIn('draft text', command[3:])
                    for flag in ['--prompt', '--prompt-interactive', '--query', '--interactive']:
                        self.assertNotIn(flag, command[3:])
                finally:
                    os.unlink(command[1])
                self.assertIs(ASK['with_model'](original, ''), original)

    def test_bracketed_paste_has_no_submit_or_embedded_escape(self):
        pasted = DRAFT['paste_bytes']('one\r\ntwo\x1b[201~\x03')
        self.assertEqual(pasted, b'\x1b[200~one\ntwo[201~\x1b[201~')
        self.assertFalse(pasted.endswith(b'\r'))

    def test_every_agent_starts_without_a_prompt_argument(self):
        for agent in ASK['AGENTS']:
            command = ASK['interactive_command'](agent, 'draft text')
            try:
                self.assertEqual(Path(command[1]).read_text(), 'draft text')
                self.assertNotIn('draft text', command[3:])
                for flag in ['--prompt', '--prompt-interactive', '--query', '--interactive']:
                    self.assertNotIn(flag, command[3:])
            finally:
                os.unlink(command[1])

    def test_real_pty_pastes_only_after_editor_enables_bracketed_paste(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prompt = root / 'prompt'
            captured = root / 'captured'
            prompt.write_text('first\nsecond')
            fake = root / 'editor.py'
            fake.write_text('''import os, select, sys, time, tty
from pathlib import Path
tty.setraw(0)
assert not select.select([0], [], [], 0.2)[0], 'paste arrived before editor ready'
os.write(1, b'\\x1b[?20')
time.sleep(0.05)
os.write(1, b'04h')
data = b''
while not data.endswith(b'\\x1b[201~'):
    os.write(1, b'\\x1b[?2026hframe\\x1b[?2026l')
    if select.select([0], [], [], 0.05)[0]:
        data += os.read(0, 4096)
assert not select.select([0], [], [], 0.2)[0], 'extra submit/input followed paste'
Path(sys.argv[1]).write_bytes(data)
''')
            result = subprocess.run([sys.executable, str(ROOT / 'bin/agent-draft'),
                                     str(prompt), '--', sys.executable, str(fake), str(captured)],
                                    stdin=subprocess.DEVNULL, capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(captured.read_bytes(), b'\x1b[200~first\nsecond\x1b[201~')
            self.assertFalse(prompt.exists())


if __name__ == '__main__':
    unittest.main()
