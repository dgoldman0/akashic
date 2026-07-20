#!/usr/bin/env python3
"""Shared parser and resolver for Akashic Forth dependency markers.

KDOS recognizes line-leading uppercase ``REQUIRE`` and ``PROVIDED`` markers
separated by ASCII spaces.  Keeping that exact grammar here prevents packaging,
architecture checks, and direct dependency tests from inventing subtly different
graphs.
"""

from __future__ import annotations

import posixpath
import re
from dataclasses import dataclass
from pathlib import Path


REQUIRE_RE = re.compile(r"^ *REQUIRE +([^ \r\n]+)", re.MULTILINE)
PROVIDED_RE = re.compile(r"^ *PROVIDED +([^ \r\n]+)", re.MULTILINE)
MODULE_KEY_BYTES = 23


@dataclass(frozen=True)
class DependencyMarker:
    requiring: str
    line: int
    raw: str
    normalized: str


def normalize_module(module: str, requiring: str | None = None) -> str:
    """Normalize a module token relative to its requiring source module."""
    if module.startswith("/"):
        normalized = posixpath.normpath(module.lstrip("/"))
    else:
        base = posixpath.dirname(requiring) if requiring else ""
        normalized = posixpath.normpath(posixpath.join(base, module))
    if normalized in {"", ".", ".."} or normalized.startswith("../"):
        raise ValueError(f"REQUIRE escapes Akashic source root: {module!r}")
    return normalized


def dependency_markers(text: str, requiring: str) -> tuple[DependencyMarker, ...]:
    """Return every REQUIRE occurrence, preserving its raw and normalized form."""
    return tuple(
        DependencyMarker(
            requiring=requiring,
            line=text.count("\n", 0, match.start()) + 1,
            raw=match.group(1),
            normalized=normalize_module(match.group(1), requiring),
        )
        for match in REQUIRE_RE.finditer(text)
    )


def module_key(module_id: str) -> bytes:
    """Return KDOS's exact bounded PROVIDED lookup key."""
    return module_id.encode("utf-8")[:MODULE_KEY_BYTES].ljust(
        MODULE_KEY_BYTES, b"\0"
    )


def dependency_closure(source_root: Path, roots: tuple[str, ...]) -> tuple[str, ...]:
    """Return the deterministic transitive REQUIRE closure for *roots*."""
    pending = [normalize_module(root) for root in reversed(roots)]
    seen: set[str] = set()

    while pending:
        module = pending.pop()
        if module in seen:
            continue
        host_path = source_root / module
        if not host_path.is_file():
            raise FileNotFoundError(f"Missing Akashic module: {module}")
        seen.add(module)
        text = host_path.read_text(encoding="utf-8")
        dependencies = [
            marker.normalized for marker in dependency_markers(text, module)
        ]
        pending.extend(reversed(dependencies))

    return tuple(sorted(seen))


def dependency_order(source_root: Path, roots: tuple[str, ...]) -> tuple[str, ...]:
    """Return dependencies before their requiring modules."""
    ordered: list[str] = []
    visited: set[str] = set()
    visiting: set[str] = set()

    def visit(module: str, requiring: str | None = None) -> None:
        normalized = normalize_module(module, requiring)
        if normalized in visited:
            return
        if normalized in visiting:
            raise RuntimeError(f"Cyclic linked REQUIRE dependency: {normalized}")
        host_path = source_root / normalized
        if not host_path.is_file():
            raise FileNotFoundError(f"Missing Akashic module: {normalized}")
        visiting.add(normalized)
        text = host_path.read_text(encoding="utf-8")
        for marker in dependency_markers(text, normalized):
            visit(marker.raw, normalized)
        visiting.remove(normalized)
        visited.add(normalized)
        ordered.append(normalized)

    for root in roots:
        visit(root)
    return tuple(ordered)
