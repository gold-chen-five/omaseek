"""Talking to the SearXNG instance: one search request, whether it is up,
and its JSON rows turned into the panel's."""

import json
import urllib.error
import urllib.parse
import urllib.request

from .config import CURRENT, ICON_ENDPOINT, SearchError, TIMEOUT


def fetch(base, query, pageno):
    """One page from SearXNG. Real pagination — no hidden forms to echo back."""
    return parse(fetch_payload(base, query, pageno))


def fetch_payload(base, query, pageno, engines=None):
    params = {"q": query, "format": "json", "pageno": pageno}
    asked = CURRENT.engines if engines is None else engines
    if asked:
        params["engines"] = ",".join(asked)
    if CURRENT.language:
        params["language"] = CURRENT.language
    url = base + "/search?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            payload = json.loads(response.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as exc:
        if exc.code in (403, 404):
            # SearXNG ships `formats: [html]`, so the JSON API 403s until enabled. The setup
            # script can't fix an existing settings.yml, so this is not marked `setup`.
            raise SearchError(
                "http",
                f"SearXNG refused the JSON API at {base} — add 'json' under "
                "search.formats in settings.yml and restart it",
            )
        raise SearchError("http", f"SearXNG returned HTTP {exc.code}")
    except urllib.error.URLError as exc:
        raise SearchError(
            "network", f"SearXNG is not reachable at {base} ({exc.reason})", setup=True
        )
    except TimeoutError:
        raise SearchError("network", f"SearXNG timed out after {TIMEOUT}s")
    except ValueError:
        raise SearchError("http", "SearXNG returned an unreadable response")
    if not isinstance(payload, dict):
        raise SearchError("http", "SearXNG returned an unreadable response")
    return payload


def instance_running(base):
    """Whether SearXNG answers at all. /healthz costs it nothing upstream."""
    try:
        with urllib.request.urlopen(base + "/healthz", timeout=2) as response:
            return 200 <= response.status < 300
    except urllib.error.HTTPError:
        return True         # it answered, however unhappily
    except (urllib.error.URLError, TimeoutError, ValueError):
        return False


def parse(payload):
    rows = []
    for item in payload.get("results") or []:
        url = (item.get("url") or "").strip()
        if not url.startswith("http"):
            continue
        netloc = urllib.parse.urlparse(url).netloc
        title = (item.get("title") or "").strip() or netloc
        snippet = " ".join((item.get("content") or "").split())
        # Which engines found it: SearXNG merges a document several engines
        # returned and lists them all; older instances name only one.
        engines = [e for e in (item.get("engines") or [item.get("engine")]) if isinstance(e, str) and e]
        rows.append({
            "title": title,
            "url": url,
            "snippet": snippet[:300],
            "display_url": netloc,
            "icon": ICON_ENDPOINT + netloc + ".ico" if netloc else "",
            "engines": ", ".join(dict.fromkeys(engines)),
        })
    return rows


def read_json(url, timeout):
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8", "replace"))
