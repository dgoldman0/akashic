"""Owned bank parsing refuses escaped pointers and corrupt ACK frontiers."""
from test_field_model import run_field
from test_shell_family_clone import CLONE
from test_shell_snapshot import PRELUDE as SOURCE

FIXTURE = CLONE + SOURCE + r'''
CREATE _SB-SS 247 ALLOT CREATE _SB-BS 32775 ALLOT CREATE _SB-CS 32775 ALLOT
CREATE _SB-PS RTHP-SIZE 7 + ALLOT CREATE _SB-HS SHSN-SIZE 7 + ALLOT
CREATE _SB-XS RTE-SHELL-FACADE-SIZE 7 + ALLOT CREATE _SB-WS 4103 ALLOT
: _SB-S _SB-SS 7 + -8 AND ; : _SB-B _SB-BS 7 + -8 AND ; : _SB-C _SB-CS 7 + -8 AND ;
: _SB-P _SB-PS 7 + -8 AND ; : _SB-H _SB-HS 7 + -8 AND ; : _SB-X _SB-XS 7 + -8 AND ;
: _SB-W _SB-WS 7 + -8 AND ;
VARIABLE _SB-BO VARIABLE _SB-U VARIABLE _SB-OLD
: _SB-BUILD
    _SS-BUILD
    80 _SS-M SHM.WIDTH ! 24 _SS-M SHM.HEIGHT !
    23 1 _SS-M SHM-ENTRY SHME.ROW ! 23 2 _SS-M SHM-ENTRY SHME.ROW !
    _SS-FREEZE _SS-VALID 0= _RC-A
    _SB-S 240 0 FILL _SB-B 32768 0 FILL
    _SB-B _SB-S _RSHSP.A ! 32768 _SB-S _RSHSP.A-U !
    RSHSP-BANK-HEADER-SIZE _SB-B RSHSP-BANK.MODEL ! _SS-U @ _SB-B RSHSP-BANK.MODEL-U !
    _SS-F _SB-B RSHSP-BANK-HEADER-SIZE + _SS-U @ MOVE
    _SS-U @ 7 + -8 AND RSHSP-BANK-HEADER-SIZE + DUP _SB-BO ! _SB-B RSHSP-BANK.BATCH !
    _RC-BATCH _SB-B _SB-BO @ + 32768 _SB-BO @ - RSHFC-COPY 0= _RC-A
    _SB-BO @ + DUP _SB-U ! _SB-B RSHSP-BANK.USED !
    1234 _SB-B RSHSP-BANK.TARGET ! 3 _SB-B RSHSP-BANK.DRAW !
    7 _SB-B RSHSP-BANK.OWNER ! 9 _SB-B RSHSP-BANK.GENERATION !
    21 _SB-B RSHSP-BANK.NEXT-REGION ! 106 _SB-B RSHSP-BANK.NEXT-OBJECT ! ;
: _SB-VALID _SB-B _SB-S _RSHSP-BANK-VALID? ;
: _SB-BAD ( value field -- ) DUP @ >R DUP >R ! _SB-VALID 0= _RC-A R> R> SWAP ! ;
: _SB-BATCH _SB-B _SB-BO @ + ;
: _SB-HEADER
    _SB-S 240 0 FILL
    _RSHSP-MAGIC _SB-S _RSHSP.MAGIC ! 208 _SB-S _RSHSP.SIZE ! _SB-S _SB-S _RSHSP.SELF !
    _SB-P _SB-S _RSHSP.PRODUCER ! _SB-H _SB-S _RSHSP.SOURCE ! _SB-X _SB-S _RSHSP.SHELL !
    _SB-W _SB-S _RSHSP.WORK ! 4096 _SB-S _RSHSP.WORK-U !
    _SB-B _SB-S _RSHSP.A ! 32768 _SB-S _RSHSP.A-U !
    _SB-C _SB-S _RSHSP.B ! 32768 _SB-S _RSHSP.B-U ! ;
'''


def run(program, minimum=1):
    run_field(program, marker="CATALOG", minimum=minimum,
              extra_sources=("tui/rich-terminal/shell-screen-producer.f",))


def test_owned_bank_graph_offsets_frontiers_and_whole_clone_extent():
    run(FIXTURE + r'''
_SB-BUILD _SB-VALID _RC-A
0 _SB-B RSHSP-BANK.NEXT-REGION _SB-BAD
22 _SB-B RSHSP-BANK.NEXT-REGION _SB-BAD
0 _SB-B RSHSP-BANK.NEXT-OBJECT _SB-BAD
107 _SB-B RSHSP-BANK.NEXT-OBJECT _SB-BAD
\ A prompt identity for a model without Desk's prompt.
101 _SB-B RSHSP-BANK.PROMPT _SB-BAD
_SB-U @ 8 + _SB-B RSHSP-BANK.USED _SB-BAD
_SB-BO @ 8 + _SB-B RSHSP-BANK.BATCH _SB-BAD
RSHSP-BANK-HEADER-SIZE 8 + _SB-B RSHSP-BANK.MODEL _SB-BAD
81 _SB-B RSHSP-BANK-HEADER-SIZE + SHM.WIDTH _SB-BAD
_RC-CAT _SB-BATCH _RTE-FB.CATALOG-A _SB-BAD
_SB-B RSHSP-BANK-HEADER-SIZE + _SB-BATCH _RTE-FB.CATALOG-A _SB-BAD
_RC-FAM _SB-BATCH _RTE-FB.FAMILIES-A _SB-BAD
_SB-BATCH _RTE-FB.FAMILIES-A @ _RTE-FE.PLAN-A DUP @ _SB-OLD !
_RC-CP SWAP ! _SB-VALID 0= _RC-A
_SB-OLD @ _SB-BATCH _RTE-FB.FAMILIES-A @ _RTE-FE.PLAN-A !
_SB-BATCH _RTE-FB.FAMILIES-A @ RTE-FAMILY-ITEMS@ DROP _RTE-CONTROL.ID
0x8000000000000000 SWAP _SB-BAD
_SB-VALID _RC-A
\ A generic valid SERIES-only clone has no regions; shell bank refuses it
\ before computing a last-region pointer below its owned array.
_RC-FAM 256 + _RC-FAM 64 MOVE 64 _RC-BATCH _RTE-FB.FAMILIES-U !
0 _RC-CAT _RTE-RC.REGIONS-A ! 0 _RC-CAT _RTE-RC.REGIONS-U !
0 _RC-YI _RTE-SERIES.SAMPLES-A ! 0 _RC-YI _RTE-SERIES.SAMPLES-U !
0 _RC-FAM _RTE-FE.BYTES-A ! 0 _RC-FAM _RTE-FE.BYTES-U !
_SB-BUILD _SB-VALID 0= _RC-A
_RC-DONE
''', minimum=21)


def test_nested_descriptor_alias_refuses_before_private_scratch_store():
    run(FIXTURE + r'''
_SB-HEADER
31337 _RSHSP-S ! 41414 _RSHSP-P !
_RSHSP-S _SB-S _RSHSP.PRODUCER !
_SB-S RSHSP-VALID? 0= _RC-A _RSHSP-S @ 31337 = _RC-A _RSHSP-P @ 41414 = _RC-A
_SB-HEADER _RSHSP-P _SB-S _RSHSP.SOURCE !
_SB-S RSHSP-VALID? 0= _RC-A _RSHSP-S @ 31337 = _RC-A _RSHSP-P @ 41414 = _RC-A
_SB-HEADER _RSHSP-P _SB-S _RSHSP.SHELL !
_SB-S RSHSP-VALID? 0= _RC-A _RSHSP-S @ 31337 = _RC-A _RSHSP-P @ 41414 = _RC-A
_SB-HEADER 0 _SB-S _RSHSP.PRODUCER !
_SB-S RSHSP-VALID? 0= _RC-A _RSHSP-S @ 31337 = _RC-A
_SB-HEADER _SB-P 1+ _SB-S _RSHSP.PRODUCER !
_SB-S RSHSP-VALID? 0= _RC-A _RSHSP-S @ 31337 = _RC-A
_RC-DONE
''', minimum=13)


def test_pane_geometry_expansion_and_exact_overlap_edges():
    run(FIXTURE + r'''
_SS-BUILD
0 _SS-M SHM-ENTRY _RSHSP-CONTENT-RECT
19 = _RC-A 9 = _RC-A 0= _RC-A 0= _RC-A
0 _SS-M SHM-ENTRY 3 _SS-M SHM-ENTRY SHM-ENTRY-SIZE MOVE
0 _SS-M SHM-ENTRY 3 _SS-M SHM-ENTRY _RSHSP-OVERLAP? _RC-A
19 3 _SS-M SHM-ENTRY SHME.CONTENT-COL !
0 _SS-M SHM-ENTRY 3 _SS-M SHM-ENTRY _RSHSP-OVERLAP? 0= _RC-A
18 3 _SS-M SHM-ENTRY SHME.CONTENT-COL !
0 _SS-M SHM-ENTRY 3 _SS-M SHM-ENTRY _RSHSP-OVERLAP? _RC-A
0 3 _SS-M SHM-ENTRY SHME.CONTENT-COL !
9 3 _SS-M SHM-ENTRY SHME.CONTENT-ROW !
0 _SS-M SHM-ENTRY 3 _SS-M SHM-ENTRY _RSHSP-OVERLAP? 0= _RC-A
8 3 _SS-M SHM-ENTRY SHME.CONTENT-ROW !
0 _SS-M SHM-ENTRY 3 _SS-M SHM-ENTRY _RSHSP-OVERLAP? _RC-A
_RC-DONE
''', minimum=9)


def test_ruha_storage_is_proved_apart_from_all_four_sidecar_spans():
    """One proof of RUHA's spans covers the descriptor, work space and both
    banks: a range touching any of them is refused, a range between them
    is not."""
    run(FIXTURE + r'''
4096 64 0 _RSHSP-SPAN! 8192 128 1 _RSHSP-SPAN!
16384 256 2 _RSHSP-SPAN! 32768 512 3 _RSHSP-SPAN!
4096 1 _RSHSP-APART? 0= _RC-A 8255 2 _RSHSP-APART? 0= _RC-A
16639 1 _RSHSP-APART? 0= _RC-A 33279 1 _RSHSP-APART? 0= _RC-A
1 4095 _RSHSP-APART? _RC-A 4160 4032 _RSHSP-APART? _RC-A
33280 64 _RSHSP-APART? _RC-A
_RC-DONE
''', minimum=7)


def test_sidecar_checks_run_once_per_call_and_the_model_copy_once():
    """Each sidecar span's shape is checked once per call, RUHA's storage
    is proved apart from all four spans in one proof, and the shell's model
    copy is validated once, after the copy, before the builders that skip
    that check. The copy is only read afterwards."""
    import re
    from pathlib import Path

    source = (Path(__file__).resolve().parents[1]
              / "akashic/tui/rich-terminal/shell-screen-producer.f").read_text()

    def word(name):
        match = re.search(rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*$", source)
        assert match is not None, name
        return match.group(0)

    spans = word("_RSHSP-SPANS?")
    assert spans.count("_RUHA-SAFE-PROVE?") == 1 and "['] _RSHSP-APART?" in spans
    assert "_RSHSP-SPAN?" not in spans
    assert "_RUHA-SAFE-PROVE?" not in word("_RSHSP-EXTERNAL?")
    # The live predicate already makes the source's checks of the live
    # owners; the shell asks nothing private of the source.
    external = word("_RSHSP-EXTERNAL?")
    assert "SHSN-LIVE-STORAGE-DISJOINT?" in external and "_SHSN-" not in external
    authority = word("_RSHSP-AUTHORITY?")
    # Only the producer's arena, which the header does not cover, is checked.
    assert "_RSHSP-HEADER?" not in authority
    assert authority.count("_RSHSP-SPAN?") == 1
    assert "_RTHP.ARENA-U @ _RSHSP-SPAN?" in authority
    # Every caller checks the header, or each span, first.
    for caller, first, then in (("RSHSP-VALID?", "_RSHSP-HEADER?", "_RSHSP-AUTHORITY?"),
                                ("_RSHSP-DISPATCH", "CHK-EVERY-FRAME? IF", "_RSHSP-HEADER?"),
                                ("_RSHSP-DISPATCH", "_RSHSP-HEADER?", "_RSHSP-AUTHORITY?"),
                                ("_RSHSP-DISPATCH", "_RSHSP-AUTHORITY?", "_RSHSP-NAMED?"),
                                ("_RSHSP-DISPATCH", "_RSHSP-NAMED?", "_RSHSP-BIND"),
                                ("RSHSP-INIT", "_RSHSP-SPAN?", "_RSHSP-SPANS?")):
        body = word(caller)
        assert body.index(first) < body.index(then), caller
    build = word("_RSHSP-BUILD-BATCH")
    assert (build.index("_RSHSP-COPY _RSHSP-M !") < build.index("SHSN-FROZEN-VALIDATE")
            < build.index("_RSHSP-ALLOCATE-PLAN"))
    plan = word("_RSHSP-ALLOCATE-PLAN")
    for name in ("_RSHPL-BUILD-PROVED", "_RSHMM-BUILD-PROVED"):
        assert source.count(name) == 1 and name in plan, name
    # The copy is only read: passed on as a span, entered, or a field fetched.
    for match in re.finditer(r"_RSHSP-M @ (\S+) (\S+)", source):
        follower, after = match.groups()
        if follower.startswith("SHM."):
            assert after == "@", match.group(0)
        else:
            assert follower in ("_RSHSP-MU", "SHM-ENTRY", "SHM-PROMPT@", "SHM-NOTICE@",
                                "SHM-STATUS@"), match.group(0)
    assert not re.search(r"\bSHME?\.[A-Z-]+ \+?!", source)


def test_the_freeze_takes_the_graph_the_preflight_checked():
    """The batch's graph is checked by the preflight at the end of
    BUILD-BATCH; the freeze measures and copies it as proved. Between the two
    only the DELTA's identity mapping writes the batch, and the frozen bank
    is still checked in full."""
    import re
    from pathlib import Path

    source = (Path(__file__).resolve().parents[1]
              / "akashic/tui/rich-terminal/shell-screen-producer.f").read_text()
    code = "\n".join(line.split("\\", 1)[0] for line in source.splitlines())

    def word(name):
        match = re.search(rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*$", code)
        assert match is not None, name
        return match.group(0)

    build = word("_RSHSP-BUILD-BATCH")
    assert build.rstrip().endswith("RTE-FAMILY-BATCH-PREFLIGHT DUP IF THROW ELSE DROP THEN ;")
    freeze = word("_RSHSP-FREEZE")
    assert "_RSHSP-BATCH @ _RSHFC-MEASURE-PROVED" in freeze
    assert "RSHFC-MEASURE " not in freeze and "_RSHFC-COPY-PROVED" in freeze
    # The finished bank, a proved copy, is checked again only with
    # every-frame checks on, as is the producer's copy of the published model.
    assert freeze.rstrip().endswith(
        "CHK-EVERY-FRAME? IF\n"
        "        _RSHSP-BANK @ _RSHSP-S @ _RSHSP-BANK-VALID? _RSHSP-CHECK\n"
        "    THEN ;"
    )
    assert (
        "CHK-EVERY-FRAME? IF\n"
        "        _RSHSP-M @ _RSHSP-MU @ SHSN-FROZEN-VALIDATE SHSN-S-OK = _RSHSP-CHECK\n"
        "    THEN"
    ) in build
    # Every freeze follows a preflight, with only the mapping between them.
    start = word("_RSHSP-BUILD")
    assert start.index("_RSHSP-BUILD-BATCH") < start.index("_RSHSP-FREEZE")
    delta = word("_RSHSP-BUILD-DELTA")
    between = delta[delta.index("_RSHSP-BUILD-BATCH"):delta.index("_RSHSP-FREEZE")]
    writers = {w for w in re.findall(r"_RSHSP-D-[A-Z-]+", between)}
    assert writers == {"_RSHSP-D-CATALOG", "_RSHSP-D-FAMILIES", "_RSHSP-D-METADATA",
                       "_RSHSP-D-NEXT-OBJECT"}
    assert code.count("_RSHSP-FREEZE") == 3
