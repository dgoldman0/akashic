"""FIELD owns independent RUHA banks through capture, reuse and fallback."""

import re

from status_snapshot_runtime import run_status_forth
from test_rich_terminal_status_adapter import _status_adapter_program


FIELD_FIXTURE = r'''
CREATE _FA-DESCRIPTORS-S 256 7 + ALLOT CREATE _FA-NATIVE-S 1024 7 + ALLOT
CREATE _FA-MODEL-S 512 7 + ALLOT CREATE _FA-B-S UFLD-BUILDER-SIZE 7 + ALLOT
CREATE _FA-PANEL-S _WDG-HDR-SIZE 7 + ALLOT
_FA-DESCRIPTORS-S 7 + -8 AND CONSTANT _FA-DESCRIPTORS
_FA-NATIVE-S 7 + -8 AND CONSTANT _FA-NATIVE
_FA-MODEL-S 7 + -8 AND CONSTANT _FA-MODEL
_FA-B-S 7 + -8 AND CONSTANT _FA-B
_FA-PANEL-S 7 + -8 AND CONSTANT _FA-PANEL
VARIABLE _FA-U VARIABLE _FA-PREV VARIABLE _FA-MOUNT VARIABLE _FA-RGN VARIABLE _FA-FRGN
VARIABLE _FA-FIELD VARIABLE _FA-SC VARIABLE _FA-REV VARIABLE _FA-VALUE
: _FA-GEOM ( row col h w elem -- )
    _UTUI-SIDECAR _FA-SC ! _FA-SC @ _UTUI-SC-W!
    _FA-SC @ _UTUI-SC-H! _FA-SC @ _UTUI-SC-COL! _FA-SC @ _UTUI-SC-ROW! ;
: _FA-MODEL-INIT
    _FA-MODEL 512 _FA-B UFLD-BUILDER-INIT 0= _RA-ASSERT
    992 1 _FA-REV @ 12 2 3 0 _FA-B UFLD-BEGIN 0= _RA-ASSERT
    0 0 1 6 1 3 1 8 _FA-B UFLD-SLOTS 0= _RA-ASSERT
    S" Level" _FA-B UFLD-LABEL 0= _RA-ASSERT
    _FA-VALUE @ -200 200 10 _FA-B UFLD-INTEGER 0= _RA-ASSERT
    _FA-B UFLD-FINISH 0= _RA-ASSERT _FA-U ! ;
: _FA-DRAW DROP _FA-FIELD @ _FA-RGN @ WDG-DRAW-IN ;
: _FA-HANDLE 2DROP 0 ;
: _FA-PAINT UTUI-PAINT ;
: _FA-PAINT-OBSERVED ['] _FA-PAINT UTUI-DRAW-OBSERVE 0= _RA-ASSERT ;
: _FA-PAINT UTUI-PAINT ;
: _FA-OBSERVED-PAINT ['] _FA-PAINT UTUI-DRAW-OBSERVE 0= _RA-ASSERT ;
: _FA-INSTALL
    S" field" UTUI-BY-ID _FA-MOUNT ! 4 0 3 20 _FA-MOUNT @ _FA-GEOM
    _RA-RGN @ 4 0 3 20 RGN-SUB _FA-RGN !
    _FA-RGN @ 0 1 2 12 RGN-SUB _FA-FRGN !
    21 _FA-REV ! 105 _FA-VALUE ! _FA-MODEL-INIT
    _FA-FRGN @ FLD-NEW _FA-FIELD !
    _FA-MODEL _FA-U @ _FA-FIELD @ FLD-BIND 0= _RA-ASSERT
    _FA-PANEL WDG-T-CANVAS _FA-RGN @ ['] _FA-DRAW ['] _FA-HANDLE WDG-INIT
    _FA-PANEL _FA-MOUNT @ UTUI-WIDGET-SET ;
: _FA-FIRST
    _RA-SNAP @ RUHA-SNAPSHOT-FIELDS-DESCRIPTORS@ DROP
    _RA-DIR-A @ RUHA-DOCUMENT-FIELDS-DESCRIPTOR-OFFSET@ +
    _RA-SNAP @ RUHA-SNAPSHOT-FIELDS-NATIVE@ DROP
    _RA-DIR-A @ RUHA-DOCUMENT-FIELDS-NATIVE-OFFSET@ + UFLSN-DESCRIPTOR-NATIVE DROP ;
: _FA-UPDATE 22 _FA-REV ! -121 _FA-VALUE ! _FA-MODEL-INIT
    _FA-MODEL _FA-U @ _FA-FIELD @ FLD-BIND 0= _RA-ASSERT _FA-MOUNT @ UIDL-DIRTY! ;
'''.splitlines()


def _field_adapter_program():
    lines = _status_adapter_program()
    at = lines.index("0 _RA-FAILS ! 0 _RA-CHECKS ! DEPTH _RA-DEPTH !")
    lines[at:at] = FIELD_FIXTURE
    lines = [line.replace("0 0 0 0 _RA-ADAPTER RUHA-INIT RUHA-S-OK", "_FA-DESCRIPTORS 256 _FA-NATIVE 1024 _RA-ADAPTER RUHA-INIT RUHA-S-OK")
             .replace("</status></uidl>", "</status><region id=field/></uidl>") for line in lines]
    at = lines.index("UTUI-PAINT UTUI-DRAW-COMPLETE _RA-STACK")
    lines.insert(at, "_FA-INSTALL")
    at = lines.index("1 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT")

    at = lines.index("2 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT")
    lines[at:at] = [
        "_RA-SNAP @ RUHA-SNAPSHOT-FIELDS-COUNT@ 1 = _RA-ASSERT",
        "_RA-DIR-A @ RUHA-DOCUMENT-FIELDS-DESCRIPTOR-BYTES@ 128 = _RA-ASSERT",
        "_RA-DIR-A @ RUHA-DOCUMENT-FIELDS-NATIVE-BYTES@ 200 = _RA-ASSERT",
        "_FA-FIRST DUP _FA-PREV ! UFLD-REVISION@ 21 = _RA-ASSERT",
        "_FA-FIRST UFLD-KEY@ 992 = _RA-ASSERT",
        "_FA-FIRST UFLD-VALUE@ 105 = _RA-ASSERT",
    ]
    at = lines.index('S" aggregate beta" _RA-TEXTAREA @ TXTA-SET-TEXT')
    lines[at:at] = [
        "_RA-SNAP @ RUHA-SNAPSHOT-FIELDS-COUNT@ 1 = _RA-ASSERT",
        "_FA-FIRST DUP _FA-PREV @ <> _RA-ASSERT 200 _FA-PREV @ 200 COMPARE 0= _RA-ASSERT",
        "_FA-UPDATE",
        "_FA-FIRST UFLD-VALUE@ 105 = _RA-ASSERT",
    ]
    at = lines.index(": _RA-OVERLAY RGN-ROOT 35 0 0 DRW-CHAR ; ' _RA-OVERLAY DRW-OVERLAY")
    lines[at:at] = ["_FA-FIRST UFLD-VALUE@ -121 = _RA-ASSERT", "_FA-FIRST UFLD-REVISION@ 22 = _RA-ASSERT"]
    at = lines.index("_RA-SNAP @ RUHA-SNAPSHOT-COLLECTION-COUNT@ 0= _RA-ASSERT")
    lines.insert(at, "_RA-SNAP @ RUHA-SNAPSHOT-FIELDS-COUNT@ 0= _RA-ASSERT")
    at = next(i for i, line in enumerate(lines) if 'RUHA CONSTRUCTOR PASS' in line)
    lines[at:at] = ["_RA-SNAP @ RUHA-SNAPSHOT-FIELDS-COUNT@ 1 = _RA-ASSERT",
                    "_FA-FIRST UFLD-VALUE@ -121 = _RA-ASSERT", "_RA-STACK"]
    return [line.replace("UTUI-PAINT UTUI-DRAW-COMPLETE", "_FA-OBSERVED-PAINT UTUI-DRAW-COMPLETE") for line in lines]


def test_field_separate_banks_reuse_revision_and_overlay_fallback():
    output = run_status_forth(_field_adapter_program())
    summary = re.search(r"RUHA CONSTRUCTOR PASS\s+(\d+)\s+0", output)
    assert summary, output[-18000:]
    assert int(summary.group(1)) >= 90


def test_field_short_bank_falls_back_all_families_and_retries():
    lines = _field_adapter_program()
    at = lines.index("1 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT")
    lines = [line.replace("_FA-NATIVE 1024 _RA-ADAPTER RUHA-INIT", "_FA-NATIVE 384 _RA-ADAPTER RUHA-INIT") for line in lines[:at+1]]
    lines += [
        "_RA-SNAP @ RUHA-SNAPSHOT-DOCUMENT-COUNT@ 1 = _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-FIELDS-COUNT@ 0= _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-STATUS-FIELDS-COUNT@ 0= _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-COLLECTION-COUNT@ 0= _RA-ASSERT",
        "_RA-RECORDS _RUHA-RECORD-DIRTY? _RA-ASSERT",
        "4 1 SCR-GET CELL-CP@ 76 = _RA-ASSERT",
        "2 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-FIELDS-COUNT@ 0= _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-CONTENT-EPOCH@ 1 = _RA-ASSERT",
        # Unbinding the unsupported root lets co-resident families publish.
        "_FA-FIELD @ FLD-UNBIND _FA-MOUNT @ UIDL-DIRTY! _FA-OBSERVED-PAINT UTUI-DRAW-COMPLETE",
        "3 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-FIELDS-COUNT@ 0= _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-STATUS-FIELDS-COUNT@ 1 = _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-COLLECTION-COUNT@ 1 = _RA-ASSERT",
        "_RA-RECORDS _RUHA-RECORD-DIRTY? 0= _RA-ASSERT _RA-STACK",
        '_RA-FAILS @ 0= IF ." FIELD CAPACITY PASS " ELSE ." FIELD CAPACITY FAIL " THEN _RA-CHECKS @ . _RA-FAILS @ . CR',
    ]
    output = run_status_forth(lines)
    assert re.search(r"FIELD CAPACITY PASS\s+\d+\s+0", output), output[-18000:]


def test_field_prior_corruption_recaptures_and_constructor_alias_refuses_before_writes():
    lines = _field_adapter_program()
    at = lines.index("2 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT")
    lines = lines[:at]
    lines += [
        # Invalidating frozen constraints cannot contaminate the live model.
        "-201 _FA-FIRST UFLD-MAXIMUM-OFFSET + !",
        "_FA-MODEL UFLD-MAXIMUM@ 200 = _RA-ASSERT",
        "2 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-CONTENT-EPOCH@ 2 = _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-FIELDS-COUNT@ 1 = _RA-ASSERT",
        "_FA-FIRST UFLD-MAXIMUM@ 200 = _RA-ASSERT",
        "_FA-FIRST UFLD-VALUE@ 105 = _RA-ASSERT",
        # The constructor's full seventeen-span proof protects old ownership.
        "_RA-INIT-ARGS _RA-SF-DESCRIPTORS 256 _RA-SF-NATIVE 256",
        "_RA-SF-DESCRIPTORS 256 _FA-NATIVE 1024 _RA-ADAPTER RUHA-INIT",
        "RUHA-S-INVALID = _RA-ASSERT",
        "_RA-ADAPTER RUHA-VALID? _RA-ASSERT",
        "_RA-ADAPTER _RUHA-A.SNAP-FIELD-DESCRIPTORS-A @ _FA-DESCRIPTORS = _RA-ASSERT",
        "_RA-ADAPTER _RUHA-A.GENERATION @ 2 = _RA-ASSERT",
        "_FA-FIRST UFLD-VALUE@ 105 = _RA-ASSERT _RA-STACK",
        '_RA-FAILS @ 0= IF ." FIELD PRIOR PASS " ELSE ." FIELD PRIOR FAIL " THEN _RA-CHECKS @ . _RA-FAILS @ . CR',
    ]
    output = run_status_forth(lines)
    assert re.search(r"FIELD PRIOR PASS\s+\d+\s+0", output), output[-18000:]
