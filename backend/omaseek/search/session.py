"""Pages sliced from a per-query buffer under ~/.cache/omaseek, since a SearXNG
page is however many engines answered in time. One request per page is the
budget; a page that fails keeps its continuation for a retry."""

import hashlib
import json
import os

from .client import fetch
from .config import CACHE_DIR, CURRENT, MAX_FETCHES_PER_PAGE, SearchError, emit, fail


def session_path(query):
    # Engines and language are part of the key: switching either in settings
    # must not serve page 2 from a buffer filled under the old ones.
    key = "\0".join([query, ",".join(CURRENT.engines), CURRENT.language])
    digest = hashlib.sha256(key.encode("utf-8")).hexdigest()[:16]
    return os.path.join(CACHE_DIR, f"session-{digest}.json")


def load_session(query):
    try:
        with open(session_path(query), encoding="utf-8") as handle:
            session = json.load(handle)
    except (OSError, ValueError):
        return None
    return session if isinstance(session, dict) and session.get("rows") else None


def save_session(session):
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        with open(session_path(session["query"]), "w", encoding="utf-8") as handle:
            json.dump(session, handle)
    except OSError:
        pass  # paging will just refetch


def absorb(session, incoming):
    """Append new rows, dropping ones already buffered. Returns how many stuck.

    SearXNG merges and de-duplicates within a page, but the same document still
    turns up across page boundaries and under several canonical paths, so
    identity is domain+title as well as URL.
    """
    urls = {row["url"] for row in session["rows"]}
    documents = {(row["display_url"], row["title"].lower()) for row in session["rows"]}

    added = 0
    for row in incoming:
        document = (row["display_url"], row["title"].lower())
        if row["url"] in urls or document in documents:
            continue
        urls.add(row["url"])
        documents.add(document)
        session["rows"].append(row)
        added += 1
    return added


def start_session(query, base):
    session = {"query": query, "rows": [], "next": None, "backend": "searxng", "url": base}
    try:
        rows = fetch(base, query, 1)
    except SearchError as refused:
        fail(refused.kind, refused.message, setup=refused.setup)
    absorb(session, rows)
    session["next"] = {"pageno": 2} if rows else None
    return session


def grow_session(session, target):
    """Top the buffer up to `target` rows, within the burst limit. A failed
    fetch keeps `next`, so the same page can be asked for again, and is
    returned for the caller to report; None when every fetch answered."""
    fetches = 0
    while len(session["rows"]) < target and session["next"] and fetches < MAX_FETCHES_PER_PAGE:
        fetches += 1
        pageno = int(session["next"].get("pageno") or 2)
        try:
            rows = fetch(session["url"], session["query"], pageno)
        except SearchError as refused:
            return refused               # the continuation stays: a retry resumes here
        added = absorb(session, rows)
        session["next"] = {"pageno": pageno + 1} if rows else None
        if added == 0:
            # Repeating itself means it has run out of useful results. Stop
            # rather than spending the remaining budget.
            session["next"] = None
            break
    return None


def emit_page(session, offset):
    # Exactly one page: a lookahead row cost a whole extra request.
    refused = grow_session(session, offset + CURRENT.page_size)
    save_session(session)

    rows = session["rows"]
    page = rows[offset:offset + CURRENT.page_size]
    if refused is not None and len(page) < CURRENT.page_size and (offset > 0 or not page):
        # Not "the end": the rows past here were never fetched. A short page
        # would be cached by the panel as final, so the whole page fails. The
        # first page is the exception — something to read beats an error, and
        # `next` is still offered.
        payload = {"ok": False, "error": refused.kind, "message": refused.message, "retry": True}
        if refused.setup:
            payload["setup"] = True
        emit(payload)
        return
    has_more = len(rows) > offset + CURRENT.page_size or session["next"] is not None
    following = {"query": session["query"], "s": offset + CURRENT.page_size} if has_more else None

    empty = not page and offset == 0
    emit({
        "ok": True,
        "results": [] if empty else page,
        "next": None if empty else following,
        "backend": session["backend"],
    })
