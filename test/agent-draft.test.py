import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
DRAFT = runpy.run_path(str(ROOT / 'bin/agent-draft'))
ASK = runpy.run_path(str(ROOT / 'bin/ask'))


class DraftTests(unittest.TestCase):
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
