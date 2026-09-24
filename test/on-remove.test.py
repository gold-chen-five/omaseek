#!/usr/bin/env python3
"""bin/on-remove: staged out of the plugin, then asking only after a real removal.
docker, the terminal, gum and sleep are faked, so nothing real is touched."""

import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class OnRemoveTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        base = pathlib.Path(self.temporary.name)
        self.log = base / "calls.log"
        self.log.touch()
        self.runtime = base / "runtime"
        self.runtime.mkdir()
        self.stage = self.runtime / "omaseek-removal"
        config = base / "config"

        # The installed plugin, with this checkout's scripts in it.
        self.plugin = config / "omarchy" / "plugins" / "omaseek"
        (self.plugin / "bin").mkdir(parents=True)
        (self.plugin / "manifest.json").write_text("{}")
        for name in ("on-remove", "searxng-up", "keybind"):
            shutil.copy2(ROOT / "bin" / name, self.plugin / "bin" / name)

        self.fake_bin = base / "fakes"
        self.fake_bin.mkdir()
        log = self.log
        self.fake("docker", f'echo "docker $*" >> {log}; [[ $1 != ps ]] || echo searxng')
        self.fake("xdg-terminal-exec", f'echo "terminal $*" >> {log}')
        self.fake("gum", f'echo "gum $*" >> {log}; [[ $GUM_ANSWER == y ]]')
        self.fake("sleep", "exit 0")

        self.bindings = config / "hypr" / "bindings.lua"
        self.bindings.parent.mkdir(parents=True)
        self.bindings.write_text('o.bind("SUPER + RETURN", "Terminal", "x")\n')
        self.fake("hyprctl", f'echo "hyprctl $*" >> {log}')

        self.first_run = base / "data" / "omaseek" / "first-run.json"
        self.first_run.parent.mkdir(parents=True)
        self.first_run.write_text('{"version":1,"done":true}\n')
        self.env = dict(os.environ, XDG_RUNTIME_DIR=str(self.runtime), XDG_CONFIG_HOME=str(config),
                        XDG_DATA_HOME=str(base / "data"),
                        OMARCHY_PATH=str(base / "no-omarchy"),
                        PATH=f"{self.fake_bin}:{os.environ['PATH']}", GUM_ANSWER="n")

    def fake(self, name, body):
        path = self.fake_bin / name
        path.write_text("#!/usr/bin/env bash\n" + body)
        path.chmod(0o755)

    def run_script(self, path, flag):
        done = subprocess.run(["bash", str(path), flag], capture_output=True, text=True,
                              env=self.env, stdin=subprocess.DEVNULL)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        return done

    def stage_and_remove(self):
        self.run_script(self.plugin / "bin" / "on-remove", "--stage")
        shutil.rmtree(self.plugin)              # what omarchy plugin remove does next

    def calls(self):
        return self.log.read_text()

    def test_staging_copies_the_scripts_out_of_the_plugin(self):
        self.stage_and_remove()
        self.assertTrue((self.stage / "on-remove").is_file())
        self.assertTrue((self.stage / "searxng-up").is_file())
        self.assertTrue((self.stage / "keybind").is_file())

    def test_a_disable_or_reload_asks_nothing(self):
        self.run_script(self.plugin / "bin" / "on-remove", "--stage")
        self.run_script(self.stage / "on-remove", "--watch")
        self.assertNotIn("terminal", self.calls())
        self.assertTrue((self.stage / "on-remove").is_file(), "kept for the next unload")

    def test_a_removal_forgets_the_welcome_and_a_disable_does_not(self):
        self.run_script(self.plugin / "bin" / "on-remove", "--stage")
        self.run_script(self.stage / "on-remove", "--watch")
        self.assertTrue(self.first_run.exists(), "a disable or reload keeps it")
        self.fake("docker", f'echo "docker $*" >> {self.log}; [[ $1 == info ]]')
        shutil.rmtree(self.plugin)
        self.run_script(self.stage / "on-remove", "--watch")
        self.assertFalse(self.first_run.exists(), "a reinstall opens on the welcome page again")

    def test_the_question_names_the_key_that_was_bound(self):
        self.env["GUM_ANSWER"] = "n"
        subprocess.run(["bash", str(self.plugin / "bin" / "keybind"), "--add", "--yes", "--key", "super+shift+s"],
                       capture_output=True, env=self.env, check=True)
        self.stage_and_remove()
        self.run_script(self.stage / "on-remove", "--ask")
        self.assertIn("gum confirm Remove the SUPER + SHIFT + S line", self.calls())

    def test_a_removal_opens_a_terminal_that_asks(self):
        self.stage_and_remove()
        self.run_script(self.stage / "on-remove", "--watch")
        self.assertIn(f"terminal bash {self.stage / 'on-remove'} --ask", self.calls())

    def test_a_removal_with_no_searxng_asks_nothing(self):
        self.fake("docker", f'echo "docker $*" >> {self.log}; [[ $1 == info ]]')
        self.stage_and_remove()
        self.run_script(self.stage / "on-remove", "--watch")
        self.assertNotIn("terminal", self.calls())
        self.assertFalse(self.stage.exists(), "nothing left behind")

    def test_uninstall_having_asked_already_is_not_asked_twice(self):
        self.stage_and_remove()
        (self.stage / "searxng-decided").touch()
        self.run_script(self.stage / "on-remove", "--watch")
        self.assertNotIn("terminal", self.calls())

    def test_without_a_runtime_dir_nothing_is_staged_in_shared_tmp(self):
        del self.env["XDG_RUNTIME_DIR"]
        self.run_script(self.plugin / "bin" / "on-remove", "--stage")
        self.assertFalse(pathlib.Path("/tmp/omaseek-removal").exists())
        self.assertFalse(self.stage.exists())

    def test_yes_in_the_terminal_removes_the_container_and_image(self):
        self.env["GUM_ANSWER"] = "y"
        self.stage_and_remove()
        self.run_script(self.stage / "on-remove", "--ask")
        self.assertIn("docker rm -f searxng", self.calls())
        self.assertIn("docker image rm searxng/searxng:latest", self.calls())
        self.assertFalse(self.stage.exists())

    def test_no_in_the_terminal_keeps_searxng(self):
        self.stage_and_remove()
        done = self.run_script(self.stage / "on-remove", "--ask")
        self.assertNotIn("docker rm", self.calls())
        self.assertIn("kept", done.stdout)

    def add_keybind(self):
        subprocess.run(["bash", str(self.plugin / "bin" / "keybind"), "--add", "--yes"],
                       capture_output=True, env=self.env, check=True)

    def test_the_keybind_alone_is_worth_asking_about(self):
        self.fake("docker", f'echo "docker $*" >> {self.log}; [[ $1 == info ]]')
        self.add_keybind()
        self.stage_and_remove()
        self.run_script(self.stage / "on-remove", "--watch")
        self.assertIn("--ask", self.calls())

    def test_yes_takes_out_the_line_it_added_and_nothing_else(self):
        self.env["GUM_ANSWER"] = "y"
        self.add_keybind()
        self.stage_and_remove()
        self.run_script(self.stage / "on-remove", "--ask")
        self.assertEqual(self.bindings.read_text(), 'o.bind("SUPER + RETURN", "Terminal", "x")\n')

    def test_no_keeps_the_line(self):
        self.add_keybind()
        self.stage_and_remove()
        self.run_script(self.stage / "on-remove", "--ask")
        self.assertIn("toggle omaseek", self.bindings.read_text())

    def test_a_binding_written_by_hand_is_not_asked_about(self):
        self.env["GUM_ANSWER"] = "y"
        self.bindings.write_text('o.bind("SUPER + D", "Web search", "omarchy-shell shell toggle omaseek")\n')
        self.stage_and_remove()
        self.run_script(self.stage / "on-remove", "--ask")
        self.assertNotIn("SUPER + D line", self.calls())
        self.assertIn("Web search", self.bindings.read_text())


if __name__ == "__main__":
    unittest.main()
