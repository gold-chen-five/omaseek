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
LINE = 'o.bind("SUPER + d", "Search", "omarchy-shell shell toggle omaseek")'
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
        self.assertEqual(self.status(), {**self.status(), "state": "bound", "key": "SUPER + s"})

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

    def test_another_key_can_be_chosen_in_any_spelling(self):
        self.assertEqual(self.status_for("super+shift+s"), {**self.status_for("super+shift+s"), "state": "free", "key": "SUPER + SHIFT + s"})
        self.run_keybind("--add", "--yes", "--key", "shift + Super + s")
        self.assertIn('o.bind("SUPER + SHIFT + s", "Search", "omarchy-shell shell toggle omaseek")', self.bindings.read_text())
        self.assertEqual(self.status(), {**self.status(), "state": "bound", "key": "SUPER + SHIFT + s", "managed": True})

    def test_a_key_is_taken_whatever_its_spelling(self):
        self.bindings.write_text('o.bind("SUPER+s", "Notes", "obsidian")\n')
        self.assertEqual(self.status_for("SUPER + S")["state"], "taken")
        self.run_keybind("--add", "--yes", "--key", "SUPER + S")
        self.assertNotIn("toggle omaseek", self.bindings.read_text())

    def test_the_line_it_added_is_changed_in_place_after_asking(self):
        self.run_keybind("--add", "--yes")
        done = self.run_keybind("--add", "--key", "SUPER + ALT + SPACE")
        self.assertIn("- " + LINE, done.stdout, "the old line and the new are shown before the question")
        text = self.bindings.read_text()
        self.assertTrue(text.endswith('\n-- omaseek\no.bind("SUPER + ALT + SPACE", "Search", "omarchy-shell shell toggle omaseek")\n'))
        self.assertEqual(text.count("toggle omaseek"), 1, "changed, not added twice")
        self.run_keybind("--remove")
        self.assertEqual(self.bindings.read_text(), MINE, "and removal still gives back the file it found")

    def test_asked_about_another_key_while_bound_it_says_whether_that_one_is_free(self):
        self.run_keybind("--add", "--yes")
        self.assertNotIn("wanted", self.status(), "the key it has is not another")
        self.assertEqual(self.status_for("SUPER + S")["wanted"], "SUPER + s")
        self.assertNotIn("holder", self.status_for("SUPER + S"))
        (self.defaults / "utilities.lua").write_text('o.bind("SUPER + SPACE", "Launcher", "walker")\n')
        self.assertIn("walker", self.status_for("super + space")["holder"])

    def test_changing_to_a_taken_key_leaves_the_old_one(self):
        self.run_keybind("--add", "--yes")
        (self.defaults / "utilities.lua").write_text('o.bind("SUPER + SPACE", "Launcher", "walker")\n')
        self.run_keybind("--add", "--yes", "--key", "SUPER + SPACE")
        self.assertIn(LINE, self.bindings.read_text())

    def test_a_hand_written_binding_is_never_changed_to_another_key(self):
        mine = 'o.bind("SUPER + D", "Web search", "omarchy-shell shell toggle omaseek")\n'
        self.bindings.write_text(mine)
        self.assertFalse(self.status()["managed"])
        done = self.run_keybind("--add", "--yes", "--key", "SUPER + S")
        self.assertIn("a line you wrote", done.stdout)
        self.assertEqual(self.bindings.read_text(), mine)

    def test_what_is_not_a_key_is_refused(self):
        for raw in ("d", "SUPER +", "SUPER + SUPER + D", "HYPER + D", "SUPER + D;rm", "SUPER + SHIFT"):
            answer = self.status_for(raw)
            self.assertFalse(answer["ok"], raw)
            self.assertIn("a modifier and a key", answer["message"])
            self.assertNotEqual(self.run_keybind("--add", "--yes", "--key", raw).returncode, 0, raw)
        self.assertEqual(self.bindings.read_text(), MINE)

    def status_for(self, key):
        done = self.run_keybind("--status", "--key", key)
        self.assertEqual(done.returncode, 0, done.stderr)
        return json.loads(done.stdout)


if __name__ == "__main__":
    unittest.main()
