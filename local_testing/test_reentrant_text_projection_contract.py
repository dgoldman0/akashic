"""Lightweight contracts for non-yielding caller-state text helpers."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
UTF8 = ROOT / "akashic" / "text" / "utf8.f"
CELL_WIDTH = ROOT / "akashic" / "text" / "cell-width.f"
UTF8_DOC = ROOT / "docs" / "text" / "utf8.md"
CELL_WIDTH_DOC = ROOT / "docs" / "text" / "cell-width.md"


def _definition(source: str, word: str) -> str:
    match = re.search(
        rf"(?ms)^:\s+{re.escape(word)}(?:\s|$).*?\s;\s*(?:\\[^\n]*)?$",
        source,
    )
    assert match is not None, f"missing Forth definition {word}"
    return match.group(0)


def _has_token(source: str, token: str) -> bool:
    return re.search(rf"(?<!\S){re.escape(token)}(?!\S)", source) is not None


def test_utf8_decode_has_a_distinct_caller_state_path() -> None:
    source = UTF8.read_text(encoding="utf-8")
    decode = _definition(source, "UTF8-DECODE-WITH")
    failure = _definition(source, "_UTF8-DECODE-WITH-FAIL")
    continuation = _definition(source, "_UTF8-DECODE-WITH-CONT")
    validation = _definition(source, "_UTF8-DECODE-WITH-VALID?")
    sequence_length = _definition(source, "_UTF8-SEQLEN")
    continuation_test = _definition(source, "_UTF8-CONT?")
    display_unsafe = _definition(source, "UTF8-DISPLAY-UNSAFE?")
    display_cp = _definition(source, "UTF8-DISPLAY-CP")
    wrapper = _definition(source, "UTF8-DECODE")

    for declaration in (
        "0 CONSTANT _UTF8-DS-A",
        "8 CONSTANT _UTF8-DS-L",
        "16 CONSTANT _UTF8-DS-CP",
        "24 CONSTANT _UTF8-DS-NEED",
        "32 CONSTANT UTF8-DECODE-STATE-SIZE",
    ):
        assert declaration in source

    assert "CREATE _UTF8-DECODE-STATE UTF8-DECODE-STATE-SIZE ALLOT" in source
    assert "_UTF8-DECODE-STATE UTF8-DECODE-WITH" in wrapper
    assert "VARIABLE _UD-" not in source

    # Every continuation is unrolled: the return stack always contains the
    # caller state, never a DO-loop index, and each source byte is read once.
    for offset in (1, 2, 3):
        assert f"{offset} R@ _UTF8-DECODE-WITH-CONT" in decode
    assert not _has_token(decode, "DO")
    assert not _has_token(decode, "LOOP")
    assert continuation.count("C@") == 1
    assert "_UTF8-CONT?" in continuation
    assert "_UTF8-DS-CP + !" in continuation

    closure = (
        decode
        + failure
        + continuation
        + validation
        + sequence_length
        + continuation_test
        + display_unsafe
        + display_cp
    )
    forbidden = (
        "WITH-GUARD",
        "GUARD-ACQUIRE",
        "YIELD",
        "YIELD?",
        "PAUSE",
        "ALLOCATE",
        "RESIZE",
        "FREE",
        "CATCH",
        "THROW",
        "EXECUTE",
    )
    for word in forbidden:
        assert not _has_token(closure, word)
    for prefix in ("SCR-", "TASK-", "SEM-", "EVT-"):
        assert prefix not in closure
    assert "_UTF8-DECODE-STATE" not in decode

    # Only the shared-state compatibility API is wrapped by the module guard.
    assert "' UTF8-DECODE     CONSTANT _utf8-decode-xt" in source
    assert "' UTF8-DECODE-WITH" not in source
    assert ": UTF8-DECODE     _utf8-decode-xt _utf8-guard WITH-GUARD ;" in source


def test_utf8_caller_state_path_preserves_failure_and_scalar_rules() -> None:
    source = UTF8.read_text(encoding="utf-8")
    decode = _definition(source, "UTF8-DECODE-WITH")
    failure = _definition(source, "_UTF8-DECODE-WITH-FAIL")
    valid = _definition(source, "_UTF8-DECODE-WITH-VALID?")

    assert "UTF8-REPLACEMENT -ROT" in failure
    assert "_UTF8-DS-A + @ 1+" in failure
    assert "_UTF8-DS-L + @ 1-" in failure
    assert decode.count("_UTF8-DECODE-WITH-FAIL EXIT") == 5
    for boundary in ("0x10FFFF", "0xD800", "0xDFFF", "0x80", "0x800", "0x10000"):
        assert boundary in valid
    assert "_UTF8-DECODE-WITH-VALID? 0= IF" in decode
    assert "UTF8-REPLACEMENT R@ _UTF8-DS-CP + !" in decode


def test_cell_width_has_reentrant_search_and_projection_paths() -> None:
    source = CELL_WIDTH.read_text(encoding="utf-8")
    utf8_source = UTF8.read_text(encoding="utf-8")
    search = _definition(source, "_CW-BSEARCH-WITH")
    compare = _definition(source, "_CW-ENTRY-CMP")
    width = _definition(source, "CW-WIDTH-WITH")
    projection = _definition(source, "CW-CELL-CP-WITH")
    width_wrapper = _definition(source, "CW-WIDTH")
    projection_wrapper = _definition(source, "CW-CELL-CP")

    for declaration in (
        "0 CONSTANT _CW-BS-LO",
        "8 CONSTANT _CW-BS-HI",
        "16 CONSTANT _CW-BS-MID",
        "24 CONSTANT CW-STATE-SIZE",
    ):
        assert declaration in source

    assert "CREATE _CW-STATE CW-STATE-SIZE ALLOT" in source
    assert "_CW-STATE CW-WIDTH-WITH" in width_wrapper
    assert "_CW-STATE CW-CELL-CP-WITH" in projection_wrapper
    assert "VARIABLE _CB-" not in source

    assert "BEGIN" in search and "AGAIN" in search
    assert not _has_token(search, "DO")
    assert not _has_token(search, "LOOP")
    assert "_CW-ENTRY-CMP" in search
    assert "_CW-ZERO-TBL _CW-ZERO-N R@ _CW-BSEARCH-WITH" in width
    assert "_CW-WIDE-TBL _CW-WIDE-N R@ _CW-BSEARCH-WITH" in width
    assert "UTF8-DISPLAY-CP" in projection
    assert "R@ CW-WIDTH-WITH" in projection

    closure = (
        search
        + compare
        + width
        + projection
        + _definition(utf8_source, "UTF8-DISPLAY-CP")
        + _definition(utf8_source, "UTF8-DISPLAY-UNSAFE?")
    )
    for word in (
        "WITH-GUARD",
        "YIELD",
        "YIELD?",
        "PAUSE",
        "ALLOCATE",
        "RESIZE",
        "FREE",
        "CATCH",
        "THROW",
        "EXECUTE",
    ):
        assert not _has_token(closure, word)
    for prefix in ("SCR-", "TASK-", "SEM-", "EVT-"):
        assert prefix not in closure
    assert "_CW-STATE" not in width + projection

    assert "' CW-WIDTH-WITH" not in source
    assert "' CW-CELL-CP-WITH" not in source
    assert ": CW-WIDTH   _cw-width-xt  _cw-guard WITH-GUARD ;" in source
    assert ": CW-CELL-CP _cw-cell-cp-xt _cw-guard WITH-GUARD ;" in source


def test_reentrant_helper_ownership_is_documented() -> None:
    utf8 = UTF8_DOC.read_text(encoding="utf-8")
    width = CELL_WIDTH_DOC.read_text(encoding="utf-8")

    for phrase in (
        "UTF8-DECODE-WITH",
        "UTF8-DECODE-STATE-SIZE",
        "caller-owned state",
        "overlap it with the\nsource buffer",
    ):
        assert phrase in utf8
    assert re.search(r"must\s+not share", utf8)

    for phrase in (
        "CW-WIDTH-WITH",
        "CW-CELL-CP-WITH",
        "CW-STATE-SIZE",
        "caller-owned scratch",
        "must not overlap the read-only\nrange tables",
    ):
        assert phrase in width
