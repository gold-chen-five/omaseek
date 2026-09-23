"""What bin/search searches with, and its one-object output: the SearXNG
instance, the engines, language and page size from config.json, and emit/fail,
which always exit 0 with a JSON object."""

import json
import os
import re
import sys


SEARXNG_DEFAULT_URL = "http://localhost:8888"


# Short: this sits behind a keypress. SearXNG's own outgoing.request_timeout
# bounds a normal search.
TIMEOUT = 8


CONFIG_PATH = os.path.join(
    os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"),
    "omaseek", "config.json",
)


CACHE_DIR = os.path.join(
    os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"),
    "omaseek",
)


# A favicon CDN, not a search backend: it is sent a bare domain, never a query.
# ResultRow falls back to the domain's initial whenever it does not answer.
ICON_ENDPOINT = "https://external-content.duckduckgo.com/ip3/"


# SearXNG pages vary in size, so rows are buffered per query and sliced evenly.
DEFAULT_PAGE_SIZE = 10


class Current:
    """What this run searches with, set once by main() from config.json: the page
    size, the engines (searxng_engines, or DEFAULT_ENGINES) and the language
    (searxng_language; empty sends none). One shared object rather than module
    globals, so every module reads what main() set."""
    page_size = DEFAULT_PAGE_SIZE
    engines = []
    language = ""


CURRENT = Current


# Measured against a local instance: the engines that actually answer, fast.
# google cse is Google through its embeddable search box, which answered while
# plain google was suspended on a CAPTCHA — so plain google is a switch, not a
# default. brave and google cse page (google cse five pages deep); bing fills
# page one only; duckduckgo answers or CAPTCHAs by the hour. SearXNG silently
# ignores a name its instance does not have, so naming these is safe even where
# one is missing.
DEFAULT_ENGINES = ("google cse", "bing", "brave", "duckduckgo")


PAGE_SIZE_CHOICES = (5, 10, 15, 20)


# Mirrors settings.mjs: SearXNG's codes, 'auto' and 'all'. 'default' sends none.
LANGUAGE_PATTERN = re.compile(r"^(auto|all|[a-z]{2,3}(-[A-Z]{2})?)$")


# What --test asks: common enough that every engine has an answer.
TEST_QUERY = "searxng"


# Never burst: a single page turn may top the buffer up at most this many times.
MAX_FETCHES_PER_PAGE = 3


def emit(obj):
    json.dump(obj, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


def fail(error, message, setup=False):
    payload = {"ok": False, "error": error, "message": message}
    if setup:
        payload["setup"] = True
    emit(payload)
    sys.exit(0)  # A handled failure is still a well-formed answer.


class SearchError(Exception):
    """The instance gave up. Raised rather than exited so callers can add context."""

    def __init__(self, kind, message, setup=False):
        super().__init__(message)
        self.kind = kind
        self.message = message
        self.setup = setup      # fixable by running bin/searxng-up


def read_config():
    """Settings written by the panel's settings page. Absent or broken config
    means defaults — a typo should cost one setting, not the search."""
    try:
        with open(CONFIG_PATH, encoding="utf-8") as handle:
            config = json.load(handle)
    except (OSError, ValueError):
        return {}
    return config if isinstance(config, dict) else {}


def configured_url(config):
    """Base URL of the instance. Hand-edited; the panel does not own it."""
    url = config.get("searxng_url")
    if isinstance(url, str) and url.strip():
        return url.strip().rstrip("/")
    return SEARXNG_DEFAULT_URL


def configured_engines(config):
    """Engines to ask, by SearXNG name (hand-edited). SearXNG waits for every
    engine in the category, so naming the fast ones is the main speed lever —
    asking every enabled engine measured ~3x slower and drags in the ones
    answering with a CAPTCHA.

    An absent or malformed key means DEFAULT_ENGINES, so a fresh install gets
    the fast path without a config file. An explicit [] is the escape hatch:
    it names nothing and leaves the choice to SearXNG."""
    engines = config.get("searxng_engines")
    if not isinstance(engines, list):
        return list(DEFAULT_ENGINES)
    return [e.strip() for e in engines if isinstance(e, str) and e.strip()]


def configured_page_size(config):
    size = config.get("results_per_page")
    return size if size in PAGE_SIZE_CHOICES else DEFAULT_PAGE_SIZE


def configured_language(config):
    language = config.get("searxng_language")
    if isinstance(language, str) and LANGUAGE_PATTERN.match(language.strip()):
        return language.strip()
    return ""
