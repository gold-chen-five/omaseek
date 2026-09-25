#!/usr/bin/env python3

import os
import pathlib
import subprocess
import tempfile
import textwrap
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin" / "searxng-up"
PINNED = "searxng/searxng@sha256:38ed750807fb00c26047e51896b50f83e7843d120d9e65f950770305f62c7111"
NEWEST_TAG = "2026.9.30-abcdef123"
NEWEST_DIGEST = "sha256:" + "b" * 64
NEWEST = "searxng/searxng@" + NEWEST_DIGEST
PODMAN_PINNED = "docker.io/" + PINNED


class SearxngUpdateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = pathlib.Path(self.temporary.name)
        self.fake_bin = self.base / "bin"
        self.state = self.base / "state"
        self.fake_bin.mkdir()
        self.state.mkdir()
        (self.state / "log").touch()

        self.write_executable(
            "docker",
            r"""
            #!/usr/bin/env bash
            set -euo pipefail

            state=${FAKE_DOCKER_STATE:?}
            printf '%s\n' "$*" >> "$state/log"
            command=${1:-}
            shift || true

            record_image() {
              printf '%s\n' "$1" > "$state/container_ref"
              if [[ $1 == *searxng/searxng[:@]* ]]; then
                cp "$state/local_image" "$state/container_image"
              else
                printf '%s\n' "$1" > "$state/container_image"
              fi
            }

            case "$command" in
              info)
                exit 0
                ;;
              ps)
                [[ ! -f $state/fail_ps ]] || exit 45
                if [[ ${1:-} == -a ]]; then
                  [[ -f $state/exists ]] && printf '%s\n' searxng
                else
                  [[ -f $state/running ]] && printf '%s\n' searxng
                fi
                exit 0
                ;;
              inspect|container)
                [[ ${1:-} != inspect ]] || shift
                [[ -f $state/exists ]]
                if [[ $* == *Config.Image* ]]; then cat "$state/container_ref"; else cat "$state/container_image"; fi
                ;;
              image)
                case ${1:-} in
                  inspect) [[ -f $state/local_image ]] && cat "$state/local_image" ;;
                  rm) [[ ! -f $state/image_in_use ]] || exit 46; rm -f "$state/local_image" ;;
                  *) exit 91 ;;
                esac
                ;;
              pull)
                [[ ! -f $state/fail_pull ]] || exit 42
                cp "$state/remote_image" "$state/local_image"
                ;;
              rm)
                rm -f "$state/exists" "$state/running" "$state/container_image"
                if [[ -f $state/signal_every_remove ]]; then
                  kill -TERM "$PPID"
                  /bin/sleep 0.05
                elif [[ -f $state/signal_after_remove && ! -f $state/signalled ]]; then
                  touch "$state/signalled"
                  kill -TERM "$PPID"
                  /bin/sleep 0.05
                fi
                ;;
              run)
                image=${!#}
                [[ ! -f $state/fail_run_new || $image != *searxng/searxng[:@]* ]] || exit 43
                touch "$state/exists" "$state/running"
                record_image "$image"
                ;;
              create)
                image=${!#}
                [[ ! -f $state/fail_create_new || $image != *searxng/searxng[:@]* ]] || exit 44
                touch "$state/exists"
                rm -f "$state/running"
                record_image "$image"
                ;;
              start)
                touch "$state/running"
                ;;
              stop)
                rm -f "$state/running"
                ;;
              *)
                printf 'unexpected fake docker command: %s\n' "$command" >&2
                exit 90
                ;;
            esac
            """,
        )
        self.write_executable(
            "python3",
            r"""
            #!/usr/bin/env bash
            set -euo pipefail
            state=${FAKE_DOCKER_STATE:?}
            # bin/search --newest-image, which bin/searxng-up runs through this.
            if [[ ${2:-} == --newest-image ]]; then
              [[ -f $state/newest ]] || exit 1
              cat "$state/newest"
              exit 0
            fi
            if [[ -f $state/fail_health_for_new && -f $state/container_image ]]; then
              current=$(<"$state/container_image")
              latest=$(<"$state/local_image")
              [[ $current != "$latest" ]] || exit 1
            fi
            exit 0
            """,
        )
        self.write_executable(
            "date",
            r"""
            #!/usr/bin/env bash
            set -euo pipefail
            state=${FAKE_DOCKER_STATE:?}
            now=0
            [[ ! -f $state/clock ]] || now=$(<"$state/clock")
            printf '%s\n' "$now"
            printf '%s\n' "$((now + 61))" > "$state/clock"
            """,
        )
        self.write_executable("sleep", "#!/usr/bin/env bash\nexit 0\n")
        # The same fake behind podman, with a state of its own; absent unless a
        # test sets FAKE_PODMAN_STATE, so this machine's Podman is never reached.
        self.write_executable(
            "podman",
            f"""
            #!/usr/bin/env bash
            [[ -n ${{FAKE_PODMAN_STATE:-}} ]] || exit 1
            FAKE_DOCKER_STATE=$FAKE_PODMAN_STATE exec {self.fake_bin}/docker "$@"
            """,
        )
        self.write_executable(
            "systemctl",
            f"""
            #!/usr/bin/env bash
            printf '%s\\n' "$*" >> {self.state}/systemctl
            [[ $* != *is-enabled* ]]
            """,
        )
        self.pstate = self.base / "pstate"
        self.pstate.mkdir()
        (self.pstate / "log").touch()

        (self.state / "newest").write_text(f"{NEWEST_TAG} {NEWEST_DIGEST}\n", encoding="utf-8")
        self.choice = self.base / "state-home" / "omaseek" / "searxng-image"

        self.env = os.environ.copy()
        self.env.update(
            {
                "HOME": str(self.base / "home"),
                "XDG_CONFIG_HOME": str(self.base / "config"),
                "XDG_STATE_HOME": str(self.base / "state-home"),
                "FAKE_DOCKER_STATE": str(self.state),
                "OMASEEK_ENGINE": "docker",
                "PATH": f"{self.fake_bin}:/usr/bin:/bin",
            }
        )

    def write_executable(self, name, source):
        path = self.fake_bin / name
        path.write_text(textwrap.dedent(source).lstrip(), encoding="utf-8")
        path.chmod(0o755)

    def arrange_container(self, previous, latest, running=True, local=None, ref="searxng/searxng:latest"):
        (self.state / "exists").touch()
        (self.state / "container_ref").write_text(ref + "\n", encoding="utf-8")
        if running:
            (self.state / "running").touch()
        (self.state / "container_image").write_text(previous + "\n", encoding="utf-8")
        (self.state / "local_image").write_text((local or previous) + "\n", encoding="utf-8")
        (self.state / "remote_image").write_text(latest + "\n", encoding="utf-8")

    def run_mode(self, mode):
        return subprocess.run([str(SCRIPT), mode], cwd=ROOT, env=self.env, text=True,
                              capture_output=True, check=False)

    def run_update(self, close_stderr=False, answer="y\n"):
        command = [str(SCRIPT), "--update"]
        if close_stderr:
            command = ["bash", "-c", 'exec 2>&-; exec "$1" --update', "bash", str(SCRIPT)]
        return subprocess.run(
            command,
            cwd=ROOT,
            env=self.env,
            input=answer,
            text=True,
            capture_output=True,
            check=False,
        )

    def commands(self, state=None):
        return ((state or self.state) / "log").read_text(encoding="utf-8").splitlines()

    def with_podman(self, engine="podman"):
        self.env["FAKE_PODMAN_STATE"] = str(self.pstate)
        if engine:
            self.env["OMASEEK_ENGINE"] = engine
        else:
            del self.env["OMASEEK_ENGINE"]
        (self.pstate / "local_image").write_text("sha256:pinned\n", encoding="utf-8")

    def engine_file(self):
        return self.base / "state-home" / "omaseek" / "searxng-engine"

    def test_running_container_is_replaced_only_after_the_pull(self):
        self.arrange_container("sha256:old", "sha256:new")

        result = self.run_update()

        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.commands()
        pull = commands.index(f"pull {NEWEST}")
        inspect = next(i for i, command in enumerate(commands) if command.startswith("image inspect"))
        remove = next(i for i, command in enumerate(commands) if command.startswith("rm -f"))
        run = next(i for i, command in enumerate(commands) if command.startswith("run -d"))
        self.assertLess(pull, inspect)
        self.assertLess(pull, remove)
        self.assertLess(remove, run)
        self.assertEqual((self.state / "container_image").read_text().strip(), "sha256:new")
        self.assertTrue((self.state / "running").exists())
        self.assertIn(f"updated SearXNG to {NEWEST_TAG} and restarted it", result.stdout)
        self.assertEqual(self.choice.read_text().strip(), f"{NEWEST_TAG} {NEWEST_DIGEST}")

    def test_current_container_is_not_recreated(self):
        self.arrange_container("sha256:same", "sha256:same", ref=NEWEST)

        result = self.run_update()

        self.assertEqual(result.returncode, 0, result.stderr)
        verbs = [command.split()[0] for command in self.commands()]
        self.assertNotIn("rm", verbs)
        self.assertNotIn("run", verbs)
        self.assertNotIn("create", verbs)
        self.assertIn("already up to date", result.stdout)

    def test_the_same_image_under_the_old_latest_name_is_renamed_by_digest(self):
        self.arrange_container("sha256:same", "sha256:same")

        result = self.run_update()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.state / "container_ref").read_text().strip(), NEWEST)
        self.assertTrue((self.state / "running").exists())
        self.assertIn("restarted it", result.stdout)

    def test_stopped_container_is_updated_without_starting_it(self):
        self.arrange_container("sha256:old", "sha256:new", running=False)

        result = self.run_update()

        self.assertEqual(result.returncode, 0, result.stderr)
        verbs = [command.split()[0] for command in self.commands()]
        self.assertIn("create", verbs)
        self.assertNotIn("run", verbs)
        self.assertFalse((self.state / "running").exists())
        self.assertEqual((self.state / "container_image").read_text().strip(), "sha256:new")

    def test_update_without_a_container_only_refreshes_the_local_image(self):
        (self.state / "local_image").write_text("sha256:old\n", encoding="utf-8")
        (self.state / "remote_image").write_text("sha256:new\n", encoding="utf-8")

        result = self.run_update()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.state / "local_image").read_text().strip(), "sha256:new")
        self.assertFalse((self.state / "exists").exists())
        self.assertIn("start SearXNG from Settings", result.stdout)

    def test_pull_failure_leaves_the_running_container_untouched(self):
        self.arrange_container("sha256:old", "sha256:new")
        (self.state / "fail_pull").touch()

        result = self.run_update()

        self.assertNotEqual(result.returncode, 0)
        verbs = [command.split()[0] for command in self.commands()]
        self.assertNotIn("rm", verbs)
        self.assertEqual((self.state / "container_image").read_text().strip(), "sha256:old")
        self.assertTrue((self.state / "running").exists())

    def test_failed_state_query_does_not_pull_or_replace_anything(self):
        self.arrange_container("sha256:old", "sha256:new")
        (self.state / "fail_ps").touch()

        result = self.run_update()

        self.assertNotEqual(result.returncode, 0)
        verbs = [command.split()[0] for command in self.commands()]
        self.assertNotIn("pull", verbs)
        self.assertNotIn("rm", verbs)
        self.assertEqual((self.state / "container_image").read_text().strip(), "sha256:old")
        self.assertTrue((self.state / "running").exists())

    def test_failed_replacement_start_restores_the_previous_image(self):
        self.arrange_container("sha256:old", "sha256:new")
        (self.state / "fail_run_new").touch()

        result = self.run_update()

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.state / "container_image").read_text().strip(), "sha256:old")
        self.assertTrue((self.state / "running").exists())
        self.assertIn("restored the previous image", result.stderr)
        self.assertFalse(self.choice.exists(), "a failed switch is not remembered")

    def test_failed_stopped_replacement_restores_a_stopped_container(self):
        self.arrange_container("sha256:old", "sha256:new", running=False)
        (self.state / "fail_create_new").touch()

        result = self.run_update()

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.state / "container_image").read_text().strip(), "sha256:old")
        self.assertTrue((self.state / "exists").exists())
        self.assertFalse((self.state / "running").exists())
        self.assertIn("restored the previous stopped container", result.stderr)

    def test_interruption_after_removal_restores_the_previous_container(self):
        self.arrange_container("sha256:old", "sha256:new")
        (self.state / "signal_after_remove").touch()

        result = self.run_update()

        self.assertEqual(result.returncode, 143)
        self.assertEqual((self.state / "container_image").read_text().strip(), "sha256:old")
        self.assertTrue((self.state / "running").exists())
        self.assertIn("update interrupted", result.stderr)

    def test_closed_terminal_output_cannot_prevent_restoration(self):
        self.arrange_container("sha256:old", "sha256:new")
        (self.state / "signal_after_remove").touch()

        result = self.run_update(close_stderr=True)

        self.assertEqual(result.returncode, 143)
        self.assertEqual((self.state / "container_image").read_text().strip(), "sha256:old")
        self.assertTrue((self.state / "running").exists())

    def test_repeated_interruption_cannot_interrupt_the_restoration(self):
        self.arrange_container("sha256:old", "sha256:new")
        (self.state / "signal_every_remove").touch()

        result = self.run_update()

        self.assertEqual(result.returncode, 143)
        self.assertEqual((self.state / "container_image").read_text().strip(), "sha256:old")
        self.assertTrue((self.state / "running").exists())

    def test_unhealthy_update_restores_the_previous_running_image(self):
        self.arrange_container("sha256:old", "sha256:new")
        (self.state / "fail_health_for_new").touch()

        result = self.run_update()

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.state / "container_image").read_text().strip(), "sha256:old")
        self.assertTrue((self.state / "running").exists())
        self.assertIn("restored the previous image", result.stderr)

    def test_purge_removes_the_container_and_its_image_but_not_the_config(self):
        self.arrange_container("sha256:old", "sha256:old")
        config = self.base / "config" / "searxng"
        config.mkdir(parents=True)

        result = self.run_mode("--purge")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.state / "exists").exists())
        self.assertFalse((self.state / "local_image").exists())
        self.assertTrue(config.is_dir())
        self.assertIn(f"removed the {PINNED} image", result.stdout)

    def test_purge_keeps_an_image_another_container_uses(self):
        self.arrange_container("sha256:old", "sha256:old")
        (self.state / "image_in_use").touch()

        result = self.run_mode("--purge")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.state / "exists").exists())
        self.assertIn(f"kept the {PINNED} image", result.stderr)

    def test_the_update_names_both_builds_and_changes_nothing_on_a_no(self):
        self.arrange_container("sha256:old", "sha256:new", ref=PINNED)

        result = self.run_update(answer="n\n")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("current: 2026.9.25-d8ae3abd5", result.stdout)
        self.assertIn(f"newest:  {NEWEST_TAG}  ({NEWEST_DIGEST})", result.stdout)
        verbs = [command.split()[0] for command in self.commands()]
        self.assertNotIn("pull", verbs)
        self.assertNotIn("rm", verbs)
        self.assertEqual((self.state / "container_image").read_text().strip(), "sha256:old")
        self.assertFalse(self.choice.exists())

    def test_current_names_what_the_container_was_created_from(self):
        self.arrange_container("sha256:old", "sha256:new")

        result = self.run_update(answer="n\n")

        self.assertIn("current: searxng/searxng:latest", result.stdout, "an older omaseek's container")
        self.assertIn(f"newest:  {NEWEST_TAG}", result.stdout)

    def test_a_container_already_on_the_newest_is_not_asked_about(self):
        self.arrange_container("sha256:new", "sha256:new", ref=NEWEST)

        result = self.run_update(answer="")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("newest:  the same image", result.stdout)
        self.assertNotIn("Switch SearXNG", result.stdout + result.stderr)
        self.assertIn("already up to date", result.stdout)

    def test_an_unanswered_prompt_is_a_no(self):
        self.arrange_container("sha256:old", "sha256:new")

        result = self.run_update(answer="")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("pull", [command.split()[0] for command in self.commands()])

    def test_a_failed_lookup_changes_nothing(self):
        self.arrange_container("sha256:old", "sha256:new")
        (self.state / "newest").unlink()

        result = self.run_update()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("nothing was changed", result.stderr)
        self.assertNotIn("pull", [command.split()[0] for command in self.commands()])

    def test_a_malformed_lookup_is_refused(self):
        self.arrange_container("sha256:old", "sha256:new")
        (self.state / "newest").write_text("latest sha256:nope\n", encoding="utf-8")

        result = self.run_update()

        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("pull", [command.split()[0] for command in self.commands()])

    def test_a_fresh_start_runs_the_pinned_digest(self):
        (self.state / "local_image").write_text("sha256:pinned\n", encoding="utf-8")  # what run pulls
        result = self.run_mode("start")

        self.assertEqual(result.returncode, 0, result.stderr)
        run = next(command for command in self.commands() if command.startswith("run -d"))
        self.assertTrue(run.endswith(" " + PINNED), run)

    def test_a_start_after_an_update_runs_the_chosen_digest(self):
        (self.state / "remote_image").write_text("sha256:new\n", encoding="utf-8")
        self.assertEqual(self.run_update().returncode, 0)
        (self.state / "log").write_text("", encoding="utf-8")

        result = self.run_mode("start")

        self.assertEqual(result.returncode, 0, result.stderr)
        run = next(command for command in self.commands() if command.startswith("run -d"))
        self.assertTrue(run.endswith(" " + NEWEST), run)

    def test_a_malformed_choice_falls_back_to_the_pin(self):
        (self.state / "local_image").write_text("sha256:pinned\n", encoding="utf-8")  # what run pulls
        self.choice.parent.mkdir(parents=True)
        self.choice.write_text("latest\n", encoding="utf-8")

        result = self.run_mode("start")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("ignoring", result.stderr)
        run = next(command for command in self.commands() if command.startswith("run -d"))
        self.assertTrue(run.endswith(" " + PINNED), run)

    def test_purge_also_takes_the_old_latest_image_and_the_choice(self):
        (self.state / "remote_image").write_text("sha256:new\n", encoding="utf-8")
        self.assertEqual(self.run_update().returncode, 0)
        (self.state / "local_image").write_text("sha256:x\n", encoding="utf-8")

        result = self.run_mode("--purge")

        self.assertEqual(result.returncode, 0, result.stderr)
        removed = [command for command in self.commands() if command.startswith("image rm")]
        self.assertEqual(removed, [f"image rm {NEWEST}"], "the fake holds one image, removed by the first name")
        self.assertIn(f"image inspect {PINNED}", self.commands())
        self.assertIn("image inspect searxng/searxng:latest", self.commands())
        self.assertFalse(self.choice.exists())


    def test_podman_runs_rootless_as_the_images_own_user(self):
        self.with_podman()

        result = self.run_mode("start")

        self.assertEqual(result.returncode, 0, result.stderr)
        run = next(c for c in self.commands(self.pstate) if c.startswith("run -d"))
        self.assertIn("--userns keep-id:uid=977,gid=977", run)
        self.assertIn("--restart always", run)
        self.assertTrue(run.endswith(" " + PODMAN_PINNED), run)
        self.assertEqual(self.commands(), [], "docker was not touched")
        self.assertNotIn("sudo", result.stdout + result.stderr)
        self.assertEqual(self.engine_file().read_text().strip(), "podman")
        self.assertIn("--user enable podman-restart.service", (self.state / "systemctl").read_text())

    def test_podman_is_the_default_when_installed(self):
        self.with_podman(engine=None)

        result = self.run_mode("--engine")

        self.assertEqual(result.stdout.strip(), "podman")

    def test_a_recorded_engine_wins_over_the_default(self):
        self.with_podman(engine=None)
        self.engine_file().parent.mkdir(parents=True)
        self.engine_file().write_text("docker\n", encoding="utf-8")

        self.assertEqual(self.run_mode("--engine").stdout.strip(), "docker")

    def test_docker_is_the_default_without_podman(self):
        # This machine's PATH, less podman: a directory of links to the rest.
        tools = self.base / "no-podman"
        tools.mkdir()
        for directory in ("/usr/bin", "/bin"):
            for tool in pathlib.Path(directory).iterdir():
                if tool.name != "podman" and not os.path.lexists(tools / tool.name):
                    (tools / tool.name).symlink_to(tool)
        del self.env["OMASEEK_ENGINE"]
        self.env["PATH"] = str(tools)

        self.assertEqual(self.run_mode("--engine").stdout.strip(), "docker")

    def test_an_unknown_engine_is_refused(self):
        self.env["OMASEEK_ENGINE"] = "lxc"

        result = self.run_mode("--engine")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("podman or docker", result.stderr)

    def test_use_podman_moves_searxng_out_of_docker(self):
        self.arrange_container("sha256:old", "sha256:old")
        self.with_podman(engine=None)

        result = self.run_mode("--use")
        self.assertNotEqual(result.returncode, 0, "--use needs an engine")
        result = subprocess.run([str(SCRIPT), "--use", "podman"], cwd=ROOT, env=self.env, text=True,
                                capture_output=True, check=False)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("rm -f searxng", self.commands())
        self.assertIn(f"image rm {PINNED}", self.commands())
        self.assertFalse((self.state / "exists").exists(), "the docker container is gone")
        self.assertTrue((self.pstate / "running").exists(), "and SearXNG runs under podman")
        self.assertEqual(self.engine_file().read_text().strip(), "podman")

    def test_purge_empties_both_engines(self):
        self.arrange_container("sha256:old", "sha256:old")
        self.with_podman()
        (self.pstate / "exists").touch()
        (self.pstate / "container_image").write_text("sha256:pinned\n", encoding="utf-8")

        result = self.run_mode("--purge")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.state / "exists").exists())
        self.assertFalse((self.pstate / "exists").exists())
        self.assertIn(f"removed the {PODMAN_PINNED} image", result.stdout)
        self.assertIn(f"removed the {PINNED} image", result.stdout)

    def test_purge_of_a_podman_install_leaves_docker_alone(self):
        self.arrange_container("sha256:old", "sha256:old")
        self.with_podman(engine=None)
        self.engine_file().parent.mkdir(parents=True)
        self.engine_file().write_text("podman\n", encoding="utf-8")

        result = self.run_mode("--purge")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.commands(), [], "docker, and so sudo, was never asked")
        self.assertFalse(self.engine_file().exists())

    def test_present_sees_a_podman_container(self):
        self.with_podman()
        (self.pstate / "exists").touch()
        (self.pstate / "container_ref").write_text(PODMAN_PINNED + "\n", encoding="utf-8")
        (self.pstate / "container_image").write_text("sha256:pinned\n", encoding="utf-8")
        (self.pstate / "local_image").unlink()

        self.assertEqual(self.run_mode("--present").returncode, 0)


if __name__ == "__main__":
    unittest.main()
