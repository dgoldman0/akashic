#!/usr/bin/env python3
"""Gate 2C dependency and ownership guards for the Daybook document owner."""

from __future__ import annotations

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "akashic"
INTEROP = SOURCE / "interop"
OWNER = SOURCE / "daybook" / "shared-document.f"
OLD_OWNER = INTEROP / ("shared-" + "document.f")
LENS = INTEROP / "shared-document-lens.f"
DESK = SOURCE / "tui" / "applets" / "desk" / "desk.f"

REQUIRE = re.compile(r"^\s*REQUIRE\s+(\S+)", re.MULTILINE)
TEXT_SUFFIXES = {
    ".f",
    ".json",
    ".md",
    ".py",
    ".sh",
    ".toml",
    ".txt",
    ".uidl",
    ".yaml",
    ".yml",
}


def _requires(path: Path) -> list[Path]:
    text = path.read_text(encoding="utf-8")
    return [(path.parent / value).resolve() for value in REQUIRE.findall(text)]


def _repo_text_files() -> list[Path]:
    files: list[Path] = []
    for path in ROOT.rglob("*"):
        if not path.is_file() or path.suffix not in TEXT_SUFFIXES:
            continue
        relative = path.relative_to(ROOT)
        if {".git", ".pytest_cache", "out", "__pycache__"} & set(
            relative.parts
        ):
            continue
        files.append(path)
    return files


def test_concrete_owner_lives_only_in_the_daybook_domain() -> None:
    assert OWNER.is_file()
    assert not OLD_OWNER.exists()
    assert "PROVIDED akashic-interop-shared-document" in OWNER.read_text(
        encoding="utf-8"
    )
    assert "REQUIRE ../../../daybook/shared-document.f" in DESK.read_text(
        encoding="utf-8"
    )


def test_interop_neither_imports_nor_forwards_daybook_owner_policy() -> None:
    forbidden_policy = (
        "/daybook.md",
        "org.akashic.resource.daybook",
        "SDOC-",
        "akashic-interop-shared-document",
    )
    daybook_root = (SOURCE / "daybook").resolve()

    for module in INTEROP.rglob("*.f"):
        text = module.read_text(encoding="utf-8")
        assert not any(value in text for value in forbidden_policy), module
        for dependency in _requires(module):
            assert dependency != OWNER.resolve(), module
            assert daybook_root not in dependency.parents, module


def test_shared_document_lens_contains_only_portable_mechanics() -> None:
    text = LENS.read_text(encoding="utf-8")
    for value in (
        "/daybook.md",
        "org.akashic.resource.daybook",
        "SDOC-",
        "akashic-interop-shared-document",
    ):
        assert value not in text

    dependencies = set(_requires(LENS))
    assert dependencies == {
        (INTEROP / "endpoint.f").resolve(),
        (INTEROP / "lens-binding.f").resolve(),
    }


def test_no_old_owner_path_reference_remains() -> None:
    old_path = "interop/" + "shared-document.f"
    references = []
    for path in _repo_text_files():
        text = path.read_text(encoding="utf-8")
        if old_path in text:
            references.append(path.relative_to(ROOT))
    assert references == []
