"""The Update row's hint: the running version against the newest image on
Docker Hub. Docker Hub is sent the tags URL and nothing else."""

import http.client
import re
import sys

from .client import read_json
from .config import emit, fail


# The image bin/searxng-up --update offers, as Docker Hub lists its tags. Sent
# nothing but this URL: no query, no instance address.
DOCKER_TAGS_URL = "https://hub.docker.com/v2/repositories/searxng/searxng/tags?page_size=25&ordering=last_updated"


RUNNING_VERSION = re.compile(r"^(\d{4})\.(\d{1,2})\.(\d{1,2})\+([0-9a-f]{7,40})")


TAG_VERSION = re.compile(r"^(\d{4})\.(\d{1,2})\.(\d{1,2})-([0-9a-f]{7,40})$")


DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")


def latest_tag(tags):
    """Docker Hub's tag list -> the dated tag `latest` points at, or None.

    `latest` names no version itself; the dated tag sharing its digest does. A
    list without it falls back to the newest dated tag."""
    named = [t for t in tags if isinstance(t, dict) and isinstance(t.get("name"), str)]
    latest = next((t for t in named if t["name"] == "latest"), None)
    dated = [t for t in named if TAG_VERSION.match(t["name"])]
    if latest and latest.get("digest"):
        for tag in dated:
            if tag.get("digest") == latest["digest"]:
                return tag["name"]
    return dated[0]["name"] if dated else None


def newest_image(tags):
    """Docker Hub's tag list -> (dated tag, digest) of the image `latest` points
    at, or None. The digest is what bin/searxng-up pulls, so the image the
    reader agreed to is the one that runs even if `latest` moves meanwhile."""
    tag = latest_tag(tags)
    digest = next((t.get("digest") for t in tags if isinstance(t, dict) and t.get("name") == tag), None)
    return (tag, digest) if tag and isinstance(digest, str) and DIGEST.match(digest) else None


def print_newest_image():
    """`bin/search --newest-image`: one line, `<dated tag> <digest>`, for
    bin/searxng-up --update to offer. Exits 1 when Docker Hub cannot say."""
    try:
        found = newest_image(read_json(DOCKER_TAGS_URL, 10).get("results") or [])
    except (OSError, http.client.HTTPException, ValueError, AttributeError):
        found = None
    if not found:
        sys.exit(1)
    print(*found)


def is_current(running, latest):
    """Whether the running version is the latest image: the same commit, or a
    newer date (a local build). None when either cannot be read."""
    ran = RUNNING_VERSION.match(running or "")
    tag = TAG_VERSION.match(latest or "")
    if not ran or not tag:
        return None
    if tag.group(4).startswith(ran.group(4)) or ran.group(4).startswith(tag.group(4)):
        return True
    date = lambda m: tuple(int(m.group(i)) for i in (1, 2, 3))
    return date(ran) > date(tag)


def report_version(base):
    """The running instance's version against the newest image. Either half
    may be missing — stopped, or offline — and says so rather than failing."""
    try:
        version = read_json(base + "/config", 3).get("version")
    except (OSError, http.client.HTTPException, ValueError, AttributeError):
        fail("network", f"SearXNG is not reachable at {base}", setup=True)
    try:
        latest = latest_tag(read_json(DOCKER_TAGS_URL, 5).get("results") or [])
    except (OSError, http.client.HTTPException, ValueError, AttributeError):
        latest = None
    emit({"ok": True, "version": version if isinstance(version, str) else None,
          "latest": latest, "current": is_current(version, latest)})
