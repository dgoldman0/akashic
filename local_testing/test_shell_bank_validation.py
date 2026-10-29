"""Owned part parsing refuses escaped pointers and corrupt ACK frontiers."""
from test_field_model import run_field
from test_rich_region_catalog import PRELUDE as CATALOG
from test_shell_screen_producer import STAGED, staged_run
from test_shell_snapshot import PRELUDE as SOURCE

FIXTURE = CATALOG + SOURCE + r'''
CREATE _SB-SS 247 ALLOT
CREATE _SB-PS RTHP-SIZE 7 + ALLOT CREATE _SB-HS SHSN-SIZE 7 + ALLOT
CREATE _SB-XS RTE-SHELL-FACADE-SIZE 7 + ALLOT
: _SB-S _SB-SS 7 + -8 AND ;
: _SB-P _SB-PS 7 + -8 AND ; : _SB-H _SB-HS 7 + -8 AND ; : _SB-X _SB-XS 7 + -8 AND ;
: _SB-HEADER
    _SB-S 240 0 FILL
    _RSHSP-MAGIC _SB-S _RSHSP.MAGIC ! RSHSP-SIZE _SB-S _RSHSP.SIZE ! _SB-S _SB-S _RSHSP.SELF !
    _SB-P _SB-S _RSHSP.PRODUCER ! _SB-H _SB-S _RSHSP.SOURCE ! _SB-X _SB-S _RSHSP.SHELL ! ;
'''


def run(program, minimum=1):
    run_field(program, marker="CATALOG", minimum=minimum,
              extra_sources=("tui/rich-terminal/shell-screen-producer.f",))


def test_a_built_part_is_whole_and_its_corruptions_are_refused():
    """The shell builds its part where it is kept.  The part is whole: each
    span inside it, past its header, or in the bank that names it, apart from
    every other, its model and batch whole, and its catalog, batch and
    frontiers those of the frame the bank records.  It need not be dense.
    Each corruption below breaks one of those, and the check refuses it."""
    staged_run(STAGED + r'''
: _SB-T ( -- bank ) _SX-P _RTHP.TARGET-PENDING @ ;
: _SB-B ( -- part ) _SB-T _RTHP-XBLOCK@ DROP ;
: _SB-U ( -- u ) _SB-T _RTHP-XBLOCK@ NIP ;
: _SB-VALID ( -- flag ) _SB-T _RSHSP-PART-VALID? ;
: _SB-BAD ( value field -- ) DUP @ >R DUP >R ! _SB-VALID 0= _SS-A R> R> SWAP ! ;
: _SB-BATCH ( -- batch ) _SB-B DUP RSHSP-PART.BATCH @ + ;
: _SB-FIRST ( -- family ) _SB-BATCH _RTE-FB.FAMILIES-A @ ;
_SX-SETUP _SX-PACK-PREPARE _SS-OK
_SB-VALID _SS-A
\ The frontiers.
0 _SB-B RSHSP-PART.NEXT-REGION _SB-BAD
_SB-B RSHSP-PART.NEXT-REGION @ 1+ _SB-B RSHSP-PART.NEXT-REGION _SB-BAD
0 _SB-B RSHSP-PART.NEXT-OBJECT _SB-BAD
_SB-B RSHSP-PART.NEXT-OBJECT @ 1+ _SB-B RSHSP-PART.NEXT-OBJECT _SB-BAD
\ A prompt identity for a model without Desk's prompt.
_SB-B DUP RSHSP-PART.MODEL @ + SHM.PROMPT-U @ 0= _SS-A
101 _SB-B RSHSP-PART.PROMPT _SB-BAD
\ A part that ends before its last span is refused; one with bytes past
\ its last span is whole.
_SB-U 8 - _SB-T _RTHP-TB.XBLOCK-BYTES _SB-BAD
_SB-U 8 + _SB-T _RTHP-TB.XBLOCK-BYTES ! _SB-VALID _SS-A
_SB-U 8 - _SB-T _RTHP-TB.XBLOCK-BYTES !
_SB-B RSHSP-PART.BATCH @ 8 + _SB-B RSHSP-PART.BATCH _SB-BAD
_SB-B RSHSP-PART.MODEL @ 8 + _SB-B RSHSP-PART.MODEL _SB-BAD
_SB-B DUP RSHSP-PART.MODEL @ + SHM.WIDTH @ 1+
    _SB-B DUP RSHSP-PART.MODEL @ + SHM.WIDTH _SB-BAD
\ The part's model, correlations, actions and membership lie apart from
\ one another and from the batch: correlations on the batch record, or a
\ membership on the model, are refused.
VARIABLE _SB-SAVE VARIABLE _SB-SAVE-U
: _SB-META-SAVE ( field -- ) DUP @ _SB-SAVE ! 8 + @ _SB-SAVE-U ! ;
: _SB-META-BACK ( field -- ) _SB-SAVE @ OVER ! _SB-SAVE-U @ SWAP 8 + ! ;
: _SB-META-ON ( offset bytes field -- ) TUCK 8 + ! ! _SB-VALID 0= _SS-A ;
_SB-B RSHSP-PART.CORRELATIONS _SB-META-SAVE
_SB-B RSHSP-PART.BATCH @ RSHPL-CORRELATION-SIZE _SB-B RSHSP-PART.CORRELATIONS _SB-META-ON
_SB-B RSHSP-PART.CORRELATIONS _SB-META-BACK
_SB-B RSHSP-PART.MEMBERSHIP _SB-META-SAVE
_SB-B RSHSP-PART.MODEL @ RSHMM-ENTRY-SIZE _SB-B RSHSP-PART.MEMBERSHIP _SB-META-ON
_SB-B RSHSP-PART.MEMBERSHIP _SB-META-BACK
_SB-VALID _SS-A
\ The bank names the part at the start of an extension block, and records
\ the frame the part's catalog and batch describe.
_SB-B 8 + _SB-T _RTHP-TB.XBLOCK _SB-BAD
_SB-T _RTHP-TB.DRAW @ 1+ _SB-T _RTHP-TB.DRAW _SB-BAD
_SB-T _RTHP-TB.OWNER @ 1+ _SB-T _RTHP-TB.OWNER _SB-BAD
_SB-T _RTHP-TB.GENERATION @ 1+ _SB-T _RTHP-TB.GENERATION _SB-BAD
\ The batch's spans lie in the part, past its header, or in the bank.
_SX-CI _SB-BATCH _RTE-FB.CATALOG-A _SB-BAD
_SB-B RSHSP-PART-HEADER-SIZE + _SB-BATCH _RTE-FB.CATALOG-A _SB-BAD
_SX-CI _SB-BATCH _RTE-FB.FAMILIES-A _SB-BAD
_SB-B _SB-BATCH _RTE-FB.FAMILIES-A _SB-BAD
_SX-CI _SB-FIRST _RTE-FE.PLAN-A _SB-BAD
_SB-FIRST RTE-FAMILY-ITEMS@ DROP _RTE-CONTROL.ID
    0x8000000000000000 SWAP _SB-BAD
_SB-VALID _SS-A
\ A part whose catalog holds no region is refused before a last-region
\ pointer is computed below its regions.
0 _SB-BATCH _RTE-FB.CATALOG-A @ _RTE-RC.REGIONS-U _SB-BAD
_SB-VALID _SS-A
_SS-DONE
''', minimum=30)


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
    """One proof of RUHA's spans covers the shell's record, its work space
    and the screen producer's two extension blocks, which the shell builds
    its parts in: a range touching any of them is refused, a range between
    them is not."""
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
    # Only the producer's arena, scratch block and extension blocks, which
    # the header does not cover, are checked.
    assert "_RSHSP-HEADER?" not in authority
    assert authority.count("_RSHSP-SPAN?") == 1
    assert "_RTHP.ARENA-U @ _RSHSP-SPAN?" in authority
    assert authority.index("_RSHSP-BLOCK-SPANS?") < authority.index("_RSHSP-SPANS? ;")
    assert word("_RSHSP-BLOCK-SPANS?").count("_RSHSP-SPAN?") == 3
    # Every caller checks the header, or each span, first.  The dispatch
    # checks the records' names in both modes, then, with every-frame checks
    # on, the header and the storage, and otherwise binds them.
    for caller, first, then in (("RSHSP-VALID?", "_RSHSP-HEADER?", "_RSHSP-AUTHORITY?"),
                                ("_RSHSP-DISPATCH", "_RSHSP-NAMED?", "CHK-EVERY-FRAME? IF"),
                                ("_RSHSP-DISPATCH", "CHK-EVERY-FRAME? IF", "_RSHSP-HEADER?"),
                                ("_RSHSP-DISPATCH", "_RSHSP-HEADER?", "_RSHSP-AUTHORITY?"),
                                ("_RSHSP-DISPATCH", "_RSHSP-AUTHORITY?", "_RSHSP-BIND"),
                                ("RSHSP-INIT", "_RSHSP-SPAN?", "_RSHSP-SPANS?")):
        body = word(caller)
        assert body.index(first) < body.index(then), caller
    build = word("_RSHSP-BUILD-BATCH")
    assert (build.index("_RSHSP-PCOPY _RSHSP-M !") < build.index("SHSN-FROZEN-VALIDATE")
            < build.index("_RSHSP-ALLOCATE-PLAN"))
    plan = word("_RSHSP-ALLOCATE-PLAN")
    for name in ("_RSHPL-BUILD-PROVED", "_RSHMM-BUILD-PROVED"):
        assert source.count(name) == 1 and name in plan, name
    # The copy is only read: passed on as a span, entered, a field fetched,
    # or its place in the part taken.
    for match in re.finditer(r"_RSHSP-M @ (\S+) (\S+)", source):
        follower, after = match.groups()
        if follower.startswith("SHM."):
            assert after == "@", match.group(0)
        else:
            assert follower in ("_RSHSP-MU", "SHM-ENTRY", "SHM-PROMPT@", "SHM-NOTICE@",
                                "SHM-STATUS@", "_RSHSP-PART-OFFSET"), match.group(0)
    assert not re.search(r"\bSHME?\.[A-Z-]+ \+?!", source)


def test_the_part_is_built_where_it_is_kept_and_finished_after_the_preflight():
    """The shell takes the frame's record from the free extension block as
    it builds it, so nothing copies the batch afterwards.  The batch's graph
    is checked by the preflight at the end of BUILD-BATCH, once the family
    vector, which grows in the scratch block, lies in the part.  Between the
    preflight and FINISH only the DELTA's identity mapping writes the batch,
    and its glyph mapping writes where the runs lie; the finished part is
    still checked in full once the pending bank names it."""
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
    assert build.rstrip().endswith(
        "_RTE-FAMILY-BATCH-PREFLIGHT-PROVED DUP IF THROW ELSE DROP THEN ;")
    assert build.index("_RSHSP-SCRATCH! _RSHSP-PART-START") < build.index(
        "_RSHSP-PCOPY _RSHSP-M !")
    vector = ("_RSHSP-FAMILIES @ _RSHSP-FAMILY-N @ RTE-FAMILY-ENTRY-SIZE * "
              "_RSHSP-PCOPY _RSHSP-FAMILIES !")
    assert build.index(vector) < build.index("_RSHSP-FAMILIES @ _RSHSP-BATCH @ _RTE-FB.FAMILIES-A !")
    assert "RSHFC" not in code and "_RSHSP-FREEZE" not in code
    # The DELTA's glyph mapping takes no storage.
    glyphs = word("_RSHSP-D-GLYPHS")
    assert "TAKE" not in glyphs and "COPY" not in glyphs
    finish = word("_RSHSP-FINISH")
    # The finished part becomes the pending bank's, and is checked again only
    # with every-frame checks on, as is the producer's copy of the published
    # model; a failure names what it found damaged (check-mode.f).
    assert finish.rstrip().endswith(
        "    _RSHSP-PART @ _RSHSP-PCURSOR @ _RSHSP-PART-OFFSET _RSHSP-P @ _RTHP-XBLOCK!\n"
        "    CHK-EVERY-FRAME? IF\n"
        "        _RSHSP-P @ _RTHP.TARGET-PENDING @ _RSHSP-PART-VALID?\n"
        "            _RSHSP-PARTS-DAMAGED CHK-NAME _RSHSP-CHECK\n"
        "    THEN ;"
    )
    assert "_RSHSP-BATCH @ _RSHSP-PART-OFFSET _RSHSP-PART @ RSHSP-PART.BATCH !" in finish
    assert (
        "CHK-EVERY-FRAME? IF\n"
        "        _RSHSP-M @ _RSHSP-MU @ SHSN-FROZEN-VALIDATE SHSN-S-OK =\n"
        "            _RSHSP-MODEL-DAMAGED CHK-NAME _RSHSP-CHECK\n"
        "    THEN"
    ) in build
    # Every finish follows a preflight, with only the mapping between them.
    start = word("_RSHSP-BUILD")
    assert start.index("_RSHSP-BUILD-BATCH") < start.index("_RSHSP-FINISH")
    assert "0 _RSHSP-DBATCH !" in start
    delta = word("_RSHSP-BUILD-DELTA")
    between = delta[delta.index("_RSHSP-BUILD-BATCH"):delta.index("_RSHSP-FINISH")]
    writers = {w for w in re.findall(r"_RSHSP-D-[A-Z-]+", between)}
    assert writers == {"_RSHSP-D-CATALOG", "_RSHSP-D-FAMILIES", "_RSHSP-D-METADATA",
                       "_RSHSP-D-NEXT-OBJECT"}
    assert code.count("_RSHSP-FINISH") == 3
    # A DELTA copies the runs of rows no draw touched, except in safe mode,
    # where every row is planned.
    assert delta.index("CHK-SAFE? 0= _RSHSP-REUSE !") < delta.index(
        "_RSHSP-BUILD-BATCH") < delta.index("0 _RSHSP-REUSE !")
    assert code.count("_RSHSP-REUSE !") == 3
