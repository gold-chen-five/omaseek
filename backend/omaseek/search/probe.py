"""The Engines rows' reports: one real search timed as a keypress sends it
(--time), and each engine asked alone (--test)."""

import time

from .client import fetch_payload, parse
from .config import CURRENT, SearchError, TEST_QUERY, emit, fail


def silent_engines(payload):
    return [{"engine": str(entry[0]), "reason": str(entry[1])}
            for entry in payload.get("unresponsive_engines") or []
            if isinstance(entry, (list, tuple)) and len(entry) >= 2]


def ask_one(base, engine):
    """One engine on its own, timed. A search asks them together, so only this
    says which of them is the slow one. A SearchError is the instance itself
    refusing, not the engine, and is left to end the whole test."""
    started = time.monotonic()
    payload = fetch_payload(base, TEST_QUERY, 1, engines=[engine])
    ms = int((time.monotonic() - started) * 1000)
    rows = 0
    for row in parse(payload):
        if engine in row["engines"].split(", "):
            rows += 1
    silent = silent_engines(payload)
    reason = ""
    for entry in silent:
        if entry["engine"] == engine:
            reason = entry["reason"]
    return {"rows": rows, "ms": ms, "reason": reason, "silent": silent}


def time_search(base):
    """The query a search sends: every engine at once. SearXNG asks them
    together, so this is the wait a keypress buys — roughly the slowest engine,
    never the sum of them."""
    started = time.monotonic()
    try:
        payload = fetch_payload(base, TEST_QUERY, 1)
    except SearchError as refused:
        fail(refused.kind, refused.message, setup=refused.setup)
    ms = int((time.monotonic() - started) * 1000)
    emit({"ok": True, "url": base, "ms": ms, "rows": len(parse(payload)),
          "unresponsive": silent_engines(payload), "asked": CURRENT.engines, "language": CURRENT.language})


def test_endpoint(base):
    """Each engine alone and in turn: the rows and the time asking them together
    cannot tell apart. In turn on purpose — side by side they would time each
    other's waiting. What a search costs is --time; these never add up to it."""
    if not CURRENT.engines:
        # No list means SearXNG asks every engine it has enabled, and there is
        # no way to name them here; one combined query is all that can be timed.
        started = time.monotonic()
        try:
            payload = fetch_payload(base, TEST_QUERY, 1)
        except SearchError as refused:
            fail(refused.kind, refused.message, setup=refused.setup)
        ms = int((time.monotonic() - started) * 1000)
        engines = {}
        for row in parse(payload):
            for engine in row["engines"].split(", "):
                if engine:
                    engines.setdefault(engine, {"rows": 0, "ms": None, "reason": ""})["rows"] += 1
        emit({"ok": True, "url": base, "ms": ms, "engines": engines,
              "unresponsive": silent_engines(payload), "asked": CURRENT.engines, "language": CURRENT.language})
        return

    started = time.monotonic()
    engines = {}
    unresponsive = []
    seen = set()
    for engine in CURRENT.engines:
        try:
            answer = ask_one(base, engine)
        except SearchError as refused:
            fail(refused.kind, refused.message, setup=refused.setup)
        engines[engine] = {"rows": answer["rows"], "ms": answer["ms"], "reason": answer["reason"]}
        # An engine the instance has suspended is worth naming even when it is
        # not one of ours; asking one at a time would otherwise report it once
        # per query.
        for entry in answer["silent"]:
            key = (entry["engine"], entry["reason"])
            if key not in seen:
                seen.add(key)
                unresponsive.append(entry)
    emit({"ok": True, "url": base, "ms": int((time.monotonic() - started) * 1000),
          "engines": engines, "unresponsive": unresponsive,
          "asked": CURRENT.engines, "language": CURRENT.language})
