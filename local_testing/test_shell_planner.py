"""Native canonical shell planning: exact bands, ownership and atomic bounds."""
from test_field_model import run_field
from test_shell_snapshot import PRELUDE

PLAN = PRELUDE + r'''
CREATE _SP-QS 263 ALLOT CREATE _SP-ES 39 ALLOT
CREATE _SP-RS 1031 ALLOT CREATE _SP-PS 1031 ALLOT CREATE _SP-CS 1607 ALLOT
CREATE _SP-TS 263 ALLOT CREATE _SP-XS 1543 ALLOT CREATE _SP-LS 1031 ALLOT
CREATE _SP-OS 159 ALLOT CREATE _SP-AS 263 ALLOT
: _SP-Q _SP-QS 7 + -8 AND ; : _SP-E _SP-ES 7 + -8 AND ;
: _SP-R _SP-RS 7 + -8 AND ; : _SP-P _SP-PS 7 + -8 AND ;
: _SP-C _SP-CS 7 + -8 AND ; : _SP-T _SP-TS 7 + -8 AND ;
: _SP-X _SP-XS 7 + -8 AND ; : _SP-L _SP-LS 7 + -8 AND ;
: _SP-O _SP-OS 7 + -8 AND ; : _SP-ACT _SP-AS 7 + -8 AND ;
: _SP-CONTROL ( index -- control ) RTE-CONTROL-SIZE * _SP-C + ;
: _SP-CORR ( index -- correlation ) RSHPL-CORRELATION-SIZE * _SP-X + ;
: _SP-CLAIM ( index -- claim ) RSHPL-CLAIM-SIZE * _SP-L + ;
: _SP-REGION ( index -- region ) RTE-INSTRUMENT-REGION-SIZE * _SP-R + ;
: _SP-INIT
    _SS-BUILD 6 2 _SS-M SHM-ENTRY SHME.COL ! 10 _SS-M SHM.END-COL !
    _SS-FREEZE
    _SP-Q RSHPL-REQUEST-CLEAR _SP-E 32 0 FILL 1 _SP-E !
    _SS-F _SS-U @ 77 88 _SP-E 24 3 _SP-Q RSHPL-REQUEST-SOURCE!
    1011 2011 100 500 200 _SP-Q RSHPL-REQUEST-IDENTITY!
    -1 0 1 _SP-Q RSHPL-REQUEST-Z!
    _SP-R 1024 _SP-P 1024 _SP-C 1600 _SP-T 256 _SP-X 1536
    _SP-L 1024 _SP-ACT 256 _SP-O 152 _SP-Q RSHPL-REQUEST-OUTPUT! ;
: _SP-BUILD _SP-Q RSHPL-BUILD _SS-OK ;
: _SP-ZERO? ( a u -- flag )
    0 ?DO DUP I + C@ IF DROP 0 UNLOOP EXIT THEN LOOP DROP -1 ;
: _SP-CLEARED
    _SP-R 1024 _SP-ZERO? _SS-A _SP-P 1024 _SP-ZERO? _SS-A
    _SP-C 1600 _SP-ZERO? _SS-A _SP-T 256 _SP-ZERO? _SS-A
    _SP-X 1536 _SP-ZERO? _SS-A _SP-L 1024 _SP-ZERO? _SS-A
    _SP-ACT 256 _SP-ZERO? _SS-A _SP-O 152 _SP-ZERO? _SS-A ;
: _SP-BAD ( value field -- )
    ! _SP-Q RSHPL-BUILD RSHPL-S-INVALID = _SS-A _SP-CLEARED ;
'''


def run(program, minimum):
    run_field(program, marker="SHELL SNAP", minimum=minimum,
              extra_sources=("tui/rich-terminal/shell-planner.f",))


def test_shell_planner_exact_regions_bands_copied_text_and_provenance():
    run(PLAN + r'''
_SP-INIT _SP-BUILD
_SP-O RSHPL-RESULT.REGIONS @ 3 = _SS-A
_SP-O RSHPL-RESULT.PANES @ 1 = _SS-A
_SP-O RSHPL-RESULT.CONTROLS @ 4 = _SS-A
_SP-O RSHPL-RESULT.TEXT-BYTES @ 13 = _SS-A
_SP-O RSHPL-RESULT.CORRELATIONS @ 5 = _SS-A
_SP-O RSHPL-RESULT.CLAIMS @ 4 = _SS-A
_SP-O RSHPL-RESULT.LAST-REGION @ 102 = _SS-A
_SP-O RSHPL-RESULT.LAST-OBJECT @ 500 = _SS-A
_SP-O RSHPL-RESULT.LAST-CONTROL @ 203 = _SS-A
_SP-O RSHPL-RESULT.TASKBARS @ 2 = _SS-A
_SP-O RSHPL-RESULT.EPOCH @ 1 = _SS-A
_SP-O RSHPL-RESULT.SOURCE-OWNER @ 7 = _SS-A
_SP-O RSHPL-RESULT.SOURCE-GENERATION @ 9 = _SS-A
_SP-O RSHPL-RESULT.DRAW @ 88 = _SS-A
_SP-O RSHPL-RESULT.ATTACHMENT @ 77 = _SS-A
_SP-P _RTE-PANE.ID @ 500 = _SS-A
_SP-P _RTE-PANE.OWNER @ 1011 = _SS-A
_SP-P _RTE-PANE.GENERATION @ 2011 = _SS-A
_SP-P _RTE-PANE.CONTENT-REGION @ 101 = _SS-A
_SP-P _RTE-PANE.REGION @ 100 = _SS-A
_SP-P _RTE-PANE.CONTENT-HEIGHT @ 9 = _SS-A
_SP-P _RTE-PANE.CONTENT-WIDTH @ 19 = _SS-A
_SP-P _RTE-PANE.CONTENT-ROW @ 0= _SS-A
_SP-P _RTE-PANE.CONTENT-COL @ 0= _SS-A
_SP-P _RTE-PANE.VISIBLE @ -1 = _SS-A
_SP-P _RTE-PANE.FOCUSED @ -1 = _SS-A
_SP-P _RTE-PANE.TITLE-A @ _SP-P _RTE-PANE.TITLE-U @ S" Editor" COMPARE 0= _SS-A
1 _SP-REGION _RTE-IR.CLIP-COLS @ 19 = _SS-A
1 _SP-REGION _RTE-IR.CLIP-ROWS @ 9 = _SS-A
1 _SP-REGION _RTE-IR.COLS @ 32 = _SS-A
1 _SP-REGION _RTE-IR.ROWS @ 12 = _SS-A
2 _SP-REGION _RTE-IR.CLIP-Y @ 11 = _SS-A
2 _SP-REGION _RTE-IR.CLIP-COLS @ 10 = _SS-A
0 _SP-CONTROL _RTE-CONTROL.KIND @ RTE-CONTROL-TASKBAR = _SS-A
0 _SP-CONTROL _RTE-CONTROL.COL @ 0= _SS-A
0 _SP-CONTROL _RTE-CONTROL.WIDTH @ 4 = _SS-A
0 _SP-CONTROL _RTE-CONTROL.ROW @ 11 = _SS-A
1 _SP-CONTROL _RTE-CONTROL.KIND @ RTE-CONTROL-TASK = _SS-A
1 _SP-CONTROL _RTE-CONTROL.STATE @ 11 = _SS-A
1 _SP-CONTROL _RTE-CONTROL.PARENT @ 200 = _SS-A
1 _SP-CONTROL _RTE-CONTROL.COL @ 0= _SS-A
2 _SP-CONTROL _RTE-CONTROL.COL @ 6 = _SS-A
2 _SP-CONTROL _RTE-CONTROL.WIDTH @ 4 = _SS-A
3 _SP-CONTROL _RTE-CONTROL.KIND @ RTE-CONTROL-LAUNCHER = _SS-A
3 _SP-CONTROL _RTE-CONTROL.PARENT @ 202 = _SS-A
3 _SP-CONTROL _RTE-CONTROL.COL @ 0= _SS-A
3 _SP-CONTROL _RTE-CONTROL.WIDTH @ 3 = _SS-A
0 _SP-CORR RSHPL-CORRELATION.IDENTITY @ 11 = _SS-A
0 _SP-CORR RSHPL-CORRELATION.OWNER @ 2 = _SS-A
0 _SP-CORR RSHPL-CORRELATION.GENERATION @ 3 = _SS-A
1 _SP-CORR RSHPL-CORRELATION.INDEX @ -1 = _SS-A
3 _SP-CORR RSHPL-CORRELATION.INDEX @ -2 = _SS-A
4 _SP-CORR RSHPL-CORRELATION.ACTION @ 7 = _SS-A
4 _SP-CORR RSHPL-CORRELATION.IDENTITY @ 99 = _SS-A
4 _SP-CORR RSHPL-CORRELATION.ACTION-OFFSET @ _SP-ACT +
4 _SP-CORR RSHPL-CORRELATION.ACTION-BYTES @ S" start" COMPARE 0= _SS-A
0 _SP-CLAIM RSHPL-CLAIM.ROW @ 9 = _SS-A
0 _SP-CLAIM RSHPL-CLAIM.WIDTH @ 20 = _SS-A
1 _SP-CLAIM RSHPL-CLAIM.COL @ 19 = _SS-A
1 _SP-CLAIM RSHPL-CLAIM.HEIGHT @ 9 = _SS-A
2 _SP-CLAIM RSHPL-CLAIM.COL @ 0= _SS-A
2 _SP-CLAIM RSHPL-CLAIM.WIDTH @ 4 = _SS-A
3 _SP-CLAIM RSHPL-CLAIM.COL @ 6 = _SS-A
3 _SP-CLAIM RSHPL-CLAIM.WIDTH @ 4 = _SS-A
\ The canonical separator [4,6) and unmodeled text [10,32) are never claimed.
SHM-K-LAUNCHER _SS-F _SS-U @ RSHPL-BAND-BOUNDS
_SS-OK 4 = _SS-A 1 = _SS-A 6 = _SS-A 11 = _SS-A
0 SHM-K-LAUNCHER _SS-F _SS-U @ RSHPL-GAP-BOUNDS
_SS-OK 1 = _SS-A 1 = _SS-A 9 = _SS-A 11 = _SS-A
1 SHM-K-LAUNCHER _SS-F _SS-U @ RSHPL-GAP-BOUNDS
RSHPL-S-END = _SS-A OR OR OR 0= _SS-A
0 SHM-K-TASK _SS-F _SS-U @ RSHPL-GAP-BOUNDS
RSHPL-S-END = _SS-A OR OR OR 0= _SS-A
\ All neutral display and dispatch action bytes survive source bank reuse.
_SS-F 4096 0 FILL _SS-M 4096 0 FILL
_SP-P _RTE-PANE.TITLE-A @ _SP-P _RTE-PANE.TITLE-U @ S" Editor" COMPARE 0= _SS-A
3 _SP-CONTROL DUP _RTE-CONTROL.LABEL-A @ SWAP _RTE-CONTROL.LABEL-U @
S" Run" COMPARE 0= _SS-A
4 _SP-CORR RSHPL-CORRELATION.ACTION-OFFSET @ _SP-ACT +
4 _SP-CORR RSHPL-CORRELATION.ACTION-BYTES @ S" start" COMPARE 0= _SS-A
    _SS-DONE
''', 85)


def test_shell_planner_general_chrome_strips_unsigned_endpoints_and_exact_banks():
    run(PLAN + r'''
_SP-INIT
1 0 _SS-ENTRY SHME.CONTENT-ROW ! 1 0 _SS-ENTRY SHME.CONTENT-COL !
7 0 _SS-ENTRY SHME.CONTENT-H ! 17 0 _SS-ENTRY SHME.CONTENT-W !
_SP-BUILD
_SP-O RSHPL-RESULT.CLAIMS @ 6 = _SS-A
_SP-O RSHPL-RESULT.PANE-UTF8 @ 6 = _SS-A
_SP-O RSHPL-RESULT.CONTROL-UTF8 @ 7 = _SS-A
_SP-O RSHPL-RESULT.ACTION-BYTES @ 5 = _SS-A
0 _SP-CLAIM RSHPL-CLAIM.ROW @ 0= _SS-A
0 _SP-CLAIM RSHPL-CLAIM.HEIGHT @ 1 = _SS-A
0 _SP-CLAIM RSHPL-CLAIM.WIDTH @ 20 = _SS-A
1 _SP-CLAIM RSHPL-CLAIM.ROW @ 8 = _SS-A
1 _SP-CLAIM RSHPL-CLAIM.HEIGHT @ 2 = _SS-A
1 _SP-CLAIM RSHPL-CLAIM.WIDTH @ 20 = _SS-A
2 _SP-CLAIM RSHPL-CLAIM.ROW @ 1 = _SS-A
2 _SP-CLAIM RSHPL-CLAIM.HEIGHT @ 7 = _SS-A
2 _SP-CLAIM RSHPL-CLAIM.WIDTH @ 1 = _SS-A
3 _SP-CLAIM RSHPL-CLAIM.COL @ 18 = _SS-A
3 _SP-CLAIM RSHPL-CLAIM.HEIGHT @ 7 = _SS-A
3 _SP-CLAIM RSHPL-CLAIM.WIDTH @ 2 = _SS-A
\ Exact endpoint > signed-i32 is legal, while each origin stays representable.
_SP-INIT 2147483649 _SS-F SHM.WIDTH !
2147483647 0 _SS-ENTRY SHME.COL !
2147483647 0 _SS-ENTRY SHME.CONTENT-COL !
2 0 _SS-ENTRY SHME.WIDTH ! 1 0 _SS-ENTRY SHME.CONTENT-W !
_SP-BUILD
_SP-P _RTE-PANE.COL @ 2147483647 = _SS-A
_SP-P _RTE-PANE.WIDTH @ 2 = _SS-A
1 _SP-REGION _RTE-IR.CLIP-X @ 2147483647 = _SS-A
\ A selected taskbar with an unrepresentable signed origin is refused whole.
_SP-INIT 2147483649 _SS-F SHM.HEIGHT !
2147483648 1 _SS-ENTRY SHME.ROW ! 2147483648 2 _SS-ENTRY SHME.ROW !
_SP-Q RSHPL-BUILD RSHPL-S-INVALID = _SS-A _SP-CLEARED
0 _SP-Q _RSHPL-Q.BANDS ! _SP-BUILD
_SP-O RSHPL-RESULT.PANES @ 1 = _SS-A
_SP-O RSHPL-RESULT.CONTROLS @ 0= _SS-A
\ Exact bounded output capacities, with action storage outside display quotas.
_SP-INIT
288 _SP-Q _RSHPL-Q.REGIONS-U ! 184 _SP-Q _RSHPL-Q.PANES-U !
800 _SP-Q _RSHPL-Q.CONTROLS-U ! 13 _SP-Q _RSHPL-Q.TEXT-U !
960 _SP-Q _RSHPL-Q.CORRELATIONS-U ! 256 _SP-Q _RSHPL-Q.CLAIMS-U !
5 _SP-Q _RSHPL-Q.ACTIONS-U ! _SP-BUILD
_SP-O RSHPL-RESULT.TEXT-BYTES @ 13 = _SS-A
4 _SP-Q _RSHPL-Q.ACTIONS-U !
_SP-Q RSHPL-BUILD RSHPL-S-CAPACITY = _SS-A
_SP-O 152 _SP-ZERO? _SS-A _SP-ACT 4 _SP-ZERO? _SS-A
\ A source-authored divider may not extend a semantic band past END-COL.
_SP-INIT 12 _SS-F SHM.DIVIDER-COL !
_SP-Q RSHPL-BUILD RSHPL-S-INVALID = _SS-A _SP-CLEARED
\ A band may never absorb the other source group's label as supposed spacing.
_SP-INIT -1 _SS-F SHM.DIVIDER-COL ! 1 _SP-Q _RSHPL-Q.BANDS !
_SP-Q RSHPL-BUILD RSHPL-S-INVALID = _SS-A _SP-CLEARED
\ Unsafe source bytes refuse all tentative output, without rewriting the source.
_SP-INIT
1 _SS-ENTRY SHME.LABEL-OFF @ _SS-F + 10 SWAP C!
_SP-Q RSHPL-BUILD RSHPL-S-INVALID = _SS-A _SP-CLEARED
1 _SS-ENTRY SHME.LABEL-OFF @ _SS-F + C@ 10 = _SS-A
_SS-DONE
''', 75)


def test_shell_planner_shared_chrome_never_hides_under_admitted_content():
    run(PLAN + r'''
_SP-INIT
4096 2 _SS-M SHM-INIT _SS-A
7 _SS-M SHM.OWNER-ID ! 9 _SS-M SHM.OWNER-GEN ! 2 _SS-M SHM.EPOCH !
32 _SS-M SHM.WIDTH ! 12 _SS-M SHM.HEIGHT !
_SS-M SHM-APPEND
2 OVER SHME.KEY ! 1 OVER SHME.KIND !
10 OVER SHME.HEIGHT ! 20 OVER SHME.WIDTH !
9 OVER SHME.CONTENT-H ! 19 OVER SHME.CONTENT-W !
2 OVER SHME.OWNER-ID ! 3 OVER SHME.OWNER-GEN !
2 OVER SHME.IDENTITY ! 2 SWAP SHME.ACTION !
_SS-M SHM-APPEND
2 OVER SHME.KEY ! 1 OVER SHME.KIND ! 8 OVER SHME.FLAGS !
10 OVER SHME.HEIGHT ! 20 OVER SHME.WIDTH !
10 OVER SHME.CONTENT-H ! 20 OVER SHME.CONTENT-W !
3 OVER SHME.OWNER-ID ! 4 OVER SHME.OWNER-GEN !
-2 OVER SHME.IDENTITY ! -2 SWAP SHME.ACTION !
_SS-M SHM-SEAL _SS-FREEZE _SS-VALID _SS-OK
_SS-U @ _SP-Q _RSHPL-Q.MODEL-U ! 16 _SP-Q _RSHPL-Q.ELIGIBLE-U !
0 _SP-Q _RSHPL-Q.BANDS ! 1 _SP-E 8 + !
\ Distinct ordinary/overlay lifecycle with the same display key is valid
\ source. Its normal chrome cannot be published underneath overlay content.
_SP-Q RSHPL-BUILD RSHPL-S-INVALID = _SS-A _SP-CLEARED
0 _SP-E ! _SP-BUILD
_SP-O RSHPL-RESULT.PANES @ 1 = _SS-A
_SP-O RSHPL-RESULT.CLAIMS @ 0= _SS-A
0 _SP-CORR RSHPL-CORRELATION.IDENTITY @ -2 = _SS-A
0 _SP-CORR RSHPL-CORRELATION.OWNER @ 3 = _SS-A
\ Reverse geometry likewise refuses overlay chrome underneath normal content.
1 _SP-E !
10 0 _SS-ENTRY SHME.CONTENT-H ! 20 0 _SS-ENTRY SHME.CONTENT-W !
9 1 _SS-ENTRY SHME.CONTENT-H ! 19 1 _SS-ENTRY SHME.CONTENT-W !
_SP-Q RSHPL-BUILD RSHPL-S-INVALID = _SS-A _SP-CLEARED
0 _SP-E ! _SP-BUILD
_SP-O RSHPL-RESULT.CLAIMS @ 2 = _SS-A
_SS-DONE
''', 34)


def test_shell_planner_pane_descriptor_publishes_through_real_provider():
    """The native planner's actual bytes must satisfy the real leaf/wire ABI."""
    import struct
    from test_rich_terminal_pane_provider import PaneProvider

    runtime = run_field(PLAN + r'''
_SP-INIT 20 _SS-F SHM.WIDTH ! 2 _SS-F SHM.HEIGHT !
1 0 _SS-ENTRY SHME.HEIGHT ! 1 0 _SS-ENTRY SHME.CONTENT-H !
1 1 _SS-ENTRY SHME.ROW ! 1 2 _SS-ENTRY SHME.ROW !
0 _SP-Q _RSHPL-Q.BANDS !
1 1 100 500 200 _SP-Q RSHPL-REQUEST-IDENTITY! _SP-BUILD _SS-DONE
''', marker="SHELL SNAP", minimum=5,
        extra_sources=("tui/rich-terminal/shell-planner.f",))

    def address(word):
        runtime.execute(word)
        value = runtime.main_context.data.pop()
        assert runtime.main_context.data.snapshot() == ()
        return value

    pane = list(struct.unpack("<23Q", runtime.memory.read_bytes(address("_SP-P"), 184)))
    regions = runtime.memory.read_bytes(address("_SP-R"), 192)
    title = runtime.memory.read_bytes(pane[20], pane[21])
    h = PaneProvider("native")
    try:
        assert h.call("RTAPT-RICH-BEGIN", h.constant("PT-RET-REPLACE-START"), h.engine)[0] == (0,)
        for offset in (0, 96):
            region = list(struct.unpack_from("<12Q", regions, offset))
            if region[9] >= 1 << 63:
                region[9] -= 1 << 64
            assert h.call("RTAPT-REGION-DEFINE", 1, 1, *region[:11], h.engine)[0] == (0,)
        pane[20] = h.allocate(title)
        record = h.allocate(struct.pack("<23Q", *pane))
        assert h.call("RTAPT-PANE-DEFINE", record, h.engine)[0] == (0,)
        h.publish()
        actual = h.installed().objects[500]
        assert actual.body.title == "Editor"
        assert actual.body.focused
        assert actual.body.content_region_id == 101
        assert actual.body.content_bounds.cell_cols == 19
        assert actual.body.content_bounds.cell_rows == 1
        assert h.installed().usage.utf8_bytes == 6
    finally:
        h.close()






def test_shell_planner_taskbar_records_publish_exact_slots_without_action_utf8():
    import struct
    from test_rich_terminal_taskbar_provider import TaskbarProvider

    runtime = run_field(PLAN + r'''
_SP-INIT 20 _SS-F SHM.WIDTH ! 2 _SS-F SHM.HEIGHT !
1 0 _SS-ENTRY SHME.HEIGHT ! 1 0 _SS-ENTRY SHME.CONTENT-H !
1 1 _SS-ENTRY SHME.ROW ! 1 2 _SS-ENTRY SHME.ROW !
0 _SP-E !
1 1 100 500 200 _SP-Q RSHPL-REQUEST-IDENTITY! _SP-BUILD _SS-DONE
''', marker="SHELL SNAP", minimum=5,
        extra_sources=("tui/rich-terminal/shell-planner.f",))

    def address(word):
        runtime.execute(word)
        value = runtime.main_context.data.pop()
        assert runtime.main_context.data.snapshot() == ()
        return value

    controls = runtime.memory.read_bytes(address("_SP-C"), 800)
    region = struct.unpack("<12Q", runtime.memory.read_bytes(address("_SP-R"), 96))
    h = TaskbarProvider("native")
    try:
        assert h.call("RTAPT-RICH-BEGIN", h.constant("PT-RET-REPLACE-START"), h.engine)[0] == (0,)
        assert h.call("RTAPT-REGION-DEFINE", 1, 1, *region[:11], h.engine)[0] == (0,)
        for offset in range(0, 800, 200):
            control = list(struct.unpack_from("<25Q", controls, offset))
            if control[16]:
                label = runtime.memory.read_bytes(control[15], control[16])
                control[15] = h.allocate(label)
            assert h.call("RTAPT-CONTROL-DEFINE", *control, h.engine)[0] == (0,)
        h.publish()
        actual = h.installed()
        assert [actual.controls[i].kind.value for i in range(200, 204)] == [10, 11, 10, 12]
        assert actual.controls[200].bounds.cell_cols == 4
        assert actual.controls[202].bounds.cell_x == 6
        assert actual.controls[202].bounds.cell_cols == 4
        assert actual.controls[203].parent_control_id == 202
        assert actual.controls[203].bounds.cell_x == 0
        assert actual.controls[203].bounds.cell_cols == 3
        assert actual.controls[201].label == "Edit"
        assert actual.controls[203].label == "Run"
        assert actual.usage.utf8_bytes == 7
    finally:
        h.close()

def test_shell_planner_atomic_capacity_aliasing_omission_and_signed_overlay():
    run(PLAN + r'''
_SP-INIT _SP-BUILD
1 _SP-Q _RSHPL-Q.RESERVED _SP-BAD
_SP-INIT 2 _SP-E ! _SP-Q RSHPL-BUILD RSHPL-S-INVALID = _SS-A _SP-CLEARED
_SP-INIT 1 _SP-E 8 + ! _SP-Q RSHPL-BUILD RSHPL-S-INVALID = _SS-A _SP-CLEARED
_SP-INIT 12 _SP-Q _RSHPL-Q.TEXT-U !
_SP-Q RSHPL-BUILD RSHPL-S-CAPACITY = _SS-A
_SP-T 12 _SP-ZERO? _SS-A _SP-ACT 256 _SP-ZERO? _SS-A _SP-O 152 _SP-ZERO? _SS-A
_SP-INIT -1 _SP-Q _RSHPL-Q.FIRST-CONTROL !
_SP-Q RSHPL-BUILD RSHPL-S-CAPACITY = _SS-A _SP-CLEARED
\ Untrusted overlapping output spans are rejected without touching outputs.
_SP-INIT _SP-R 1024 90 FILL _SP-P 1024 91 FILL
_SP-R _SP-Q _RSHPL-Q.PANES-A !
_SP-Q RSHPL-BUILD RSHPL-S-INVALID = _SS-A
_SP-R C@ 90 = _SS-A _SP-P C@ 91 = _SS-A _SS-VALID _SS-OK
_SP-INIT _SS-F _SP-Q _RSHPL-Q.TEXT-A !
_SP-Q RSHPL-BUILD RSHPL-S-INVALID = _SS-A _SS-VALID _SS-OK
_SP-INIT _SP-Q _SP-Q _RSHPL-Q.RESULT-A !
_SP-Q RSHPL-BUILD RSHPL-S-INVALID = _SS-A
_SP-INIT _RSHPL-SPANS _SP-Q _RSHPL-Q.REGIONS-A !
_SP-Q RSHPL-BUILD RSHPL-S-INVALID = _SS-A
_SP-INIT -8 _SP-Q _RSHPL-Q.REGIONS-A !
_SP-Q RSHPL-BUILD RSHPL-S-INVALID = _SS-A
\ Independent feature/provenance omission consumes no IDs for absent roots.
_SP-INIT 0 _SP-E ! 2 _SP-Q _RSHPL-Q.BANDS ! _SP-BUILD
_SP-O RSHPL-RESULT.REGIONS @ 1 = _SS-A
_SP-O RSHPL-RESULT.PANES @ 0= _SS-A
_SP-O RSHPL-RESULT.CONTROLS @ 2 = _SS-A
_SP-O RSHPL-RESULT.LAST-OBJECT @ 0= _SS-A
_SP-O RSHPL-RESULT.LAST-CONTROL @ 201 = _SS-A
0 _SP-CONTROL _RTE-CONTROL.COL @ 6 = _SS-A
_SP-INIT 0 _SP-Q _RSHPL-Q.BANDS ! _SP-BUILD
_SP-O RSHPL-RESULT.REGIONS @ 2 = _SS-A
_SP-O RSHPL-RESULT.CONTROLS @ 0= _SS-A
_SP-O RSHPL-RESULT.LAST-CONTROL @ 0= _SS-A
_SP-INIT 0 _SP-E ! 0 _SP-Q _RSHPL-Q.BANDS ! _SP-BUILD
_SP-O RSHPL-RESULT.REGIONS @ 0= _SS-A
_SP-O RSHPL-RESULT.TEXT-BYTES @ 0= _SS-A
_SP-O RSHPL-RESULT.LAST-REGION @ 0= _SS-A
\ Modal backgrounds stay visually present but taskbar input is disabled.
_SP-INIT 2 _SS-F SHM.FLAGS ! _SP-BUILD
0 _SP-CONTROL _RTE-CONTROL.STATE @ 1 = _SS-A
2 _SP-CONTROL _RTE-CONTROL.STATE @ 1 = _SS-A
\ Signed overlay identity is copied intact; zero chrome has no false claim.
_SP-INIT
9 0 _SS-ENTRY SHME.FLAGS ! -11 0 _SS-ENTRY SHME.IDENTITY !
-11 0 _SS-ENTRY SHME.ACTION !
19 0 _SS-ENTRY SHME.WIDTH ! 9 0 _SS-ENTRY SHME.HEIGHT !
_SP-BUILD
0 _SP-CORR RSHPL-CORRELATION.KEY @ 11 = _SS-A
0 _SP-CORR RSHPL-CORRELATION.IDENTITY @ -11 = _SS-A
1 _SP-REGION _RTE-IR.Z @ 1 = _SS-A
_SP-O RSHPL-RESULT.CLAIMS @ 2 = _SS-A
_SS-DONE
''', 85)
