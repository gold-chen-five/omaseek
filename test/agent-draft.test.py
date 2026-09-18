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
# bin/ask's names, from its package's front door: run_chat.__globals__ is then
# run.py's own, which is where the tests patch WORK_DIR.
sys.path.insert(0, str(ROOT / 'backend'))
import omaseek.ask  # noqa: E402
ASK = vars(omaseek.ask)


CLAUDE = next(a for a in ASK['AGENTS'] if a['id'] == 'claude')


def delta(text):
    return {'type': 'stream_event',
            'event': {'type': 'content_block_delta', 'delta': {'type': 'text_delta', 'text': text}}}


class StreamTests(unittest.TestCase):
    def feed(self, events):
        """The events in order -> what was shown, and what was settled on."""
        parse, state, shown, settled = ASK['claude_event'], {}, [], None
        for event in events:
            text, answer = parse(state, event)
            if text:
                shown.append(text)
            if answer is not None:
                settled = answer
        return ''.join(shown), settled

    def test_token_deltas_are_shown_and_the_result_is_what_is_kept(self):
        shown, settled = self.feed([
            {'type': 'system', 'subtype': 'init'},
            delta('bl'), delta('ue'),
            {'type': 'result', 'subtype': 'success', 'result': 'blue'},
        ])
        self.assertEqual(shown, 'blue')
        self.assertEqual(settled, 'blue')

    def test_a_finished_message_beside_partials_is_not_shown_twice(self):
        # --include-partial-messages sends the whole message as well; taking
        # both would print the answer twice.
        shown, _ = self.feed([
            delta('bl'), delta('ue'),
            {'type': 'assistant', 'message': {'content': [{'type': 'text', 'text': 'blue'}]}},
        ])
        self.assertEqual(shown, 'blue')

    def test_without_partials_the_finished_message_is_all_there_is(self):
        shown, _ = self.feed([
            {'type': 'assistant', 'message': {'content': [
                {'type': 'text', 'text': 'blue'},
                {'type': 'tool_use', 'name': 'WebSearch'},
                {'type': 'text', 'text': ' and green'},
            ]}},
        ])
        self.assertEqual(shown, 'blue and green')

    def test_events_with_nothing_to_say_are_ignored(self):
        shown, settled = self.feed([
            {'type': 'rate_limit_event'},
            {'type': 'stream_event', 'event': {'type': 'message_start'}},
            {'type': 'stream_event', 'event': {'type': 'content_block_delta',
                                               'delta': {'type': 'thinking_delta', 'thinking': 'hmm'}}},
            {'type': 'assistant', 'message': {}},
            {},
        ])
        self.assertEqual(shown, '')
        self.assertIsNone(settled)

    def test_claude_streams_and_the_rest_fall_back(self):
        self.assertIn('--include-partial-messages', CLAUDE['stream'])
        self.assertIn(CLAUDE['stream_format'], ASK['STREAM_PARSERS'])
        # Measured: codex exec --json carries no text deltas, so it has no
        # streaming spelling and takes the whole-answer path.
        for agent in ASK['AGENTS']:
            if agent['id'] != 'claude':
                self.assertNotIn('stream', agent, agent['id'])

    def test_a_model_choice_reaches_the_streaming_spelling(self):
        chosen = ASK['with_model'](CLAUDE, 'claude-opus-5')
        for kind in ('chat', 'stream', 'launch'):
            self.assertIn('--model', chosen[kind], kind)
        # The prompt-consuming flag stays last: the prompt is appended to it.
        self.assertEqual(chosen['stream'][-1], '--')


class OutcomeTests(unittest.TestCase):
    """One classifier for both paths, so a streamed failure reads the same."""

    def outcome(self, code, out, err, text):
        return ASK['chat_outcome']({'id': 'codex', 'name': 'Codex'}, code, out, err, text)

    def test_an_answer_is_an_answer(self):
        self.assertEqual(self.outcome(0, '', '', 'hello'), {'ok': True, 'text': 'hello'})

    def test_signed_out_and_out_of_allowance_stay_apart(self):
        signed_out = self.outcome(1, '', 'Not logged in', '')
        self.assertEqual(signed_out['error'], 'auth')
        self.assertTrue(signed_out['login'])
        # Only being signed out has a sign-in worth opening.
        self.assertEqual(self.outcome(1, '', 'usage limit reached', '')['error'], 'quota')
        self.assertNotIn('login', self.outcome(1, '', 'usage limit reached', ''))

    def test_a_logged_catalogue_is_never_diagnosed(self):
        # The 47KB model catalogue on stderr that once read as a sign-out.
        catalogue = '2024-01-01T00:00:00Z DEBUG please sign in\n' + 'x' * 500 + ' please sign in\n'
        self.assertEqual(self.outcome(1, '', catalogue, 'the answer'), {'ok': True, 'text': 'the answer'})

    def test_nothing_at_all_is_a_failure_even_on_a_clean_exit(self):
        self.assertEqual(self.outcome(0, '', '', '')['error'], 'agent')


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
                    if original.get('launch_model') is False:
                        # Crush: only `crush run` takes --model, so the draft
                        # opens on the CLI's own model rather than failing.
                        self.assertNotIn('--model', command)
                    else:
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


    def run_fake(self, editor, stdin=subprocess.DEVNULL, prompt_text='https://example.org/draft', timeout=15):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prompt = root / 'prompt'
            captured = root / 'captured'
            prompt.write_text(prompt_text)
            fake = root / 'editor.py'
            fake.write_text(editor)
            result = subprocess.run([sys.executable, str(ROOT / 'bin/agent-draft'),
                                     str(prompt), '--', sys.executable, str(fake), str(captured)],
                                    stdin=stdin, capture_output=True, timeout=timeout)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return captured.read_bytes()

    # An agent like OpenCode 1.18: bracketed paste on at once, input box only
    # later, and every paste before that silently dropped.
    SLOW_EDITOR = '''import os, select, sys, time, tty
from pathlib import Path
tty.setraw(0)
os.write(1, b'\\x1b[?2004h')
ready_at = time.monotonic() + {ready}
accepted = []
deadline = time.monotonic() + {deadline}
while time.monotonic() < deadline:
    if select.select([0], [], [], 0.05)[0]:
        data = os.read(0, 4096)
        if time.monotonic() >= ready_at and b'\\x1b[200~' in data:
            accepted.append(data)
            os.write(1, b'\\x1b[2;3H' + data.split(b'\\x1b[200~')[1].split(b'\\x1b[201~')[0])
Path(sys.argv[1]).write_bytes(b'|'.join(accepted))
'''

    def test_a_paste_dropped_before_the_editor_is_ready_is_retried_once_it_is(self):
        accepted = self.run_fake(self.SLOW_EDITOR.format(ready=1.6, deadline=3.6))
        self.assertEqual(accepted, b'\x1b[200~https://example.org/draft\x1b[201~',
                         'the retry landed, and stopped once the draft was on screen')

    def test_terminal_replies_do_not_count_as_the_reader_typing(self):
        # A real terminal answers the agent's capability queries on its input.
        read, write = os.pipe()
        os.write(write, b'\x1b[?62;22c\x1b[?1u\x1b]11;rgb:0000/0000/0000\x07')
        accepted = self.run_fake(self.SLOW_EDITOR.format(ready=1.6, deadline=3.6), stdin=read)
        os.close(write)
        os.close(read)
        self.assertEqual(accepted, b'\x1b[200~https://example.org/draft\x1b[201~')

    def test_typing_stops_the_retries(self):
        read, write = os.pipe()
        os.write(write, b'my own question')
        accepted = self.run_fake(self.SLOW_EDITOR.format(ready=1.6, deadline=3.6), stdin=read)
        os.close(write)
        os.close(read)
        self.assertEqual(accepted, b'', 'no paste may land in the middle of what the reader types')

    def test_a_long_draft_is_confirmed_by_the_pasted_label(self):
        editor = '''import os, select, sys, time, tty
from pathlib import Path
tty.setraw(0)
os.write(1, b'\\x1b[?2004h')
count = 0
deadline = time.monotonic() + 3
while time.monotonic() < deadline:
    if select.select([0], [], [], 0.05)[0] and b'\\x1b[200~' in os.read(0, 4096):
        count += 1
        os.write(1, b'[Pasted ~3 lines]')
Path(sys.argv[1]).write_bytes(str(count).encode())
'''
        self.assertEqual(self.run_fake(editor, prompt_text='one\ntwo\nthree'), b'1', 'shown once, pasted once')

    def test_the_draft_signature_skips_the_scheme_and_survives_styling(self):
        self.assertEqual(DRAFT['signature']('https://www.rust-lang.org/learn\nmore'), 'rust-lang.org/le')
        self.assertTrue(DRAFT['shows_paste'](b'\x1b[31mrust-lang\x1b[0m.org/le\x1b[2Carn',
                                             DRAFT['signature']('https://www.rust-lang.org/learn')))
        self.assertFalse(DRAFT['shows_paste'](b'Ask anything https://opencode.ai', 'example.org/draf'))


if __name__ == '__main__':
    unittest.main()
