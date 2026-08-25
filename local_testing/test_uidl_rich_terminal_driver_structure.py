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
    ]

    # This driver is a host/UIDL lifecycle boundary, not another terminal
    # transport or presentation engine and not part of their source closure.
    for forbidden in (
        "PT-",
        "_PT-",
        "RTAPT-",
        "_RTAPT-",
        "APTSCB-",
        "UART-",
        "rich-terminal.f",
        "apt1-engine.f",
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


def test_public_contract_has_exact_statuses_sizes_and_entry_points() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    region = REGION.read_text(encoding="utf-8")

    assert re.findall(
        r"(?m)^(\d+) CONSTANT (RTERM-S-[A-Z-]+)\s*$", source
    ) == [
        ("0", "RTERM-S-OK"),
        ("1", "RTERM-S-WOULD-BLOCK"),
        ("2", "RTERM-S-UNAVAILABLE"),
        ("3", "RTERM-S-CAPACITY"),
        ("4", "RTERM-S-STALE"),
        ("5", "RTERM-S-INVALID"),
        ("6", "RTERM-S-SESSION-LOST"),
        ("7", "RTERM-S-SOURCE"),
    ]
    assert "8 U<" in _definition(source, "RTERM-STATUS-VALID?")

    assert "96 CONSTANT RTERM-HOST-BINDING-SIZE" in source
    assert "144 CONSTANT RTERM-UIDL-BINDING-SIZE" in source
    assert "96 CONSTANT RTERM-UIDL-BACKEND-SIZE" in source
    assert "_RGN-DESC-SIZE CONSTANT RGN-SIZE" in region
    assert "RTERM-UIDL-BINDING-SIZE" in _definition(
        source, "RTERM-UIDL-BINDING-BYTES"
    )
    assert "RTERM-UIDL-BACKEND-SIZE" in _definition(
        source, "RTERM-UIDL-BACKEND-BYTES"
    )

    signatures = {
        "RTERM-STATUS-VALID?": "( status -- flag )",
        "RTERM-UIDL-BINDING-BYTES": "( -- bytes )",
        "RTERM-UIDL-BACKEND-BYTES": "( -- bytes )",
        "RTERM-UIDL-INIT": "( host records-a records-u backend -- status )",
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
        assert signature in _definition(source, name).splitlines()[0]


def test_public_scratch_entries_catch_bodies_then_scrub_every_borrowed_cell() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    wrappers = {
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


def test_init_preflights_all_ranges_before_publishing_mutation() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    ranges = _definition(source, "_RTERM-UIDL-RANGES?")
    init = _definition(source, "_RTERM-UIDL-INIT-BODY")

    assert ranges.count("_RTERM-SPAN?") == 3
    assert "RTERM-UIDL-BINDING-SIZE MOD" in ranges
    assert "RTERM-UIDL-BINDING-SIZE / 0=" in ranges
    assert ranges.count("_RTERM-DISJOINT?") == 3
    assert "!" not in ranges

    preflight = init.index("_RTERM-UIDL-RANGES? 0= IF")
    records_fill = init.index("_RTERM-I-RECORDS-U @ 0 FILL")
    backend_fill = init.index("RTERM-UIDL-BACKEND-SIZE 0 FILL")
    magic = init.index("_RTERM-B.MAGIC !")
    assert preflight < records_fill < backend_fill < magic
    assert init.count("0 FILL") == 2
    for field in (
        "_RTERM-B.ABI !",
        "_RTERM-B.SIZE !",
        "_RTERM-B.SELF !",
        "_RTERM-B.HOST !",
        "_RTERM-B.RECORDS-A !",
        "_RTERM-B.RECORDS-U !",
        "_RTERM-B.CAPACITY !",
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
    backend = fini.index("RTERM-UIDL-BACKEND-SIZE 0 FILL", records)
    assert span < blank < valid < active < records < backend
    assert "DROP RTERM-S-WOULD-BLOCK EXIT" in fini[active:records]
    assert fini.count("0 FILL") == 2


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
    assert "UTUI-RICH-TERM-ATTACH" in attach_body
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

    fill = populate.index("RTERM-UIDL-BINDING-SIZE 0 FILL")
    token = populate.index("_RTERM-R.TOKEN !", fill)
    state = populate.index("_RTERM-R.STATE !", token)
    active = populate.index("_RTERM-B.ACTIVE +!", state)
    assert fill < token < state < active


def test_project_is_explicitly_unavailable_and_wire_inert() -> None:
    source = DRIVER.read_text(encoding="utf-8")
    project = _definition(source, "_RTERM-UCTX-PROJECT-BODY")

    lookup = project.index("_RTERM-CALL-LOOKUP")
    attached = project.index("_RTERM-BINDING-ST-ATTACHED <>", lookup)
    live = project.index("_RTERM-CALL-LIVE?", attached)
    note = project.index("RTERM-S-UNAVAILABLE _RTERM-C-RECORD @", live)
    returned = project.rindex("RTERM-S-UNAVAILABLE")
    assert lookup < attached < live < note < returned
    assert project.count("RTERM-S-UNAVAILABLE") == 2
    assert project.count("!") == 1
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
    context_install = _definition(uidl, "_UTUI-RICH-TERM-DRIVER!")

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
    d_save = detach.index("_RTERM-R.TOKEN @ _RTERM-D-TOKEN !", d_active)
    d_scrub = detach.index("RTERM-UIDL-BINDING-SIZE 0 FILL", d_save)
    d_token = detach.index("_RTERM-R.TOKEN !", d_scrub)
    d_issuer = detach.index("_RTERM-R.ISSUER !", d_token)
    d_status = detach.index("_RTERM-R.LAST-STATUS !", d_issuer)
    d_state = detach.index("_RTERM-R.STATE !", d_status)
    d_count = detach.index("-1 _RTERM-C-BACKEND @ _RTERM-B.ACTIVE +!", d_state)
    assert d_lookup < d_detached < d_quiesced < d_live < d_active < d_save
    assert d_save < d_scrub < d_token < d_issuer < d_status < d_state < d_count
    assert "RTERM-S-INVALID _RTERM-CALL-FAIL EXIT" in detach
    assert "RTERM-S-SOURCE" not in detach
    assert "_RTERM-R.HOST 104 _RTERM-ZERO?" in detached_valid
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
    driver_call = install.index("_UTUI-RICH-TERM-DRIVER!")
    installed = install.index("_RTERM-B.INSTALLED !", driver_call)
    assert callback_positions == sorted(callback_positions)
    assert callback_positions[-1] < driver_call < installed
    assert "DUP\n    ['] RTERM-UCTX-ATTACH" in install
    assert install.count("_UTUI-RICH-TERM-DRIVER!") == 1

    repeat_guard = context_install.index("_UTUI-RT-DRIVER-INSTALLED @ IF")
    first_store = context_install.index(
        "_UTUI-RTI-CONTEXT @ _UTUI-RT-DRIVER-CONTEXT !"
    )
    repeat_branch = context_install[repeat_guard:first_store]
    for field in (
        "_UTUI-RT-DRIVER-CONTEXT @ _UTUI-RTI-CONTEXT @ =",
        "_UTUI-RT-ATTACH-XT  @ _UTUI-RTI-ATTACH  @ =",
        "_UTUI-RT-PROJECT-XT @ _UTUI-RTI-PROJECT @ =",
        "_UTUI-RT-RELAYOUT-XT @ _UTUI-RTI-RELAYOUT @ =",
        "_UTUI-RT-QUIESCE-XT @ _UTUI-RTI-QUIESCE @ =",
        "_UTUI-RT-DETACH-XT  @ _UTUI-RTI-DETACH  @ =",
    ):
        assert field in repeat_branch
    assert "EXIT" in repeat_branch
    for incoming in (
        "_UTUI-RTI-CONTEXT @ 0<>",
        "_UTUI-RTI-ATTACH @ 0<>",
        "_UTUI-RTI-PROJECT @ 0<>",
        "_UTUI-RTI-RELAYOUT @ 0<>",
        "_UTUI-RTI-QUIESCE @ 0<>",
        "_UTUI-RTI-DETACH @ 0<>",
    ):
        assert context_install.index(incoming, repeat_guard) < first_store
    installed_last = context_install.index("_UTUI-RT-DRIVER-INSTALLED !")
    assert first_store < installed_last
    assert context_install.count("_UTUI-RT-DRIVER-CONTEXT !") == 1
    assert context_install.count("_UTUI-RT-DRIVER-INSTALLED !") == 1
