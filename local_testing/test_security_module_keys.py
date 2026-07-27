#!/usr/bin/env python3
"""Validate compact, unique PROVIDED keys for security modules."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE_GLOBS = (
    "akashic/security/jose/*.f",
    "akashic/security/oauth2/*.f",
    "local_testing/jose-*-test.f",
    "local_testing/oauth2-*-test.f",
)
MAX_KEY_BYTES = 23
PROVIDED = re.compile(r"(?m)^[ \t]*PROVIDED[ \t]+(\S+)")


def _module_paths() -> list[Path]:
    paths = sorted(
        path
        for pattern in MODULE_GLOBS
        for path in ROOT.glob(pattern)
    )
    assert paths, "no JOSE or OAuth2 security modules or fixtures found"
    return paths


def _provided_key(path: Path) -> str:
    keys = PROVIDED.findall(path.read_text(encoding="utf-8"))
    relative = path.relative_to(ROOT)
    assert len(keys) == 1, (
        f"{relative}: expected exactly one leading PROVIDED token, "
        f"found {len(keys)}"
    )
    return keys[0]


def test_security_module_keys() -> None:
    seen: dict[str, Path] = {}

    for path in _module_paths():
        key = _provided_key(path)
        relative = path.relative_to(ROOT)

        try:
            encoded = key.encode("ascii")
        except UnicodeEncodeError as error:
            raise AssertionError(
                f"{relative}: PROVIDED key is not ASCII: {key!r}"
            ) from error

        assert len(encoded) <= MAX_KEY_BYTES, (
            f"{relative}: PROVIDED key {key!r} is {len(encoded)} bytes; "
            f"maximum is {MAX_KEY_BYTES}"
        )

        prior = seen.get(key)
        assert prior is None, (
            f"duplicate PROVIDED key {key!r}: "
            f"{prior.relative_to(ROOT)} and {relative}"
        )
        seen[key] = path


def main() -> int:
    test_security_module_keys()
    print("SECURITY MODULE KEYS PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
