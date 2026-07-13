#!/usr/bin/env python3
"""Focused end-to-end contracts for the headless shared document owner.

The test registers a private profile with the supported Akashic/MegaPad
harness rather than adding another permanent branch to ``akashic_tui.py``.
It drives two pointer-free lens bindings against one real MP64FS-backed
``/daybook.md`` owner through the generic request bus.
"""

from __future__ import annotations

from pathlib import Path
import sys


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import Profile, PROFILES, build_image, smoke  # noqa: E402


PROFILE_NAME = "shared-document-contracts"

AUTOEXEC = r'''\ autoexec.f - shared document owner contracts
ENTER-USERLAND
." [akashic] loading shared document contracts" CR
REQUIRE interop/shared-document.f
REQUIRE interop/lens-binding.f
REQUIRE utils/fs/drivers/vfs-mp64fs.f

VARIABLE _sd-fails
VARIABLE _sd-checks
VARIABLE _sd-depth

: _sd-assert  ( flag -- )
    1 _sd-checks +!
    0= IF 1 _sd-fails +! ." ASSERT " _sd-checks @ . CR THEN ;

: _sd-stack  ( -- ) DEPTH _sd-depth @ = _sd-assert ;

: _sd-id!  ( value id -- ) DUP RID-CLEAR ! ;

CREATE _sd-head PHEAD-SIZE ALLOT
CREATE _sd-rid RID-SIZE ALLOT
CREATE _sd-other-rid RID-SIZE ALLOT
CREATE _sd-ref RREF-SIZE ALLOT
CREATE _sd-bind-a LBIND-SIZE ALLOT
CREATE _sd-bind-b LBIND-SIZE ALLOT
CREATE _sd-direct-a VREPL-SIZE ALLOT
CREATE _sd-direct-b VREPL-SIZE ALLOT
CREATE _sd-direct-read 128 ALLOT

VARIABLE _sd-vfs
VARIABLE _sd-context
VARIABLE _sd-creg
VARIABLE _sd-rreg
VARIABLE _sd-owner
VARIABLE _sd-bus
VARIABLE _sd-snapshot-a
VARIABLE _sd-replace-a
VARIABLE _sd-stale-b
VARIABLE _sd-snapshot-b
VARIABLE _sd-no-expect
VARIABLE _sd-stamp-bind
VARIABLE _sd-stamp-cap
VARIABLE _sd-stamp-request
VARIABLE _sd-direct-fd
VARIABLE _sd-direct-a0
VARIABLE _sd-direct-u0

: _sd-vrepl-committed?  ( status -- flag )
    DUP VREPL-S-OK = SWAP VREPL-S-COMMITTED-CLEANUP = OR ;

: _sd-direct-file=  ( expected-a expected-u -- flag )
    _sd-direct-u0 ! _sd-direct-a0 !
    S" /daybook.md" VFS-OPEN DUP 0= IF DROP 0 EXIT THEN
    _sd-direct-fd !
    _sd-direct-fd @ VFS-SIZE _sd-direct-u0 @ <> IF
        _sd-direct-fd @ VFS-CLOSE 0 EXIT
    THEN
    _sd-direct-read _sd-direct-u0 @ _sd-direct-fd @ VFS-READ-EXACT IF
        _sd-direct-fd @ VFS-CLOSE 0 EXIT
    THEN
    _sd-direct-fd @ VFS-CLOSE
    _sd-direct-read _sd-direct-u0 @
        _sd-direct-a0 @ _sd-direct-u0 @ COMPARE 0= ;

: _sd-new-request  ( -- request )
    CBR-NEW DUP 0= _sd-assert DROP DUP 0<> _sd-assert ;

: _sd-result=  ( request text-a text-u -- flag )
    >R >R CBR.RESULT DUP CV-DATA@ SWAP CV-LEN@
    R> R> STR-STR= ;

: _sd-stamp  ( binding capability request -- )
    _sd-stamp-request ! _sd-stamp-cap ! _sd-stamp-bind !
    _sd-stamp-bind @ _sd-context @ _sd-stamp-request @
        LBIND-REQUEST! LBIND-S-OK = _sd-assert
    CPRINC-USER _sd-stamp-request @ CBR.PRINCIPAL !
    _sd-stamp-cap @ _sd-stamp-request @ CBR.CAP ! ;

: _sd-free-requests  ( -- )
    _sd-snapshot-a @ CBR-FREE
    _sd-replace-a @ CBR-FREE
    _sd-stale-b @ CBR-FREE
    _sd-snapshot-b @ CBR-FREE
    _sd-no-expect @ CBR-FREE ;

: _sd-run  ( -- )
    0 _sd-fails ! 0 _sd-checks !
    71 _sd-rid _sd-id!
    72 _sd-other-rid _sd-id!
    _sd-head PHEAD-INIT
    11 _sd-head PHEAD.ID _sd-id!
    12 _sd-head PHEAD.CURRENT-ROOT _sd-id!

    2097152 A-XMEM ARENA-NEW IF -1 THROW THEN
    VMP-NEW DUP _sd-vfs ! DUP VMP-INIT 0= _sd-assert VFS-USE

    \ Control: two ordinary path clients can both publish successfully.  The
    \ second has no exact-revision contract and silently replaces the first;
    \ VREPL supplies atomic file publication, not conflict detection.
    _sd-vfs @ _sd-direct-a VREPL-INIT VREPL-S-OK = _sd-assert
    _sd-vfs @ _sd-direct-b VREPL-INIT VREPL-S-OK = _sd-assert
    S" /daybook.md" _sd-direct-a VREPL-DERIVE-PATHS!
        VREPL-S-OK = _sd-assert
    S" /daybook.md" _sd-direct-b VREPL-DERIVE-PATHS!
        VREPL-S-OK = _sd-assert
    S" Daybook direct writer A" _sd-direct-a VREPL-REPLACE
        _sd-vrepl-committed? _sd-assert
    S" Daybook direct writer A" _sd-direct-file= _sd-assert
    S" Daybook direct writer B" _sd-direct-b VREPL-REPLACE
        _sd-vrepl-committed? _sd-assert
    S" Daybook direct writer B" _sd-direct-file= _sd-assert

    77 CTX-NEW DUP 0= _sd-assert DROP _sd-context !
    _sd-head _sd-context @ CTX.PRACTICE !
    CTX-F-ACTIVE _sd-context @ CTX.FLAGS !
    CREG-NEW DUP 0= _sd-assert DROP _sd-creg !
    _sd-creg @ _sd-context @ RREG-NEW
        DUP RREG-S-OK = _sd-assert DROP _sd-rreg !

    _sd-vfs @ _sd-rid _sd-context @ _sd-rreg @ _sd-creg @
        SDOC-ACTIVATE
    DUP SDOC-S-OK = _sd-assert DROP
    DUP 0<> _sd-assert DUP _sd-owner !
    SDOC-VALID? _sd-assert
    _sd-owner @ CINST.REVISION @ 1 = _sd-assert
    _sd-rreg @ RREG.COUNT @ 1 = _sd-assert
    _sd-creg @ CREG.INST-N @ 1 = _sd-assert

    \ A second owner cannot claim the activation or backing path.
    _sd-vfs @ _sd-rid _sd-context @ _sd-rreg @ _sd-creg @
        SDOC-ACTIVATE
    DUP SDOC-S-BUSY = _sd-assert SWAP 0= _sd-assert DROP

    _sd-owner @ _sd-ref SDOC-REF SDOC-S-OK = _sd-assert
    _sd-ref RREF.REVISION @ 1 = _sd-assert
    _sd-ref _sd-context @ _sd-rreg @ _sd-bind-a LBIND-ATTACH
        LBIND-S-OK = _sd-assert
    _sd-ref _sd-context @ _sd-rreg @ _sd-bind-b LBIND-ATTACH
        LBIND-S-OK = _sd-assert

    _sd-creg @ 0 CBUS-NEW DUP 0= _sd-assert DROP _sd-bus !
    DEPTH _sd-depth !

    \ Lens A reads the initial MP64FS file without advancing revision.
    _sd-new-request _sd-snapshot-a !
    _sd-bind-a SDOC-CAP-SNAPSHOT _sd-snapshot-a @ _sd-stamp
    _sd-snapshot-a @ _sd-bus @ CBUS-DISPATCH
        CBUS-S-OK = _sd-assert
    _sd-snapshot-a @ CBR.RESULT CV-TYPE@ CV-T-STRING = _sd-assert
    _sd-snapshot-a @ CBR.RESULT DUP CV-DATA@ SWAP CV-LEN@
        S" Daybook" STR-STR-CONTAINS _sd-assert
    _sd-snapshot-a @ CBR.ACTUAL-REV @ 1 = _sd-assert
    _sd-owner @ CINST.REVISION @ 1 = _sd-assert
    _sd-stack

    \ Lens A performs one exact-revision replace.  CBUS, not the handler,
    \ advances the owner exactly once and reports revision two.
    _sd-new-request _sd-replace-a !
    _sd-bind-a SDOC-CAP-REPLACE _sd-replace-a @ _sd-stamp
    S" first commit" _sd-replace-a @ CBR.ARGS CV-STRING! 0= _sd-assert
    _sd-replace-a @ _sd-bus @ CBUS-DISPATCH
        CBUS-S-OK = _sd-assert
    _sd-replace-a @ CBR.RESULT CV-TYPE@ CV-T-BOOL = _sd-assert
    _sd-replace-a @ CBR.RESULT CV-DATA@ _sd-assert
    _sd-replace-a @ CBR.ACTUAL-REV @ 2 = _sd-assert
    _sd-owner @ CINST.REVISION @ 2 = _sd-assert
    _sd-replace-a @ _sd-context @ _sd-bind-a LBIND-ADVANCE
        LBIND-S-OK = _sd-assert
    _sd-bind-a LBIND.REVISION @ 2 = _sd-assert
    _sd-bind-b LBIND.REVISION @ 1 = _sd-assert
    _sd-stack

    \ Lens B's old revision is rejected before publication.  The owner's
    \ current revision and eventual snapshot remain unchanged.
    _sd-new-request _sd-stale-b !
    _sd-bind-b SDOC-CAP-REPLACE _sd-stale-b @ _sd-stamp
    S" stale overwrite" _sd-stale-b @ CBR.ARGS CV-STRING! 0= _sd-assert
    _sd-stale-b @ _sd-bus @ CBUS-DISPATCH
        CBUS-S-STALE-REVISION = _sd-assert
    _sd-stale-b @ CBR.STATUS @ CBUS-S-STALE-REVISION = _sd-assert
    _sd-stale-b @ CBR.ACTUAL-REV @ 0= _sd-assert
    _sd-owner @ CINST.REVISION @ 2 = _sd-assert

    \ Refresh B from the semantic owner reference, then observe A's text.
    _sd-owner @ _sd-ref SDOC-REF SDOC-S-OK = _sd-assert
    _sd-ref RREF.REVISION @ 2 = _sd-assert
    _sd-ref _sd-context @ _sd-rreg @ _sd-bind-b LBIND-ATTACH
        LBIND-S-OK = _sd-assert
    _sd-new-request _sd-snapshot-b !
    _sd-bind-b SDOC-CAP-SNAPSHOT _sd-snapshot-b @ _sd-stamp
    _sd-snapshot-b @ _sd-bus @ CBUS-DISPATCH
        CBUS-S-OK = _sd-assert
    _sd-snapshot-b @ S" first commit" _sd-result= _sd-assert
    _sd-owner @ CINST.REVISION @ 2 = _sd-assert

    \ A read-only Practice rejects publication at the owner boundary.  The
    \ request remains exact and otherwise valid, so this proves the Context
    \ flag itself prevents both VFS mutation and revision advancement.
    _sd-new-request _sd-no-expect !
    _sd-bind-a SDOC-CAP-REPLACE _sd-no-expect @ _sd-stamp
    S" read-only overwrite" _sd-no-expect @ CBR.ARGS CV-STRING!
        0= _sd-assert
    _sd-context @ CTX.FLAGS DUP @ CTX-F-READONLY OR SWAP !
    _sd-no-expect @ _sd-bus @ CBUS-DISPATCH
        CBUS-S-DENIED = _sd-assert
    _sd-no-expect @ CBR.STATUS @ CBUS-S-DENIED = _sd-assert
    _sd-no-expect @ CBR.ERROR-CODE @ SDOC-S-READONLY = _sd-assert
    _sd-owner @ CINST.REVISION @ 2 = _sd-assert
    _sd-context @ CTX.FLAGS DUP @ CTX-F-READONLY INVERT AND SWAP !

    \ A replace with no expected revision is not a blind-write escape.
    _sd-bind-a SDOC-CAP-REPLACE _sd-no-expect @ _sd-stamp
    0 _sd-no-expect @ CBR.EXPECT-REV !
    S" unversioned" _sd-no-expect @ CBR.ARGS CV-STRING! 0= _sd-assert
    _sd-no-expect @ _sd-bus @ CBUS-DISPATCH
        CBUS-S-INVALID = _sd-assert
    _sd-owner @ CINST.REVISION @ 2 = _sd-assert

    \ A valid target handle cannot be used to substitute another semantic
    \ resource identity at the owner boundary.
    _sd-bind-a SDOC-CAP-REPLACE _sd-no-expect @ _sd-stamp
    _sd-other-rid _sd-no-expect @ CBR.RESOURCE-ID RID-COPY
    S" wrong resource" _sd-no-expect @ CBR.ARGS CV-STRING! 0= _sd-assert
    _sd-no-expect @ _sd-bus @ CBUS-DISPATCH
        CBUS-S-INVALID = _sd-assert
    _sd-owner @ CINST.REVISION @ 2 = _sd-assert

    \ Reuse B's completed snapshot envelope to prove the rejected writes
    \ did not change the VFS content.
    _sd-bind-b SDOC-CAP-SNAPSHOT _sd-snapshot-b @ _sd-stamp
    _sd-snapshot-b @ _sd-bus @ CBUS-DISPATCH
        CBUS-S-OK = _sd-assert
    _sd-snapshot-b @ S" first commit" _sd-result= _sd-assert
    _sd-stack

    \ Owner teardown does not inspect or mutate either lens binding.
    _sd-owner @ SDOC-DEACTIVATE SDOC-S-OK = _sd-assert
    0 _sd-owner !
    _sd-rreg @ RREG.COUNT @ 0= _sd-assert
    _sd-creg @ CREG.INST-N @ 0= _sd-assert
    _sd-bind-a LBIND-VALID? _sd-assert
    _sd-bind-b LBIND-VALID? _sd-assert
    _sd-ref _sd-context @ _sd-rreg @ RREG-RESOLVE
    DUP RREG-S-NOT-FOUND = _sd-assert SWAP 0= _sd-assert DROP

    _sd-free-requests
    _sd-bus @ CBUS-FREE
    _sd-rreg @ RREG-FREE
    _sd-creg @ CREG-FREE
    _sd-context @ CTX-FREE
    _sd-stack

    _sd-fails @ 0= IF
        ." SHARED DOCUMENT PASS " _sd-checks @ .
    ELSE
        ." SHARED DOCUMENT FAIL " _sd-fails @ . ." / " _sd-checks @ .
    THEN CR ;

_sd-run
'''


def test_shared_document_contracts(tmp_path: Path) -> None:
    PROFILES[PROFILE_NAME] = Profile(
        roots=(
            "interop/shared-document.f",
            "interop/lens-binding.f",
            "utils/fs/drivers/vfs-mp64fs.f",
        ),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("SHARED DOCUMENT PASS",),
        stable_markers=("SHARED DOCUMENT PASS",),
        failure_markers=("SHARED DOCUMENT FAIL",),
    )
    image = build_image(PROFILE_NAME, tmp_path / "shared-document.img")
    assert smoke(
        PROFILE_NAME,
        image,
        cols=100,
        rows=30,
        max_steps=1_200_000_000,
        timeout=45.0,
    )


if __name__ == "__main__":
    import tempfile

    with tempfile.TemporaryDirectory() as directory:
        test_shared_document_contracts(Path(directory))
