"""Lock rich-terminal and collection semantics below the applet layer."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
APPLETS = ROOT / "akashic" / "tui" / "applets"
AKASHIC = ROOT / "akashic"
UIDL_CORE = AKASHIC / "liraq" / "uidl.f"
UIDL_SEMANTIC_CORE = AKASHIC / "liraq" / "uidl-semantic.f"
UIDL_DOC = ROOT / "docs" / "liraq" / "uidl.md"
UIDL_SEMANTIC_DOC = ROOT / "docs" / "liraq" / "uidl-semantic.md"
PROJECTION_CONTRACT = ROOT / "docs" / "rich-terminal" / "UIDL-PROJECTION-CANDIDATE.md"
ARCHITECTURE_CONTRACT = ROOT / "docs" / "rich-terminal" / "AKASHIC-RICH-TERMINAL.md"

FORBIDDEN_IMPORT = re.compile(
    r"(?im)^\s*(?:REQUIRE|INCLUDE|INCLUDED)\s+"
    r"\S*(?:rich-terminal|semantic-collections|uidl-collection-snapshot)\S*"
)
FORBIDDEN_TOKEN = re.compile(
    r"(?<![A-Z0-9_-])(?:_*(?:USCOL-|UCSN-|UTUI-SEMANTIC-)"
    r"[A-Z0-9_?!@+*/<>=.-]*|EL-SET-SEMANTICS)(?![A-Z0-9_-])",
    re.IGNORECASE,
)


def _forth_code(source: str) -> str:
    """Discard comments so prose cannot look like a production dependency."""

    source = re.sub(r"(?m)\\.*$", "", source)
    return re.sub(r"(?s)\([^)]*\)", "", source)


def test_production_applets_do_not_own_rich_terminal_semantics() -> None:
    violations: list[str] = []

    for path in sorted(APPLETS.rglob("*.f")):
        code = _forth_code(path.read_text(encoding="utf-8"))
        for pattern, description in (
            (FORBIDDEN_IMPORT, "forbidden lower-layer import"),
            (FORBIDDEN_TOKEN, "forbidden semantic-provider token"),
        ):
            match = pattern.search(code)
            if match is not None:
                relative = path.relative_to(ROOT)
                line = code.count("\n", 0, match.start()) + 1
                violations.append(
                    f"{relative}:{line}: {description}: {match.group(0)!r}"
                )

    assert not violations, "\n".join(violations)


def test_semantic_hook_installation_is_owned_by_uidl_core_modules() -> None:
    owners: set[Path] = set()

    for path in sorted(AKASHIC.rglob("*.f")):
        if path == UIDL_CORE:
            continue
        code = _forth_code(path.read_text(encoding="utf-8"))
        if re.search(r"(?<![A-Z0-9_-])EL-SET-SEMANTICS(?![A-Z0-9_-])", code):
            owners.add(path)

    assert owners == {UIDL_SEMANTIC_CORE}

    uidl_doc = " ".join(UIDL_DOC.read_text(encoding="utf-8").split())
    semantic_doc = " ".join(
        UIDL_SEMANTIC_DOC.read_text(encoding="utf-8").split()
    )
    assert "core element-definition authority, not an application extension point" in (
        uidl_doc.lower()
    )
    assert "hook installation is restricted to reviewed core element-definition modules" in (
        semantic_doc.lower()
    )


def test_documented_boundary_keeps_applets_as_targets_only() -> None:
    projection = " ".join(PROJECTION_CONTRACT.read_text(encoding="utf-8").split())
    architecture = " ".join(
        ARCHITECTURE_CONTRACT.read_text(encoding="utf-8").split()
    )

    for phrase in (
        "Pad and Daybook are acceptance targets, not semantic providers",
        "There is no generic mounted-provider registry",
        "automatically by residual `GLYPH_RUN`s",
        "Collection capability bit 9 remains off",
        "That dependency inversion is complete",
        "beneath both the canonical widget library and UIDL-TUI",
    ):
        assert phrase.lower() in projection.lower()

    for phrase in (
        "Pad and Daybook are acceptance targets, never collection providers",
        "Applet-authored semantic snapshots are removed",
        "collection capability bit 9 remains off",
        "custom applet panels require no semantic adapter",
    ):
        assert phrase.lower() in architecture.lower()
