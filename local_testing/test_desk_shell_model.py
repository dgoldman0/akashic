"""Linked real-Desk qualification of ordinary shell publication and actions."""

import sys

import test_desk_host_characterization as characterization


SHELL_CASES = r'''
VARIABLE _dh-model
VARIABLE _dh-panes
VARIABLE _dh-tasks
VARIABLE _dh-record
VARIABLE _dh-want-kind
VARIABLE _dh-want-id
VARIABLE _dh-seen-shell
CREATE _dh-stale-task SHM-ENTRY-SIZE ALLOT
CREATE _dh-long-title 50000 ALLOT
_dh-long-title 50000 65 FILL

: _dh-shell-observer ( model host context -- )
    731 = _dh-assert
    _DESK-HOST = _dh-assert
    DUP IF DUP SHM.READY @ _dh-assert THEN
    _dh-model ! 1 _dh-seen-shell +! ;
: _dh-shell-find ( kind slot-id -- entry|0 )
    _dh-want-id ! _dh-want-kind !
    _dh-model @ SHM.COUNT @ 0 ?DO
        I _dh-model @ SHM-ENTRY
        DUP SHME.KIND @ _dh-want-kind @ =
        OVER SHME.IDENTITY @ _dh-want-id @ = AND IF UNLOOP EXIT THEN DROP
    LOOP 0 ;
: _dh-shell-counts ( -- )
    0 _dh-panes ! 0 _dh-tasks !
    _DESK-HOST AHOST-SHELL-MODEL@ DUP _dh-model ! 0<> _dh-assert
    _dh-model @ SHM.COUNT @ 0 ?DO
        I _dh-model @ SHM-ENTRY
        DUP SHME.KIND @ SHM-K-PANE = IF 1 _dh-panes +! THEN
        DUP SHME.KIND @ SHM-K-TASK = IF
            1 _dh-tasks +!
            DUP SHME.FLAGS @ SHM-F-SELECTED SHM-F-MINIMIZED OR AND
            SHM-F-SELECTED SHM-F-MINIMIZED OR <> _dh-assert
        THEN DROP
    LOOP ;
: _dh-shell-after-paint ( -- )
    _dh-shell-counts
    _dh-tasks @ 2 = _dh-assert
    _DESK-FULLFRAME-ACTIVE? IF 1 ELSE 2 THEN _dh-panes @ = _dh-assert
    SHM-K-PANE _dh-bid @ _dh-shell-find DUP 0<> _dh-assert
    DUP SHME.CONTENT-W @ _dh-bs @ _SL-RGN @ RGN-W = _dh-assert
    SHME.WIDTH @ _dh-bs @ _SL-RGN @ RGN-W = _dh-assert ;

: _dh-shell-cases ( -- )
    ['] _dh-shell-observer 731 AHOST-SHELL-OBSERVE!
    _dh-desk @ DESK-PAINT-CB
    _dh-seen-shell @ 1 = _dh-assert
    SHM-K-PANE _dh-aid @ _dh-shell-find DUP SHME.CONTENT-W @ 49 = _dh-assert
    SHME.WIDTH @ 50 = _dh-assert
    SHM-K-TASK _dh-aid @ _dh-shell-find DUP _dh-stale-task SHM-ENTRY-SIZE CMOVE
    DUP SHME.ROW @ OVER SHME.COL @ _dh-model @ SHM-HIT = _dh-assert
    SHM-K-TASK _dh-aid @ _dh-shell-find DUP SHME.COL @ SWAP SHME.WIDTH @ +
    SCR-H 1- SWAP _dh-model @ SHM-HIT 0= _dh-assert

    \ The ordinary hotbar returns through the catalog resolver even when it
    \ merely focuses an already running app. No terminal action is involved.
    S" test.desk.host.a" _DESK-CATALOG @ ACAT-FIND-ID DUP 0<> _dh-assert
    DUP ACE.FLAGS DUP @ ACAT-F-PINNED OR SWAP ! DROP
    _dh-desk @ DESK-PAINT-CB
    _dh-model @ SHM.COUNT @ 0 ?DO
        I _dh-model @ SHM-ENTRY DUP SHME.KIND @ SHM-K-LAUNCHER = IF
            DUP _dh-model @ SHME-ACTION$ S" test.desk.host.a" STR-STR= IF
                _DESK-SHELL-LAUNCH _dh-assert LEAVE
            THEN
        THEN DROP
    LOOP
    _DESK-FOCUS-SA @ _dh-as @ = _dh-assert
    _DESK-HOST AHOST-SHELL-MODEL@ 0= _dh-assert
    _dh-bid @ DESK-FOCUS-ID

    \ Prompt paint owns the taskbar row and removes its hit targets.
    S" Ask:" 0 0 _DESK-AGENT-PROMPT @ PRM-SHOW
    _dh-desk @ DESK-PAINT-CB
    _dh-model @ SHM.FLAGS @ SHM-F-TASKBAR-HIDDEN AND 0<> _dh-assert
    SCR-H 1- 0 _dh-model @ SHM-HIT 0= _dh-assert
    _DESK-AGENT-PROMPT @ PRM-HIDE

    \ A model capacity refusal keeps the whole ordinary display and offers
    \ no partial shell model. Restore descriptors before continuing.
    _dh-long-title _dh-app-a APP.TITLE-A ! 50000 _dh-app-a APP.TITLE-U !
    _dh-desk @ DESK-PAINT-CB
    _DESK-HOST AHOST-SHELL-MODEL@ 0= _dh-assert
    _DESK-SHELL-FALLBACK @ _dh-assert
    0 _dh-app-a APP.TITLE-A ! 0 _dh-app-a APP.TITLE-U !
    _dh-desk @ DESK-PAINT-CB
    _DESK-HOST AHOST-SHELL-MODEL@ 0<> _dh-assert
    0 0 AHOST-SHELL-OBSERVE!
    _dh-stack ;
'''


def test_linked_desk_shell_model_and_existing_host_lifecycle(tmp_path, monkeypatch):
    source = characterization.AUTOEXEC
    # Reuse the linked host layout/lifecycle driver, not its historical
    # allocator-fault injection fixture. Current hosts preserve hidden regions.
    source = source.replace("    _dh-failure-cases\n", "")
    source = source.replace("    _dh-bs @ _SL-RGN @ 0= _dh-assert",
                            "    _dh-bs @ _SL-RGN @ 0<> _dh-assert\n"
                            "    _dh-bs @ 0 _DESK-HOST AHOST-PRESENTED? 0= _dh-assert")
    source = source.replace("    _dh-fill-sentinels\n",
                            "    _dh-fill-sentinels\n"
                            "    _dh-app-a ACAT-F-ENABLED ACAT-F-PINNED OR ACAT-F-BUILTIN OR\n"
                            "        _DESK-CATALOG @ ACAT-BIND-BUILTIN ACAT-S-OK = _dh-assert\n")

    source = source.replace("    _dh-desk @ DESK-PAINT-CB\n", "    _dh-desk @ DESK-PAINT-CB\n    _dh-shell-after-paint\n", 2)
    source = source.replace(": _dh-layout-cases", SHELL_CASES + "\n: _dh-layout-cases")
    marker = "    _dh-sentinels-stable? _dh-assert _dh-isolation\n\n    _dh-aid @ APP-CLOSE-R-WINDOW"
    assert marker in source
    source = source.replace(marker, "    _dh-shell-cases\n" + marker)
    marker = "    _dh-shutdown-a @ 1 = _dh-assert _dh-shutdown-b @ 0= _dh-assert"
    source = source.replace(marker, "    _dh-stale-task _DESK-SHELL-TASK-SLOT 0= _dh-assert\n" + marker)
    # Input's shared Unicode row cache belongs to the module, not to a prompt
    # instance. Warm it before lifecycle accounting so first prompt paint is
    # not mistaken for leaked per-Desk storage.
    source = source.replace("HEAP-FREE-BYTES _dh-shell-heap !",
                            'S" warm" 0 BIDI-AUTO _INP-ROW TROW-LAYOUT DROP\nHEAP-FREE-BYTES _dh-shell-heap !')
    monkeypatch.setattr(characterization, "AUTOEXEC", source)
    monkeypatch.setattr(characterization, "IMAGE", tmp_path / "desk-shell-model.img")
    monkeypatch.setattr(sys, "argv", ["test_desk_shell_model", "--timeout", "90"])
    assert characterization.main() == 0
