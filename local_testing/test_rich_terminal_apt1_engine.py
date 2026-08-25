"""Seconds-only structural qualification for the neutral APT-1 engine."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "akashic" / "tui" / "rich-terminal" / "apt1-engine.f"


def _definition(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*(?:\\[^\n]*)?$", source
    )
    assert match is not None, f"missing Forth definition {name}"
    return match.group(0)


def test_rich_terminal_engine_owner_lifecycle_structure() -> None:
    source = SOURCE.read_text(encoding="utf-8")

    provider = "akashic-tui-rtapt1"
    assert f"PROVIDED {provider}" in source
    assert len(provider.encode("ascii")) <= 23
    assert not re.search(r"(?m)^REQUIRE\s+.*presentation-terminal\.f\s*$", source)
    assert "REQUIRE ../../utils/memory-span.f" in source
    assert " CONSTANT APTR-" not in source
    assert "\n: APTR-" not in source
    assert "104 CONSTANT RTAPT-OWNER-SIZE" in source
    assert ": _RTAPT-O.PRIOR-GENERATION" in source

    config = _definition(source, "RTAPT-CONFIG-INIT")
    init = _definition(source, "RTAPT-INIT")
    fini = _definition(source, "RTAPT-FINI")
    assert "_RTAPT-CONFIG-RANGES?" in config
    assert "_RTAPT-ENGINE-DISJOINT?" in init
    assert "PT-RETAINED-DISCOVER" in init
    assert "_RTAPT-E.OWNER-CAP" in init
    assert "_RTAPT-E.OP-CAP" in init
    assert init.index("_RTAPT-ENGINE-MAGIC = IF") < init.index(
        "PT-RETAINED-DISCOVER"
    )
    assert "_RTAPT-E.OWNER-USED" in fini
    assert "RTAPT-S-BUSY" in fini
    assert "_RTAPT-SESSION-ENDED?" in fini

    ranges = _definition(source, "_RTAPT-CONFIG-RANGES?")
    engine_ranges = _definition(source, "_RTAPT-ENGINE-DISJOINT?")
    assert ranges.count("MSPAN-OVERLAP?") == 10
    assert ranges.count("PT-STORAGE-DISJOINT?") == 4
    assert engine_ranges.count("MSPAN-OVERLAP?") == 5
    assert engine_ranges.count("PT-STORAGE-DISJOINT?") == 1
    assert "RTAPT-OWNER-SIZE MOD" in ranges
    assert "RTAPT-OP-SIZE MOD" in ranges
    assert "_RTAPT-CI-CU @ 7 AND" not in ranges

    validate = _definition(source, "_RTAPT-ENGINE-VALID?")
    quarantine_coherent = _definition(source, "_RTAPT-QUARANTINE-COHERENT?")
    stored_ranges = _definition(source, "_RTAPT-ENGINE-RANGES?")
    assert "_RTAPT-ENGINE-RANGES?" in validate
    assert validate.index("_RTAPT-ENGINE-MAGIC <>") < validate.index(
        "_RTAPT-ENGINE-RANGES?"
    )
    assert stored_ranges.count("PT-STORAGE-DISJOINT?") == 4
    assert stored_ranges.count("MSPAN-OVERLAP?") == 6
    assert "_RTAPT-OWNER-POINTER-OR-ZERO?" in validate
    assert "_RTAPT-ACTIVE-QUARANTINED" in validate
    assert "RTAPT-OWNER-ST-TOMBSTONE-DROPPING" in validate
    assert "_RTAPT-QUARANTINE-COHERENT?" in validate
    assert "_RTAPT-E.OWNER-CAP @ 0 ?DO" in quarantine_coherent
    assert "RTAPT-OWNER-ST-FREE" in quarantine_coherent
    assert "RTAPT-OWNER-ST-QUARANTINED" in quarantine_coherent
    assert "_RTAPT-QV-EXPECT @ <>" in quarantine_coherent

    quarantine = _definition(source, "_RTAPT-QUARANTINE-ALL")
    assert "_RTAPT-E.OWNER-CAP @ 0 ?DO" in quarantine
    assert "RTAPT-OWNER-ST-QUARANTINED" in quarantine
    assert "_RTAPT-E.QUEUE-HEAD" in quarantine
    assert "_RTAPT-E.QUEUE-TAIL" in quarantine
    assert "_RTAPT-ACTIVE-QUARANTINED" in quarantine
    assert "_RTAPT-O.NEXT" in quarantine

    tombstone = _definition(source, "_RTAPT-OWNER>TOMBSTONE")
    restore_tombstone = _definition(source, "_RTAPT-OWNER-RESTORE-TOMBSTONE")
    assert "RTAPT-OWNER-SIZE 0 FILL" in tombstone
    assert "_RTAPT-O.OWNER" in tombstone
    assert "_RTAPT-O.GENERATION" in tombstone
    assert "RTAPT-OWNER-ST-TOMBSTONE" in tombstone
    assert "_RTAPT-O.PRIOR-GENERATION" in restore_tombstone
    assert "RTAPT-OWNER-SIZE 0 FILL" in restore_tombstone

    owner_open = _definition(source, "RTAPT-OWNER-OPEN")
    owner_drop = _definition(source, "RTAPT-OWNER-DROP")
    send = _definition(source, "_RTAPT-OWNER-SEND")
    reconcile_open = _definition(source, "_RTAPT-RECONCILE-OPEN")
    reconcile_drop = _definition(source, "_RTAPT-RECONCILE-DROP")
    assert "_RTAPT-OWNER-ID-FIND" in owner_open
    assert "_RTAPT-OWNER-FREE-SLOT" in owner_open
    assert "RTAPT-OWNER-ST-TOMBSTONE" in owner_open
    assert "_RTAPT-OO-GEN @ U<" in owner_open
    assert "_RTAPT-OO-REUSED" in owner_open
    assert "_RTAPT-OO-PRIOR-GEN" in owner_open
    assert "RTAPT-OWNER-ST-TOMBSTONE-OPEN-QUEUED" in owner_open
    assert "_RTAPT-QUEUE-PUSH" in owner_open
    assert "RTAPT-OWNER-ST-TOMBSTONE-DROP-QUEUED" in owner_drop
    assert "RTAPT-OWNER-ST-DROP-RETRY-QUEUED" in owner_drop
    assert "PT-TX-RESULT-INVALID" in owner_drop
    assert "PT-TX-RESULT-STALE" in owner_drop
    assert "PT-OWNER-OPEN" in send
    assert "PT-OWNER-DROP" in send
    assert "RTAPT-OWNER-ST-TOMBSTONE-OPENING" in send
    assert "RTAPT-OWNER-ST-TOMBSTONE-DROPPING" in send
    assert "PT-COMPLETE-RET PT-REQUEST-OWNER-OPEN" in reconcile_open
    assert "_RTAPT-OWNER-RESTORE-TOMBSTONE" in reconcile_open
    assert "_RTAPT-O.PRIOR-GENERATION" in reconcile_open
    assert "PT-COMPLETE-TX PT-REQUEST-OWNER-DROP" in reconcile_drop
    assert "_RTAPT-OWNER-CLEAR" not in reconcile_drop
    assert "PT-TX-RESULT-OK = IF" in reconcile_drop
    assert "RTAPT-OWNER-ST-TOMBSTONE" in reconcile_drop
    assert "RTAPT-OWNER-ST-DROPPING" in reconcile_drop
    assert reconcile_drop.count("_RTAPT-OWNER>TOMBSTONE") == 2
    assert "PT-TX-RESULT-ABORTED" in reconcile_drop
    assert "_RTAPT-QUARANTINE-ALL" in reconcile_drop

    step = _definition(source, "RTAPT-STEP")
    assert "_RTAPT-POLL-COMPLETION" in step
    assert step.count("_RTAPT-QUEUE-POP") == 1
    assert step.count("_RTAPT-OWNER-SEND") == 1
    assert step.index("_RTAPT-READY-STATUS") < step.index(
        "_RTAPT-E.QUEUE-HEAD @ 0= IF"
    )
    assert step.index("_RTAPT-E.QUEUE-HEAD @") < step.index("_RTAPT-OWNER-SEND")
    assert step.index("_RTAPT-OWNER-SEND") < step.index("_RTAPT-QUEUE-POP")
    assert step.index("_RTAPT-ACTIVE-NONE <> IF") < step.index(
        "_RTAPT-POLL-COMPLETION"
    )
    assert "_RTAPT-OWNER-ADMISSION-FAILED" in step
    assert "_RTAPT-ST-PT @ RTAPT-S-SESSION-LOST = IF" in step
    assert "_RTAPT-QUARANTINE-ALL" in step
    assert "_RTAPT-ACTIVE-QUARANTINED" in step
    assert "_RTAPT-QUARANTINE-ALL" in reconcile_open
    assert "PT-SERVICE" not in step

    # PT's public surface is the engine's lower boundary.  Depending on a PT
    # private word would duplicate or bypass its wire/session authority.
    assert not re.search(r"(?<!RTAPT)\b_PT-", source)
