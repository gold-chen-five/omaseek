#!/usr/bin/env python3
"""bin/keybind: which state the Settings row shows, and a line added only when
the key is free, taken out again exactly. hyprctl and gum are faked."""

import json
import os
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
LINE = 'o.bind("SUPER + D", "Search", "omarchy-shell shell toggle omaseek")'
MINE = 'o.bind("SUPER + RETURN", "Terminal", "x")\n\no.bind("SUPER + B", "Browser", "y")\n'


class KeybindTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        base = pathlib.Path(self.temporary.name)
        self.log = base / "calls.log"
        self.log.touch()
        self.bindings = base / "config" / "hypr" / "bindings.lua"
        self.bindings.parent.mkdir(parents=True)
        self.bindings.write_text(MINE)
        self.defaults = base / "omarchy" / "default" / "hypr" / "bindings"
        self.defaults.mkdir(parents=True)

        fakes = base / "fakes"
        fakes.mkdir()
        for name, body in (("hyprctl", f'echo "hyprctl $*" >> {self.log}'),
                           ("gum", f'echo "gum $*" >> {self.log}; [[ $GUM_ANSWER == y ]]')):
            (fakes / name).write_text("#!/usr/bin/env bash\n" + body)
            (fakes / name).chmod(0o755)
        self.env = dict(os.environ, XDG_CONFIG_HOME=str(base / "config"), OMARCHY_PATH=str(base / "omarchy"),
                        PATH=f"{fakes}:{os.environ['PATH']}", GUM_ANSWER="y")

    def run_keybind(self, *args):
        return subprocess.run(["bash", str(ROOT / "bin" / "keybind"), *args], capture_output=True, text=True,
                              env=self.env, stdin=subprocess.DEVNULL)

    def status(self):
        done = self.run_keybind("--status")
        self.assertEqual(done.returncode, 0, done.stderr)
        return json.loads(done.stdout)

    def test_a_free_key_is_offered(self):
        self.assertEqual(self.status()["state"], "free")

    def test_adding_asks_then_appends_one_line_after_a_backup(self):
        done = self.run_keybind("--add")
        self.assertIn(LINE, done.stdout, "the line is shown before the question")
        self.assertIn("gum confirm", self.log.read_text())
        self.assertTrue(self.bindings.read_text().endswith(f"\n-- omaseek\n{LINE}\n"))
        self.assertEqual(pathlib.Path(f"{self.bindings}.omaseek-backup").read_text(), MINE)
        self.assertIn("hyprctl reload", self.log.read_text())
        self.assertEqual(self.status()["state"], "bound")

    def test_no_leaves_the_file_as_it_was(self):
        self.env["GUM_ANSWER"] = "n"
        self.run_keybind("--add")
        self.assertEqual(self.bindings.read_text(), MINE)
        self.assertNotIn("hyprctl", self.log.read_text())

    def test_yes_skips_the_question_for_bin_install(self):
        self.run_keybind("--add", "--yes")
        self.assertNotIn("gum", self.log.read_text())
        self.assertIn(LINE, self.bindings.read_text())

    def test_adding_twice_adds_once(self):
        self.run_keybind("--add", "--yes")
        self.run_keybind("--add", "--yes")
        self.assertEqual(self.bindings.read_text().count(LINE), 1)

    def test_a_key_the_user_bound_is_never_replaced(self):
        self.bindings.write_text('o.bind("SUPER + D", "Notes", "obsidian")\n')
        self.assertEqual(self.status()["state"], "taken")
        self.assertIn("obsidian", self.status()["holder"])
        self.run_keybind("--add", "--yes")
        self.assertNotIn("toggle omaseek", self.bindings.read_text())

    def test_a_key_omarchy_binds_by_default_counts_as_taken(self):
        (self.defaults / "utilities.lua").write_text('o.bind("SUPER + D", "Dictation", "z")\n')
        self.assertEqual(self.status()["state"], "taken")

    def test_a_commented_out_binding_binds_nothing(self):
        self.bindings.write_text('-- o.bind("SUPER + D", "Notes", "obsidian")\n')
        self.assertEqual(self.status()["state"], "free")

    def test_a_hand_written_binding_to_omaseek_counts_whatever_its_key(self):
        self.bindings.write_text('o.bind("SUPER + S", "Web search", "omarchy-shell shell toggle omaseek")\n')
        self.assertEqual(self.status(), {**self.status(), "state": "bound", "key": "SUPER + S"})

    def test_no_bindings_file_says_where_the_line_goes(self):
        self.bindings.unlink()
        self.assertEqual(self.status()["state"], "missing")
        self.assertEqual(self.status()["line"], LINE)

    def test_removing_gives_back_the_file_it_found(self):
        self.run_keybind("--add", "--yes")
        self.assertEqual(self.run_keybind("--present").returncode, 0)
        self.run_keybind("--remove")
        self.assertEqual(self.bindings.read_text(), MINE)
        self.assertNotEqual(self.run_keybind("--present").returncode, 0)

    def test_removing_leaves_a_hand_written_binding(self):
        self.bindings.write_text('o.bind("SUPER + D", "Web search", "omarchy-shell shell toggle omaseek")\n')
        self.run_keybind("--remove")
        self.assertIn("Web search", self.bindings.read_text())


if __name__ == "__main__":
    unittest.main()
