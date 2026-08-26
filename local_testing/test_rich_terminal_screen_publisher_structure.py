"""Seconds-only structural locks for the neutral screen publisher bridge."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SCREEN = ROOT / "akashic" / "tui" / "screen-backend-apt1.f"
ENGINE = ROOT / "akashic" / "tui" / "rich-terminal" / "apt1-engine.f"
BRIDGE = ROOT / "akashic" / "tui" / "rich-terminal" / "screen-adapter-apt1.f"
SHELL = ROOT / "akashic" / "tui" / "app-shell-apt1.f"


def _definition(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*(?:\\[^\n]*)?$", source
    )
    assert match is not None, f"missing Forth definition {name}"
    return match.group(0)


def test_baseline_publisher_is_neutral_exact_and_immutable() -> None:
    source = SCREEN.read_text(encoding="utf-8")

    assert "RTAPT-" not in source
    assert "rich-terminal/apt1-engine.f" not in source
    assert "REQUIRE screen.f" in source
    assert "REQUIRE ../utils/memory-span.f" in source

    valid = _definition(source, "APTSCB-PUBLISHER-VALID?")
    for field in (
        "APTSCBP.SESSION",
        "APTSCBP.CONTEXT",
        "APTSCBP.BEGIN-XT",
        "APTSCBP.SPAN-XT",
        "APTSCBP.CELL-XT",
        "APTSCBP.CURSOR-XT",
        "APTSCBP.COMMIT-XT",
        "APTSCBP.ABORT-XT",
        "APTSCBP.STEP-XT",
        "APTSCBP.SETTLE-XT",
        "APTSCBP.MAGIC",
    ):
        assert field in valid
    assert "7 AND" in valid
    assert "MSPAN-NONWRAPPING?" in valid

    init = _definition(source, "APTSCB-PUBLISHER-INIT")
    first_mutation = init.index("0 FILL")
    assert init.index("PT-STORAGE-DISJOINT?") < first_mutation
    assert init.index("MSPAN-NONWRAPPING?") < first_mutation
    assert init.index("_APTSCBPI-SETTLE @ 0= OR") < first_mutation

    attach = _definition(source, "APTSCB-PUBLISHER!")
    assert "_APTSCB-ROUTE-IDLE <>" in attach
    assert "APTSCBP.SESSION" in attach
    assert "APTSCB-STORAGE-DISJOINT?" in attach
    assert "APTSCB.PUBLISHER @ ?DUP IF" in attach
    assert "_APTSCBPA-PUBLISHER @ = IF SCB-S-OK" in attach
    assert attach.count("APTSCB.PUBLISHER !") == 1

    adapter_storage = _definition(source, "_APTSCBI-STORAGE-VALID?")
    assert "PT-STORAGE-DISJOINT?" in adapter_storage


def test_screen_transaction_pins_one_route_and_normalizes_cells_once() -> None:
    source = SCREEN.read_text(encoding="utf-8")
    begin = _definition(source, "_APTSCB-BEGIN")
    span_begin = _definition(source, "_APTSCB-SPAN-BEGIN")
    write_cell = _definition(source, "_APTSCB-WRITE-CELL")
    span = _definition(source, "_APTSCB-SPAN")
    cursor = _definition(source, "_APTSCB-CURSOR")
    commit = _definition(source, "_APTSCB-COMMIT")
    abort = _definition(source, "_APTSCB-ABORT")

    assert "PT-RETAINED-AVAILABLE?" in begin
    assert begin.count("_APTSCB.ROUTE !") == 3
    assert "_APTSCB-ROUTE-DIRECT" in begin
    assert "_APTSCB-ROUTE-OUTPUT" in begin
    assert "PT-CELL-REPLACE" in begin
    assert "PT-CELL-DELTA" in begin
    assert begin.index("PT-RETAINED-AVAILABLE?") < begin.index(
        "APTSCBP.BEGIN-XT"
    )

    assert "APTSCBP.SPAN-XT" in span_begin
    assert "APTSCBP.CELL-XT" in write_cell
    assert "_APTSCB-CELL-CP" in write_cell
    assert "_APTSCB-WIRE-ATTRS" in write_cell
    assert span.index("_APTSCB-SPAN-BEGIN") < span.index("_APTSCB-WRITE-CELL")
    assert "_APTSCB.ROUTE !" not in span
    assert "_APTSCB.ROUTE !" not in cursor
    assert "_APTSCB-ROUTE-DIRECT" in cursor
    assert "_APTSCB-ROUTE-OUTPUT" in cursor
    for finalizer in (commit, abort):
        assert "_APTSCB-ROUTE-DIRECT" in finalizer
        assert "_APTSCB-ROUTE-OUTPUT" in finalizer
        assert "_APTSCB-ROUTE-IDLE" in finalizer


def test_normal_service_and_close_settlement_have_disjoint_schedulers() -> None:
    screen = SCREEN.read_text(encoding="utf-8")
    shell = SHELL.read_text(encoding="utf-8")
    normal = _definition(screen, "APTSCB-SERVICE")
    normal_dispatch = _definition(screen, "_APTSCB-PUBLISHER-STEP")
    settle_dispatch = _definition(screen, "_APTSCB-PUBLISHER-SETTLE")
    ansi_retire = _definition(screen, "_APTSCB-ANSI-RETIRE")
    close = _definition(screen, "APTSCB-CLOSE-STEP")
    shell_close = _definition(shell, "_APTAS-CLOSE")

    assert normal.index("PT-SERVICE") < normal.index("_APTSCB-PUBLISHER-STEP")
    assert "_APTSCB-PUBLISHER-SETTLE" not in normal
    assert normal.count("_APTSCB-ANSI-RETIRE") == 2
    active_gate = normal.index("PT-ACTIVE? 0= IF")
    assert normal.index("PT-SERVICE") < active_gate
    assert active_gate < normal.index("_APTSCB-PUBLISHER-STEP")
    assert "APTSCBP.STEP-XT" in normal_dispatch
    assert "APTSCBP.SETTLE-XT" not in normal_dispatch

    assert "APTSCBP.SETTLE-XT" in settle_dispatch
    assert "APTSCBP.STEP-XT" not in settle_dispatch
    assert "PT-STREAM-OWNED?" in ansi_retire
    assert "_APTSCB-PUBLISHER-SETTLE 2DROP" in ansi_retire
    assert ansi_retire.index("_APTSCB-PUBLISHER-SETTLE") < ansi_retire.index(
        "_APTSCB-ROUTE-IDLE"
    ) < ansi_retire.index("_APTSCB-FALLBACK")
    latch_path = close.split("\\ Latch PT's immutable close reason", 1)[1]
    close_call = latch_path.index("PT-CLOSE")
    service_call = latch_path.index("PT-SERVICE", close_call)
    settle_call = latch_path.rindex("_APTSCB-PUBLISHER-SETTLE")
    assert close_call < service_call < settle_call
    assert latch_path.count("PT-CLOSE") == 1
    for state in ("PT-ST-ANSI", "PT-ST-LOST", "PT-ST-CLOSING"):
        assert state in latch_path[close_call:service_call]
        assert state in latch_path[service_call:settle_call]
    assert close.count("_APTSCB-PUBLISHER-SETTLE") == close.count(
        "_APTSCB-PUBLISHER-SETTLE 2DROP"
    )
    assert close.count("_APTSCB-ANSI-RETIRE") == 4
    assert "_APTSCB-PENDING" not in close
    assert "_APTSCB-PUBLISHER-STEP" not in close
    assert "MS@" not in close
    assert "_PT.S" not in close

    assert shell_close.count("APTSCB-CLOSE-STEP") == 1
    assert "APTSCB-SERVICE" not in shell_close
    assert "PT-CLOSE" not in shell_close
    assert "PT-SERVICE" not in shell_close
    assert "_APTAS-STATE-OWNS?" in shell_close
    shell_step = shell_close.index("APTSCB-CLOSE-STEP")
    post_state = shell_close.index("PT-STATE@", shell_step)
    status_gate = shell_close.index("_APTAS-STATUS @ DUP SCB-S-OK <>", post_state)
    yield_call = shell_close.index("YIELD?", status_gate)
    retry = shell_close.index("AGAIN", yield_call)
    assert shell_step < post_state < status_gate < yield_call < retry
    assert "SCB-S-WOULD-BLOCK <> AND IF" in shell_close[status_gate:yield_call]
    owner_storage = _definition(shell, "_APTASI-STORAGE-VALID?")
    assert "PT-STORAGE-DISJOINT?" in owner_storage


def test_concrete_bridge_is_caller_bounded_and_one_to_one() -> None:
    source = BRIDGE.read_text(encoding="utf-8")

    assert "PROVIDED akashic-tui-rtaptscb1" in source
    assert "REQUIRE ../screen-backend-apt1.f" in source
    assert "REQUIRE apt1-engine.f" in source
    assert not re.search(r"(?m)^REQUIRE\s+.*(?:MegaPad|rich-terminal)\.f\s*$", source)
    assert "PT-SERVICE" not in source
    assert "PT-PRESENT-" not in source
    assert "PT-SNAPSHOT-BEGIN" not in source
    assert "PT-TX-BEGIN" not in source
    assert not re.search(r"\b(?:CREATE|ALLOT|XBUF)\b", source)

    callbacks = {
        "_RTAPTSCB-BEGIN": "RTAPT-CELL-BEGIN",
        "_RTAPTSCB-SPAN": "RTAPT-CELL-SPAN-BEGIN",
        "_RTAPTSCB-CELL": "RTAPT-CELL-WRITE",
        "_RTAPTSCB-CURSOR": "RTAPT-CELL-CURSOR",
        "_RTAPTSCB-COMMIT": "RTAPT-CELL-COMMIT",
        "_RTAPTSCB-ABORT": "RTAPT-CELL-ABORT",
        "_RTAPTSCB-ENGINE-STEP": "RTAPT-STEP",
        "_RTAPTSCB-SETTLE": "RTAPT-SETTLE",
    }
    for word, target in callbacks.items():
        body = _definition(source, word)
        assert body.count(target) == 1

    init = _definition(source, "RTAPTSCB-INIT")
    assert "RTAPT-VALID?" in init
    assert "RTAPT-USES-SESSION?" in init
    assert "RTAPT-STORAGE-DISJOINT?" in init
    assert "APTSCB-PUBLISHER-INIT" in init
    attach = _definition(source, "RTAPTSCB-ATTACH")
    assert "RTAPTSCB-SIZE" in attach
    assert "APTSCB-SIZE" in attach
    assert "MSPAN-OVERLAP?" in attach
    assert "RTAPT-STORAGE-DISJOINT?" in attach
    assert "APTSCB-PUBLISHER!" in attach

    settle = _definition(source, "_RTAPTSCB-SETTLE")
    pending = settle.index("_RTAPTSCB-PENDING @ IF")
    assert settle.index("SCB-S-WOULD-BLOCK -1 EXIT", pending) > pending
    assert settle.index("SCB-S-OK 0", pending) > pending
    assert "_RTAPTSCB-MAP-STATUS" not in settle

    mapper = _definition(source, "_RTAPTSCB-MAP-STATUS")
    assert "RTAPT-S-OK" in mapper
    assert "RTAPT-S-WOULD-BLOCK" in mapper
    assert "RTAPT-S-BUSY" in mapper
    assert "RTAPT-S-SESSION-LOST" in mapper
    assert "DROP SCB-S-INVALID" in mapper


def test_output_producer_hook_is_optional_immutable_and_caller_bounded() -> None:
    source = BRIDGE.read_text(encoding="utf-8")

    assert "APTSCB-PUBLISHER-SIZE 104 + CONSTANT RTAPTSCB-SIZE" in source
    for suffix, offset in {
        "PRODUCER-CONTEXT": 16,
        "PRODUCER-U": 24,
        "PRODUCER-BUDGET": 32,
        "PRODUCER-STEP-XT": 40,
        "PRODUCER-PREPARE-XT": 48,
        "ADAPTER": 56,
        "SURFACE-COLS": 64,
        "SURFACE-ROWS": 72,
        "SURFACE-GENERATION": 80,
        "MORE-WORK": 88,
        "OUTPUT-NEEDED": 96,
    }.items():
        assert (
            f"APTSCB-PUBLISHER-SIZE {offset} + CONSTANT "
            f"_RTAPTSCB-O-{suffix}"
        ) in source

    producer_valid = _definition(source, "_RTAPTSCB-PRODUCER-VALID?")
    for token in (
        "_RTAPTSCB-SPAN?",
        "_RTAPTSCB.PRODUCER-BUDGET @",
        "_RTAPTSCB.PRODUCER-STEP-XT @",
        "_RTAPTSCB.PRODUCER-PREPARE-XT @",
        "_RTAPTSCB-BOOL?",
        "MSPAN-OVERLAP?",
        "RTAPT-STORAGE-DISJOINT?",
        "APTSCB-STORAGE-DISJOINT?",
    ):
        assert token in producer_valid
    assert "_RTAPTSCB-VALID-CONTEXT @ 0= IF" in producer_valid

    binder = _definition(source, "RTAPTSCB-OUTPUT-PRODUCER!")
    first_store = binder.index("_RTAPTSCB.PRODUCER-CONTEXT !")
    for preflight in (
        "RTAPTSCB-VALID?",
        "_RTAPTSCB-SPAN?",
        "0> 0= IF",
        "MSPAN-OVERLAP?",
        "RTAPT-STORAGE-DISJOINT?",
        "APTSCB-STORAGE-DISJOINT?",
    ):
        assert binder.index(preflight) < first_store
    assert "_RTAPTSCB.PRODUCER-CONTEXT @ IF" in binder
    assert "IF SCB-S-OK ELSE SCB-S-INVALID THEN EXIT" in binder
    assert binder.count("_RTAPTSCB.PRODUCER-CONTEXT !") == 1
    assert "_RTAPTSCB.SURFACE-GENERATION @ IF" in binder
    context_publish = binder.index("_RTAPTSCB.PRODUCER-CONTEXT !")
    for field in (
        "_RTAPTSCB.PRODUCER-U !",
        "_RTAPTSCB.PRODUCER-BUDGET !",
        "_RTAPTSCB.PRODUCER-STEP-XT !",
        "_RTAPTSCB.PRODUCER-PREPARE-XT !",
    ):
        assert binder.index(field) < context_publish

    attach = _definition(source, "RTAPTSCB-ATTACH")
    assert "_RTAPTSCB.ADAPTER @ ?DUP IF" in attach
    assert "APTSCB-STORAGE-DISJOINT?" in attach
    first_attach_store = attach.index("_RTAPTSCB.ADAPTER !")
    assert attach.index("APTSCB-PUBLISHER!") < first_attach_store
    assert attach.count("_RTAPTSCB.ADAPTER !") == 1


def test_output_producer_runs_after_reconciliation_at_exact_surface() -> None:
    source = BRIDGE.read_text(encoding="utf-8")
    code = "\n".join(line.split("\\", 1)[0] for line in source.splitlines())

    step = _definition(source, "_RTAPTSCB-STEP")
    assert step.index("_RTAPTSCB-ENGINE-STEP") < step.index(
        "_RTAPTSCB-PRODUCER-STEP"
    )
    producer_step = _definition(source, "_RTAPTSCB-PRODUCER-STEP")
    call_order = (
        "_RTAPTSCB.SURFACE-COLS @",
        "_RTAPTSCB.SURFACE-ROWS @",
        "_RTAPTSCB.SURFACE-GENERATION @",
        "_RTAPTSCB.PRODUCER-BUDGET @",
        "_RTAPTSCB.PRODUCER-CONTEXT @",
        "_RTAPTSCB.PRODUCER-STEP-XT @ EXECUTE",
    )
    callback_tuple = producer_step.index("_RTAPTSCB-EXACT-SCREEN?")
    positions = [producer_step.index(token, callback_tuple) for token in call_order]
    assert positions == sorted(positions)
    producer_save = producer_step.index("_RTAPTSCB-R @ >R", callback_tuple)
    producer_execute = producer_step.index(
        "_RTAPTSCB.PRODUCER-STEP-XT @ EXECUTE", producer_save
    )
    producer_restore = producer_step.index("R> _RTAPTSCB-R !", producer_execute)
    assert producer_save < producer_execute < producer_restore
    status_gate = producer_step.index("_RTAPTSCB-SCB-STATUS? 0= IF")
    bool_gate = producer_step.index("_RTAPTSCB-BOOL? 0=", status_gate)
    fatal_gate = producer_step.index(
        "_RTAPTSCB-PRODUCER-STATUS @ DUP SCB-S-SESSION-LOST =", bool_gate
    )
    fatal_more = producer_step.index(
        "0 _RTAPTSCB-R @ _RTAPTSCB.MORE-WORK !", fatal_gate
    )
    fatal_output = producer_step.index(
        "0 _RTAPTSCB-R @ _RTAPTSCB.OUTPUT-NEEDED !", fatal_more
    )
    latch = producer_step.rindex("_RTAPTSCB.MORE-WORK !")
    output_latch = producer_step.rindex("_RTAPTSCB.OUTPUT-NEEDED !")
    assert status_gate < bool_gate < fatal_gate < fatal_more < fatal_output
    assert fatal_output < latch < output_latch

    observe = _definition(source, "_RTAPTSCB-SURFACE-OBSERVE")
    assert "_RTAPTSCB-DIMENSION?" in observe
    assert "_RTAPTSCB.SURFACE-GENERATION @ 0= IF" in observe
    assert "1 _RTAPTSCB-SURFACE-PUBLISHER @" in observe
    assert "1+ DUP 0= IF DROP SCB-S-INVALID EXIT THEN" in observe
    assert observe.index("_RTAPTSCB-SURFACE-NEXT !") < observe.index(
        "_RTAPTSCB.SURFACE-COLS !", observe.index("_RTAPTSCB-SURFACE-NEXT !")
    )

    begin = _definition(source, "_RTAPTSCB-BEGIN")
    producer_guard = begin.index("_RTAPTSCB-PRODUCER-BOUND? IF")
    surface_observe = begin.index("_RTAPTSCB-SURFACE-OBSERVE", producer_guard)
    assert producer_guard < surface_observe < begin.index(
        "_RTAPTSCB-PRODUCER-PREPARE"
    ) < begin.index("RTAPT-CELL-BEGIN")
    clear_latch = begin.index("_RTAPTSCB.OUTPUT-NEEDED !")
    assert begin.index("SCB-S-OK = IF") < clear_latch

    prepare = _definition(source, "_RTAPTSCB-PRODUCER-PREPARE")
    assert "_RTAPTSCB-EXACT-SCREEN?" in prepare
    assert prepare.index("_RTAPTSCB.SURFACE-COLS @") < prepare.index(
        "_RTAPTSCB.PRODUCER-PREPARE-XT @ EXECUTE"
    )
    prepare_save = prepare.index("_RTAPTSCB-R @ >R")
    prepare_execute = prepare.index(
        "_RTAPTSCB.PRODUCER-PREPARE-XT @ EXECUTE", prepare_save
    )
    prepare_restore = prepare.index("R> _RTAPTSCB-R !", prepare_execute)
    assert prepare_save < prepare_execute < prepare_restore

    engine_step = _definition(source, "_RTAPTSCB-ENGINE-STEP")
    rejected = engine_step.index("RTAPT-S-REJECTED = IF SCB-S-OK EXIT THEN")
    mapped = engine_step.index("_RTAPTSCB-MAP-STATUS", rejected)
    assert rejected < mapped
    output_query = _definition(source, "RTAPTSCB-OUTPUT-NEEDED?")
    assert "RTAPTSCB-VALID?" in output_query
    assert "_RTAPTSCB-EXACT-SCREEN?" in output_query

    for forbidden in (
        "RTE-LABEL-PREFLIGHT",
        "RTERM-",
        "PRESENT-",
        "PRESENT_",
        "SCR-FORCE",
    ):
        assert forbidden not in code


def test_engine_settlement_only_reconciles_active_wire_authority() -> None:
    source = ENGINE.read_text(encoding="utf-8")
    settle = _definition(source, "RTAPT-SETTLE")

    assert "_RTAPT-E.ACTIVE-KIND" in settle
    assert "_RTAPT-POLL-COMPLETION" in settle
    assert "_RTAPT-SESSION-ENDED?" in settle
    ended = settle.index("_RTAPT-SESSION-ENDED?")
    active_none = settle.index("_RTAPT-ACTIVE-NONE =")
    poll = settle.index("_RTAPT-POLL-COMPLETION")
    assert ended < active_none < poll
    for forbidden in (
        "RTAPT-STEP",
        "_RTAPT-E.QUEUE-HEAD",
        "_RTAPT-E.QUEUE-TAIL",
        "_RTAPT-OWNER-SEND",
        "_RTAPT-QUEUE-POP",
        "PT-OWNER-OPEN",
        "PT-OWNER-DROP",
        "PT-SERVICE",
    ):
        assert forbidden not in settle
