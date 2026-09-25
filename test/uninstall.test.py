#!/usr/bin/env python3
"""bin/uninstall with omarchy, docker and gum faked, so nothing real is removed."""

import os
import pathlib
import shlex
import shutil
import subprocess
import tempfile
import textwrap
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
BIND_LINE = 'o.bind("SUPER + D", "Search", "omarchy-shell shell toggle omaseek")'


class UninstallTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        base = pathlib.Path(self.temporary.name)
        self.config = base / "config"
        self.runtime = base / "runtime"
        self.log = base / "calls.log"
        self.log.touch()
        self.fake_bin = base / "fakes"
        self.fake_bin.mkdir()
        self.bindings = self.config / "hypr" / "bindings.lua"
        self.bindings.parent.mkdir(parents=True)
        self.bindings.write_text(f'o.bind("SUPER + RETURN", "Terminal", "x")\n\n-- omaseek\n{BIND_LINE}\n')

        # A copy of the plugin's bin, so its searxng-up is the one that runs.
        self.plugin = base / "omaseek"
        (self.plugin / "bin").mkdir(parents=True)
        for name in ("uninstall", "searxng-up", "keybind"):
            shutil.copy2(ROOT / "bin" / name, self.plugin / "bin" / name)

        log = self.log
        self.fake("omarchy", f'echo "omarchy $*" >> {log}')
        self.fake("hyprctl", f'echo "hyprctl $*" >> {log}')
        self.fake("docker", f'echo "docker $*" >> {log}; [[ $1 != ps ]] || echo searxng')
        # This machine's own Podman and daemons stay out of it.
        self.fake("podman", "exit 1")
        self.fake("systemctl", "exit 0")
        # Answers each question from $GUM_ANSWERS in turn: y or n.
        self.fake("gum", textwrap.dedent(f"""\
            echo "gum $*" >> {log}
            n=$(grep -c '^gum ' {log})
            answer=$(cut -c"$n" <<<"$GUM_ANSWERS")
            [[ $answer == y ]]
        """))

    def fake(self, name, body):
        path = self.fake_bin / name
        path.write_text("#!/usr/bin/env bash\n" + body)
        path.chmod(0o755)

    def run_uninstall(self, *args, answers="", tty=False, path=None):
        env = dict(os.environ, XDG_CONFIG_HOME=str(self.config), OMARCHY_PATH=str(self.config / "no-omarchy"), GUM_ANSWERS=answers,
                   XDG_RUNTIME_DIR=str(self.runtime), XDG_STATE_HOME=str(self.config / "state"),
                   PATH=path or f"{self.fake_bin}:{os.environ['PATH']}")
        command = [str(self.plugin / "bin" / "uninstall"), *args]
        if tty:
            command = [shutil.which("script", path=env["PATH"]), "-qec", shlex.join(command), "/dev/null"]
        return subprocess.run(command, capture_output=True, text=True, env=env, stdin=subprocess.DEVNULL)

    def calls(self):
        return self.log.read_text()

    def test_asks_about_searxng_and_removes_it_when_told_to(self):
        done = self.run_uninstall(answers="yy", tty=True)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("gum confirm Also remove the SearXNG", self.calls())
        self.assertIn("docker rm -f searxng", self.calls())
        self.assertIn("docker image rm searxng/searxng@sha256:38ed750807fb00c26047e51896b50f83e7843d120d9e65f950770305f62c7111", self.calls())
        self.assertIn("omarchy plugin remove omaseek --yes", self.calls())
        self.assertNotIn(BIND_LINE, self.bindings.read_text())
        self.assertNotIn("-- omaseek", self.bindings.read_text())
        self.assertIn("SUPER + RETURN", self.bindings.read_text(), "other bindings stay")

    def test_answering_no_keeps_searxng_but_still_removes_the_plugin(self):
        done = self.run_uninstall(answers="yn", tty=True)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertNotIn("docker rm", self.calls())
        self.assertIn("SearXNG left in place", done.stdout)
        self.assertIn("omarchy plugin remove omaseek --yes", self.calls())

    def test_declining_the_plugin_removes_nothing_and_asks_nothing_more(self):
        done = self.run_uninstall(answers="n", tty=True)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertNotIn("SearXNG", self.calls())
        self.assertNotIn("omarchy plugin remove", self.calls())
        self.assertIn(BIND_LINE, self.bindings.read_text())

    def test_without_docker_there_is_nothing_to_ask(self):
        (self.fake_bin / "docker").unlink()
        # Only the tools the script needs, so a real docker cannot be found.
        for tool in ("bash", "env", "awk", "grep", "cp", "cut", "dirname", "mkdir", "touch", "rm", "script", "sed", "head", "find"):
            (self.fake_bin / tool).symlink_to(shutil.which(tool))
        done = self.run_uninstall(answers="y", tty=True, path=str(self.fake_bin))
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertNotIn("SearXNG", self.calls() + done.stdout)

    def test_flags_decide_without_a_terminal(self):
        done = self.run_uninstall("--yes", "--keep-searxng")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertNotIn("gum", self.calls())
        self.assertNotIn("docker rm", self.calls())
        self.assertIn("omarchy plugin remove omaseek --yes", self.calls())

    def test_marks_searxng_as_decided_so_the_panel_does_not_ask_again(self):
        self.run_uninstall("--yes", "--keep-searxng")
        self.assertTrue((self.runtime / "omaseek-removal" / "searxng-decided").exists())

    def test_refuses_to_guess_without_a_terminal(self):
        done = self.run_uninstall()
        self.assertNotEqual(done.returncode, 0)
        self.assertNotIn("omarchy plugin remove", self.calls())


if __name__ == "__main__":
    unittest.main()
