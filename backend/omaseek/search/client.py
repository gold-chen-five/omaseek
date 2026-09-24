"""Talking to the SearXNG instance: one search request, whether it is up,
and its JSON rows turned into the panel's."""

import http.client
import json
import urllib.error
import urllib.parse
import urllib.request

from .config import CURRENT, ICON_ENDPOINT, SUGGEST_TIMEOUT, SearchError, TIMEOUT


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
    except (OSError, http.client.HTTPException):
        # Accepted, then dropped: urlopen wraps only the failures of sending, so
        # a hang-up while its answer is awaited or read arrives unwrapped — an
        # instance still starting behind Docker's proxy does exactly this.
        raise SearchError("network", f"SearXNG dropped the connection at {base} — is it still starting?")
    except ValueError:
        raise SearchError("http", "SearXNG returned an unreadable response")
    if not isinstance(payload, dict):
        raise SearchError("http", "SearXNG returned an unreadable response")
    return payload


def suggest(base, query):
    """What SearXNG's autocompleter offers for `query`: a list of strings, [] on
    any failure — a missing suggestion is not worth an error under the bar.
    Preferences are read from the request's own parameters, so the backend and
    language go along with it."""
    params = {"q": query, "autocomplete": CURRENT.suggestions}
    if CURRENT.language:
        params["language"] = CURRENT.language
    url = base + "/autocompleter?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=SUGGEST_TIMEOUT) as response:
            payload = json.loads(response.read().decode("utf-8", "replace"))
    except (OSError, http.client.HTTPException, ValueError):
        return []
    # OpenSearch's shape, [query, [suggestions], …]; older instances answer a
    # bare list of suggestions.
    if isinstance(payload, list) and len(payload) >= 2 and isinstance(payload[1], list):
        payload = payload[1]
    if not isinstance(payload, list):
        return []
    seen = []
    for item in payload:
        text = " ".join(item.split()) if isinstance(item, str) else ""
        if text and text not in seen:
            seen.append(text)
    return seen


def instance_running(base):
    """Whether SearXNG answers at all. /healthz costs it nothing upstream."""
    try:
        with urllib.request.urlopen(base + "/healthz", timeout=2) as response:
            return 200 <= response.status < 300
    except urllib.error.HTTPError:
        return True         # it answered, however unhappily
    except (OSError, http.client.HTTPException, ValueError):
        return False        # refused, timed out, or accepted and dropped


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
