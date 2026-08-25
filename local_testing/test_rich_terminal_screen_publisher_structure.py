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
        "_RTAPTSCB-STEP": "RTAPT-STEP",
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
