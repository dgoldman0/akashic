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
        "../../utils/memory-span.f",
        "engine.f",
        "uidl-projector.f",
    ]

    # This driver is a host/UIDL lifecycle boundary, not another terminal
    # transport or output engine and not part of their source closure.
    for forbidden in (
        "PT-",
        "_PT-",
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
    assert "104 CONSTANT RTERM-UIDL-CONFIG-SIZE" in source
    assert "5 CONSTANT _RTERM-UIDL-ABI" in source
    assert "4 CONSTANT _RTERM-UIDL-CONFIG-ABI" in source
    assert "64 CONSTANT _RTERM-CANDIDATE-META-SIZE" in source
    assert "32 CONSTANT _RTERM-IDENTITY-SIZE" in source
    assert "352 CONSTANT RTERM-UIDL-BINDING-SIZE" in source
    assert "328 CONSTANT RTERM-UIDL-BACKEND-SIZE" in source
    assert "_RGN-DESC-SIZE CONSTANT RGN-SIZE" in region
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
        "_RTERM-R.RESERVED": 344,
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

    signatures = {
        "RTERM-STATUS-VALID?": "( status -- flag )",
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

    public_words = re.findall(r"(?m)^:\s+(RTERM-[^\s]+)(?=\s)", source)
    scrubbed_public = {
        name
        for name in public_words
        if "_RTERM-SCRUB-BORROWED" in _definition(source, name)
    }
    assert scrubbed_public == set(wrappers)
    assert set(re.findall(r"(?m)^:\s+(_RTERM-P-DO-[^\s]+)", source)) == {
        do_name for do_name, _ in wrappers.values()
    }

    for public_name, (do_name, body_name) in wrappers.items():
        wrapper = _definition(source, public_name)
        caught = wrapper.index(f"['] {do_name} CATCH")
        scrubbed = wrapper.index("_RTERM-SCRUB-BORROWED")
        assert caught < scrubbed
        assert wrapper.count("CATCH") == 1
        assert wrapper.count("_RTERM-SCRUB-BORROWED") == 1
        assert body_name not in wrapper

        do_definition = _definition(source, do_name)
        assert do_definition.count(body_name) == 1
        assert "CATCH" not in do_definition
        assert "_RTERM-SCRUB-BORROWED" not in do_definition

    variables = re.findall(r"(?m)^VARIABLE\s+(_RTERM-[^\s]+)", source)
    assert len(variables) == len(set(variables))
    scrub = _definition(source, "_RTERM-SCRUB-BORROWED")
    scrubbed_variables = re.findall(
        r"(?<!\S)0\s+(_RTERM-[A-Z0-9-]+)\s+!", scrub
    )
    assert len(scrubbed_variables) == len(set(scrubbed_variables))
    assert set(scrubbed_variables) == set(variables) - {"_RTERM-NEXT-TOKEN"}
    assert "_RTERM-NEXT-TOKEN" not in scrub


def test_config_and_init_preflight_all_caller_owned_banks_before_mutation() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    geometry = _definition(source, "_RTERM-UIDL-GEOMETRY?")
    config_ranges = _definition(source, "_RTERM-CONFIG-RANGES?")
    backend_ranges = _definition(source, "_RTERM-BACKEND-RANGES?")
    config_init = _definition(source, "_RTERM-CONFIG-INIT-BODY")
    init = _definition(source, "_RTERM-UIDL-INIT-BODY")

    # Binding count determines exactly two positional banks per binding.  The
    # two product capacities remain caller supplied; checked multiplication
    # derives the exact item, positional identity, and snapshot spans without
    # a driver-side cap.
    assert "_RTERM-I-ENGINE @ RTE-VALID?" in geometry
    assert "RTERM-UIDL-BINDING-SIZE MOD" in geometry
    assert "RTERM-UIDL-BINDING-SIZE /" in geometry
    assert "_RTERM-I-CAPACITY @ 2 _RTERM-UMUL?" in geometry
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
    load = _definition(source, "_RTERM-BANK-LOAD")
    clear = _definition(source, "_RTERM-CLEAR-RECORD-BANKS")

    assert "_RTERM-B.RECORDS-A @ -" in index
    assert "RTERM-UIDL-BINDING-SIZE MOD" in index
    assert "RTERM-UIDL-BINDING-SIZE /" in index
    assert "_RTERM-B.CAPACITY @ U< 0=" in index
    assert "_RTERM-BK-BANK @ 2 U< 0=" in load
    assert "_RTERM-BK-INDEX @ 2 * _RTERM-BK-BANK @ +" in load
    assert "_RTERM-B.ITEMS-PER-BANK @ RUPJ-ITEM-BYTES" in load
    assert "_RTERM-B.ITEMS-A @" in load
    assert "_RTERM-B.ITEMS-PER-BANK @\n        _RTERM-IDENTITY-SIZE" in load
    assert "_RTERM-B.IDENTITIES-A @" in load
    assert "_RTERM-B.SNAPSHOTS-A @" in load
    assert "_RTERM-B.SNAPSHOT-BANK-U @" in load

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
    assert source.count("RUPJ-CANDIDATE-VALID?") == 2
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


def test_ordinary_validation_checks_selected_metadata_without_deep_scanning() -> None:
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
    assert metadata.count("_RTERM-LENGTH-MAX U> IF") == 2
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
        "_RTERM-UIDL-VALID-BODY?",
        "_RTERM-CALL-LOOKUP",
    ):
        body = _definition(source, hot_path)
        assert "RUPJ-CANDIDATE-VALID?" not in body
        assert "RUPJ-BUILD" not in body


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

    # This slice reads limits only.  Owner lifecycle, retained capture, and
    # output scheduling remain absent until the coherent materializer slice.
    code = _code_without_comments(source)
    assert code.count("RTE-LIMITS@") == 1
    for forbidden in (
        "RTE-OWNER-OPEN",
        "RTE-OWNER-STATE@",
        "RTE-RETAINED-BEGIN",
        "RTE-REGION-DEFINE",
        "RTE-LABEL-PREFLIGHT",
        "RTE-LABEL-DEFINE",
        "RTE-RETAINED-SEAL",
        "RTE-RETAINED-CANCEL",
        "RTE-OWNER-DROP",
    ):
        assert forbidden not in code


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
    assert "_RTERM-R.CANDIDATE 216 _RTERM-ZERO?" in detached_valid
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
