"""bin/search's commands: --status, --test, --time, --version, --newest-image,
--next, and a search."""

import json
import sys

from .client import instance_running, suggest
from .config import (CURRENT, configured_engines, configured_language, configured_page_size, configured_suggestions,
                     configured_url, emit, fail, read_config)
from .probe import test_endpoint, time_search
from .session import emit_page, load_session, start_session
from .version import print_newest_image, report_version


def main():
    config = read_config()
    base = configured_url(config)
    CURRENT.page_size = configured_page_size(config)
    CURRENT.engines = configured_engines(config)
    CURRENT.language = configured_language(config)
    CURRENT.suggestions = configured_suggestions(config)

    argv = sys.argv[1:]

    if argv and argv[0] == "--status":
        emit({"ok": True, "running": instance_running(base), "url": base})
        return

    if argv and argv[0] == "--test":
        test_endpoint(base)
        return

    if argv and argv[0] == "--time":
        time_search(base)
        return

    if argv and argv[0] == "--version":
        report_version(base)
        return

    if argv and argv[0] == "--newest-image":
        print_newest_image()
        return

    # The dropdown under the bar. Off asks nothing: the typed text stays here.
    if argv and argv[0] == "--suggest":
        query = " ".join(argv[1:]).strip()
        found = suggest(base, query) if query and CURRENT.suggestions else []
        emit({"ok": True, "query": query, "suggestions": found})
        return

    if argv and argv[0] == "--next":
        if len(argv) < 2:
            fail("usage", "--next needs a JSON payload")
        try:
            payload = json.loads(argv[1])
        except ValueError:
            fail("usage", "--next payload is not valid JSON")
        if not isinstance(payload, dict) or not payload.get("query"):
            fail("usage", "--next payload must name the query")

        query = str(payload["query"])
        try:
            offset = max(0, int(payload.get("s") or 0))
        except (TypeError, ValueError):
            fail("usage", "--next payload's offset is not a number")

        # Paging back is free: the buffer already holds those rows.
        session = load_session(query) or start_session(query, base)
        emit_page(session, offset)
        return

    query = " ".join(argv).strip()
    if not query:
        fail("usage", "no query given")

    # Enter always searches afresh rather than serving a stale buffer.
    emit_page(start_session(query, base), 0)
