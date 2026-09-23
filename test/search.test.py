#!/usr/bin/env python3
"""bin/search against a fake SearXNG: pages, a page that fails and is retried,
and what the settings page sends — engines, language — and asks of --test."""

import contextlib
import http.server
import io
import json
import os
import pathlib
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.parse


ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin" / "search"


class FakeSearxng(http.server.BaseHTTPRequestHandler):
    """Ten distinct rows a page, forever, except for the page numbers in `failing`."""

    failing = set()
    requests = []

    version = "2026.9.8+3fdc6d753"
    tags = []

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path in ("/config", "/tags"):
            body = json.dumps({"version": FakeSearxng.version} if parsed.path == "/config"
                              else {"results": FakeSearxng.tags}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body)
            return
        params = dict(urllib.parse.parse_qsl(parsed.query))
        FakeSearxng.requests.append(params)
        pageno = int(params.get("pageno", "1"))
        if pageno in FakeSearxng.failing:
            self.send_response(502)
            self.end_headers()
            return
        results = [{
            "url": f"https://site{pageno}-{i}.example/page",
            "title": f"Result {pageno}.{i}",
            "content": "snippet",
            "engines": ["brave", "bing"] if i % 2 else ["brave"],
        } for i in range(10)]
        body = json.dumps({
            "results": results,
            "unresponsive_engines": [["google", "Suspended: CAPTCHA"]],
        }).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


class SearchBackendTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), FakeSearxng)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def setUp(self):
        FakeSearxng.failing = set()
        FakeSearxng.requests = []
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = pathlib.Path(self.temporary.name)
        self.configure({})

    def configure(self, extra):
        config = {"searxng_url": f"http://127.0.0.1:{self.server.server_port}", "results_per_page": 5}
        config.update(extra)
        path = self.base / "config" / "omaseek" / "config.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(config))

    def run_search(self, *args):
        env = dict(os.environ, XDG_CONFIG_HOME=str(self.base / "config"), XDG_CACHE_HOME=str(self.base / "cache"))
        done = subprocess.run([str(SCRIPT), *args], capture_output=True, text=True, env=env, timeout=30)
        self.assertEqual(done.returncode, 0, done.stderr)
        return json.loads(done.stdout)

    def test_rows_name_the_engines_that_found_them(self):
        page = self.run_search("rust")
        self.assertTrue(page["ok"])
        self.assertEqual(page["results"][0]["engines"], "brave")
        self.assertEqual(page["results"][1]["engines"], "brave, bing")

    def test_a_failed_page_keeps_its_continuation_and_the_same_payload_retries(self):
        first = self.run_search("rust")
        following = json.dumps(first["next"])
        # Page 1 of SearXNG filled pages 1 and 2 of ours; page 3 needs SearXNG's page 2.
        second = self.run_search("--next", following)
        self.assertTrue(second["ok"])
        FakeSearxng.failing = {2}
        third_payload = json.dumps(second["next"])
        failed = self.run_search("--next", third_payload)
        self.assertFalse(failed["ok"])
        self.assertTrue(failed["retry"], "a failed page is not the end")
        self.assertEqual(failed["error"], "http")

        FakeSearxng.failing = set()
        retried = self.run_search("--next", third_payload)
        self.assertTrue(retried["ok"])
        self.assertEqual(len(retried["results"]), 5)
        self.assertEqual(retried["results"][0]["title"], "Result 2.0")
        self.assertIsNotNone(retried["next"])

    def test_a_first_page_with_rows_is_shown_even_when_topping_it_up_fails(self):
        self.configure({"results_per_page": 20})
        FakeSearxng.failing = {2}
        page = self.run_search("rust")
        self.assertTrue(page["ok"], "something to read beats an error")
        self.assertEqual(len(page["results"]), 10)
        self.assertIsNotNone(page["next"], "and the rest is still offered")

    def test_a_fresh_install_asks_the_four_default_engines(self):
        self.run_search("rust")
        self.assertEqual(FakeSearxng.requests[-1]["engines"], "google cse,bing,brave,duckduckgo",
                         "a name with a space travels as one engine")

    def test_engines_and_language_are_sent_and_key_the_buffer(self):
        self.configure({"searxng_engines": ["brave", "google"], "searxng_language": "de-DE"})
        self.run_search("rust")
        self.assertEqual(FakeSearxng.requests[-1]["engines"], "brave,google")
        self.assertEqual(FakeSearxng.requests[-1]["language"], "de-DE")
        german = set(os.listdir(self.base / "cache" / "omaseek"))

        self.configure({"searxng_engines": ["brave", "google"], "searxng_language": "not a code"})
        self.run_search("rust")
        self.assertNotIn("language", FakeSearxng.requests[-1], "a malformed code sends none")
        self.assertNotEqual(set(os.listdir(self.base / "cache" / "omaseek")), german,
                            "another language must not share page 2 with the German buffer")

    def test_the_endpoint_test_times_each_engine_on_its_own(self):
        report = self.run_search("--test")
        self.assertTrue(report["ok"])
        # One query per configured engine, so each one's time is its own.
        asked = [params.get("engines") for params in FakeSearxng.requests]
        self.assertEqual(asked, ["google cse", "bing", "brave", "duckduckgo"], "one query each")
        rows = {name: answer["rows"] for name, answer in report["engines"].items()}
        self.assertEqual(rows, {"google cse": 0, "bing": 5, "brave": 10, "duckduckgo": 0})
        for answer in report["engines"].values():
            self.assertIsInstance(answer["ms"], int)
        # Named once, however many queries the instance mentioned it in.
        self.assertEqual(report["unresponsive"], [{"engine": "google", "reason": "Suspended: CAPTCHA"}])
        self.assertIsInstance(report["ms"], int)

    def test_timing_a_search_sends_the_query_a_keypress_sends(self):
        report = self.run_search("--time")
        self.assertTrue(report["ok"])
        asked = [params.get("engines") for params in FakeSearxng.requests]
        self.assertEqual(asked, ["google cse,bing,brave,duckduckgo"], "one search, every engine at once")
        self.assertEqual(report["rows"], 10)
        self.assertIsInstance(report["ms"], int)
        self.assertEqual(report["unresponsive"], [{"engine": "google", "reason": "Suspended: CAPTCHA"}])

    def test_the_endpoint_test_reports_a_refusal(self):
        FakeSearxng.failing = {1}
        report = self.run_search("--test")
        self.assertFalse(report["ok"])
        self.assertIn("502", report["message"])

    def test_a_malformed_offset_is_a_usage_error_not_a_crash(self):
        report = self.run_search("--next", json.dumps({"query": "rust", "s": "three"}))
        self.assertEqual(report["error"], "usage")


class HangingUpTests(unittest.TestCase):
    """An instance that accepts and closes without answering — one starting
    behind Docker's proxy. urlopen does not wrap that failure, and it once
    escaped as a traceback with nothing on stdout."""

    @classmethod
    def setUpClass(cls):
        cls.listener = socket.socket()
        cls.listener.bind(("127.0.0.1", 0))
        cls.listener.listen(8)

        def hang_up():
            while True:
                try:
                    peer, _ = cls.listener.accept()
                except OSError:
                    return
                peer.recv(4096)
                peer.close()
        threading.Thread(target=hang_up, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.listener.close()

    def run_search(self, *args):
        with tempfile.TemporaryDirectory() as home:
            config = pathlib.Path(home, "omaseek", "config.json")
            config.parent.mkdir(parents=True)
            config.write_text(json.dumps({"searxng_url": f"http://127.0.0.1:{self.listener.getsockname()[1]}"}))
            env = dict(os.environ, XDG_CONFIG_HOME=home, XDG_CACHE_HOME=home)
            done = subprocess.run([str(SCRIPT), *args], capture_output=True, text=True, env=env, timeout=30)
        self.assertEqual(done.returncode, 0, done.stderr)
        return json.loads(done.stdout)

    def test_every_command_still_answers_with_one_object(self):
        for args in (["rust"], ["--time"], ["--test"]):
            report = self.run_search(*args)
            self.assertFalse(report["ok"], args)
            self.assertEqual(report["error"], "network", args)
        self.assertFalse(self.run_search("--status")["running"])
        self.assertFalse(self.run_search("--version")["ok"])



def load_search():
    """The version check's own module: DOCKER_TAGS_URL is patched where
    report_version reads it."""
    sys.path.insert(0, str(ROOT / "backend"))
    import omaseek.search.version
    return omaseek.search.version


class VersionTests(unittest.TestCase):
    """--version, in-process with Docker Hub's URL pointed at the fake: a test
    must not reach the network."""

    @classmethod
    def setUpClass(cls):
        cls.search = load_search()
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), FakeSearxng)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.base = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def report(self):
        self.search.DOCKER_TAGS_URL = self.base + "/tags"
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.search.report_version(self.base)
        return json.loads(out.getvalue())

    def test_latest_is_the_dated_tag_sharing_its_digest(self):
        tags = [
            {"name": "latest", "digest": "sha256:aaa"},
            {"name": "2026.9.16-461f174b0", "digest": "sha256:aaa"},
            {"name": "2026.9.16-1354f3952", "digest": "sha256:bbb"},
        ]
        self.assertEqual(self.search.latest_tag(tags), "2026.9.16-461f174b0")
        self.assertEqual(self.search.latest_tag(tags[2:]), "2026.9.16-1354f3952", "no latest: the newest dated tag")
        self.assertIsNone(self.search.latest_tag([{"name": "latest"}]))

    def test_current_means_the_same_commit_or_a_newer_build(self):
        current = self.search.is_current
        self.assertTrue(current("2026.9.16+461f174b0", "2026.9.16-461f174b0"))
        self.assertFalse(current("2026.9.8+3fdc6d753", "2026.9.16-461f174b0"))
        self.assertFalse(current("2026.9.16+1354f3952", "2026.9.16-461f174b0"), "same day, another commit")
        self.assertTrue(current("2026.9.20+abcdef012", "2026.9.16-461f174b0"), "a local build ahead of the image")
        self.assertIsNone(current("unknown", "2026.9.16-461f174b0"))
        self.assertIsNone(current("2026.9.16+461f174b0", None))

    def test_an_old_instance_is_reported_with_the_newer_version(self):
        FakeSearxng.version = "2026.9.8+3fdc6d753"
        FakeSearxng.tags = [{"name": "latest", "digest": "d"}, {"name": "2026.9.16-461f174b0", "digest": "d"}]
        self.assertEqual(self.report(), {"ok": True, "version": "2026.9.8+3fdc6d753",
                                         "latest": "2026.9.16-461f174b0", "current": False})

    def test_an_unreachable_docker_hub_still_reports_the_running_version(self):
        FakeSearxng.version = "2026.9.16+461f174b0"
        self.search.DOCKER_TAGS_URL = "http://127.0.0.1:9/tags"
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.search.report_version(self.base)
        self.assertEqual(json.loads(out.getvalue()),
                         {"ok": True, "version": "2026.9.16+461f174b0", "latest": None, "current": None})


if __name__ == "__main__":
    unittest.main()
