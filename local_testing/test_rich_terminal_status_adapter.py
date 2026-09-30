"""Execute independent status banks through the actual RUHA capture/reuse path."""

import re

from test_uidl_collection_snapshot import _ruha_constructor_program
from status_snapshot_runtime import run_status_forth as _run_forth


def _status_adapter_program():
    lines = _ruha_constructor_program()
    at = lines.index("0 _RA-FAILS ! 0 _RA-CHECKS ! DEPTH _RA-DEPTH !")
    lines[at:at] = [
        "CREATE _RA-SF-DESCRIPTORS-MEM 2 USFSN-DESCRIPTOR-SIZE * 7 + ALLOT",
        "CREATE _RA-SF-NATIVE-MEM 256 7 + ALLOT",
        ": _RA-SF-DESCRIPTORS _RA-SF-DESCRIPTORS-MEM 7 + -8 AND ;",
        ": _RA-SF-NATIVE _RA-SF-NATIVE-MEM 7 + -8 AND ;",
        "VARIABLE _RA-SF-A VARIABLE _RA-SF-U VARIABLE _RA-SF-PREV-A",
        ": _RA-SF-FIRST ( -- model )",
        "  _RA-SNAP @ RUHA-SNAPSHOT-STATUS-FIELDS-DESCRIPTORS@ DROP",
        "  _RA-DIR-A @ RUHA-DOCUMENT-STATUS-FIELDS-DESCRIPTOR-OFFSET@ +",
        "  _RA-SNAP @ RUHA-SNAPSHOT-STATUS-FIELDS-NATIVE@ DROP",
        "  _RA-DIR-A @ RUHA-DOCUMENT-STATUS-FIELDS-NATIVE-OFFSET@ +",
        "  USFSN-DESCRIPTOR-NATIVE DROP ;",
    ]
    for index, line in enumerate(lines):
        if line == "_RA-INIT-ARGS _RA-ADAPTER RUHA-INIT RUHA-S-OK = _RA-ASSERT":
            lines[index] = (
                "_RA-INIT-ARGS _RA-SF-DESCRIPTORS 2 USFSN-DESCRIPTOR-SIZE * "
                "_RA-SF-NATIVE 256 _RA-ADAPTER RUHA-INIT-STATUS RUHA-S-OK = _RA-ASSERT"
            )
        elif line == "_RA-ADAPTER _RUHA-A.SNAP-SFIELD-DESCRIPTORS-A @ 0= _RA-ASSERT":
            lines[index] = "_RA-ADAPTER _RUHA-A.SNAP-SFIELD-DESCRIPTORS-A @ _RA-SF-DESCRIPTORS = _RA-ASSERT"
        elif line == "_RA-ADAPTER _RUHA-A.SNAP-SFIELD-NATIVE-A @ 0= _RA-ASSERT":
            lines[index] = "_RA-ADAPTER _RUHA-A.SNAP-SFIELD-NATIVE-A @ _RA-SF-NATIVE = _RA-ASSERT"
        elif '<uidl><textarea id=note/>' in line:
            lines[index] = line.replace(
                "<textarea id=note/>",
                "<textarea id=note/><status><label id=state text=ready/></status>",
            )
    at = lines.index("2 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT")
    lines[at:at] = [
        "_RA-SNAP @ RUHA-SNAPSHOT-STATUS-FIELDS-COUNT@ 1 = _RA-ASSERT",
        "_RA-DIR-A @ RUHA-DOCUMENT-STATUS-FIELDS-DESCRIPTOR-BYTES@ USFSN-DESCRIPTOR-SIZE = _RA-ASSERT",
        "_RA-DIR-A @ RUHA-DOCUMENT-STATUS-FIELDS-NATIVE-BYTES@ 80 = _RA-ASSERT",
        "_RA-SF-FIRST DUP _RA-SF-PREV-A ! USF-VALUE@ S\" ready\" STR-STR= _RA-ASSERT",
    ]
    at = lines.index('S" aggregate beta" _RA-TEXTAREA @ TXTA-SET-TEXT')
    lines[at:at] = [
        "_RA-SNAP @ RUHA-SNAPSHOT-STATUS-FIELDS-COUNT@ 1 = _RA-ASSERT",
        "_RA-SF-FIRST DUP _RA-SF-PREV-A @ <> _RA-ASSERT",
        "  80 _RA-SF-PREV-A @ 80 COMPARE 0= _RA-ASSERT",
        ': _RA-UPDATE-STATUS S" state" UTUI-BY-ID S" text" S" done" UIDL-SET-ATTR ; _RA-UPDATE-STATUS',
    ]
    at = next(i for i, line in enumerate(lines) if 'RUHA CONSTRUCTOR PASS' in line)
    lines[at:at] = [
        "_RA-SNAP @ RUHA-SNAPSHOT-STATUS-FIELDS-COUNT@ 1 = _RA-ASSERT",
        "_RA-SF-FIRST USF-VALUE@ S\" done\" STR-STR= _RA-ASSERT",
        # A later foreground write refuses all semantic slices together.
        ": _RA-OVERLAY RGN-ROOT 35 0 0 DRW-CHAR ; ' _RA-OVERLAY DRW-OVERLAY",
        "4 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-DOCUMENT-COUNT@ 1 = _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-STATUS-FIELDS-COUNT@ 0= _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-COLLECTION-COUNT@ 0= _RA-ASSERT",
        "_RA-RECORDS _RUHA-RECORD-DIRTY? _RA-ASSERT",
        # Ordinary repaint exposes both roots and the dirty record recaptures.
        'S" note" UTUI-BY-ID UIDL-DIRTY! S" state" UTUI-BY-ID UIDL-DIRTY!',
        "UTUI-PAINT UTUI-DRAW-COMPLETE",
        "5 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-STATUS-FIELDS-COUNT@ 1 = _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-COLLECTION-COUNT@ 1 = _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-CONTENT-EPOCH@ 5 = _RA-ASSERT",
        "_RA-SF-FIRST USF-VALUE@ S\" done\" STR-STR= _RA-ASSERT",
        "_RA-STACK",
    ]
    return lines


def test_status_banks_capture_reuse_and_recapture_without_collection_aliasing():
    output = _run_forth(_status_adapter_program(), max_steps=20_000_000)
    summary = re.search(r"RUHA CONSTRUCTOR PASS\s+(\d+)\s+0", output)
    assert summary, output[-18000:]
    assert int(summary.group(1)) >= 65


def test_legacy_constructor_status_absence_and_full_source_load():
    output = _run_forth(_ruha_constructor_program())
    summary = re.search(r"RUHA CONSTRUCTOR PASS\s+(\d+)\s+0", output)
    assert summary, output[-18000:]



def test_status_capacity_falls_back_atomically_and_retries_the_dirty_document():
    lines = _status_adapter_program()
    first_query = lines.index("1 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT")
    lines = [line.replace("_RA-SF-NATIVE 256 _RA-ADAPTER RUHA-INIT-STATUS",
                          "_RA-SF-NATIVE 144 _RA-ADAPTER RUHA-INIT-STATUS")
             for line in lines[:first_query + 1]]
    lines += [
        "_RA-SNAP @ RUHA-SNAPSHOT-DOCUMENT-COUNT@ 1 = _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-STATUS-FIELDS-COUNT@ 0= _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-COLLECTION-COUNT@ 0= _RA-ASSERT",
        "_RA-DIR-A @ RUHA-DOCUMENT-STATUS-FIELDS-DESCRIPTOR-BYTES@ 0= _RA-ASSERT",
        "_RA-DIR-A @ RUHA-DOCUMENT-STATUS-FIELDS-NATIVE-BYTES@ 0= _RA-ASSERT",
        "_RA-RECORDS _RUHA-RECORD-DIRTY? _RA-ASSERT",
        'S" state" UTUI-BY-ID _UTUI-SIDECAR DUP _UTUI-SC-ROW@ SWAP _UTUI-SC-COL@',
        "SCR-GET CELL-CP@ 114 = _RA-ASSERT",
        "2 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-STATUS-FIELDS-COUNT@ 0= _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-CONTENT-EPOCH@ 1 = _RA-ASSERT",
        # Empty whole-value text fits the same 72-byte native bank.
        ': _RA-EMPTY-STATUS S" state" UTUI-BY-ID S" text" 0 0 UIDL-SET-ATTR ; _RA-EMPTY-STATUS',
        "UTUI-PAINT UTUI-DRAW-COMPLETE",
        "3 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-STATUS-FIELDS-COUNT@ 1 = _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-COLLECTION-COUNT@ 1 = _RA-ASSERT",
        "_RA-DIR-A @ RUHA-DOCUMENT-STATUS-FIELDS-NATIVE-BYTES@ 72 = _RA-ASSERT",
        "_RA-SF-FIRST USF-VALUE@ NIP 0= _RA-ASSERT",
        "_RA-RECORDS _RUHA-RECORD-DIRTY? 0= _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-CONTENT-EPOCH@ 3 = _RA-ASSERT",
        "_RA-STACK",
        '_RA-FAILS @ 0= IF ." RUHA CAPACITY PASS " ELSE ." RUHA CAPACITY FAIL " THEN _RA-CHECKS @ . _RA-FAILS @ . CR',
    ]
    output = _run_forth(lines)
    summary = re.search(r"RUHA CAPACITY PASS\s+(\d+)\s+0", output)
    assert summary, output[-18000:]
    assert int(summary.group(1)) >= 40
