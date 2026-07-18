#!/usr/bin/env python3
"""Focused contracts for Daybook as a shared-document lens.

The ordinary ``daybook-contracts`` profile remains the standalone VFS/VREPL
control.  This fixture supplies the same four services that Desk lends to an
applet and exercises Daybook through the semantic owner without starting the
TUI shell.
"""

from __future__ import annotations

from pathlib import Path
import sys


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import Profile, PROFILES, build_image, smoke  # noqa: E402


PROFILE_NAME = "daybook-shared-lens-contracts"

AUTOEXEC = r'''\ autoexec.f - Daybook shared lens contracts
ENTER-USERLAND
." [akashic] loading Daybook shared lens contracts" CR
REQUIRE tui/applets/daybook/daybook.f
REQUIRE daybook/shared-document.f
REQUIRE utils/fs/drivers/vfs-mp64fs.f

VARIABLE _dsl-fails
VARIABLE _dsl-checks
VARIABLE _dsl-depth
VARIABLE _dsl-vfs
CREATE _dsl-bd /BLOCK-DEVICE ALLOT
CREATE _dsl-volume /VOLUME ALLOT
VARIABLE _dsl-context
VARIABLE _dsl-creg
VARIABLE _dsl-rreg
VARIABLE _dsl-owner
VARIABLE _dsl-bus
VARIABLE _dsl-a
VARIABLE _dsl-b
VARIABLE _dsl-blocked
VARIABLE _dsl-no-context
VARIABLE _dsl-capture
VARIABLE _dsl-owner-rev
VARIABLE _dsl-text-a
VARIABLE _dsl-text-u
VARIABLE _dsl-base-count

CREATE _dsl-head PHEAD-SIZE ALLOT
CREATE _dsl-rid RID-SIZE ALLOT
CREATE _dsl-policy CPOLICY-SIZE ALLOT
CREATE _dsl-endpoint IENDPOINT-SIZE ALLOT
CREATE _dsl-blocked-endpoint IENDPOINT-SIZE ALLOT
CREATE _dsl-no-context-endpoint IENDPOINT-SIZE ALLOT
CREATE _dsl-source CV-SIZE ALLOT
CREATE _dsl-source-ref RREF-SIZE ALLOT

: _dsl-assert  ( flag -- )
    1 _dsl-checks +!
    0= IF 1 _dsl-fails +! ." ASSERT " _dsl-checks @ . CR THEN ;

: _dsl-stack  ( -- )
    DEPTH DUP _dsl-depth @ <> IF
        ." DAYBOOK SHARED STACK " _dsl-depth @ . ." -> " DUP . CR .S CR
    THEN
    _dsl-depth @ = _dsl-assert ;
: _dsl-id!  ( value id -- ) DUP RID-CLEAR ! ;

: _dsl-service  ( id-a id-u context -- service | 0 )
    DROP
    2DUP S" org.akashic.runtime.context" STR-STR= IF
        2DROP _dsl-context @ EXIT
    THEN
    2DUP S" org.akashic.runtime.resource-registry" STR-STR= IF
        2DROP _dsl-rreg @ EXIT
    THEN
    2DUP S" org.akashic.interop.request-bus" STR-STR= IF
        2DROP _dsl-bus @ EXIT
    THEN
    S" org.akashic.resource.daybook" STR-STR= IF
        _dsl-rid EXIT
    THEN
    0 ;

: _dsl-blocked-service  ( id-a id-u context -- service | 0 )
    DROP
    S" org.akashic.runtime.context" STR-STR= IF
        _dsl-context @
    ELSE
        0
    THEN ;

: _dsl-new-daybook  ( endpoint -- instance )
    >R
    DAYBOOK-COMP-DESC CINST-NEW DUP 0= _dsl-assert DROP
    DUP R@ SWAP CINST.ENDPOINT !
    DUP _dsl-creg @ CREG-INST+ 0= _dsl-assert
    R> DROP ;

: _dsl-lens-init  ( instance -- )
    _DB-ACTIVATE
    0 _DB-SOURCE-BLOCKED ! 0 _DB-SAVE-STALE !
    _DB-TODAY _DB-SELECTED-DATE !
    _DB-SHARED-INIT ;

: _dsl-add  ( text-a text-u -- )
    _dsl-text-u ! _dsl-text-a !
    _DB-K-TASK 0 _DB-SELECTED-DATE @ -1
        _dsl-text-a @ _dsl-text-u @ _DB-ADD
    0>= _dsl-assert ;

: _dsl-write  ( -- status )
    _DB-SERIALIZE _DB-WRITE ;

: _dsl-free-daybook  ( instance -- )
    DUP _DB-ACTIVATE _DB-SHARED-FINI
    DUP _dsl-creg @ CREG-INST- 0= _dsl-assert
    CINST-FREE ;

: _dsl-run  ( -- )
    0 _dsl-fails ! 0 _dsl-checks !
    _dsl-head PHEAD-INIT
    41 _dsl-head PHEAD.ID _dsl-id!
    42 _dsl-head PHEAD.CURRENT-ROOT _dsl-id!
    71 _dsl-rid _dsl-id!

    _dsl-bd BD-OPEN THROW
    _dsl-bd _dsl-volume VOL-RAW THROW
    2097152 A-XMEM ARENA-NEW IF -1 THROW THEN
    _dsl-volume VMP-NEW ?DUP IF THROW THEN DUP _dsl-vfs ! VFS-USE

    77 CTX-NEW DUP 0= _dsl-assert DROP _dsl-context !
    _dsl-head _dsl-context @ CTX.PRACTICE !
    CTX-F-ACTIVE _dsl-context @ CTX.FLAGS !
    _dsl-vfs @ _dsl-context @ CTX.VFS !
    CREG-NEW DUP 0= _dsl-assert DROP _dsl-creg !
    _dsl-creg @ _dsl-context @ RREG-NEW
        DUP RREG-S-OK = _dsl-assert DROP _dsl-rreg !
    _dsl-policy CPOLICY-INIT
    _dsl-creg @ _dsl-policy CBUS-NEW
        DUP 0= _dsl-assert DROP _dsl-bus !
    _dsl-policy _dsl-context @ CTX.POLICY !
    _dsl-bus @ _dsl-context @ CTX.QUEUE !
    _dsl-vfs @ _dsl-rid _dsl-context @ _dsl-rreg @ _dsl-creg @
        SDOC-ACTIVATE
    DUP SDOC-S-OK = _dsl-assert DROP _dsl-owner !

    _dsl-endpoint IENDPOINT-INIT
    ['] _dsl-service _dsl-endpoint IEND.SERVICE-XT !
    _dsl-blocked-endpoint IENDPOINT-INIT
    ['] _dsl-blocked-service _dsl-blocked-endpoint IEND.SERVICE-XT !
    _dsl-no-context-endpoint IENDPOINT-INIT
    _DAYBOOK-COMP-SETUP
    DEPTH _dsl-depth !

    _dsl-endpoint _dsl-new-daybook DUP _dsl-a ! _dsl-lens-init
    _DB-RESOURCE-MODE @ SDLENS-M-SHARED = _dsl-assert
    _DB-LOAD _DB-L-S-OK = _dsl-assert
    _DB-COUNT @ DUP _dsl-base-count ! 0>= _dsl-assert
    _DB-SHARED-BIND LBIND.REVISION @ 1 = _dsl-assert
    _dsl-stack

    _dsl-endpoint _dsl-new-daybook DUP _dsl-b ! _dsl-lens-init
    _dsl-stack
    _DB-LOAD _DB-L-S-OK = _dsl-assert
    _DB-SHARED-BIND LBIND.REVISION @ 1 = _dsl-assert
    _dsl-stack

    \ Lens A publishes revision two.
    _dsl-a @ _DB-ACTIVATE
    S" from lens A" _dsl-add
    _dsl-write 0= _dsl-assert
    _DB-SHARED-BIND LBIND.REVISION @ 2 = _dsl-assert
    _dsl-owner @ CINST.REVISION @ 2 = _dsl-assert
    _dsl-stack

    \ Lens B never refreshes before replace, so its exact revision-one save
    \ remains dirty/stale and cannot overwrite A.
    _dsl-b @ _DB-ACTIVATE
    S" stale lens B" _dsl-add
    -1 _DB-DIRTY !
    _DB-SAVE CBUS-S-STALE-REVISION = _dsl-assert
    _DB-SAVE-STALE @ _dsl-assert
    _DB-DIRTY @ _dsl-assert
    _DB-SHARED-BIND LBIND.REVISION @ 1 = _dsl-assert
    _dsl-owner @ CINST.REVISION @ 2 = _dsl-assert
    _dsl-stack

    \ Reload explicitly reattaches B, observes A, and advances its binding.
    _DB-LOAD _DB-L-S-OK = _dsl-assert
    _DB-COUNT @ _dsl-base-count @ 1+ = _dsl-assert
    _dsl-base-count @ _DB-ENTRY _DB-E-TEXT + 11
        S" from lens A" STR-STR= _dsl-assert
    _DB-SHARED-BIND LBIND.REVISION @ 2 = _dsl-assert
    _dsl-stack

    \ Shared source capabilities expose the semantic RID, not /daybook.md.
    _dsl-source CV-NULL!
    _dsl-source _DB-SOURCE-VALUE! IRES-S-OK = _dsl-assert
    _dsl-source _dsl-source-ref IRES-RREF@ IRES-S-OK = _dsl-assert
    _dsl-source-ref RREF.ID _dsl-rid RID= _dsl-assert
    _dsl-source-ref RREF.REVISION @ 2 = _dsl-assert

    \ A user-authorized capture performs one nested, explicitly approved
    \ implementation-hop replace and advances both owner and lens.
    CBR-NEW DUP 0= _dsl-assert DROP _dsl-capture !
    CPRINC-USER _dsl-capture @ CBR.PRINCIPAL !
    _dsl-b @ _dsl-capture @ CBR-TARGET!
    DAYBOOK-CAP-CAPTURE _dsl-capture @ CBR.CAP !
    S" nested capture" _dsl-capture @ CBR.ARGS CV-STRING! 0= _dsl-assert
    _dsl-capture @ _dsl-bus @ CBUS-DISPATCH CBUS-S-OK = _dsl-assert
    _dsl-owner @ CINST.REVISION @ 3 = _dsl-assert
    _dsl-b @ _DB-ACTIVATE
    _DB-SHARED-BIND LBIND.REVISION @ 3 = _dsl-assert
    _DB-LOAD _DB-L-S-OK = _dsl-assert
    _DB-COUNT @ _dsl-base-count @ 2 + = _dsl-assert
    _dsl-stack

    \ A valid Practice Context with an incomplete service set is blocked.
    \ It cannot silently use the ordinary backing path.
    _dsl-blocked-endpoint _dsl-new-daybook
        DUP _dsl-blocked ! _dsl-lens-init
    _DB-RESOURCE-MODE @ SDLENS-M-BLOCKED = _dsl-assert
    _DB-SOURCE-BLOCKED @ _dsl-assert
    _dsl-owner @ CINST.REVISION @ _dsl-owner-rev !
    _DB-IO-RESET S" must not publish" _DB-IO-APPEND
    _DB-WRITE 0<> _dsl-assert
    _dsl-owner @ CINST.REVISION @ _dsl-owner-rev @ = _dsl-assert
    _dsl-stack

    \ A present endpoint which fails to supply Context is broken runtime
    \ wiring, not the endpoint-free standalone control.  It must also block
    \ instead of falling open to direct /daybook.md access.
    _dsl-no-context-endpoint _dsl-new-daybook
        DUP _dsl-no-context ! _dsl-lens-init
    _DB-RESOURCE-MODE @ SDLENS-M-BLOCKED = _dsl-assert
    _DB-SOURCE-BLOCKED @ _dsl-assert
    _DB-IO-RESET S" endpoint must not publish" _DB-IO-APPEND
    _DB-WRITE 0<> _dsl-assert
    _dsl-owner @ CINST.REVISION @ _dsl-owner-rev @ = _dsl-assert
    _dsl-stack
    _dsl-capture @ CBR-FREE
    _dsl-source CV-FREE
    _dsl-a @ _dsl-free-daybook
    _dsl-b @ _dsl-free-daybook
    _dsl-blocked @ _dsl-free-daybook
    _dsl-no-context @ _dsl-free-daybook
    _dsl-owner @ SDOC-DEACTIVATE SDOC-S-OK = _dsl-assert
    _dsl-bus @ CBUS-FREE
    _dsl-rreg @ RREG-FREE
    _dsl-creg @ CREG-FREE
    _dsl-context @ CTX-FREE
    _dsl-stack

    _dsl-fails @ 0= IF
        ." DAYBOOK SHARED LENS PASS " _dsl-checks @ .
    ELSE
        ." DAYBOOK SHARED LENS FAIL " _dsl-fails @ . ." / " _dsl-checks @ .
    THEN CR ;

_dsl-run
'''


def test_daybook_shared_lens_contracts(tmp_path: Path) -> None:
    PROFILES[PROFILE_NAME] = Profile(
        roots=(
            "tui/applets/daybook/daybook.f",
            "daybook/shared-document.f",
            "utils/fs/drivers/vfs-mp64fs.f",
        ),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("DAYBOOK SHARED LENS PASS",),
        stable_markers=("DAYBOOK SHARED LENS PASS",),
        failure_markers=("DAYBOOK SHARED LENS FAIL",),
    )
    image = build_image(PROFILE_NAME, tmp_path / "daybook-shared-lens.img")
    assert smoke(
        PROFILE_NAME,
        image,
        cols=100,
        rows=30,
        max_steps=2_500_000_000,
        timeout=50.0,
    )


if __name__ == "__main__":
    import tempfile

    with tempfile.TemporaryDirectory() as directory:
        test_daybook_shared_lens_contracts(Path(directory))
