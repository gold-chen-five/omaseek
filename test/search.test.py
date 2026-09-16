#!/usr/bin/env python3
"""bin/search against a fake SearXNG: pages, a page that fails and is retried,
and what the settings page sends — engines, language — and asks of --test."""

import http.server
import json
import os
import pathlib
import subprocess
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

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
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

    def test_a_fresh_install_asks_the_default_engines_including_google_cse(self):
        self.run_search("rust")
        self.assertEqual(FakeSearxng.requests[-1]["engines"], "brave,bing,google,google cse",
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

    def test_the_endpoint_test_counts_rows_per_engine_and_names_the_silent_ones(self):
        report = self.run_search("--test")
        self.assertTrue(report["ok"])
        self.assertEqual(report["engines"], {"brave": 10, "bing": 5})
        self.assertEqual(report["unresponsive"], [{"engine": "google", "reason": "Suspended: CAPTCHA"}])
        self.assertIsInstance(report["ms"], int)

    def test_the_endpoint_test_reports_a_refusal(self):
        FakeSearxng.failing = {1}
        report = self.run_search("--test")
        self.assertFalse(report["ok"])
        self.assertIn("502", report["message"])


if __name__ == "__main__":
    unittest.main()
