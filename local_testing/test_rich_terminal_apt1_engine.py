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
    assert not re.search(
        r"(?m)^REQUIRE\s+.*(?:presentation-terminal|rich-terminal)\.f\s*$",
        source,
    )
    assert "REQUIRE ../../utils/memory-span.f" in source
    assert " CONSTANT APTR-" not in source
    assert "\n: APTR-" not in source
    assert "144 CONSTANT RTAPT-OWNER-SIZE" in source
    assert ": _RTAPT-O.PRIOR-GENERATION" in source
    assert ": _RTAPT-O.ACTIVE-REGIONS" in source
    assert ": _RTAPT-O.HIDDEN-REGIONS" in source
    assert ": _RTAPT-O.REGION-HIGH" in source
    assert ": _RTAPT-O.PENDING-REGIONS" in source
    assert ": _RTAPT-O.PENDING-REGION-HIGH" in source
    assert "72 CONSTANT _RTAPT-REGION-DEFINE-COPY-SIZE" in source
    assert "88 CONSTANT _RTAPT-REGION-DEFINE-FRAME-BYTES" in source

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

    captured = _definition(source, "_RTAPT-CAPTURED-BANKS?")
    ledgers = _definition(source, "_RTAPT-OWNER-LEDGERS?")
    rich_begin = _definition(source, "RTAPT-RICH-BEGIN")
    region_define = _definition(source, "RTAPT-REGION-DEFINE")
    rich_seal = _definition(source, "RTAPT-RICH-SEAL")
    rich_cancel = _definition(source, "RTAPT-RICH-CANCEL")
    candidate_preflight = _definition(source, "_RTAPT-CANDIDATE-PREFLIGHT?")
    cell_begin = _definition(source, "RTAPT-CELL-BEGIN")
    cell_span = _definition(source, "RTAPT-CELL-SPAN-BEGIN")
    cell_write = _definition(source, "RTAPT-CELL-WRITE")
    cell_cursor = _definition(source, "RTAPT-CELL-CURSOR")
    cell_abort = _definition(source, "RTAPT-CELL-ABORT")
    abort_open = _definition(source, "_RTAPT-ABORT-OPEN")
    cell_commit = _definition(source, "RTAPT-CELL-COMMIT")
    commit_failed = _definition(source, "_RTAPT-COMMIT-FAILED")
    reconcile_output = _definition(source, "_RTAPT-RECONCILE-OUTPUT")
    apply_output = _definition(source, "_RTAPT-APPLY-OUTPUT")
    output_identity = _definition(source, "_RTAPT-OUTPUT-COMPLETION?")
    poll_completion = _definition(source, "_RTAPT-POLL-COMPLETION")
    storage_disjoint = _definition(source, "RTAPT-STORAGE-DISJOINT?")

    assert "_RTAPT-E.OP-CAP" in captured
    assert "_RTAPT-E.OP-COUNT @ _RTAPT-U32?" in captured
    assert "_RTAPT-E.COPY-U" in captured
    assert "_RTAPT-REGION-DEFINE-COPY-SIZE" in captured
    assert "_RTAPT-REGION-DEFINE-FRAME-BYTES" in captured
    assert "_RTAPT-E.RET-BYTES" in captured
    assert "PT-RET-DELTA" in ledgers
    assert "PT-RET-REPLACE-START" in ledgers
    assert "PT-RET-LAYOUT-START" in ledgers
    assert "_RTAPT-O.ACTIVE-REGIONS" in ledgers
    assert "_RTAPT-O.HIDDEN-REGIONS" in ledgers

    assert "PT-PRESENT-BEGIN" not in rich_begin
    assert "RTAPT-UPDATE-CAPTURING" in rich_begin
    assert "_RTAPT-E.OP-CAP" in region_define
    assert "_RTAPT-E.OP-COUNT @ 0xFFFFFFFF U<" in region_define
    assert "_RTAPT-E.COPY-U" in region_define
    assert "_RTAPT-O.REGION-HIGH" in region_define
    assert "_RTAPT-O.PENDING-REGION-HIGH" in region_define
    assert "_RTAPT-O.PENDING-REGIONS" in region_define
    assert not re.search(r"(?<!R)\bPT-REGION-DEFINE\b", region_define)
    assert "_RTAPT-MODE-DISPOSITION?" in rich_seal
    assert "RTAPT-UPDATE-SEALED" in rich_seal
    assert "_RTAPT-CANDIDATE-DISCARD" in rich_cancel

    assert "_RTAPT-REGION-COPY-SHAPE?" in candidate_preflight
    assert "_RTAPT-O.REGION-HIGH" in candidate_preflight
    assert "_RTAPT-O.PENDING-REGIONS" in candidate_preflight
    assert cell_begin.count("PT-PRESENT-BEGIN") == 2
    assert cell_begin.index("_RTAPT-CANDIDATE-PREFLIGHT?") < cell_begin.index(
        "PT-PRESENT-BEGIN"
    )
    assert "PT-RET-NONE" in cell_begin
    assert "RTAPT-COUPLING-CELL" in cell_begin
    assert "RTAPT-COUPLING-RETAINED" in cell_begin
    assert "RTAPT-UPDATE-CELL-OPEN" in cell_begin
    assert "PT-SPAN-BEGIN" in cell_span
    assert "PT-CELL" in cell_write
    assert "PT-CURSOR" in cell_cursor
    assert "_RTAPT-ABORT-OPEN" in cell_abort

    assert "_RTAPT-SEND-CAPTURED" in cell_commit
    assert cell_commit.index("_RTAPT-CANDIDATE-PREFLIGHT?") < cell_commit.index(
        "_RTAPT-SEND-CAPTURED"
    )
    assert "PT-PRESENT-COMMIT" in cell_commit
    assert "_RTAPT-COMMIT-FAILED" in cell_commit
    assert "RTAPT-UPDATE-AWAITING" in cell_commit
    assert "_RTAPT-ACTIVE-OUTPUT" in cell_commit
    assert "PT-TX-ABORT" in abort_open
    assert "_RTAPT-WIRE-REWIND" in abort_open
    assert "_RTAPT-ABORT-OPEN" in commit_failed
    assert "_RTAPT-CANDIDATE-DISCARD" in reconcile_output
    assert "_RTAPT-WIRE-REWIND" in reconcile_output
    assert "RTAPT-COUPLING-RETAINED" in reconcile_output
    assert "_RTAPT-QUARANTINE-ALL" in reconcile_output
    assert "PT-REQUEST-PRESENT-COMMIT" in output_identity
    assert "PT-COMPLETION-TXID@ 0<>" in output_identity
    assert "PT-COMPLETION-DETAIL@ 0=" in output_identity
    assert "_RTAPT-APPLY-OUTPUT" in reconcile_output
    assert "PT-RET-REPLACE-START" in apply_output
    assert "PT-RET-LAYOUT-START" in apply_output
    assert "PT-COMMIT-AND-REVEAL" in apply_output
    assert "_RTAPT-ACTIVE-OUTPUT" in poll_completion

    assert "RTAPT-USES-SESSION?" in source
    assert "RTAPT-SESSION@" not in source
    assert "PT-STORAGE-DISJOINT?" in storage_disjoint
    assert storage_disjoint.count("MSPAN-OVERLAP?") == 4
    assert "PT-SERVICE" not in source.replace(
        "It never calls PT-SERVICE and cannot consume input events.", ""
    )

    # PT's public surface is the engine's lower boundary.  Depending on a PT
    # private word would duplicate or bypass its wire/session authority.
    assert not re.search(r"(?<!RTAPT)\b_PT-", source)
