"""Seconds-only structural locks for the optional UIDL rich-terminal driver."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DRIVER = ROOT / "akashic" / "tui" / "rich-terminal" / "uidl-driver.f"
UIDL = ROOT / "akashic" / "tui" / "uidl-tui.f"
REGION = ROOT / "akashic" / "tui" / "region.f"


def _definition(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:\s+{re.escape(name)}(?=\s).*?;\s*(?:\\[^\n]*)?$",
        source,
    )
    assert match is not None, f"missing Forth definition {name}"
    return match.group(0)


def _code_without_comments(source: str) -> str:
    return "\n".join(line.split("\\", 1)[0] for line in source.splitlines())


def test_driver_is_optional_neutral_and_caller_bounded() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    code = _code_without_comments(source)

    assert "PROVIDED akashic-tui-rterm-uidl1" in code
    assert re.findall(r"(?m)^REQUIRE\s+(\S+)\s*$", code) == [
        "../applet-host/host.f",
        "../color.f",
        "../../utils/memory-span.f",
        "engine.f",
        "uidl-projector.f",
    ]

    # This driver is a host/UIDL lifecycle boundary, not another terminal
    # transport or output engine and not part of their source closure.
    assert not re.search(r"(?<![A-Z0-9_-])_?PT-", code)
    for forbidden in (
        "RTAPT-",
        "_RTAPT-",
        "APTSCB-",
        "PRESENT-",
        "PRESENT_",
        "UART-",
        "rich-terminal.f",
        "apt1-engine.f",
        "engine-apt1.f",
        "screen-adapter-apt1.f",
    ):
        assert forbidden not in code

    # VARIABLE cells hold bounded scalar working state, but the module owns no
    # caller payload buffer and performs no dictionary or heap allocation.
    assert not re.search(
        r"(?m)(?:^|[ \t])(?:CREATE|ALLOT|ALLOCATE|FREE|RESIZE|XBUF)"
        r"(?=[ \t]|$)",
        code,
    )
    assert "RTERM-UIDL-BINDING-SIZE /" in code
    assert "RTERM-UIDL-BACKEND-SIZE 0 FILL" in code
    assert "RTERM-UIDL-BINDING-SIZE 0 FILL" in code
    assert "ELIGIBLE-BYTES" not in code


def test_public_contract_has_exact_statuses_sizes_and_entry_points() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    region = REGION.read_text(encoding="utf-8")

    assert re.findall(
        r"(?m)^(RTE-S-[A-Z-]+)\s+CONSTANT (RTERM-S-[A-Z-]+)\s*$",
        source,
    ) == [
        ("RTE-S-OK", "RTERM-S-OK"),
        ("RTE-S-WOULD-BLOCK", "RTERM-S-WOULD-BLOCK"),
        ("RTE-S-UNAVAILABLE", "RTERM-S-UNAVAILABLE"),
        ("RTE-S-CAPACITY", "RTERM-S-CAPACITY"),
        ("RTE-S-STALE", "RTERM-S-STALE"),
        ("RTE-S-INVALID", "RTERM-S-INVALID"),
        ("RTE-S-SESSION-LOST", "RTERM-S-SESSION-LOST"),
        ("RTE-S-SOURCE", "RTERM-S-SOURCE"),
    ]
    assert "8 U<" in _definition(source, "RTERM-STATUS-VALID?")

    assert "96 CONSTANT RTERM-HOST-BINDING-SIZE" in source
    assert "32 CONSTANT RTERM-SURFACE-SNAPSHOT-SIZE" in source
    assert "104 CONSTANT RTERM-UIDL-CONFIG-SIZE" in source
    assert "8 CONSTANT _RTERM-UIDL-ABI" in source
    assert "7 CONSTANT _RTERM-UIDL-CONFIG-ABI" in source
    assert "64 CONSTANT _RTERM-CANDIDATE-META-SIZE" in source
    assert "32 CONSTANT _RTERM-IDENTITY-SIZE" in source
    assert "384 CONSTANT RTERM-UIDL-BINDING-SIZE" in source
    assert "512 CONSTANT RTERM-UIDL-BACKEND-SIZE" in source
    assert "_RGN-DESC-SIZE CONSTANT RGN-SIZE" in region
    assert "RTERM-SURFACE-SNAPSHOT-SIZE" in _definition(
        source, "RTERM-SURFACE-SNAPSHOT-BYTES"
    )
    assert "RTERM-UIDL-CONFIG-SIZE" in _definition(
        source, "RTERM-UIDL-CONFIG-BYTES"
    )
    assert "RTERM-UIDL-BINDING-SIZE" in _definition(
        source, "RTERM-UIDL-BINDING-BYTES"
    )
    assert "RTERM-UIDL-BACKEND-SIZE" in _definition(
        source, "RTERM-UIDL-BACKEND-BYTES"
    )
    assert "RUPJ-ITEM-BYTES" in _definition(
        source, "RTERM-UIDL-CANDIDATE-ITEM-BYTES"
    )
    assert "_RTERM-IDENTITY-SIZE" in _definition(
        source, "RTERM-UIDL-CANDIDATE-IDENTITY-BYTES"
    )

    # Candidate authority is positional in the caller-owned A/B banks.  A
    # binding stores only one selector and two fixed metadata records.
    binding_fields = {
        "_RTERM-R.LAST-STATUS": 128,
        "_RTERM-R.CANDIDATE": 136,
        "_RTERM-R.CANDIDATE-A": 144,
        "_RTERM-R.CANDIDATE-B": 208,
        "_RTERM-R.OWNER": 272,
        "_RTERM-R.OWNER-GEN": 280,
        "_RTERM-R.ROOT-REGION": 288,
        "_RTERM-R.OBJECT-HIGH": 296,
        "_RTERM-R.ELIGIBLE": 304,
        "_RTERM-R.ELIGIBLE-GEN": 312,
        "_RTERM-R.ELIGIBLE-REGIONS": 320,
        "_RTERM-R.ELIGIBLE-OBJECTS": 328,
        "_RTERM-R.ELIGIBLE-UTF8": 336,
        "_RTERM-R.MAT-STATE": 344,
        "_RTERM-R.STAGED-GEN": 352,
        "_RTERM-R.MATERIALIZED-GEN": 360,
        "_RTERM-R.MATERIALIZED-SURFACE-GEN": 368,
        "_RTERM-R.RESERVED": 376,
    }
    for field, offset in binding_fields.items():
        assert f": {field}" in source
        assert f"{offset} +" in _definition(source, field)
    for field, offset in {
        "_RTERM-K.ITEMS": 8,
        "_RTERM-K.SNAPSHOTS": 16,
        "_RTERM-K.REGIONS": 24,
        "_RTERM-K.OBJECTS": 32,
        "_RTERM-K.UTF8": 40,
        "_RTERM-K.ROOT-H": 48,
        "_RTERM-K.ROOT-W": 56,
    }.items():
        assert f"{offset} +" in _definition(source, field)

    assert "+" not in _definition(source, "_RTERM-S.COLS")
    for field, offset in {
        "_RTERM-S.ROWS": 8,
        "_RTERM-S.GENERATION": 16,
        "_RTERM-S.RESERVED": 24,
    }.items():
        assert f"{offset} +" in _definition(source, field)

    signatures = {
        "RTERM-STATUS-VALID?": "( status -- flag )",
        "RTERM-SURFACE-SNAPSHOT-BYTES": "( -- bytes )",
        "RTERM-SURFACE-SNAPSHOT-VALID?": "( surface -- flag )",
        "RTERM-SURFACE-SNAPSHOT-INIT": (
            "( cols rows generation surface -- status )"
        ),
        "RTERM-UIDL-CONFIG-BYTES": "( -- bytes )",
        "RTERM-UIDL-BINDING-BYTES": "( -- bytes )",
        "RTERM-UIDL-BACKEND-BYTES": "( -- bytes )",
        "RTERM-UIDL-CANDIDATE-ITEM-BYTES": "( -- bytes )",
        "RTERM-UIDL-CANDIDATE-IDENTITY-BYTES": "( -- bytes )",
        "RTERM-UIDL-CONFIG-INIT": (
            "( host engine records-a records-u items-a items-per-bank\n"
            "    identities-a snapshots-a snapshot-bank-u config -- status )"
        ),
        "RTERM-UIDL-INIT": "( config backend -- status )",
        "RTERM-UIDL-FINI": "( backend -- status )",
        "RTERM-UIDL-VALID?": "( backend -- flag )",
        "RTERM-UIDL-STORAGE-DISJOINT?": "( a u backend -- flag )",
        "RTERM-UIDL-STATUS@": "( backend -- status )",
        "RTERM-UIDL-ACTIVE@": "( backend -- count status )",
        "RTERM-BACKEND-STEP": (
            "( cols rows generation budget backend -- status more? "
            "output-needed? )"
        ),
        "RTERM-BACKEND-PREPARE": (
            "( cols rows generation backend -- status )"
        ),
        "RTERM-HOST-BINDING-INIT": "( host-binding -- )",
        "RTERM-HOST-BINDING-VALID?": "( host-binding -- flag )",
        "RTERM-HOST-BINDING-CAPTURE": (
            "( host slot host-binding -- status )"
        ),
        "RTERM-AHOST-UIDL-READY": (
            "( host slot host-binding -- ior )"
        ),
        "RTERM-UCTX-ATTACH": "( host-binding backend -- binding-token status )",
        "RTERM-UCTX-PROJECT": "( binding-token backend -- status )",
        "RTERM-UCTX-MATERIALIZATION-PREFLIGHT": (
            "( surface binding-token backend -- status )"
        ),
        "RTERM-UCTX-RELAYOUT": (
            "( visible region binding-token backend -- status )"
        ),
        "RTERM-UCTX-QUIESCE": "( binding-token backend -- status )",
        "RTERM-UCTX-DETACH": "( binding-token backend -- status )",
        "RTERM-UIDL-INSTALL": "( backend -- status )",
    }
    public_words = re.findall(r"(?m)^:\s+(RTERM-[^\s]+)(?=\s)", source)
    assert set(public_words) == set(signatures)
    assert len(public_words) == len(signatures)
    for name, signature in signatures.items():
        assert signature in _definition(source, name)


def test_materializer_schema_is_persistent_neutral_and_lifecycle_validated() -> None:
    source = DRIVER.read_text(encoding="utf-8")

    for field, offset in {
        "_RTERM-B.LIMITS": 160,
        "_RTERM-B.EPOCH": 320,
        "_RTERM-B.MAT": 328,
        "_RTERM-B.RESERVED": 504,
    }.items():
        assert f"{offset} +" in _definition(source, field)

    assert "+" not in _definition(source, "_RTERM-M.PHASE")
    for field, offset in {
        "_RTERM-M.FLAGS": 8,
        "_RTERM-M.SURFACE-COLS": 16,
        "_RTERM-M.SURFACE-ROWS": 24,
        "_RTERM-M.SURFACE-GEN": 32,
        "_RTERM-M.TOKEN": 40,
        "_RTERM-M.RECORD-INDEX": 48,
        "_RTERM-M.SELECTOR": 56,
        "_RTERM-M.CANDIDATE-GEN": 64,
        "_RTERM-M.OWNER": 72,
        "_RTERM-M.OWNER-GEN": 80,
        "_RTERM-M.ITEMS": 88,
        "_RTERM-M.SNAPSHOTS": 96,
        "_RTERM-M.REGIONS": 104,
        "_RTERM-M.OBJECTS": 112,
        "_RTERM-M.UTF8": 120,
        "_RTERM-M.ROOT-H": 128,
        "_RTERM-M.ROOT-W": 136,
        "_RTERM-M.OBJECT-HIGH": 144,
        "_RTERM-M.REGION-X": 152,
        "_RTERM-M.REGION-Y": 160,
        "_RTERM-M.RESERVED": 168,
    }.items():
        assert f"{offset} +" in _definition(source, field)
    assert "176 CONSTANT _RTERM-MAT-SIZE" in source

    assert re.findall(
        r"(?m)^(\d+) CONSTANT (_RTERM-EPOCH-[A-Z-]+)$", source
    ) == [
        ("0", "_RTERM-EPOCH-COLD"),
        ("1", "_RTERM-EPOCH-REBUILD"),
        ("2", "_RTERM-EPOCH-LIVE"),
        ("3", "_RTERM-EPOCH-QUARANTINED"),
    ]
    assert re.findall(
        r"(?m)^(\d+) CONSTANT (_RTERM-MAT-ST-[A-Z-]+)$", source
    ) == [
        ("0", "_RTERM-MAT-ST-NONE"),
        ("1", "_RTERM-MAT-ST-OPENING"),
        ("2", "_RTERM-MAT-ST-OPEN"),
        ("3", "_RTERM-MAT-ST-STAGED"),
        ("4", "_RTERM-MAT-ST-LIVE"),
        ("5", "_RTERM-MAT-ST-DROP-PENDING"),
        ("6", "_RTERM-MAT-ST-DROPPING"),
        ("7", "_RTERM-MAT-ST-QUARANTINED"),
    ]
    assert re.findall(
        r"(?m)^(\d+) CONSTANT (_RTERM-MAT-PHASE-[A-Z-]+)$", source
    ) == [
        ("0", "_RTERM-MAT-PHASE-IDLE"),
        ("1", "_RTERM-MAT-PHASE-COHORT"),
        ("2", "_RTERM-MAT-PHASE-OPENING"),
        ("3", "_RTERM-MAT-PHASE-OPEN"),
        ("4", "_RTERM-MAT-PHASE-HIDDEN-SEALED"),
        ("5", "_RTERM-MAT-PHASE-HIDDEN-AWAITING"),
        ("6", "_RTERM-MAT-PHASE-REVEAL-SEALED"),
        ("7", "_RTERM-MAT-PHASE-REVEAL-AWAITING"),
        ("8", "_RTERM-MAT-PHASE-DROP-PENDING"),
        ("9", "_RTERM-MAT-PHASE-DROPPING"),
        ("10", "_RTERM-MAT-PHASE-QUARANTINED"),
    ]
    for validator, bound in {
        "_RTERM-EPOCH-VALID?": "4 U<",
        "_RTERM-MAT-ST-VALID?": "8 U<",
        "_RTERM-MAT-PHASE-VALID?": "11 U<",
    }.items():
        assert bound in _definition(source, validator)
    assert "1 CONSTANT _RTERM-MAT-F-STARTED" in source
    assert "2 CONSTANT _RTERM-MAT-F-RESTART" in source
    assert "3 CONSTANT _RTERM-MAT-F-MASK" in source

    mat_valid = _definition(source, "_RTERM-MAT-VALID?")
    assert "_RTERM-MAT-PHASE-VALID?" in mat_valid
    assert "_RTERM-MAT-F-MASK INVERT AND" in mat_valid
    assert "_RTERM-MAT-PHASE-IDLE = IF" in mat_valid
    assert "_RTERM-MAT-SIZE _RTERM-ZERO?" in mat_valid
    assert "_RTERM-MAT-PHASE-COHORT = IF" in mat_valid
    for phase_shape in (
        ("DUP _RTERM-MAT-PHASE-COHORT = IF", "_RTERM-MAT-COHORT-SCALARS?"),
        ("DUP _RTERM-MAT-PHASE-OPENING =", "_RTERM-MAT-ACTIVE-SCALARS?"),
        ("OVER _RTERM-MAT-PHASE-OPEN = OR IF", "_RTERM-MAT-ACTIVE-SCALARS?"),
        (
            "DUP _RTERM-MAT-PHASE-HIDDEN-SEALED =",
            "_RTERM-MAT-HIDDEN-SCALARS?",
        ),
        (
            "OVER _RTERM-MAT-PHASE-HIDDEN-AWAITING = OR IF",
            "_RTERM-MAT-HIDDEN-SCALARS?",
        ),
        (
            "DUP _RTERM-MAT-PHASE-REVEAL-SEALED =",
            "_RTERM-MAT-REVEAL-SCALARS?",
        ),
        (
            "OVER _RTERM-MAT-PHASE-REVEAL-AWAITING = OR IF",
            "_RTERM-MAT-REVEAL-SCALARS?",
        ),
        (
            "DUP _RTERM-MAT-PHASE-DROP-PENDING =",
            "_RTERM-MAT-DROP-SCALARS?",
        ),
        (
            "SWAP _RTERM-MAT-PHASE-DROPPING = OR IF",
            "_RTERM-MAT-DROP-SCALARS?",
        ),
    ):
        phase_pattern, shape = phase_shape
        phase_at = mat_valid.index(phase_pattern)
        assert mat_valid.index(shape, phase_at) > phase_at
    assert "_RTERM-MAT-QUARANTINED?" in mat_valid

    active_scalars = _definition(source, "_RTERM-MAT-ACTIVE-SCALARS?")
    for field in (
        "TOKEN",
        "RECORD-INDEX",
        "SELECTOR",
        "CANDIDATE-GEN",
        "OWNER",
        "OWNER-GEN",
        "ITEMS",
        "SNAPSHOTS",
        "REGIONS",
        "OBJECTS",
        "UTF8",
        "ROOT-H",
        "ROOT-W",
        "OBJECT-HIGH",
        "REGION-X",
        "REGION-Y",
    ):
        assert f"_RTERM-M.{field}" in active_scalars
    assert "_RTERM-M.SNAPSHOTS @ 7 AND" in active_scalars
    assert active_scalars.count("_RTERM-LENGTH-MAX U>") == 3
    assert active_scalars.count("_RTERM-UADD?") == 2

    hidden_scalars = _definition(source, "_RTERM-MAT-HIDDEN-SCALARS?")
    for field in (
        "TOKEN",
        "RECORD-INDEX",
        "SELECTOR",
        "CANDIDATE-GEN",
        "OWNER",
        "OWNER-GEN",
    ):
        assert f"_RTERM-M.{field}" in hidden_scalars
    assert "_RTERM-M.ITEMS 80 _RTERM-ZERO?" in hidden_scalars

    drop_scalars = _definition(source, "_RTERM-MAT-DROP-SCALARS?")
    for field in ("TOKEN", "RECORD-INDEX", "OWNER", "OWNER-GEN"):
        assert f"_RTERM-M.{field}" in drop_scalars
    assert "_RTERM-M.SELECTOR 16 _RTERM-ZERO?" in drop_scalars
    assert "_RTERM-M.ITEMS 80 _RTERM-ZERO?" in drop_scalars

    cohort_scalars = _definition(source, "_RTERM-MAT-COHORT-SCALARS?")
    assert "_RTERM-M.TOKEN @ IF" in cohort_scalars
    assert "_RTERM-M.RECORD-INDEX @ 0<" in cohort_scalars
    assert "_RTERM-M.SELECTOR 112 _RTERM-ZERO?" in cohort_scalars

    reveal_scalars = _definition(source, "_RTERM-MAT-REVEAL-SCALARS?")
    assert "_RTERM-MAT-F-STARTED <>" in reveal_scalars
    assert "_RTERM-M.TOKEN @ IF" in reveal_scalars
    assert "_RTERM-B.CAPACITY @ <>" in reveal_scalars
    assert "_RTERM-M.SELECTOR 112 _RTERM-ZERO?" in reveal_scalars
    assert "8 + 168 _RTERM-ZERO?" in _definition(
        source, "_RTERM-MAT-QUARANTINED?"
    )

    record_validated = _definition(
        source, "_RTERM-RECORD-MATERIALIZATION-VALID?"
    )
    for field in (
        "_RTERM-R.MAT-STATE",
        "_RTERM-R.STAGED-GEN",
        "_RTERM-R.MATERIALIZED-GEN",
        "_RTERM-R.MATERIALIZED-SURFACE-GEN",
        "_RTERM-R.RESERVED",
    ):
        assert field in record_validated
    for state in (
        "NONE",
        "OPENING",
        "OPEN",
        "STAGED",
        "LIVE",
        "DROP-PENDING",
        "DROPPING",
        "QUARANTINED",
    ):
        assert f"_RTERM-MAT-ST-{state}" in record_validated
    assert "_RTERM-RECORD-GENERATIONS-VALID?" in record_validated

    record_live = _definition(source, "_RTERM-RECORD-LIVE?")
    materialization = record_live.index(
        "_RTERM-RECORD-MATERIALIZATION-VALID?"
    )
    candidates = record_live.index("_RTERM-RECORD-CANDIDATES-VALID?")
    eligibility = record_live.index("_RTERM-RECORD-ELIGIBILITY-VALID?")
    assert materialization < candidates < eligibility
    record_valid = _definition(source, "_RTERM-RECORD-VALID?")
    assert "RTERM-UIDL-BINDING-SIZE\n            _RTERM-ZERO?" in record_valid

    backend_validated = _definition(
        source, "_RTERM-BACKEND-MATERIALIZATION-VALID?"
    )
    assert "_RTERM-EPOCH-VALID?" in backend_validated
    assert "_RTERM-EPOCH-COLD = IF" in backend_validated
    assert "_RTERM-EPOCH-REBUILD <> IF" in backend_validated
    assert backend_validated.count("_RTERM-MAT-VALID?") == 4
    correlation = _definition(source, "_RTERM-MAT-CORRELATION?")
    for field in (
        "TOKEN",
        "OWNER",
        "OWNER-GEN",
        "ROOT-REGION",
        "COL",
        "ROW",
        "HEIGHT",
        "WIDTH",
    ):
        assert f"_RTERM-R.{field}" in correlation
    valid = _definition(source, "_RTERM-UIDL-VALID-BODY?")
    backend_gate = valid.index("_RTERM-BACKEND-MATERIALIZATION-VALID?")
    geometry = valid.index("_RTERM-UIDL-GEOMETRY?", backend_gate)
    phase = valid.index("_RTERM-B.MAT _RTERM-M.PHASE @", geometry)
    deep_attempt = valid.index("_RTERM-MAT-ATTEMPT-DEEP?", phase)
    attempt = valid.index("_RTERM-ATTEMPT-BANK-ZERO?", deep_attempt)
    record_loop = valid.index("_RTERM-B.CAPACITY @ 0 ?DO", attempt)
    final_correlation = valid.index("_RTERM-MAT-CORRELATION?", record_loop)
    assert (
        backend_gate
        < geometry
        < phase
        < deep_attempt
        < attempt
        < record_loop
        < final_correlation
    )
    assert "_RTERM-MAT-PHASE-OPENING =" in valid[phase:deep_attempt]
    assert "_RTERM-MAT-PHASE-OPEN = OR" in valid[phase:deep_attempt]

    deep = _definition(source, "_RTERM-MAT-ATTEMPT-DEEP?")
    attempt_load = deep.index("_RTERM-ATTEMPT-BANK-LOAD")
    candidate_deep = deep.index("RUPJ-CANDIDATE-VALID?", attempt_load)
    identity_deep = deep.index("_RTERM-IDENTITY-BANK-VALID?", candidate_deep)
    exact_max = deep.index("_RTERM-MAT-ATTEMPT-MAX?", identity_deep)
    assert attempt_load < candidate_deep < identity_deep < exact_max
    for field in (
        "ITEMS",
        "SNAPSHOTS",
        "REGIONS",
        "OBJECTS",
        "UTF8",
        "ROOT-H",
        "ROOT-W",
        "OBJECT-HIGH",
    ):
        assert f"_RTERM-M.{field} @" in deep
    attempt_max = _definition(source, "_RTERM-MAT-ATTEMPT-MAX?")
    assert "_RTERM-X.OBJECT @" in attempt_max
    assert "_RTERM-MV-OBJECT-MAX @ U>" in attempt_max
    assert "_RTERM-M.OBJECT-HIGH @ =" in attempt_max

    start = _definition(source, "_RTERM-MS-START-EPOCH")
    assert start.index("_RTERM-MAT-PHASE-COHORT") < start.index(
        "_RTERM-EPOCH-REBUILD"
    )
    opening = _definition(source, "_RTERM-MS-PUBLISH-OPENING")
    assert opening.index("_RTERM-MAT-ST-OPENING") < opening.index(
        "_RTERM-MAT-PHASE-OPENING"
    )
    staged = _definition(source, "_RTERM-MS-STAGE-HIDDEN")
    assert staged.index("_RTERM-R.STAGED-GEN !") < staged.index(
        "_RTERM-MAT-ST-STAGED"
    )
    assert "_RTERM-MAT-F-STARTED OR" in staged
    assert "0 _RTERM-MS-CLEAR-ASSOCIATION" in staged


def test_public_scratch_entries_catch_bodies_then_scrub_every_borrowed_cell() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    wrappers = {
        "RTERM-UIDL-CONFIG-INIT": (
            "_RTERM-P-DO-CONFIG-INIT",
            "_RTERM-CONFIG-INIT-BODY",
        ),
        "RTERM-UIDL-INIT": (
            "_RTERM-P-DO-UIDL-INIT",
            "_RTERM-UIDL-INIT-BODY",
        ),
        "RTERM-UIDL-FINI": (
            "_RTERM-P-DO-UIDL-FINI",
            "_RTERM-UIDL-FINI-BODY",
        ),
        "RTERM-UIDL-VALID?": (
            "_RTERM-P-DO-UIDL-VALID",
            "_RTERM-UIDL-VALID-BODY?",
        ),
        "RTERM-UIDL-STORAGE-DISJOINT?": (
            "_RTERM-P-DO-UIDL-STORAGE-DISJOINT",
            "_RTERM-UIDL-STORAGE-DISJOINT-BODY?",
        ),
        "RTERM-UIDL-STATUS@": (
            "_RTERM-P-DO-UIDL-STATUS",
            "_RTERM-UIDL-STATUS-BODY@",
        ),
        "RTERM-UIDL-ACTIVE@": (
            "_RTERM-P-DO-UIDL-ACTIVE",
            "_RTERM-UIDL-ACTIVE-BODY@",
        ),
        "RTERM-BACKEND-STEP": (
            "_RTERM-P-DO-BACKEND-STEP",
            "_RTERM-BACKEND-STEP-BODY",
        ),
        "RTERM-BACKEND-PREPARE": (
            "_RTERM-P-DO-BACKEND-PREPARE",
            "_RTERM-BACKEND-PREPARE-BODY",
        ),
        "RTERM-HOST-BINDING-VALID?": (
            "_RTERM-P-DO-HB-VALID",
            "_RTERM-HOST-BINDING-VALID-BODY?",
        ),
        "RTERM-HOST-BINDING-CAPTURE": (
            "_RTERM-P-DO-HB-CAPTURE",
            "_RTERM-HOST-BINDING-CAPTURE-BODY",
        ),
        "RTERM-UCTX-ATTACH": (
            "_RTERM-P-DO-ATTACH",
            "_RTERM-UCTX-ATTACH-BODY",
        ),
        "RTERM-UCTX-PROJECT": (
            "_RTERM-P-DO-PROJECT",
            "_RTERM-UCTX-PROJECT-BODY",
        ),
        "RTERM-UCTX-MATERIALIZATION-PREFLIGHT": (
            "_RTERM-P-DO-MATERIALIZATION-PREFLIGHT",
            "_RTERM-UCTX-MATERIALIZATION-PREFLIGHT-BODY",
        ),
        "RTERM-UCTX-RELAYOUT": (
            "_RTERM-P-DO-RELAYOUT",
            "_RTERM-UCTX-RELAYOUT-BODY",
        ),
        "RTERM-UCTX-QUIESCE": (
            "_RTERM-P-DO-QUIESCE",
            "_RTERM-UCTX-QUIESCE-BODY",
        ),
        "RTERM-UCTX-DETACH": (
            "_RTERM-P-DO-DETACH",
            "_RTERM-UCTX-DETACH-BODY",
        ),
        "RTERM-UIDL-INSTALL": (
            "_RTERM-P-DO-UIDL-INSTALL",
            "_RTERM-UIDL-INSTALL-BODY",
        ),
    }
    nested_recovery = {
        "RTERM-BACKEND-STEP": (
            "_RTERM-P-DO-BACKEND-STEP-RECOVER",
            "_RTERM-MS-QUARANTINE",
        ),
        "RTERM-BACKEND-PREPARE": (
            "_RTERM-P-DO-BACKEND-PREPARE-RECOVER",
            "_RTERM-MS-CAPTURE-RECOVER",
        ),
    }

    public_words = re.findall(r"(?m)^:\s+(RTERM-[^\s]+)(?=\s)", source)
    scrubbed_public = {
        name
        for name in public_words
        if "_RTERM-SCRUB-BORROWED" in _definition(source, name)
    }
    assert scrubbed_public == set(wrappers)
    expected_do_words = {do_name for do_name, _ in wrappers.values()}
    expected_do_words.update(
        recovery_name for recovery_name, _ in nested_recovery.values()
    )
    assert set(re.findall(r"(?m)^:\s+(_RTERM-P-DO-[^\s]+)", source)) == (
        expected_do_words
    )

    for public_name, (do_name, body_name) in wrappers.items():
        wrapper = _definition(source, public_name)
        caught = wrapper.index(f"['] {do_name} CATCH")
        if public_name in nested_recovery:
            recovery_name, _ = nested_recovery[public_name]
            recovered = wrapper.index(f"['] {recovery_name} CATCH", caught)
            scrubbed = wrapper.index("_RTERM-SCRUB-BORROWED", recovered)
            assert caught < recovered < scrubbed
            assert wrapper.count("CATCH") == 2
            assert "RTERM-S-INVALID 0 0" in wrapper[recovered:] or (
                "RTERM-S-INVALID" in wrapper[recovered:]
            )
        else:
            scrubbed = wrapper.index("_RTERM-SCRUB-BORROWED", caught)
            assert caught < scrubbed
            assert wrapper.count("CATCH") == 1
        assert wrapper.count("_RTERM-SCRUB-BORROWED") == 1
        assert body_name not in wrapper

        do_definition = _definition(source, do_name)
        assert do_definition.count(body_name) == 1
        assert "CATCH" not in do_definition
        assert "_RTERM-SCRUB-BORROWED" not in do_definition

    step_recovery = _definition(
        source, "_RTERM-P-DO-BACKEND-STEP-RECOVER"
    )
    envelope = step_recovery.index("_RTERM-UIDL-RECOVERY-STORAGE?")
    backend = step_recovery.index("_RTERM-MS-BACKEND !", envelope)
    quarantine = step_recovery.index("_RTERM-MS-QUARANTINE", backend)
    assert envelope < backend < quarantine
    assert "RTERM-S-INVALID 0 0 EXIT" in step_recovery
    assert "_RTERM-UIDL-VALID-BODY?" not in step_recovery

    recovery_storage = _definition(source, "_RTERM-UIDL-RECOVERY-STORAGE?")
    span = recovery_storage.index("RTERM-UIDL-BACKEND-SIZE _RTERM-SPAN?")
    magic = recovery_storage.index("_RTERM-B.MAGIC @", span)
    abi = recovery_storage.index("_RTERM-B.ABI @", magic)
    size = recovery_storage.index("_RTERM-B.SIZE @", abi)
    self_pointer = recovery_storage.index("_RTERM-B.SELF @", size)
    reserved = recovery_storage.index("_RTERM-B.RESERVED @", self_pointer)
    geometry = recovery_storage.index("_RTERM-UIDL-GEOMETRY?", reserved)
    ranges = recovery_storage.index("_RTERM-BACKEND-RANGES?", geometry)
    assert span < magic < abi < size < self_pointer < reserved < geometry < ranges
    for field, scratch in (
        ("HOST", "HOST"),
        ("ENGINE", "ENGINE"),
        ("RECORDS-A", "RECORDS-A"),
        ("RECORDS-U", "RECORDS-U"),
        ("ITEMS-A", "ITEMS-A"),
        ("ITEMS-PER-BANK", "ITEMS-PER-BANK"),
        ("IDENTITIES-A", "IDENTITIES-A"),
        ("SNAPSHOTS-A", "SNAPSHOTS-A"),
        ("SNAPSHOT-BANK-U", "SNAPSHOT-BANK-U"),
    ):
        assert f"_RTERM-B.{field} @ _RTERM-I-{scratch} !" in recovery_storage
    for derived, stored in (
        ("CAPACITY", "CAPACITY"),
        ("ITEMS-U", "ITEMS-U"),
        ("IDENTITIES-U", "IDENTITIES-U"),
        ("SNAPSHOTS-U", "SNAPSHOTS-U"),
    ):
        assert f"_RTERM-I-{derived} @ OVER _RTERM-B.{stored} @" in recovery_storage
    for semantic_state in (
        "_RTERM-B.STATUS",
        "_RTERM-B.INSTALLED",
        "_RTERM-B.ACTIVE",
        "_RTERM-B.EPOCH",
        "_RTERM-B.MAT",
        "_RTERM-UIDL-VALID-BODY?",
        "_RTERM-BACKEND-MATERIALIZATION-VALID?",
        "_RTERM-RECORD-VALID?",
        "_RTERM-MAT-CORRELATION?",
        "_RTERM-ATTEMPT-BANK",
    ):
        assert semantic_state not in recovery_storage
    assert not re.search(r"_RTERM-B\.[A-Z-]+\s+!", recovery_storage)

    prepare_recovery = _definition(
        source, "_RTERM-P-DO-BACKEND-PREPARE-RECOVER"
    )
    assert prepare_recovery.index("_RTERM-MS-BACKEND !") < (
        prepare_recovery.index("_RTERM-MS-CAPTURE-RECOVER")
    )
    prepare_public = _definition(source, "RTERM-BACKEND-PREPARE")
    second_catch = prepare_public.index(
        "['] _RTERM-P-DO-BACKEND-PREPARE-RECOVER CATCH"
    )
    finish = prepare_public.index("_RTERM-MS-PREPARE-FINISH", second_catch)
    scrub = prepare_public.index("_RTERM-SCRUB-BORROWED", finish)
    assert second_catch < finish < scrub

    variables = re.findall(r"(?m)^VARIABLE\s+(_RTERM-[^\s]+)", source)
    assert len(variables) == len(set(variables))
    definitions = re.findall(r"(?m)^:\s+(_RTERM-[^\s]+)", source)
    assert set(variables).isdisjoint(definitions)
    scrubbed_variables: list[str] = []
    for scrub_name in (
        "_RTERM-SCRUB-BORROWED",
        "_RTERM-SURFACE-INIT-SCRUB",
        "_RTERM-MP-SCRUB",
    ):
        scrub = _definition(source, scrub_name)
        scrubbed_here = re.findall(
            r"(?<!\S)0\s+(_RTERM-[A-Z0-9-]+)\s+!", scrub
        )
        assert len(scrubbed_here) == len(set(scrubbed_here))
        scrubbed_variables.extend(scrubbed_here)
        assert "_RTERM-NEXT-TOKEN" not in scrub
    assert len(scrubbed_variables) == len(set(scrubbed_variables))
    assert set(scrubbed_variables) == set(variables) - {"_RTERM-NEXT-TOKEN"}


def test_surface_snapshot_is_small_checked_and_call_borrowed() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    fields = _definition(source, "_RTERM-SURFACE-FIELDS?")
    valid = _definition(source, "RTERM-SURFACE-SNAPSHOT-VALID?")
    body = _definition(source, "_RTERM-SURFACE-SNAPSHOT-INIT-BODY")
    public = _definition(source, "RTERM-SURFACE-SNAPSHOT-INIT")
    scrub = _definition(source, "_RTERM-SURFACE-INIT-SCRUB")

    assert "_RTERM-S.COLS @ 0> 0=" in fields
    assert "_RTERM-S.ROWS @ 0> 0=" in fields
    assert "_RTERM-S.GENERATION @ 0=" in fields
    assert "_RTERM-S.RESERVED @ 0=" in fields
    assert "RTERM-SURFACE-SNAPSHOT-SIZE _RTERM-SPAN? 0=" in valid
    assert valid.index("_RTERM-SPAN? 0=") < valid.index(
        "_RTERM-SURFACE-FIELDS?"
    )

    span = body.index("RTERM-SURFACE-SNAPSHOT-SIZE\n        _RTERM-SPAN? 0=")
    cols = body.index("_RTERM-SI-COLS @ 0> 0=", span)
    rows = body.index("_RTERM-SI-ROWS @ 0> 0=", cols)
    generation = body.index("_RTERM-SI-GENERATION @ 0=", rows)
    fill = body.index("RTERM-SURFACE-SNAPSHOT-SIZE 0 FILL", generation)
    stores = [
        body.index("_RTERM-S.COLS !", fill),
        body.index("_RTERM-S.ROWS !", fill),
        body.index("_RTERM-S.GENERATION !", fill),
    ]
    assert span < cols < rows < generation < fill < min(stores)
    assert stores == sorted(stores)
    assert "_RTERM-S.RESERVED !" not in body

    caught = public.index("['] _RTERM-SURFACE-SNAPSHOT-INIT-BODY CATCH")
    cleaned = public.index("_RTERM-SURFACE-INIT-SCRUB", caught)
    assert caught < cleaned
    assert public.count("CATCH") == 1
    assert public.count("_RTERM-SURFACE-INIT-SCRUB") == 1
    for variable in (
        "_RTERM-SI-COLS",
        "_RTERM-SI-ROWS",
        "_RTERM-SI-GENERATION",
        "_RTERM-SI-SURFACE",
    ):
        assert f"0 {variable} !" in scrub


def test_materialization_preflight_freezes_validates_maps_and_cleans() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    code = _code_without_comments(source)
    load = _definition(source, "_RTERM-MP-LOAD-SELECTED?")
    freeze = _definition(source, "_RTERM-MP-FREEZE?")
    frozen_valid = _definition(source, "_RTERM-MP-FROZEN-VALID?")
    next_item = _definition(source, "_RTERM-MP-NEXT?")
    plan_one = _definition(source, "_RTERM-MP-PLAN-ONE")
    plan = _definition(source, "_RTERM-MP-PLAN-BUILD?")
    body = _definition(source, "_RTERM-UCTX-MATERIALIZATION-PREFLIGHT-BODY")
    clean = _definition(source, "_RTERM-MP-CLEAN-STORAGE")
    clean_attempt = _definition(source, "_RTERM-MP-CLEAN-ATTEMPT")
    clean_plan = _definition(source, "_RTERM-MP-CLEAN-PLAN")
    finish = _definition(source, "_RTERM-MP-FINISH")
    wrapper = _definition(source, "RTERM-UCTX-MATERIALIZATION-PREFLIGHT")

    # Admission is ordered after neutral authority, liveness, visibility, and
    # frozen eligibility checks.  Deep validation sees the frozen attempt,
    # never concurrently mutable desired-bank bytes.
    ordered_checks = (
        "_RTERM-UIDL-VALID-BODY?",
        "RTERM-SURFACE-SNAPSHOT-VALID?",
        "_RTERM-UIDL-STORAGE-DISJOINT-BODY?",
        "_RTERM-CALL-LOOKUP",
        "_RTERM-R.STATE @",
        "_RTERM-CALL-LIVE?",
        "_RTERM-R.VISIBLE @",
        "_RTERM-R.ELIGIBLE @",
        "_RTERM-R.MAT-STATE @",
        "_RTERM-B.MAT _RTERM-M.PHASE @",
        "_RTERM-RECORD-INDEX?",
        "_RTERM-MP-CAN-SCRUB !",
        "_RTERM-MP-LOAD-SELECTED?",
        "_RTERM-MP-FREEZE?",
        "_RTERM-MP-FROZEN-VALID?",
        "_RTERM-MP-PLAN-BUILD?",
        "RTE-LABEL-PREFLIGHT",
    )
    positions = [body.index(token) for token in ordered_checks]
    assert positions == sorted(positions)
    assert body.count("RTE-LABEL-PREFLIGHT") == 1
    grant = body.index("_RTERM-MP-CAN-SCRUB !")
    assert "RTERM-S-WOULD-BLOCK EXIT" in body[:grant]
    assert "_RTERM-MAT-ST-NONE <>" in body[:grant]
    assert "_RTERM-MAT-PHASE-IDLE =" in body[:grant]
    assert "_RTERM-MAT-PHASE-COHORT = OR" in body[:grant]

    for meta_field, frozen_cell in (
        ("GENERATION", "_RTERM-MP-GENERATION"),
        ("ITEMS", "_RTERM-MP-COUNT"),
        ("SNAPSHOTS", "_RTERM-MP-SNAPSHOT-USED"),
        ("REGIONS", "_RTERM-MP-REGIONS"),
        ("OBJECTS", "_RTERM-MP-OBJECTS"),
        ("UTF8", "_RTERM-MP-CANDIDATE-UTF8"),
        ("ROOT-H", "_RTERM-MP-ROOT-H"),
        ("ROOT-W", "_RTERM-MP-ROOT-W"),
    ):
        assert f"_RTERM-K.{meta_field} @" in load
        assert f"{frozen_cell} !" in load

    attempt = freeze.index("_RTERM-ATTEMPT-BANK-LOAD")
    copy_items = freeze.index(
        "_RTERM-MP-SOURCE-ITEMS @ _RTERM-MP-ITEMS @", attempt
    )
    copy_identities = freeze.index(
        "_RTERM-MP-SOURCE-IDENTITIES @ _RTERM-MP-IDENTITIES @",
        copy_items,
    )
    copy_snapshots = freeze.index(
        "_RTERM-MP-SOURCE-SNAPSHOTS @ _RTERM-MP-SNAPSHOTS @",
        copy_identities,
    )
    item_shape = freeze.index(
        "RUPJ-ITEM-BYTES RTE-LABEL-PLAN-ITEM-SIZE <>", copy_snapshots
    )
    inactive = freeze.index(
        "_RTERM-MP-SELECTOR @ 1 = IF 1 ELSE 0 THEN", item_shape
    )
    plan_scratch = freeze.index("_RTERM-BANK-LOAD", inactive)
    assert attempt < copy_items < copy_identities < copy_snapshots
    assert copy_snapshots < item_shape < inactive < plan_scratch
    assert freeze.count("MOVE") == 3
    assert "_RTERM-BK-ITEM-U @ _RTERM-I-ITEM-BANK-U @ <>" in freeze
    assert "_RTERM-BK-ITEM-A @ _RTERM-MP-PLAN-ITEMS !" in freeze

    deep_candidate = frozen_valid.index("RUPJ-CANDIDATE-VALID?")
    deep_identity = frozen_valid.index(
        "_RTERM-IDENTITY-BANK-VALID?", deep_candidate
    )
    assert deep_candidate < deep_identity
    assert "_RTERM-MP-ITEMS @" in frozen_valid
    assert "_RTERM-MP-IDENTITIES @" in frozen_valid
    assert "_RTERM-MP-SNAPSHOTS @" in frozen_valid

    # Stable private object IDs determine deterministic ascending plan order.
    prior = next_item.index("_RTERM-MP-PRIOR-OBJECT @ U>")
    best = next_item.index("_RTERM-MP-BEST-OBJECT @ U<", prior)
    assert prior < best
    assert "_RTERM-MP-BEST-INDEX !" in next_item
    assert "_RTERM-MP-BEST-OBJECT @ _RTERM-MP-PRIOR-OBJECT !" in plan_one

    for getter, target in (
        ("RUPJ-ITEM-RESOLVED-ROW@", "_RTE-LPI.ROW !"),
        ("RUPJ-ITEM-RESOLVED-COL@", "_RTE-LPI.COL !"),
        ("RUPJ-ITEM-RESOLVED-HEIGHT@", "_RTE-LPI.HEIGHT !"),
        ("RUPJ-ITEM-RESOLVED-WIDTH@", "_RTE-LPI.WIDTH !"),
        ("RUPJ-ITEM-RESOLVED-Z@", "_RTE-LPI.Z !"),
        ("RUPJ-ITEM-EFFECTIVE-VISIBLE?", "_RTE-LPI.VISIBLE !"),
        ("RUPJ-ITEM-RESOLVED-FG@", "_RTE-LPI.RGBA !"),
        ("RUPJ-ITEM-RESOLVED-ALIGN@", "_RTE-LPI.H-ALIGN !"),
        (
            "UIDL-LABEL-SNAPSHOT-TEXT-CAPACITY@",
            "_RTE-LPI.TEXT-CAPACITY !",
        ),
    ):
        getter_at = plan_one.index(getter)
        assert getter_at < plan_one.index(target, getter_at)
    assert "TUI-PALETTE>RGBA" in plan_one
    assert (
        "_RTERM-MP-BEST-OBJECT @\n"
        "        _RTERM-MP-CURRENT-PLAN-ITEM @ _RTE-LPI.OBJECT !"
        in plan_one
    )
    assert (
        "0 _RTERM-MP-CURRENT-PLAN-ITEM @ _RTE-LPI.PARENT !" in plan_one
    )
    assert (
        "_RTERM-MP-ROOT-H @\n"
        "        _RTERM-MP-CURRENT-PLAN-ITEM @ _RTE-LPI.ROOT-HEIGHT !"
        in plan_one
    )
    assert (
        "_RTERM-MP-ROOT-W @\n"
        "        _RTERM-MP-CURRENT-PLAN-ITEM @ _RTE-LPI.ROOT-WIDTH !"
        in plan_one
    )
    assert (
        "0 _RTERM-MP-CURRENT-PLAN-ITEM @ _RTE-LPI.V-ALIGN !" in plan_one
    )
    assert (
        "0 _RTERM-MP-CURRENT-PLAN-ITEM @ _RTE-LPI.ELLIPSIZE !" in plan_one
    )

    for mapping in (
        "_RTERM-MP-SURFACE-COLS @\n"
        "        _RTERM-MP-PLAN @ _RTE-LP.SURFACE-COLS !",
        "_RTERM-MP-SURFACE-ROWS @\n"
        "        _RTERM-MP-PLAN @ _RTE-LP.SURFACE-ROWS !",
        "_RTERM-R.COL @\n        _RTERM-MP-PLAN @ _RTE-LP.REGION-X !",
        "_RTERM-R.ROW @\n        _RTERM-MP-PLAN @ _RTE-LP.REGION-Y !",
        "_RTERM-R.ROOT-REGION @\n        _RTERM-MP-PLAN @ _RTE-LP.REGION-ID !",
        "_RTERM-MP-ROOT-W @\n        _RTERM-MP-PLAN @ _RTE-LP.REGION-COLS !",
        "_RTERM-MP-ROOT-H @\n        _RTERM-MP-PLAN @ _RTE-LP.REGION-ROWS !",
        "0 _RTERM-MP-PLAN @ _RTE-LP.REGION-Z !",
        "3 _RTERM-MP-PLAN @ _RTE-LP.REGION-FLAGS !",
        "_RTERM-MP-PLAN-ITEMS @ _RTERM-MP-PLAN @ _RTE-LP.ITEMS-A !",
    ):
        assert mapping in plan
    assert "_RTERM-R.OWNER @\n        _RTERM-MP-PLAN @ _RTE-LP.OWNER !" in plan
    assert "_RTERM-R.OWNER-GEN @" in plan
    assert "_RTERM-S.GENERATION @" not in plan
    assert "RTE-LABEL-PLAN-ITEM-SIZE\n        _RTERM-UMUL?" in plan
    assert "RTE-LABEL-PLAN-VALID?" in plan

    # Every temporary payload is scrubbed before status diagnostics are
    # published; the public wrapper then clears its generic borrowed cells.
    assert "_RTERM-MP-CLEAN-ATTEMPT" in clean
    assert "_RTERM-MP-CLEAN-PLAN" in clean
    assert "_RTERM-MP-CAN-SCRUB @ 0= IF EXIT" in clean_attempt
    assert "_RTERM-MP-CAN-SCRUB @ 0= IF EXIT" in clean_plan
    assert clean_attempt.count("0 FILL") == 3
    assert clean_plan.count("0 FILL") == 2
    for extent in (
        "_RTERM-BK-ITEM-A @ _RTERM-BK-ITEM-U @ 0 FILL",
        "_RTERM-BK-IDENTITY-A @ _RTERM-BK-IDENTITY-U @ 0 FILL",
        "_RTERM-BK-SNAPSHOT-A @ _RTERM-BK-SNAPSHOT-U @ 0 FILL",
    ):
        assert extent in clean_attempt
    for extent in (
        "_RTERM-I-ITEM-BANK-U @ 0 FILL",
        "_RTERM-B.LIMITS RTE-LIMITS-SIZE 0 FILL",
    ):
        assert extent in clean_plan
    cleaned = finish.index("_RTERM-MP-CLEAN-STORAGE")
    record_status = finish.index("_RTERM-R.LAST-STATUS !", cleaned)
    sticky_status = finish.index("_RTERM-NOTE", record_status)
    scratch_scrub = finish.index("_RTERM-MP-SCRUB", sticky_status)
    assert cleaned < record_status < sticky_status < scratch_scrub
    caught = wrapper.index("['] _RTERM-P-DO-MATERIALIZATION-PREFLIGHT CATCH")
    finished = wrapper.index("_RTERM-MP-FINISH", caught)
    borrowed_scrub = wrapper.index("_RTERM-SCRUB-BORROWED", finished)
    assert caught < finished < borrowed_scrub
    assert wrapper.count("CATCH") == 1

    preflight_start = source.index("VARIABLE _RTERM-MP-SURFACE")
    preflight_end = source.index("VARIABLE _RTERM-RL-VISIBLE")
    preflight_section = _code_without_comments(
        source[preflight_start:preflight_end]
    )
    assert preflight_section.count("RTE-LABEL-PREFLIGHT") == 1
    assert not re.search(r"(?<![A-Z0-9_-])_?PT-", preflight_section)
    for forbidden in (
        "RTE-OWNER-OPEN",
        "RTE-RETAINED-BEGIN",
        "RTE-REGION-DEFINE",
        "RTE-LABEL-DEFINE",
        "RTE-RETAINED-SEAL",
        "RTE-RETAINED-CANCEL",
        "RTE-OWNER-DROP",
        "RTAPT-",
        "_RTAPT-",
        "PRESENT",
        "_RTERM-R.CANDIDATE !",
        "_RTERM-R.ELIGIBLE !",
        "_RTERM-R.OBJECT-HIGH !",
    ):
        assert forbidden not in preflight_section
    assert "_RTERM-B.ATTEMPT" not in code
    assert "_RTERM-R.ATTEMPT" not in code


def test_materializer_persists_admission_and_drops_before_mutation() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    admit = _definition(source, "_RTERM-MS-ADMIT")
    owner_open = _definition(source, "_RTERM-MS-OWNER-OPEN")
    publish = _definition(source, "_RTERM-MS-PUBLISH-OPENING")
    opening = _definition(source, "_RTERM-MS-OPENING-STEP")
    open_step = _definition(source, "_RTERM-MS-OPEN-STEP")
    associate_drop = _definition(source, "_RTERM-MS-ASSOCIATE-DROP")
    publish_drop = _definition(source, "_RTERM-MS-PUBLISH-DROP-PENDING")
    drop_pending = _definition(source, "_RTERM-MS-DROP-PENDING-STEP")
    owner_drop = _definition(source, "_RTERM-MS-OWNER-DROP-CALL")
    dropping = _definition(source, "_RTERM-MS-DROPPING-STEP")
    settled = _definition(source, "_RTERM-MS-DROP-SETTLED")
    cohort = _definition(source, "_RTERM-MS-COHORT-STEP")

    # The exact OPENING tuple is durable before the sole mutating admission
    # call.  A throw records restart uncertainty but retains the frozen
    # attempt; deterministic refusal alone rolls the association back.
    preflight = admit.index("_RTERM-MS-ADMISSION-PREFLIGHT-CALL")
    published = admit.index("_RTERM-MS-PUBLISH-OPENING", preflight)
    opened = admit.index("['] _RTERM-MS-OWNER-OPEN-CALL CATCH", published)
    restart = admit.index("_RTERM-MAT-F-RESTART OR", opened)
    clean_plan = admit.index("_RTERM-MP-CLEAN-PLAN", restart)
    rollback = admit.index("_RTERM-MS-ROLLBACK-OPENING", clean_plan)
    assert preflight < published < opened < restart < clean_plan < rollback
    assert "_RTERM-MP-CLEAN-ATTEMPT" not in admit[published:clean_plan]
    assert "_RTERM-MP-PRIOR-OBJECT @" in owner_open
    assert "_RTERM-MP-COUNT @" not in owner_open
    assert "1 0" in owner_open
    assert "0 0 _RTERM-MP-CANDIDATE-UTF8 @ 0" in owner_open

    stores = [
        publish.index(f"_RTERM-M.{field} !")
        for field in (
            "TOKEN",
            "RECORD-INDEX",
            "SELECTOR",
            "CANDIDATE-GEN",
            "OWNER",
            "OWNER-GEN",
            "ITEMS",
            "SNAPSHOTS",
            "REGIONS",
            "OBJECTS",
            "UTF8",
            "ROOT-H",
            "ROOT-W",
            "OBJECT-HIGH",
            "REGION-X",
            "REGION-Y",
        )
    ]
    binding_opening = publish.index("_RTERM-R.MAT-STATE !", max(stores))
    global_opening = publish.index("_RTERM-M.PHASE !", binding_opening)
    assert stores == sorted(stores)
    assert max(stores) < binding_opening < global_opening

    surface_restart = opening.index("_RTERM-MS-SURFACE=? 0=")
    queried = opening.index("RTE-OWNER-STATE@", surface_restart)
    binding_open = opening.index("_RTERM-MAT-ST-OPEN", queried)
    phase_open = opening.index("_RTERM-MAT-PHASE-OPEN", binding_open)
    retire = opening.index("_RTERM-MS-BEGIN-RESTART-DROP", phase_open)
    assert surface_restart < queried < binding_open < phase_open < retire
    assert "_RTERM-MS-REQUEST-RESTART" in opening[:queried]
    assert "_RTERM-MS-SURFACE=? 0= IF _RTERM-MS-REQUEST-RESTART" in open_step
    assert "_RTERM-MS-BEGIN-RESTART-DROP" in open_step

    # Staged/live owners first become a pointer-free DROP-PENDING tuple.
    cleared = associate_drop.index("_RTERM-M.TOKEN 128 0 FILL")
    copied = [
        associate_drop.index(f"_RTERM-M.{field} !", cleared)
        for field in ("TOKEN", "RECORD-INDEX", "OWNER", "OWNER-GEN")
    ]
    record_pending = associate_drop.index("_RTERM-MAT-ST-DROP-PENDING")
    phase_pending = associate_drop.index(
        "_RTERM-MAT-PHASE-DROP-PENDING", record_pending
    )
    assert cleared < min(copied) <= max(copied) < record_pending < phase_pending
    assert "RTE-OWNER-DROP" not in associate_drop

    attempt_clean = publish_drop.index("_RTERM-MS-CLEAN-ATTEMPT")
    selector_zero = publish_drop.index("_RTERM-M.SELECTOR 16 0 FILL")
    payload_zero = publish_drop.index("_RTERM-M.ITEMS 80 0 FILL")
    record_pending = publish_drop.index("_RTERM-MAT-ST-DROP-PENDING")
    phase_pending = publish_drop.index(
        "_RTERM-MAT-PHASE-DROP-PENDING", record_pending
    )
    assert attempt_clean < selector_zero < payload_zero < record_pending
    assert record_pending < phase_pending

    # Uncertainty is published before OWNER-DROP.  Subsequent retries poll
    # exact owner state and never blindly replay a possibly accepted drop.
    exact_load = drop_pending.index("_RTERM-MS-DROP-LOAD?")
    idle = drop_pending.index("RTE-UPDATE-IDLE <>", exact_load)
    record_dropping = drop_pending.index("_RTERM-MAT-ST-DROPPING", idle)
    phase_dropping = drop_pending.index(
        "_RTERM-MAT-PHASE-DROPPING", record_dropping
    )
    mutate = drop_pending.index("_RTERM-MS-TRY-OWNER-DROP", phase_dropping)
    assert exact_load < idle < record_dropping < phase_dropping < mutate
    assert "RTE-OWNER-DROP" not in drop_pending
    assert "RTE-OWNER-DROP" in owner_drop
    assert "CATCH" in _definition(source, "_RTERM-MS-TRY-OWNER-DROP")
    poll = dropping.index("RTE-OWNER-STATE@")
    tombstone = dropping.index("RTE-OWNER-ST-TOMBSTONE", poll)
    open_again = dropping.index("RTE-OWNER-ST-OPEN", tombstone)
    still_dropping = dropping.index("RTE-OWNER-ST-DROPPING", open_again)
    stale = dropping.index(
        "_RTERM-MS-UPDATE-STATUS @ RTERM-S-STALE = IF", still_dropping
    )
    republished = dropping.index("_RTERM-MS-PUBLISH-DROP-PENDING", stale)
    result = dropping.index("RTERM-S-OK -1 0 _RTERM-MS-RESULT!", republished)
    assert poll < tombstone < open_again < still_dropping
    assert still_dropping < stale < republished < result

    minted = settled.index("_RTERM-TAKE-TOKEN")
    generation = settled.index("_RTERM-R.OWNER-GEN !", minted)
    record_clear = settled.index("_RTERM-R.MAT-STATE 32 0 FILL", generation)
    rescan = settled.index("0 _RTERM-MS-CLEAR-ASSOCIATION", record_clear)
    assert minted < generation < record_clear < rescan

    # A restart is persistent across budget slices.  Staged and live owners
    # are retired before any fresh admission, and restart begins at index zero.
    staged = cohort.index("_RTERM-MAT-ST-STAGED")
    request = cohort.index("_RTERM-MS-REQUEST-RESTART", staged)
    staged_drop = cohort.index("_RTERM-MS-ASSOCIATE-DROP", request)
    live = cohort.index("_RTERM-MAT-ST-LIVE", staged_drop)
    live_request = cohort.index("_RTERM-MS-REQUEST-RESTART", live)
    live_drop = cohort.index("_RTERM-MS-ASSOCIATE-DROP", live_request)
    admit_call = cohort.index("_RTERM-MS-ADMIT", live_drop)
    assert staged < request < staged_drop < live < live_request < live_drop
    assert live_drop < admit_call
    start = _definition(source, "_RTERM-MS-START-EPOCH")
    assert "0 _RTERM-MS-MAT @ _RTERM-M.RECORD-INDEX !" in start


def test_materializer_captures_and_settles_hidden_work_with_rescan() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    ready = _definition(source, "_RTERM-MS-CAPTURE-READY?")
    load = _definition(source, "_RTERM-MS-LOAD-FROZEN?")
    label = _definition(source, "_RTERM-MS-LABEL-BUILD?")
    capture = _definition(source, "_RTERM-MS-CAPTURE-TRANSACTION")
    recover = _definition(source, "_RTERM-MS-CAPTURE-RECOVER")
    prepare = _definition(source, "_RTERM-MS-PREPARE-OPEN")
    hidden = _definition(source, "_RTERM-MS-HIDDEN-STEP")
    staged = _definition(source, "_RTERM-MS-STAGE-HIDDEN")

    for gate in (
        "_RTERM-MAT-PHASE-OPEN <>",
        "_RTERM-MS-ACTIVE-LOAD?",
        "_RTERM-MAT-ST-OPEN <>",
        "_RTERM-MAT-F-RESTART AND",
        "_RTERM-MS-SURFACE=?",
        "_RTERM-MS-CURRENT-DESIRED?",
    ):
        assert gate in ready
    assert "_RTERM-MP-FROZEN-VALID?" in load
    assert "_RTERM-ATTEMPT-BANK-LOAD" in load
    for getter, field in (
        ("RUPJ-ITEM-RESOLVED-ROW@", "ROW"),
        ("RUPJ-ITEM-RESOLVED-COL@", "COL"),
        ("RUPJ-ITEM-RESOLVED-HEIGHT@", "HEIGHT"),
        ("RUPJ-ITEM-RESOLVED-WIDTH@", "WIDTH"),
        ("RUPJ-ITEM-RESOLVED-Z@", "Z"),
        ("RUPJ-ITEM-EFFECTIVE-VISIBLE?", "VISIBLE"),
        ("RUPJ-ITEM-RESOLVED-FG@", "RGBA"),
        ("RUPJ-ITEM-RESOLVED-ALIGN@", "H-ALIGN"),
    ):
        assert label.index(getter) < label.index(f"_RTE-LABEL.{field} !")
    assert "UIDL-LABEL-SNAPSHOT-TEXT@" in label
    assert label.index("_RTE-LABEL.TEXT-U !") < label.index(
        "_RTE-LABEL.TEXT-A !"
    )

    begin_owned = capture.index("-1 _RTERM-MS-BEGIN-OWNED !")
    begin = capture.index("RTE-RETAINED-BEGIN", begin_owned)
    region = capture.index("RTE-REGION-DEFINE", begin_owned)
    labels = capture.index("_RTERM-MS-LABEL-EMIT", region)
    exact_high = capture.index("_RTERM-M.OBJECT-HIGH @ <>", labels)
    seal = capture.index("RTE-RETAINED-SEAL", exact_high)
    assert begin_owned < begin < region < labels < exact_high < seal
    assert capture.count("-1 _RTERM-MS-BEGIN-OWNED !") == 1
    assert "RTE-RETAINED-REPLACE-START" in capture
    assert "RTE-RETAINED-REPLACE-CONTINUE" in capture
    assert "RTE-COMMIT" in capture

    assert "_RTERM-MS-TRY-CANCEL" in recover
    assert recover.index("_RTERM-MS-TRY-CANCEL") < recover.index(
        "_RTERM-MS-BEGIN-OWNED !"
    )
    assert recover.count("_RTERM-MS-QUARANTINE") == 2
    inner_catch = prepare.index("['] _RTERM-MS-CAPTURE-TRANSACTION CATCH")
    recover_call = prepare.index("_RTERM-MS-CAPTURE-RECOVER", inner_catch)
    attempt_clean = prepare.index("_RTERM-MS-CLEAN-ATTEMPT", recover_call)
    payload_clear = prepare.index("_RTERM-M.ITEMS 80 0 FILL", attempt_clean)
    sealed = prepare.index("_RTERM-MAT-PHASE-HIDDEN-SEALED", payload_clear)
    assert inner_catch < recover_call < attempt_clean < payload_clear < sealed

    sealed_state = hidden.index("RTE-UPDATE-SEALED =")
    cancel = hidden.index("_RTERM-MS-TRY-CANCEL", sealed_state)
    restart_drop = hidden.index("_RTERM-MS-BEGIN-RESTART-DROP", cancel)
    stable_output = hidden.index(
        "_RTERM-MAT-PHASE-HIDDEN-SEALED", restart_drop
    )
    publishing = hidden.index("RTE-UPDATE-PUBLISHING", stable_output)
    awaiting = hidden.index("_RTERM-MAT-PHASE-HIDDEN-AWAITING", publishing)
    idle = hidden.index("RTE-UPDATE-IDLE =", awaiting)
    request_restart = hidden.index("_RTERM-MS-REQUEST-RESTART", idle)
    settle = hidden.index("_RTERM-MS-STAGE-HIDDEN", request_restart)
    assert sealed_state < cancel < restart_drop < stable_output
    assert stable_output < publishing < awaiting < idle < request_restart < settle
    for drift in (
        "_RTERM-MS-RESTART?",
        "_RTERM-MS-SURFACE=? 0= OR",
        "_RTERM-MS-RECORD-LIVE? 0= OR",
        "_RTERM-MS-CURRENT-DESIRED? 0= OR",
    ):
        assert drift in hidden[sealed_state:cancel]
        assert drift in hidden[idle:settle]

    generation = staged.index("_RTERM-R.STAGED-GEN !")
    state = staged.index("_RTERM-MAT-ST-STAGED", generation)
    started = staged.index("_RTERM-MAT-F-STARTED OR", state)
    rescan = staged.index("0 _RTERM-MS-CLEAR-ASSOCIATION", started)
    assert generation < state < started < rescan


def test_materializer_reveals_zero_op_cohort_and_promotes_live_last() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    cohort = _definition(source, "_RTERM-MS-COHORT-STEP")
    ready = _definition(source, "_RTERM-MS-REVEAL-READY?")
    promotable = _definition(source, "_RTERM-MS-REVEAL-PROMOTABLE?")
    transact = _definition(source, "_RTERM-MS-REVEAL-TRANSACTION")
    prepare = _definition(source, "_RTERM-MS-PREPARE-REVEAL")
    reveal = _definition(source, "_RTERM-MS-REVEAL-STEP")
    promote = _definition(source, "_RTERM-MS-PROMOTE-REVEAL")

    complete = cohort.rindex("_RTERM-B.CAPACITY @ U< IF")
    started = cohort.index("_RTERM-MAT-F-STARTED AND IF", complete)
    output = cohort.index("RTERM-S-OK 0 -1", started)
    assert complete < started < output
    assert "_RTERM-MAT-PHASE-COHORT <>" in ready
    surface_ready = ready.index("_RTERM-MS-SURFACE=?")
    cohort_shape = ready.index("_RTERM-MS-REVEAL-PROMOTABLE?", surface_ready)
    cohort_current = ready.index("_RTERM-MS-REVEAL-CURRENT?", cohort_shape)
    assert surface_ready < cohort_shape < cohort_current

    assert "_RTERM-MAT-F-STARTED <>" in promotable
    assert "_RTERM-B.CAPACITY @ <>" in promotable
    assert "_RTERM-ATTEMPT-BANK-ZERO?" in promotable
    assert "_RTERM-MAT-ST-STAGED" in promotable
    assert "_RTERM-MAT-ST-NONE <>" in promotable
    assert "_RTERM-MV-OPEN-COUNT @ 0>" in promotable

    current = _definition(source, "_RTERM-MS-REVEAL-CURRENT?")
    staged_state = current.index("_RTERM-MAT-ST-STAGED = IF")
    staged_current = current.index("_RTERM-MS-STAGED-CURRENT?", staged_state)
    staged_live = current.index("_RTERM-MS-RECORD-LIVE?", staged_current)
    none_state = current.index("_RTERM-MAT-ST-NONE = IF", staged_live)
    newly_eligible = current.index("_RTERM-MS-COHORT-CANDIDATE?", none_state)
    reject = current.index("0 UNLOOP EXIT", newly_eligible)
    assert staged_state < staged_current < staged_live < none_state
    assert none_state < newly_eligible < reject

    mode = transact.index("RTE-RETAINED-REPLACE-CONTINUE")
    owned = transact.index("-1 _RTERM-MS-BEGIN-OWNED !", mode)
    begin = transact.index("RTE-RETAINED-BEGIN", owned)
    reveal_seal = transact.index("RTE-COMMIT-AND-REVEAL", owned)
    seal = transact.index("RTE-RETAINED-SEAL", reveal_seal)
    assert mode < owned < begin < reveal_seal < seal
    assert transact.count("-1 _RTERM-MS-BEGIN-OWNED !") == 1
    for content_op in ("RTE-REGION-DEFINE", "RTE-LABEL-DEFINE"):
        assert content_op not in transact

    caught = prepare.index("['] _RTERM-MS-REVEAL-TRANSACTION CATCH")
    recovered = prepare.index("_RTERM-MS-CAPTURE-RECOVER", caught)
    sealed_phase = prepare.index("_RTERM-MAT-PHASE-REVEAL-SEALED", recovered)
    assert caught < recovered < sealed_phase

    sealed_state = reveal.index("RTE-UPDATE-SEALED =")
    current = reveal.index("_RTERM-MS-REVEAL-CURRENT?", sealed_state)
    cancel = reveal.index("_RTERM-MS-TRY-CANCEL", current)
    rescan = reveal.index("0 _RTERM-MS-CLEAR-ASSOCIATION", cancel)
    restart = reveal.index("_RTERM-MS-REQUEST-RESTART", rescan)
    stable_output = reveal.index("_RTERM-MAT-PHASE-REVEAL-SEALED", restart)
    publishing = reveal.index("RTE-UPDATE-PUBLISHING", stable_output)
    awaiting = reveal.index("_RTERM-MAT-PHASE-REVEAL-AWAITING", publishing)
    idle = reveal.index("RTE-UPDATE-IDLE =", awaiting)
    promotion = reveal.index("_RTERM-MS-PROMOTE-REVEAL", idle)
    assert sealed_state < current < cancel < rescan < restart < stable_output
    assert stable_output < publishing < awaiting < idle < promotion

    # PROMOTABLE is a complete validation pass before the mutation loop.
    validated = promote.index("_RTERM-MS-REVEAL-PROMOTABLE?")
    mutation_loop = promote.index("_RTERM-B.CAPACITY @ 0 ?DO", validated)
    materialized = promote.index("_RTERM-R.MATERIALIZED-GEN !", mutation_loop)
    surface = promote.index(
        "_RTERM-R.MATERIALIZED-SURFACE-GEN !", materialized
    )
    staged_clear = promote.index("_RTERM-R.STAGED-GEN !", surface)
    status = promote.index("_RTERM-R.LAST-STATUS !", staged_clear)
    live = promote.index("_RTERM-MAT-ST-LIVE", status)
    mat_clear = promote.index("_RTERM-MAT-SIZE 0 FILL", live)
    epoch_live = promote.index("_RTERM-EPOCH-LIVE", mat_clear)
    assert validated < mutation_loop < materialized < surface < staged_clear
    assert staged_clear < status < live < mat_clear < epoch_live


def test_materializer_dispatches_each_persistent_phase_without_global_surface_gate() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    step = _definition(source, "_RTERM-BACKEND-STEP-BODY")
    dispatch = _definition(source, "_RTERM-MS-DISPATCH")

    observed = step.index("RTE-UPDATE-STATE@")
    cold = step.index("_RTERM-EPOCH-COLD = IF", observed)
    live = step.index("_RTERM-EPOCH-LIVE = IF", cold)
    mat = step.index("_RTERM-B.MAT _RTERM-MS-MAT !", live)
    dispatched = step.index("_RTERM-MS-DISPATCH", mat)
    assert observed < cold < live < mat < dispatched
    assert "_RTERM-MS-SURFACE=?" not in step

    phase_handlers = (
        ("COHORT", "_RTERM-MS-COHORT-STEP"),
        ("OPENING", "_RTERM-MS-OPENING-STEP"),
        ("OPEN", "_RTERM-MS-OPEN-STEP"),
        ("HIDDEN-SEALED", "_RTERM-MS-HIDDEN-STEP"),
        ("REVEAL-SEALED", "_RTERM-MS-REVEAL-STEP"),
        ("DROP-PENDING", "_RTERM-MS-DROP-PENDING-STEP"),
        ("DROPPING", "_RTERM-MS-DROPPING-STEP"),
    )
    handler_positions = []
    for phase, handler in phase_handlers:
        phase_at = dispatch.index(f"_RTERM-MAT-PHASE-{phase}")
        handler_at = dispatch.index(handler, phase_at)
        assert phase_at < handler_at
        handler_positions.append(handler_at)
    assert handler_positions == sorted(handler_positions)
    assert "_RTERM-MAT-PHASE-HIDDEN-AWAITING = OR" in dispatch
    assert "_RTERM-MAT-PHASE-REVEAL-AWAITING = OR" in dispatch

    cohort = dispatch.index("_RTERM-MAT-PHASE-COHORT")
    surface = dispatch.index("_RTERM-MS-SURFACE=? 0=", cohort)
    restart = dispatch.index("_RTERM-MS-REQUEST-RESTART", surface)
    idle = dispatch.index("RTE-UPDATE-IDLE <>", restart)
    cohort_step = dispatch.index("_RTERM-MS-COHORT-STEP", idle)
    assert cohort < surface < restart < idle < cohort_step

    lifecycle_start = source.index("VARIABLE _RTERM-MS-COLS")
    lifecycle_end = source.index("VARIABLE _RTERM-P-A0")
    lifecycle = _code_without_comments(source[lifecycle_start:lifecycle_end])
    assert not re.search(r"(?<![A-Z0-9_-])_?PT-", lifecycle)
    for forbidden in ("RTAPT-", "_RTAPT-", "PRESENT"):
        assert forbidden not in lifecycle


def test_materializer_quarantine_publishes_normalized_terminal_status() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    quarantine = _definition(source, "_RTERM-MS-QUARANTINE")

    normalized = quarantine.index("RTERM-S-SESSION-LOST <>")
    cause = quarantine.index("_RTERM-MS-CALL-STATUS !", normalized)
    attempt = quarantine.index("_RTERM-MS-CLEAN-ATTEMPT", cause)
    records = quarantine.index("_RTERM-B.CAPACITY @ 0 ?DO", attempt)
    suffix = quarantine.index("_RTERM-R.MAT-STATE 40 0 FILL", records)
    record_status = quarantine.index("_RTERM-R.LAST-STATUS !", suffix)
    record_state = quarantine.index("_RTERM-MAT-ST-QUARANTINED", record_status)
    limits = quarantine.index("_RTERM-B.LIMITS RTE-LIMITS-SIZE 0 FILL")
    mat_phase = quarantine.index("_RTERM-MAT-PHASE-QUARANTINED", limits)
    backend_status = quarantine.index("_RTERM-B.STATUS !", mat_phase)
    epoch = quarantine.index("_RTERM-EPOCH-QUARANTINED", backend_status)
    returned = quarantine.rindex("_RTERM-MS-CALL-STATUS @")
    assert normalized < cause < attempt < records < suffix < record_status
    assert record_status < record_state < limits < mat_phase
    assert mat_phase < backend_status < epoch < returned
    assert quarantine.count("_RTERM-R.MAT-STATE 40 0 FILL") == 2
    assert "_RTERM-NOTE" not in quarantine


def test_config_and_init_preflight_all_caller_owned_banks_before_mutation() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    geometry = _definition(source, "_RTERM-UIDL-GEOMETRY?")
    config_ranges = _definition(source, "_RTERM-CONFIG-RANGES?")
    backend_ranges = _definition(source, "_RTERM-BACKEND-RANGES?")
    config_init = _definition(source, "_RTERM-CONFIG-INIT-BODY")
    init = _definition(source, "_RTERM-UIDL-INIT-BODY")

    # Binding count determines two positional desired banks per binding plus
    # one backend-global frozen-attempt bank.  Checked arithmetic derives all
    # item, identity, and snapshot spans without adding a driver-side cap.
    assert "_RTERM-I-ENGINE @ RTE-VALID?" in geometry
    assert "RTERM-UIDL-BINDING-SIZE MOD" in geometry
    assert "RTERM-UIDL-BINDING-SIZE /" in geometry
    doubled = geometry.index("_RTERM-I-CAPACITY @ 2 _RTERM-UMUL?")
    global_attempt = geometry.index("1 _RTERM-UADD?", doubled)
    bank_count = geometry.index("_RTERM-I-BANK-COUNT !", global_attempt)
    assert doubled < global_attempt < bank_count
    assert "_RTERM-I-ITEMS-PER-BANK @ RUPJ-ITEM-BYTES" in geometry
    assert "_RTERM-I-BANK-COUNT @ _RTERM-I-ITEM-BANK-U @" in geometry
    assert "_RTERM-I-ITEMS-PER-BANK @ _RTERM-IDENTITY-SIZE" in geometry
    assert "_RTERM-I-BANK-COUNT @ _RTERM-I-IDENTITY-BANK-U @" in geometry
    assert "_RTERM-I-BANK-COUNT @ _RTERM-I-SNAPSHOT-BANK-U @" in geometry
    assert geometry.count("_RTERM-DISJOINT?") == 15
    assert geometry.count("RTE-STORAGE-DISJOINT?") == 5
    assert geometry.count("UTUI-STORAGE-DISJOINT?") == 4
    assert geometry.count("UIDL-STORAGE-DISJOINT?") == 4
    assert geometry.count("ST-STORAGE-DISJOINT?") == 4

    for address, extent in (
        ("_RTERM-I-RECORDS-A @", "_RTERM-I-RECORDS-U @"),
        ("_RTERM-I-ITEMS-A @", "_RTERM-I-ITEMS-U @"),
        ("_RTERM-I-IDENTITIES-A @", "_RTERM-I-IDENTITIES-U @"),
        ("_RTERM-I-SNAPSHOTS-A @", "_RTERM-I-SNAPSHOTS-U @"),
    ):
        assert f"{address} {extent}\n        UTUI-STORAGE-DISJOINT?" in geometry

    # The call-borrowed config and long-lived backend are also disjoint from
    # every authority and payload range before either construction mutates it.
    for ranges in (config_ranges, backend_ranges):
        assert ranges.count("_RTERM-SPAN?") == 1
        assert ranges.count("_RTERM-DISJOINT?") == 6
        assert ranges.count("RTE-STORAGE-DISJOINT?") == 1
        assert ranges.count("UTUI-STORAGE-DISJOINT?") == 1
        assert ranges.count("UIDL-STORAGE-DISJOINT?") == 1
        assert ranges.count("ST-STORAGE-DISJOINT?") == 1

    assert (
        "_RTERM-I-CONFIG @ RTERM-UIDL-CONFIG-SIZE\n"
        "        UTUI-STORAGE-DISJOINT?"
    ) in config_ranges
    assert (
        "_RTERM-I-BACKEND @ RTERM-UIDL-BACKEND-SIZE\n"
        "        UTUI-STORAGE-DISJOINT?"
    ) in backend_ranges

    geometry_at = config_init.index("_RTERM-UIDL-GEOMETRY? 0= IF")
    config_ranges_at = config_init.index("_RTERM-CONFIG-RANGES? 0= IF")
    config_fill = config_init.index("RTERM-UIDL-CONFIG-SIZE 0 FILL")
    config_magic = config_init.index("_RTERM-C.MAGIC !")
    assert geometry_at < config_ranges_at < config_fill < config_magic
    assert config_init.count("0 FILL") == 1
    for field in (
        "_RTERM-C.ABI !",
        "_RTERM-C.SIZE !",
        "_RTERM-C.HOST !",
        "_RTERM-C.ENGINE !",
        "_RTERM-C.RECORDS-A !",
        "_RTERM-C.RECORDS-U !",
        "_RTERM-C.ITEMS-A !",
        "_RTERM-C.ITEMS-PER-BANK !",
        "_RTERM-C.IDENTITIES-A !",
        "_RTERM-C.SNAPSHOTS-A !",
        "_RTERM-C.SNAPSHOT-BANK-U !",
    ):
        assert config_fill < config_init.index(field) < config_magic

    config_valid = init.index("_RTERM-CONFIG-VALID? 0= IF")
    backend_valid = init.index("_RTERM-BACKEND-RANGES? 0= IF", config_valid)
    config_disjoint = init.index("_RTERM-DISJOINT? 0= IF", backend_valid)
    records_fill = init.index("_RTERM-I-RECORDS-U @ 0 FILL")
    items_fill = init.index("_RTERM-I-ITEMS-U @ 0 FILL", records_fill)
    identities_fill = init.index(
        "_RTERM-I-IDENTITIES-U @ 0 FILL", items_fill
    )
    snapshots_fill = init.index(
        "_RTERM-I-SNAPSHOTS-U @ 0 FILL", identities_fill
    )
    backend_fill = init.index("RTERM-UIDL-BACKEND-SIZE 0 FILL")
    magic = init.index("_RTERM-B.MAGIC !")
    assert config_valid < backend_valid < config_disjoint
    assert config_disjoint < records_fill < items_fill < identities_fill
    assert identities_fill < snapshots_fill
    assert snapshots_fill < backend_fill < magic
    assert init.count("0 FILL") == 5
    for field in (
        "_RTERM-B.ABI !",
        "_RTERM-B.SIZE !",
        "_RTERM-B.SELF !",
        "_RTERM-B.HOST !",
        "_RTERM-B.ENGINE !",
        "_RTERM-B.RECORDS-A !",
        "_RTERM-B.RECORDS-U !",
        "_RTERM-B.CAPACITY !",
        "_RTERM-B.ITEMS-A !",
        "_RTERM-B.ITEMS-U !",
        "_RTERM-B.ITEMS-PER-BANK !",
        "_RTERM-B.IDENTITIES-A !",
        "_RTERM-B.IDENTITIES-U !",
        "_RTERM-B.SNAPSHOTS-A !",
        "_RTERM-B.SNAPSHOTS-U !",
        "_RTERM-B.SNAPSHOT-BANK-U !",
    ):
        assert backend_fill < init.index(field) < magic
    assert "RTERM-UIDL-BINDING-SIZE /" in init


def test_fini_unbinds_only_a_zero_active_backend_and_is_blank_idempotent() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    fini = _definition(source, "_RTERM-UIDL-FINI-BODY")

    span = fini.index("RTERM-UIDL-BACKEND-SIZE _RTERM-SPAN? 0= IF")
    blank = fini.index("RTERM-UIDL-BACKEND-SIZE _RTERM-ZERO? IF")
    valid = fini.index("_RTERM-UIDL-VALID-BODY? 0= IF")
    active = fini.index("_RTERM-B.ACTIVE @ IF")
    records = fini.index("_RTERM-B.RECORDS-U @ 0 FILL")
    items = fini.index("_RTERM-B.ITEMS-U @ 0 FILL", records)
    identities = fini.index("_RTERM-B.IDENTITIES-U @ 0 FILL", items)
    snapshots = fini.index("_RTERM-B.SNAPSHOTS-U @ 0 FILL", identities)
    backend = fini.index("RTERM-UIDL-BACKEND-SIZE 0 FILL", snapshots)
    assert span < blank < valid < active < records < items < identities
    assert identities < snapshots < backend
    assert "DROP RTERM-S-WOULD-BLOCK EXIT" in fini[active:records]
    assert fini.count("0 FILL") == 5


def test_candidate_bank_addresses_are_rederived_from_record_position() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    index = _definition(source, "_RTERM-RECORD-INDEX?")
    slot = _definition(source, "_RTERM-SLOT-LOAD")
    load = _definition(source, "_RTERM-BANK-LOAD")
    attempt = _definition(source, "_RTERM-ATTEMPT-BANK-LOAD")
    attempt_zero = _definition(source, "_RTERM-ATTEMPT-BANK-ZERO?")
    valid = _definition(source, "_RTERM-UIDL-VALID-BODY?")
    clear = _definition(source, "_RTERM-CLEAR-RECORD-BANKS")

    assert "_RTERM-B.RECORDS-A @ -" in index
    assert "RTERM-UIDL-BINDING-SIZE MOD" in index
    assert "RTERM-UIDL-BINDING-SIZE /" in index
    assert "_RTERM-B.CAPACITY @ U< 0=" in index

    # Every physical address is derived through one checked slot loader.  Its
    # upper bound is exactly 2C+1, while record-local callers remain restricted
    # to A/B and the attempt caller selects only physical slot 2C.
    doubled = slot.index("_RTERM-B.CAPACITY @ 2")
    multiplied = slot.index("_RTERM-UMUL?", doubled)
    added = slot.index("1 _RTERM-UADD?", multiplied)
    bounded = slot.index("_RTERM-BK-SLOT @ U> 0= IF", added)
    assert doubled < multiplied < added < bounded
    assert slot.count("_RTERM-UMUL?") == 6
    assert slot.count("_RTERM-UADD?") == 7
    for geometry_token in (
        "_RTERM-B.ITEMS-PER-BANK @ RUPJ-ITEM-BYTES",
        "_RTERM-B.ITEMS-A @",
        "_RTERM-B.ITEMS-PER-BANK @\n        _RTERM-IDENTITY-SIZE",
        "_RTERM-B.IDENTITIES-A @",
        "_RTERM-B.SNAPSHOTS-A @",
        "_RTERM-B.SNAPSHOT-BANK-U @",
    ):
        assert geometry_token in slot
    assert "_RTERM-BK-BANK @ 2 U< 0=" in load
    assert "2 * _RTERM-BK-BANK @ +" in load
    assert load.count("_RTERM-SLOT-LOAD") == 1
    assert "_RTERM-B.CAPACITY @ 2" in attempt
    assert "_RTERM-UMUL?" in attempt
    assert attempt.count("_RTERM-SLOT-LOAD") == 1

    for extent in (
        "_RTERM-BK-ITEM-A @ _RTERM-BK-ITEM-U @",
        "_RTERM-BK-IDENTITY-A @ _RTERM-BK-IDENTITY-U @",
        "_RTERM-BK-SNAPSHOT-A @ _RTERM-BK-SNAPSHOT-U @",
    ):
        assert extent in attempt_zero
    assert attempt_zero.count("_RTERM-ZERO?") == 3
    limits_zero = valid.index(
        "_RTERM-B.LIMITS RTE-LIMITS-SIZE\n        _RTERM-ZERO?"
    )
    attempt_is_zero = valid.index("_RTERM-ATTEMPT-BANK-ZERO?", limits_zero)
    record_scan = valid.index("0 ?DO", attempt_is_zero)
    assert limits_zero < attempt_is_zero < record_scan

    # Both banks are scrubbed as one record-local ownership action.  No bank
    # pointer is retained in the binding record itself.
    assert clear.count("_RTERM-BANK-LOAD") == 2
    assert clear.count("0 FILL") == 6
    assert "_RTERM-CL-RECORD @ 0 _RTERM-CL-BACKEND @" in clear
    assert "_RTERM-CL-RECORD @ 1 _RTERM-CL-BACKEND @" in clear
    for forbidden_field in (
        "_RTERM-R.ITEMS-A",
        "_RTERM-R.SNAPSHOTS-A",
        "_RTERM-R.ITEM-U",
        "_RTERM-R.SNAPSHOT-U",
    ):
        assert forbidden_field not in source


def test_ahost_adapter_captures_attaches_and_scrubs_call_borrowed_binding() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    adapter = _definition(source, "RTERM-AHOST-UIDL-READY")
    attach_body = _definition(source, "_RTERM-AHOST-UIDL-ATTACH-BODY")

    preflight = adapter.index("RTERM-HOST-BINDING-SIZE _RTERM-SPAN? 0= IF")
    capture = adapter.index("RTERM-HOST-BINDING-CAPTURE")
    refusal = adapter.index("NIP NIP R> DROP EXIT", capture)
    caught = adapter.index("['] _RTERM-AHOST-UIDL-ATTACH-BODY CATCH", refusal)
    success_scrub = adapter.index("R@ RTERM-HOST-BINDING-INIT", caught)
    assert preflight < capture < refusal < caught < success_scrub
    assert "RTERM-HOST-BINDING-INIT" not in adapter[capture:refusal]
    assert "AHS-VISIBLE?" in attach_body
    assert "_UTUI-PROJECTION-ATTACH" in attach_body
    assert "CATCH" not in attach_body
    assert "RTERM-UCTX-ATTACH" not in adapter
    assert "VARIABLE" not in adapter


def test_binding_tokens_are_global_nonpointer_monotonic_and_never_reused() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    take = _definition(source, "_RTERM-TAKE-TOKEN")
    attach = _definition(source, "_RTERM-UCTX-ATTACH-BODY")
    populate = _definition(source, "_RTERM-ATTACH-POPULATE")
    detach = _definition(source, "_RTERM-UCTX-DETACH-BODY")

    assert source.count("VARIABLE _RTERM-NEXT-TOKEN") == 1
    assert source.count("_RTERM-NEXT-TOKEN !") == 2
    assert "1 _RTERM-NEXT-TOKEN !" in source
    assert "_RTERM-NEXT-TOKEN @ DUP 0= IF EXIT THEN" in take
    assert "DUP 1+ _RTERM-NEXT-TOKEN !" in take
    for pointer_source in (
        "HERE",
        "MS@",
        "XOR",
        "_RTERM-R.",
        "_RTERM-B.",
        "_RTERM-HB.",
        "_RTERM-A-",
    ):
        assert pointer_source not in take

    assert attach.index("_RTERM-TAKE-TOKEN") < attach.index(
        "_RTERM-ATTACH-POPULATE"
    )
    assert "_RTERM-A-TOKEN @ OVER _RTERM-R.TOKEN !" in populate
    save = detach.index("_RTERM-R.TOKEN @ _RTERM-D-TOKEN !")
    scrub = detach.index("RTERM-UIDL-BINDING-SIZE 0 FILL", save)
    restore = detach.index("_RTERM-D-TOKEN @ _RTERM-C-RECORD @ _RTERM-R.TOKEN !")
    assert save < scrub < restore


def test_host_capture_proves_exact_live_membership_before_mutation() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    acyclic = _definition(source, "_RTERM-HOST-LIST-ACYCLIC?")
    exact_slot = _definition(source, "_RTERM-HOST-EXACT-SLOT?")
    identity = _definition(source, "_RTERM-LIVE-IDENTITY?")
    binding_valid = _definition(source, "_RTERM-HOST-BINDING-VALID-BODY?")
    capture = _definition(source, "_RTERM-HOST-BINDING-CAPTURE-BODY")

    assert "_RTERM-LIST-SLOW" in acyclic
    assert acyclic.count("_RTERM-LIST-FAST") >= 6
    assert acyclic.count("_RTERM-SLOT-NEXT?") == 3
    assert "_RTERM-LIST-SLOW @ _RTERM-LIST-FAST @ = IF 0 EXIT" in acyclic

    assert exact_slot.index("_RTERM-HOST-LIST-ACYCLIC?") < exact_slot.index(
        "AHOST.HEAD @"
    )
    assert "DUP _RTERM-HX-SLOT @ =" in exact_slot
    assert "OVER AHS.ID @ _RTERM-HX-ID @ = OR IF" in exact_slot
    assert "OVER AHS.ID @ _RTERM-HX-ID @ = AND 0= IF" in exact_slot
    assert "1 _RTERM-HX-MATCHES +!" in exact_slot
    assert "_RTERM-HX-MATCHES @ 1 =" in exact_slot

    for exact_check in (
        "_RTERM-HOST-EXACT-SLOT?",
        "AHS.HAS-UIDL @ -1 <> IF 0 EXIT",
        "AHS.ID @ _RTERM-L-SLOT-ID @ <>",
        "AHS.INST @ _RTERM-L-INST @ <>",
        "AHS.UCTX @ _RTERM-L-UCTX @ <>",
        "APP-DESC-VALID?",
        "CINST.DESC @ _RTERM-L-COMP-DESC @ <>",
        "CINST.ID @ _RTERM-L-INST-ID @ <>",
        "CINST.GENERATION @",
        "_RTERM-L-INST-GEN @ <> IF 0 EXIT",
    ):
        assert exact_check in identity
    assert re.findall(r"AHS-S-[A-Z-]+", identity) == [
        "AHS-S-RUNNING",
        "AHS-S-MINIMIZED",
        "AHS-S-FOCUSED",
    ]
    normalized_identity = re.sub(r"\s+", " ", identity)
    assert (
        "_RTERM-L-SLOT @ AHS.STATE @ DUP AHS-S-RUNNING = "
        "OVER AHS-S-MINIMIZED = OR SWAP AHS-S-FOCUSED = OR "
        "0= IF 0 EXIT THEN"
    ) in normalized_identity
    assert identity.count("AHS.HAS-UIDL @ -1 <> IF 0 EXIT") == 1
    assert "AHS-ALIVE?" not in identity

    assert "_RTERM-LIVE-ATTACH?" in binding_valid
    assert "_RTERM-LIVE-OBJECTS-DISJOINT?" in binding_valid
    assert "_RTERM-HB-DISJOINT-LIVE?" in binding_valid

    first_mutation = capture.index("RTERM-HOST-BINDING-SIZE 0 FILL")
    for preflight in (
        "AHOST-SIZE _RTERM-SPAN?",
        "AHS-SIZE _RTERM-SPAN?",
        "_RTERM-HOST-EXACT-SLOT?",
        "CINST.ID @",
        "CINST.GENERATION @",
        "_RTERM-LIVE-ATTACH?",
        "_RTERM-LIVE-OBJECTS-DISJOINT?",
        "_RTERM-HB-DISJOINT-LIVE?",
    ):
        assert capture.index(preflight) < first_mutation
    magic = capture.index("_RTERM-HB.MAGIC !", first_mutation)
    for field in (
        "_RTERM-HB.HOST !",
        "_RTERM-HB.SLOT !",
        "_RTERM-HB.SLOT-ID !",
        "_RTERM-HB.INST !",
        "_RTERM-HB.INST-ID !",
        "_RTERM-HB.INST-GEN !",
        "_RTERM-HB.UCTX !",
        "_RTERM-HB.REGION !",
    ):
        assert first_mutation < capture.index(field) < magic


def test_live_runtime_sizes_bound_every_alias_predicate() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    identity = _definition(source, "_RTERM-LIVE-IDENTITY?")
    normalized = re.sub(r"\s+", " ", identity)

    # The fixed descriptor sizes are only the safe minimum needed before the
    # runtime size cells can be read.  Every later span is the exact advertised
    # APP.SIZE, COMP.SIZE, or COMP.STATE-SIZE extent.
    app_capture = (
        "_RTERM-L-APP-DESC @ APP.SIZE @ DUP _RTERM-L-APP-SIZE ! "
        "DUP APP-DESC < IF DROP 0 EXIT THEN "
        "_RTERM-L-APP-DESC @ SWAP _RTERM-SPAN? 0= IF 0 EXIT THEN"
    )
    comp_capture = (
        "_RTERM-L-COMP-DESC @ COMP.SIZE @ DUP _RTERM-L-COMP-SIZE ! "
        "DUP COMP-DESC < IF DROP 0 EXIT THEN "
        "_RTERM-L-COMP-DESC @ SWAP _RTERM-SPAN? 0= IF 0 EXIT THEN"
    )
    state_capture = (
        "_RTERM-L-COMP-DESC @ COMP.STATE-SIZE @ "
        "DUP _RTERM-L-STATE-SIZE ! DUP 0< IF DROP 0 EXIT THEN "
        "_RTERM-L-INST @ CINST.STATE @ _RTERM-L-STATE ! "
        "0= IF _RTERM-L-STATE @ 0= EXIT THEN "
        "_RTERM-L-STATE @ _RTERM-L-STATE-SIZE @ _RTERM-SPAN?"
    )
    assert app_capture in normalized
    assert comp_capture in normalized
    assert state_capture in normalized
    assert "0<=" not in source

    exact_live_spans = (
        "_RTERM-L-APP-DESC @ _RTERM-L-APP-SIZE @",
        "_RTERM-L-COMP-DESC @ _RTERM-L-COMP-SIZE @",
        "_RTERM-L-STATE @ _RTERM-L-STATE-SIZE @",
    )
    alias_predicates = (
        "_RTERM-LIVE-CORE-DISJOINT?",
        "_RTERM-LIVE-OBJECTS-DISJOINT?",
        "_RTERM-HB-DISJOINT-LIVE?",
        "_RTERM-LIVE-DISJOINT-BACKEND-CORE?",
    )
    for name in alias_predicates:
        predicate = _definition(source, name)
        normalized_predicate = re.sub(r"\s+", " ", predicate)
        for exact_span in exact_live_spans:
            assert exact_span in normalized_predicate
        assert not re.search(
            r"(?<!\S)(?:APP-DESC|COMP-DESC)(?=\s)", predicate
        )

    backend_alias = re.sub(
        r"\s+", " ", _definition(source, "_RTERM-LIVE-DISJOINT-BACKEND?")
    )
    assert (
        "DUP _RTERM-LIVE-DISJOINT-BACKEND-CORE? "
        "0= IF DROP 0 EXIT THEN"
    ) in backend_alias
    assert (
        "_RTERM-L-REGION @ RGN-SIZE _RTERM-DB-BACKEND @ "
        "_RTERM-UIDL-STORAGE-DISJOINT-BODY?"
    ) in backend_alias


def test_attach_is_idempotent_and_rejects_collisions_before_claiming_storage() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    exact = _definition(source, "_RTERM-RECORD=HB?")
    collides = _definition(source, "_RTERM-RECORD-COLLIDES-HB?")
    scan = _definition(source, "_RTERM-ATTACH-SCAN")
    populate = _definition(source, "_RTERM-ATTACH-POPULATE")
    attach = _definition(source, "_RTERM-UCTX-ATTACH-BODY")

    for field in (
        "HOST",
        "SLOT",
        "SLOT-ID",
        "INST",
        "INST-ID",
        "INST-GEN",
        "UCTX",
        "REGION",
    ):
        assert f"_RTERM-R.{field} @" in exact
        assert f"_RTERM-HB.{field} @" in exact
    for identity in ("HOST", "SLOT", "SLOT-ID", "INST", "INST-ID", "UCTX"):
        assert f"_RTERM-R.{identity} @" in collides
        assert f"_RTERM-HB.{identity} @" in collides

    assert "_RTERM-BINDING-ST-FREE" in scan
    assert "_RTERM-BINDING-ST-DETACHED" in scan
    assert "_RTERM-RECORD=HB?" in scan
    assert "_RTERM-RECORD-COLLIDES-HB?" in scan
    assert "-1 _RTERM-A-COLLISION !" in scan

    ordered = (
        "_RTERM-UIDL-VALID-BODY?",
        "_RTERM-HOST-BINDING-VALID-BODY?",
        "_RTERM-B.HOST @ <>",
        "_RTERM-UIDL-STORAGE-DISJOINT-BODY?",
        "_RTERM-LIVE-LOAD-HB",
        "_RTERM-LIVE-DISJOINT-BACKEND?",
        "_RTERM-ATTACH-SCAN",
        "_RTERM-A-COLLISION @",
        "_RTERM-A-EXACT @ ?DUP IF",
        "_RTERM-A-FREE @",
        "_RTERM-TAKE-TOKEN",
        "_RTERM-ATTACH-POPULATE",
    )
    positions = [attach.index(fragment) for fragment in ordered]
    assert positions == sorted(positions)
    exact_branch = attach.index("_RTERM-A-EXACT @ ?DUP IF")
    free_choice = attach.index("_RTERM-A-FREE @", exact_branch)
    assert "_RTERM-BINDING-ST-ATTACHED <> IF" in attach[exact_branch:free_choice]
    assert "_RTERM-R.TOKEN @ RTERM-S-OK EXIT" in attach[exact_branch:free_choice]
    assert "RTERM-S-STALE _RTERM-ATTACH-FAIL EXIT" in attach
    assert "RTERM-S-CAPACITY _RTERM-ATTACH-FAIL EXIT" in attach

    bank_clear = populate.index("_RTERM-CLEAR-RECORD-BANKS")
    fill = populate.index("RTERM-UIDL-BINDING-SIZE 0 FILL", bank_clear)
    token = populate.index("_RTERM-R.TOKEN !", fill)
    state = populate.index("_RTERM-R.STATE !", token)
    active = populate.index("_RTERM-B.ACTIVE +!", state)
    assert bank_clear < fill < token < state < active
    assert "RTERM-S-INVALID _RTERM-ATTACH-FAIL EXIT" in populate[
        bank_clear:fill
    ]


def test_project_maps_inactive_bank_and_publishes_selector_last() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    project = _definition(source, "_RTERM-UCTX-PROJECT-BODY")
    select = _definition(source, "_RTERM-PROJECT-SELECT")
    validate = _definition(source, "_RTERM-PROJECT-CANDIDATE-VALID?")
    clear_inactive = _definition(source, "_RTERM-PROJECT-CLEAR-INACTIVE")
    publish = _definition(source, "_RTERM-PROJECT-PUBLISH")
    fail = _definition(source, "_RTERM-PROJECT-FAIL")

    lookup = project.index("_RTERM-CALL-LOOKUP")
    attached = project.index("_RTERM-BINDING-ST-ATTACHED <>", lookup)
    live = project.index("_RTERM-CALL-LIVE?", attached)
    choose = project.index("_RTERM-PROJECT-SELECT", live)
    revoke = project.index("_RTERM-CANDIDATE-META-SIZE 0 FILL", choose)
    identity_revoke = project.index("_RTERM-PJ-IDENTITY-U @ 0 FILL", revoke)
    build = project.index("RUPJ-BUILD", identity_revoke)
    build_status = project.index("RUPJ-S-OK <>", build)
    validated = project.index("_RTERM-PROJECT-CANDIDATE-VALID?", build_status)
    mapped = project.index("_RTERM-PROJECT-MAP-IDENTITIES", validated)
    negotiated = project.index("_RTERM-PROJECT-ELIGIBILITY", mapped)
    published = project.index("_RTERM-PROJECT-PUBLISH", negotiated)
    assert lookup < attached < live < choose < revoke < build
    assert revoke < identity_revoke < build < build_status
    assert build_status < validated < mapped < negotiated < published

    # Selector zero starts at A/generation one; later construction always uses
    # the opposite bank and derives a monotonic generation from the selected
    # metadata.  Capacity exhaustion cannot wrap and publish an ABA generation.
    normalized_select = re.sub(r"\s+", " ", select)
    assert "_RTERM-PJ-ACTIVE @ 0= IF 1 _RTERM-PJ-GENERATION !" in normalized_select
    assert "_RTERM-LENGTH-MAX = IF" in select
    assert "RTERM-S-CAPACITY EXIT" in select
    generation_exhausted = select.index("_RTERM-LENGTH-MAX = IF")
    assert (
        "_RTERM-PJ-META @ _RTERM-CANDIDATE-META-SIZE 0 FILL"
        in select[generation_exhausted:]
    )
    assert "_RTERM-PJ-ACTIVE @ 1 = IF" in select
    assert "1 _RTERM-PJ-BANK !" in select
    assert "2 _RTERM-PJ-PUBLISH !" in select
    assert "0 _RTERM-PJ-BANK !" in select
    assert "1 _RTERM-PJ-PUBLISH !" in select
    assert "_RTERM-BANK-LOAD" in select

    assert "RUPJ-CANDIDATE-VALID?" in validate
    root_h = validate.index("_RTERM-PJ-ROOT-H @ _RTERM-C-RECORD @ _RTERM-R.HEIGHT @")
    root_w = validate.index("_RTERM-PJ-ROOT-W @ _RTERM-C-RECORD @ _RTERM-R.WIDTH @")
    deep = validate.index("RUPJ-CANDIDATE-VALID?", root_w)
    assert root_h < root_w < deep
    assert "_RTERM-PJ-ROOT-H @ _RTERM-PJ-ROOT-W @" in validate
    assert clear_inactive.count("0 FILL") == 4
    invalid_clear = project.index("_RTERM-PROJECT-CLEAR-INACTIVE", validated)
    invalid_fail = project.index("RTERM-S-INVALID _RTERM-PROJECT-FAIL", invalid_clear)
    assert validated < invalid_clear < invalid_fail < published
    # Projection, old-bank reuse, advisory freezing, and the persistent
    # OPENING/OPEN attempt validator each deep-check candidate bytes.
    assert source.count("RUPJ-CANDIDATE-VALID?") == 4
    assert source.count("RUPJ-BUILD") == 1
    assert "RUPJ-S-CAPACITY = IF" in project
    assert "RTERM-S-CAPACITY" in project
    assert "RTERM-S-INVALID" in project
    mapping_clear = project.index("_RTERM-PROJECT-CLEAR-INACTIVE", mapped)
    mapping_fail = project.index("_RTERM-PROJECT-FAIL EXIT", mapping_clear)
    assert mapped < mapping_clear < mapping_fail < negotiated

    # RUPJ returns ROOT-H/ROOT-W immediately below status.  The driver unpacks
    # the entire tuple before checking status, then checks those exact extents.
    normalized_project = re.sub(r"\s+", " ", project)
    assert (
        "RUPJ-BUILD _RTERM-PJ-BUILD-STATUS ! _RTERM-PJ-ROOT-W ! "
        "_RTERM-PJ-ROOT-H ! _RTERM-PJ-UTF8 ! _RTERM-PJ-OBJECTS ! "
        "_RTERM-PJ-REGIONS ! _RTERM-PJ-SNAPSHOT-USED ! _RTERM-PJ-ITEMS !"
    ) in normalized_project

    # Metadata, stable identity high-water, frozen eligibility, LAST-STATUS, and
    # sticky status are complete before the selector is the final publication
    # store.  A negotiation refusal withholds only eligibility authority; the
    # selected desired candidate retains its exact private identity mapping.
    metadata_stores = [
        publish.index(f"_RTERM-K.{field} !")
        for field in (
            "GENERATION",
            "ITEMS",
            "SNAPSHOTS",
            "REGIONS",
            "OBJECTS",
            "UTF8",
            "ROOT-H",
            "ROOT-W",
        )
    ]
    object_high = publish.index("_RTERM-R.OBJECT-HIGH !")
    eligibility_clear = publish.index("_RTERM-ELIGIBILITY-CLEAR", object_high)
    eligible_branch = publish.index("_RTERM-PJ-ELIGIBILITY-STATUS @ RTERM-S-OK = IF")
    frozen = [
        publish.index(f"_RTERM-R.{field} !", eligible_branch)
        for field in (
            "ELIGIBLE",
            "ELIGIBLE-GEN",
            "ELIGIBLE-REGIONS",
            "ELIGIBLE-OBJECTS",
            "ELIGIBLE-UTF8",
        )
    ]
    last_status = publish.index("_RTERM-R.LAST-STATUS !", max(frozen))
    sticky = publish.index("_RTERM-NOTE", last_status)
    selector = publish.index("_RTERM-R.CANDIDATE !", last_status)
    assert metadata_stores == sorted(metadata_stores)
    assert metadata_stores[-1] < object_high < eligibility_clear < eligible_branch
    assert eligible_branch < min(frozen) <= max(frozen) < last_status
    assert last_status < sticky < selector
    assert "_RTERM-PJ-IDENTITY-U @ 0 FILL" not in publish
    assert publish.index("!", selector) == publish.rindex("!")
    eligibility = _definition(source, "_RTERM-PROJECT-ELIGIBILITY")
    assert "_RTERM-PJ-ITEMS @ 0= IF RTERM-S-UNAVAILABLE EXIT" in eligibility

    # All failure exits record status without touching the selected metadata or
    # selector.  The partially written inactive bank therefore has no authority.
    assert "_RTERM-R.LAST-STATUS !" in fail
    assert "_RTERM-R.CANDIDATE" not in fail
    for forbidden in (
        "EXECUTE",
        "PT-",
        "RTAPT-",
        "APTSCB-",
        "UART-",
        "_RTERM-R.STATE !",
        "_RTERM-R.TOKEN !",
        "_RTERM-B.ACTIVE",
    ):
        assert forbidden not in project


def test_ordinary_record_validation_is_shallow_but_open_attempts_are_deep() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    candidates = _definition(source, "_RTERM-RECORD-CANDIDATES-VALID?")
    metadata = _definition(source, "_RTERM-CANDIDATE-META-VALID?")

    # Inactive metadata is build scratch and may be partial after a caught
    # exception.  Selector zero authorizes neither bank; otherwise only the
    # selected fixed-size metadata is relevant to ordinary backend validity.
    normalized = re.sub(r"\s+", " ", candidates)
    assert "_RTERM-RV-SELECTOR @ 0= IF -1 EXIT THEN" in normalized
    assert candidates.count("_RTERM-CANDIDATE-META-VALID?") == 2
    assert "_RTERM-CANDIDATE-META-BLANK?" not in candidates
    assert "GENERATION @" not in candidates

    # Shallow validation still rejects quota combinations that no eligible
    # LABEL candidate can produce.  Snapshot strides are ALIGN8(64+capacity),
    # so their checked total lies between the exact header+UTF8 sum and at
    # most seven alignment bytes per positive-capacity item above it.  There
    # can be no more of those than min(item count, UTF8 quota).
    assert "_RTERM-K.ITEMS @ 0= IF" in metadata
    assert "_RTERM-K.SNAPSHOTS @ 0=" in metadata
    assert "UIDL-LABEL-SNAPSHOT-HEADER-SIZE _RTERM-UMUL?" in metadata
    assert "_RTERM-K.UTF8 @ _RTERM-UADD?" in metadata
    assert "_RTERM-K.ROOT-H @ DUP 0> 0= IF" in metadata
    assert "_RTERM-K.ROOT-W @ DUP 0> 0= IF" in metadata
    assert metadata.count("_RTERM-LENGTH-MAX U> IF") == 3
    empty = metadata.index("_RTERM-K.ITEMS @ 0= IF")
    assert metadata.index("_RTERM-K.ROOT-H @") < empty
    assert metadata.index("_RTERM-K.ROOT-W @") < empty
    normalized_metadata = re.sub(r"\s+", " ", metadata)
    assert (
        "_RTERM-K.ITEMS @ _RTERM-RV-META @ _RTERM-K.UTF8 @ MIN"
        in normalized_metadata
    )
    assert "7 _RTERM-UMUL?" in metadata
    assert "_RTERM-RV-SNAPSHOT-MIN @ SWAP _RTERM-UADD?" in metadata

    for hot_path in (
        "_RTERM-RECORD-CANDIDATES-VALID?",
        "_RTERM-RECORD-LIVE?",
        "_RTERM-RECORD-VALID?",
        "_RTERM-CALL-LOOKUP",
    ):
        body = _definition(source, hot_path)
        assert "RUPJ-CANDIDATE-VALID?" not in body
        assert "RUPJ-BUILD" not in body

    backend = _definition(source, "_RTERM-UIDL-VALID-BODY?")
    assert "_RTERM-MAT-ATTEMPT-DEEP?" in backend
    assert "RUPJ-CANDIDATE-VALID?" not in backend
    assert "RUPJ-BUILD" not in backend


def test_private_identity_mapping_is_exact_monotonic_and_wire_inert() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    populate = _definition(source, "_RTERM-ATTACH-POPULATE")
    validate = _definition(source, "_RTERM-IDENTITY-BANK-VALID?")
    old = _definition(source, "_RTERM-OLD-CANDIDATE-LOAD?")
    lookup = _definition(source, "_RTERM-MAP-OLD-ID")
    mint = _definition(source, "_RTERM-MAP-NEW-ID")
    map_all = _definition(source, "_RTERM-PROJECT-MAP-IDENTITIES")

    for field, offset in {
        "_RTERM-X.SUBKEY": 8,
        "_RTERM-X.KIND": 16,
        "_RTERM-X.OBJECT": 24,
    }.items():
        assert f"{offset} +" in _definition(source, field)

    # The bounded record ordinal is the reusable owner ID; the globally fresh
    # opaque token is its strictly newer owner generation.  Neither is a
    # pointer, markup ID, or hash-derived authority.
    ordinal = populate.index("_RTERM-RECORD-INDEX?")
    owner = populate.index("1+", ordinal)
    fill = populate.index("RTERM-UIDL-BINDING-SIZE 0 FILL", owner)
    owner_store = populate.index("_RTERM-R.OWNER !", fill)
    generation_store = populate.index("_RTERM-R.OWNER-GEN !", owner_store)
    region_store = populate.index("_RTERM-R.ROOT-REGION !", generation_store)
    assert ordinal < owner < fill < owner_store < generation_store < region_store
    assert "_RTERM-A-TOKEN @ OVER _RTERM-R.OWNER-GEN !" in populate
    assert "1 OVER _RTERM-R.ROOT-REGION !" in populate
    for forbidden in ("HERE", "XOR", "UIDL-ATTR", "HASH"):
        assert forbidden not in populate

    # Exact semantic keys and exact prior object IDs are checked positionally.
    # A high-water bounds minted IDs but is never treated as existence proof.
    for accessor in (
        "RUPJ-ITEM-ELEMENT-INDEX@",
        "RUPJ-ITEM-SUBKEY@",
        "RUPJ-ITEM-KIND@",
    ):
        assert accessor in validate
        assert accessor in lookup
    assert "_RTERM-X.OBJECT @" in validate
    assert "_RTERM-IV-HIGH @ U>" in validate
    assert "J _RTERM-IV-IDENTITY-AT _RTERM-X.OBJECT @" in validate
    assert "_RTERM-X.OBJECT @ _RTERM-MAP-OBJECT !" in lookup
    assert "_RTERM-LENGTH-MAX = IF 0 0 EXIT" in mint
    assert "1 _RTERM-PJ-NEXT-HIGH +!" in mint
    assert "_RTERM-R.OBJECT-HIGH @ _RTERM-PJ-NEXT-HIGH !" in map_all
    assert "_RTERM-MAP-OLD-ID" in map_all
    assert "_RTERM-MAP-NEW-ID" in map_all

    # Caller mutation cannot forge a reusable mapping: the old selected recipe
    # and its identity bank are both deep-validated before key reuse.
    assert "RUPJ-CANDIDATE-VALID?" in old
    assert "_RTERM-IDENTITY-BANK-VALID?" in old
    assert "_RTERM-R.CANDIDATE @" in old
    assert "_RTERM-R.ELIGIBLE" not in old
    assert "_RTERM-OLD-BANK @" in old
    assert "_RTERM-PJ-BANK" not in old
    assert old.index("RUPJ-CANDIDATE-VALID?") < old.index(
        "_RTERM-IDENTITY-BANK-VALID?"
    )

    # Projection remains wire-inert.  The separate owner service repeats the
    # neutral preflight before it opens or captures anything.
    code = _code_without_comments(source)
    assert code.count("RTE-LIMITS@") == 1
    assert code.count("RTE-LABEL-PREFLIGHT") == 2
    assert not re.search(r"(?<![A-Z0-9_-])_?PT-", code)
    project = _definition(source, "_RTERM-UCTX-PROJECT-BODY")
    for forbidden in (
        "RTE-OWNER-OPEN",
        "RTE-OWNER-STATE@",
        "RTE-RETAINED-BEGIN",
        "RTE-REGION-DEFINE",
        "RTE-LABEL-DEFINE",
        "RTE-RETAINED-SEAL",
        "RTE-RETAINED-CANCEL",
        "RTE-OWNER-DROP",
        "RTAPT-",
        "_RTAPT-",
        "PRESENT",
    ):
        assert forbidden not in project


def test_stable_mapping_precedes_terminal_negotiated_eligibility() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    limits = _definition(source, "_RTERM-PROJECT-LIMITS?")
    negotiate_body = _definition(source, "_RTERM-PROJECT-NEGOTIATE-BODY")
    negotiate = _definition(source, "_RTERM-PROJECT-NEGOTIATE")
    eligibility = _definition(source, "_RTERM-PROJECT-ELIGIBILITY")
    publish = _definition(source, "_RTERM-PROJECT-PUBLISH")
    project = _definition(source, "_RTERM-UCTX-PROJECT-BODY")

    assert "RTE-LIMITS-FEATURES@" in limits
    assert "RTE-F-INSTRUMENT AND 0=" in limits
    for accessor in (
        "RTE-LIMITS-REGIONS@",
        "RTE-LIMITS-OBJECTS@",
        "RTE-LIMITS-UTF8-BYTES@",
        "RTE-LIMITS-LABEL-BYTES@",
    ):
        assert accessor in limits
    for provider_detail in (
        "RTE-LIMITS-OPS@",
        "RTE-LIMITS-UPDATE-BYTES@",
        "_RTERM-PJ-ELIGIBILITY-BYTES",
        "120 _RTERM-UMUL?",
        "248 _RTERM-UADD?",
        "288 _RTERM-UADD?",
        "PRESENT",
        "PT-",
    ):
        assert provider_detail not in limits
    for compatibility in (
        "RUPJ-ITEM-HAS-RESOLVED?",
        "UIDL-SNAPSHOT-K-LABEL <>",
        "RUPJ-ITEM-SUBKEY@ IF",
        "RUPJ-ITEM-RESOLVED-ATTRS@ IF",
        "UIDL-LABEL-SNAPSHOT-TEXT-CAPACITY@",
    ):
        assert compatibility in limits

    # The embedded fixed-record scratch is always cleared, even if the facade
    # or validation throws; no provider-owned limits pointer survives.
    assert "RTE-LIMITS@" in negotiate_body
    assert "['] _RTERM-PROJECT-NEGOTIATE-BODY CATCH" in negotiate
    assert negotiate.count("RTE-LIMITS-SIZE 0 FILL") == 2
    assert negotiate.index("CATCH") < negotiate.rindex("RTE-LIMITS-SIZE 0 FILL")

    mapping = project.index("_RTERM-PROJECT-MAP-IDENTITIES")
    eligibility_call = project.index("_RTERM-PROJECT-ELIGIBILITY", mapping)
    assert mapping < eligibility_call
    assert "_RTERM-PROJECT-MAP-IDENTITIES" not in eligibility
    assert "_RTERM-PROJECT-NEGOTIATE" in eligibility
    assert "_RTERM-R.OBJECT-HIGH !" not in eligibility
    assert "_RTERM-R.ELIGIBLE" not in eligibility
    assert publish.index("_RTERM-R.OBJECT-HIGH !") < publish.index(
        "_RTERM-R.CANDIDATE !"
    )
    assert publish.index("_RTERM-R.OBJECT-HIGH !") < publish.index(
        "_RTERM-ELIGIBILITY-CLEAR"
    )
    assert "_RTERM-PJ-IDENTITY-U @ 0 FILL" not in publish


def test_relayout_separates_visible_geometry_from_hidden_scrub() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    geometry = _definition(source, "_RTERM-GEOMETRY?")
    relayout = _definition(source, "_RTERM-UCTX-RELAYOUT-BODY")
    visible = _definition(source, "_RTERM-RELAYOUT-VISIBLE?")
    hidden = _definition(source, "_RTERM-RELAYOUT-HIDDEN?")
    commit = _definition(source, "_RTERM-RELAYOUT-COMMIT")

    boolean = relayout.index("_RTERM-BOOL? 0= IF")
    lookup = relayout.index("_RTERM-CALL-LOOKUP", boolean)
    attached = relayout.index("_RTERM-BINDING-ST-ATTACHED <>", lookup)
    live = relayout.index("_RTERM-CALL-LIVE?", attached)
    branch = relayout.index("_RTERM-RL-VISIBLE @ IF", live)
    visible_call = relayout.index("_RTERM-RELAYOUT-VISIBLE?", branch)
    hidden_call = relayout.index("_RTERM-RELAYOUT-HIDDEN?", visible_call)
    commit_call = relayout.index("_RTERM-RELAYOUT-COMMIT", hidden_call)
    success = relayout.rindex("RTERM-S-OK")
    assert boolean < lookup < attached < live < branch
    assert branch < visible_call < hidden_call < commit_call < success

    for check in (
        "AHS-VISIBLE? 0= IF",
        "_RTERM-RL-REGION @ 0= IF",
        "AHS.RGN @ _RTERM-RL-REGION @ <> IF",
        "_RTERM-REGION-SANE? 0= IF",
        "_RTERM-LIVE-OBJECTS-DISJOINT? 0= IF",
        "_RTERM-LIVE-DISJOINT-BACKEND?",
    ):
        assert check in visible
    assert "_RTERM-RL-REGION @ IF 0 EXIT" in hidden
    assert "AHS-VISIBLE? 0=" in hidden

    visible_branch = commit.index("_RTERM-RL-VISIBLE @ IF")
    hidden_scrub = commit.index("_RTERM-R.REGION 48 0 FILL", visible_branch)
    for field in (
        "_RTERM-R.REGION !",
        "_RTERM-R.ROW !",
        "_RTERM-R.COL !",
        "_RTERM-R.HEIGHT !",
        "_RTERM-R.WIDTH !",
        "_RTERM-R.VISIBLE !",
    ):
        assert visible_branch < commit.index(field) < hidden_scrub
    assert commit.count("_RTERM-R.VISIBLE !") == 1
    assert commit.count("_RTERM-ELIGIBILITY-CLEAR") == 2
    for persistent_mapping_authority in (
        "_RTERM-R.CANDIDATE",
        "_RTERM-R.OBJECT-HIGH",
        "_RTERM-PJ-IDENTITY",
        "_RTERM-CLEAR-RECORD-BANKS",
    ):
        assert persistent_mapping_authority not in commit
    for successful_path in (relayout, visible, hidden, commit):
        assert "_RTERM-R.LAST-STATUS" not in successful_path
    assert "0<=" not in source
    assert "_RTERM-G-HEIGHT @ 0> 0= IF" in geometry
    assert "_RTERM-G-WIDTH @ 0> 0= IF" in geometry


def test_quiesce_detach_scrub_and_install_one_immutable_context() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    uidl = UIDL.read_text(encoding="utf-8")
    detached_valid = _definition(source, "_RTERM-RECORD-DETACHED?")
    quiesce = _definition(source, "_RTERM-UCTX-QUIESCE-BODY")
    detach = _definition(source, "_RTERM-UCTX-DETACH-BODY")
    install = _definition(source, "_RTERM-UIDL-INSTALL-BODY")
    context_install = _definition(uidl, "_UTUI-PROJECTION-ADAPTER!")

    q_lookup = quiesce.index("_RTERM-CALL-LOOKUP")
    q_detached = quiesce.index("_RTERM-BINDING-ST-DETACHED = IF", q_lookup)
    q_states = quiesce.index("_RTERM-BINDING-ST-ATTACHED = SWAP", q_detached)
    q_live = quiesce.index("_RTERM-CALL-LIVE?", q_states)
    q_status = quiesce.index("_RTERM-R.LAST-STATUS !", q_live)
    q_state = quiesce.index("_RTERM-R.STATE !", q_status)
    assert q_lookup < q_detached < q_states < q_live < q_status < q_state
    assert "_RTERM-BINDING-ST-QUIESCED = OR" in quiesce

    d_lookup = detach.index("_RTERM-CALL-LOOKUP")
    d_detached = detach.index("_RTERM-BINDING-ST-DETACHED = IF", d_lookup)
    d_quiesced = detach.index("_RTERM-BINDING-ST-QUIESCED <>", d_detached)
    d_live = detach.index("_RTERM-CALL-LIVE?", d_quiesced)
    d_active = detach.index("_RTERM-B.ACTIVE @ 0= IF", d_live)
    d_banks = detach.index("_RTERM-CLEAR-RECORD-BANKS", d_active)
    d_save = detach.index("_RTERM-R.TOKEN @ _RTERM-D-TOKEN !", d_banks)
    d_scrub = detach.index("RTERM-UIDL-BINDING-SIZE 0 FILL", d_save)
    d_token = detach.index("_RTERM-R.TOKEN !", d_scrub)
    d_issuer = detach.index("_RTERM-R.ISSUER !", d_token)
    d_status = detach.index("_RTERM-R.LAST-STATUS !", d_issuer)
    d_state = detach.index("_RTERM-R.STATE !", d_status)
    d_count = detach.index("-1 _RTERM-C-BACKEND @ _RTERM-B.ACTIVE +!", d_state)
    assert d_lookup < d_detached < d_quiesced < d_live < d_active < d_banks
    assert d_banks < d_save
    assert d_save < d_scrub < d_token < d_issuer < d_status < d_state < d_count
    assert "RTERM-S-INVALID _RTERM-CALL-FAIL EXIT" in detach
    assert "RTERM-S-SOURCE" not in detach
    assert "_RTERM-R.HOST 104 _RTERM-ZERO?" in detached_valid
    assert "_RTERM-R.CANDIDATE 248 _RTERM-ZERO?" in detached_valid
    assert "_RTERM-R.TOKEN @ 0<>" in detached_valid
    assert "_RTERM-R.ISSUER @ _RTERM-RV-BACKEND @ =" in detached_valid
    assert "_RTERM-R.LAST-STATUS @" in detached_valid

    callbacks = (
        "RTERM-UCTX-ATTACH",
        "RTERM-UCTX-PROJECT",
        "RTERM-UCTX-RELAYOUT",
        "RTERM-UCTX-QUIESCE",
        "RTERM-UCTX-DETACH",
    )
    callback_positions = [install.index(f"['] {name}") for name in callbacks]
    adapter_call = install.index("_UTUI-PROJECTION-ADAPTER!")
    installed = install.index("_RTERM-B.INSTALLED !", adapter_call)
    assert callback_positions == sorted(callback_positions)
    assert callback_positions[-1] < adapter_call < installed
    assert "DUP\n    ['] RTERM-UCTX-ATTACH" in install
    assert install.count("_UTUI-PROJECTION-ADAPTER!") == 1

    repeat_guard = context_install.index("_UTUI-PROJ-ADAPTER-INSTALLED @ IF")
    first_store = context_install.index(
        "_UTUI-PAI-CONTEXT @ _UTUI-PROJ-ADAPTER-CONTEXT !"
    )
    repeat_branch = context_install[repeat_guard:first_store]
    for field in (
        "_UTUI-PROJ-ADAPTER-CONTEXT @ _UTUI-PAI-CONTEXT @ =",
        "_UTUI-PROJ-ATTACH-XT  @ _UTUI-PAI-ATTACH  @ =",
        "_UTUI-PROJ-PROJECT-XT @ _UTUI-PAI-PROJECT @ =",
        "_UTUI-PROJ-RELAYOUT-XT @ _UTUI-PAI-RELAYOUT @ =",
        "_UTUI-PROJ-QUIESCE-XT @ _UTUI-PAI-QUIESCE @ =",
        "_UTUI-PROJ-DETACH-XT  @ _UTUI-PAI-DETACH  @ =",
    ):
        assert field in repeat_branch
    assert "EXIT" in repeat_branch
    for incoming in (
        "_UTUI-PAI-CONTEXT @ 0<>",
        "_UTUI-PAI-ATTACH @ 0<>",
        "_UTUI-PAI-PROJECT @ 0<>",
        "_UTUI-PAI-RELAYOUT @ 0<>",
        "_UTUI-PAI-QUIESCE @ 0<>",
        "_UTUI-PAI-DETACH @ 0<>",
    ):
        assert context_install.index(incoming, repeat_guard) < first_store
    installed_last = context_install.index("_UTUI-PROJ-ADAPTER-INSTALLED !")
    assert first_store < installed_last
    assert context_install.count("_UTUI-PROJ-ADAPTER-CONTEXT !") == 1
    assert context_install.count("_UTUI-PROJ-ADAPTER-INSTALLED !") == 1
