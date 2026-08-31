"""Lock rich-terminal and collection semantics below the applet layer."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
APPLETS = ROOT / "akashic" / "tui" / "applets"
PROJECTION_CONTRACT = ROOT / "docs" / "rich-terminal" / "UIDL-PROJECTION-CANDIDATE.md"
ARCHITECTURE_CONTRACT = ROOT / "docs" / "rich-terminal" / "AKASHIC-RICH-TERMINAL.md"

FORBIDDEN_IMPORT = re.compile(
    r"(?im)^\s*(?:REQUIRE|INCLUDE|INCLUDED)\s+"
    r"\S*(?:rich-terminal|uidl-semantic-collections)\S*"
)
FORBIDDEN_TOKEN = re.compile(
    r"(?<![A-Z0-9_-])(?:USCOL-|UTUI-SEMANTIC-)[A-Z0-9_?!@+*/<>=.-]*",
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


def test_documented_boundary_keeps_applets_as_targets_only() -> None:
    projection = " ".join(PROJECTION_CONTRACT.read_text(encoding="utf-8").split())
    architecture = " ".join(
        ARCHITECTURE_CONTRACT.read_text(encoding="utf-8").split()
    )

    for phrase in (
        "Pad and Daybook are acceptance targets, not semantic providers",
        "Production applets may not call them",
        "automatically by residual `GLYPH_RUN`s",
        "Collection capability bit 9 remains off",
        "That lower path also requires dependency inversion",
    ):
        assert phrase.lower() in projection.lower()

    for phrase in (
        "Pad and Daybook are acceptance targets, never collection providers",
        "prohibited to production applets",
        "collection capability bit 9 remains off",
        "custom applet panels require no semantic adapter",
    ):
        assert phrase.lower() in architecture.lower()
