#!/usr/bin/env python3
"""Structural contracts for lightweight runtime service discovery."""

from __future__ import annotations

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SERVICE_ENDPOINT = REPO_ROOT / "akashic" / "interop" / "service-endpoint.f"
ENDPOINT = REPO_ROOT / "akashic" / "interop" / "endpoint.f"


def _source(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _definition(source: str, word: str) -> str:
    match = re.search(
        rf"^:\s+{re.escape(word)}(?:\s|$).*?;\s*$",
        source,
        re.MULTILINE | re.DOTALL,
    )
    assert match is not None, word
    return match.group(0)


def test_service_endpoint_is_a_runtime_only_leaf() -> None:
    source = _source(SERVICE_ENDPOINT)
    code = "\n".join(
        line for line in source.splitlines()
        if not line.lstrip().startswith("\\")
    )
    requires = re.findall(r"^REQUIRE\s+(.+?)\s*$", source, re.MULTILINE)

    assert requires == ["../runtime/instance.f"]
    provided = re.findall(r"^PROVIDED\s+(\S+)\s*$", source, re.MULTILINE)
    assert provided == ["akashic-isvc-endpoint"]
    assert len(provided[0].encode("ascii")) <= 23
    for forbidden in (
        "request-bus",
        "schema",
        "json",
        "authority",
        "desk",
        "agent",
        "provider",
        "vfs",
    ):
        assert forbidden not in code.lower()


def test_service_endpoint_owns_the_shared_layout_and_lookup_words() -> None:
    service = _source(SERVICE_ENDPOINT)
    endpoint = _source(ENDPOINT)

    for token in (
        "40 CONSTANT IENDPOINT-SIZE",
        ": IENDPOINT-INIT",
        ": IEND-SERVICE",
        ": CINST-SERVICE",
    ):
        assert token in service
        assert token not in endpoint

    lookup = _definition(service, "IEND-SERVICE")
    assert "IEND.SERVICE-XT @" in lookup
    assert "IEND.CONTEXT @" in lookup
    assert "EXECUTE" in lookup


def test_complete_endpoint_extends_the_service_endpoint() -> None:
    source = _source(ENDPOINT)

    assert "REQUIRE service-endpoint.f" in source
    assert "REQUIRE request-bus.f" in source
    assert ": IEND-POST" in source
    assert ": IEND-INTENT" in source
    assert ": CINST-POST" in source
    assert ": CINST-POST-INTENT" in source
