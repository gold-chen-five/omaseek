#!/usr/bin/env python3
"""bin/install on a README install — a clone made straight into the plugins
directory — with omarchy's commands faked, so nothing touches the real shell."""

import os
import pathlib
import shutil
import subprocess
import tempfile
import textwrap
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        base = pathlib.Path(self.temporary.name)
        self.home = base / "home"
        self.config = self.home / ".config"
        self.data = self.home / ".local" / "share"
        self.log = base / "calls.log"
        self.log.touch()
        self.fake_bin = base / "bin"
        self.fake_bin.mkdir()
        (self.config / "hypr").mkdir(parents=True)
        (self.config / "hypr" / "bindings.lua").write_text('o.bind("SUPER + RETURN", "Terminal", "x")\n')

        log = self.log
        shell_json = self.config / "omarchy" / "shell.json"
        self.fake("omarchy-shell", f'echo "omarchy-shell $*" >> {log}')
        self.fake("hyprctl", f'echo "hyprctl $*" >> {log}')
        self.fake("omarchy-restart-shell", f'echo "omarchy-restart-shell" >> {log}')
        self.fake("omarchy", textwrap.dedent(f"""\
            echo "omarchy $*" >> {log}
            if [[ $1 == bar && $2 == put ]]; then
              mkdir -p {shell_json.parent}
              echo '{{"bar":{{"layout":{{"center":["omaseek"]}}}}}}' > {shell_json}
            fi
        """))

        # The README's clone, then this checkout's installer over the committed one.
        self.plugin = self.config / "omarchy" / "plugins" / "omaseek"
        self.plugin.parent.mkdir(parents=True)
        subprocess.run(["git", "clone", "--quiet", str(ROOT), str(self.plugin)], check=True)
        shutil.copy2(ROOT / "bin" / "install", self.plugin / "bin" / "install")

    def fake(self, name, body):
        path = self.fake_bin / name
        path.write_text("#!/usr/bin/env bash\n" + body)
        path.chmod(0o755)

    def install(self):
        env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.config),
                   XDG_DATA_HOME=str(self.data), PATH=f"{self.fake_bin}:{os.environ['PATH']}")
        done = subprocess.run([str(self.plugin / "bin" / "install")], capture_output=True, text=True, env=env)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        return done.stdout + done.stderr

    def calls(self):
        return self.log.read_text()

    def test_a_clone_in_place_keeps_its_git_directory_for_omarchy_plugin_update(self):
        self.install()
        self.assertTrue((self.plugin / ".git").is_dir(), "omarchy plugin update needs a .git directory")
        self.assertNotIn("omarchy-restart-shell", self.calls(), "a first install has nothing old to replace")
        self.assertIn("toggle omaseek", (self.config / "hypr" / "bindings.lua").read_text())

    def test_re_running_after_a_pull_restarts_the_shell_so_the_new_panel_loads(self):
        self.install()
        out = self.install()
        self.assertIn("omarchy-restart-shell", self.calls())
        self.assertIn("restarted omarchy-shell", out)
        self.assertIn("keybind already there", out)

if __name__ == "__main__":
    unittest.main()
