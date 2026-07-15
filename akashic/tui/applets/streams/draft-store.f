\ =====================================================================
\  draft-store.f - Streams-owned crash-recoverable local draft storage
\ =====================================================================
\  This module persists one unpublished Streams draft.  It deliberately
\  stores only the applet-owned UTF-8 text and its local draft revision;
\  credentials, feed data, capability authority, and Practice state have no
\  representation here.
\
\  The target is replaced through VREPL, so activation-time LOAD first
\  resolves a prior interrupted replacement.  The application record has a
\  fixed V1 envelope, bounded payload, header CRC, and payload CRC.  CRCs are
\  accidental-corruption detection, not authentication.
\
\  Public API:
\    STREAMS-DRAFT-STORE-INIT-AT
\      ( target-a target-u vfs store -- status )
\    STREAMS-DRAFT-STORE-INIT
\      ( vfs store -- status )
\    STREAMS-DRAFT-STORE-RECOVER
\      ( store -- status )
\    STREAMS-DRAFT-STORE-SAVE
\      ( text-a text-u revision store -- status )
\    STREAMS-DRAFT-STORE-LOAD
\      ( destination capacity store -- text-u revision status )
\
\  LOAD is transactional with respect to DESTINATION: every non-OK result
\  leaves caller memory unchanged.  Empty drafts are present records with a
\  positive revision and a zero-byte payload; they are not ABSENT.
\ =====================================================================

PROVIDED akashic-tui-streams-draft-store

REQUIRE ../../../utils/fs/vfs-replace.f
REQUIRE ../../../text/utf8.f
REQUIRE ../../../math/crc.f
REQUIRE ../../../concurrency/guard.f

\ =====================================================================
\  Public bounds and statuses
\ =====================================================================

3000 CONSTANT STREAMS-DRAFT-TEXT-MAX

0 CONSTANT SDSTORE-S-OK
1 CONSTANT SDSTORE-S-ABSENT
2 CONSTANT SDSTORE-S-CORRUPT
3 CONSTANT SDSTORE-S-UNSUPPORTED
4 CONSTANT SDSTORE-S-INVALID
5 CONSTANT SDSTORE-S-CAPACITY
6 CONSTANT SDSTORE-S-IO
7 CONSTANT SDSTORE-S-RECOVERY
8 CONSTANT SDSTORE-S-BUSY

\ =====================================================================
\  Versioned record envelope
\ =====================================================================

1  CONSTANT STREAMS-DRAFT-FORMAT-V1
64 CONSTANT STREAMS-DRAFT-HEADER-SIZE
STREAMS-DRAFT-HEADER-SIZE STREAMS-DRAFT-TEXT-MAX +
    CONSTANT STREAMS-DRAFT-RECORD-MAX

CREATE _SDR-MAGIC
65 C, 75 C, 83 C, 68 C, 82 C, 48 C, 48 C, 49 C,  \ "AKSDR001"

 0 CONSTANT _SDR-H-MAGIC
 8 CONSTANT _SDR-H-FORMAT
16 CONSTANT _SDR-H-HEADER-SIZE
24 CONSTANT _SDR-H-REVISION
32 CONSTANT _SDR-H-TEXT-SIZE
40 CONSTANT _SDR-H-TEXT-CRC
48 CONSTANT _SDR-H-HEADER-CRC
56 CONSTANT _SDR-H-FLAGS

CREATE _SDR-RECORD STREAMS-DRAFT-RECORD-MAX ALLOT

: _STREAMS-DRAFT-RECORD-WIPE  ( -- )
    _SDR-RECORD STREAMS-DRAFT-RECORD-MAX 0 FILL ;

\ The common envelope is stable across format versions.  Its CRC excludes
\ only its own cell, covering the format discriminator and all other header
\ fields.  A future supported format may change payload semantics, but must
\ retain this prefix before this reader can classify it as UNSUPPORTED.
: _STREAMS-DRAFT-HEADER-CRC  ( record -- crc32 )
    CRC32-BEGIN
    DUP _SDR-H-HEADER-CRC CRC32-ADD
    DUP _SDR-H-FLAGS + 8 CRC32-ADD
    DROP CRC32-END ;

: _STREAMS-DRAFT-TEXT-CRC  ( a u -- crc32 )
    CRC32-BEGIN CRC32-ADD CRC32-END ;

VARIABLE _SDRE-A
VARIABLE _SDRE-U
VARIABLE _SDRE-REV

: _STREAMS-DRAFT-ENCODE  ( text-a text-u revision -- length status )
    _SDRE-REV ! _SDRE-U ! _SDRE-A !
    _SDRE-U @ 0< IF 0 SDSTORE-S-INVALID EXIT THEN
    _SDRE-U @ STREAMS-DRAFT-TEXT-MAX > IF
        0 SDSTORE-S-CAPACITY EXIT
    THEN
    _SDRE-U @ 0> _SDRE-A @ 0= AND IF
        0 SDSTORE-S-INVALID EXIT
    THEN
    _SDRE-REV @ 0> 0= IF 0 SDSTORE-S-INVALID EXIT THEN
    _SDRE-U @ IF
        _SDRE-A @ _SDRE-U @ UTF8-VALID? 0= IF
            0 SDSTORE-S-INVALID EXIT
        THEN
    THEN
    _SDR-RECORD STREAMS-DRAFT-RECORD-MAX 0 FILL
    _SDR-MAGIC _SDR-RECORD _SDR-H-MAGIC + 8 CMOVE
    STREAMS-DRAFT-FORMAT-V1 _SDR-RECORD _SDR-H-FORMAT + !
    STREAMS-DRAFT-HEADER-SIZE _SDR-RECORD _SDR-H-HEADER-SIZE + !
    _SDRE-REV @ _SDR-RECORD _SDR-H-REVISION + !
    _SDRE-U @ _SDR-RECORD _SDR-H-TEXT-SIZE + !
    _SDRE-U @ IF
        _SDRE-A @ _SDR-RECORD STREAMS-DRAFT-HEADER-SIZE +
            _SDRE-U @ CMOVE
    THEN
    _SDR-RECORD STREAMS-DRAFT-HEADER-SIZE + _SDRE-U @
        _STREAMS-DRAFT-TEXT-CRC
        _SDR-RECORD _SDR-H-TEXT-CRC + !
    _SDR-RECORD _STREAMS-DRAFT-HEADER-CRC
        _SDR-RECORD _SDR-H-HEADER-CRC + !
    STREAMS-DRAFT-HEADER-SIZE _SDRE-U @ + SDSTORE-S-OK ;

\ =====================================================================
\  Store descriptor and replacement ownership
\ =====================================================================

0x53445253544F5231 CONSTANT _SDSTORE-MAGIC  \ "SDRSTOR1"

 0 CONSTANT _SDS-MAGIC
 8 CONSTANT _SDS-VFS
16 CONSTANT _SDS-LAST-VREPL
24 CONSTANT _SDS-RESERVED
32 CONSTANT _SDS-REPLACE
_SDS-REPLACE VREPL-SIZE + CONSTANT STREAMS-DRAFT-STORE-SIZE

: STREAMS-DRAFT-STORE.MAGIC       ( store -- a ) _SDS-MAGIC + ;
: STREAMS-DRAFT-STORE.VFS         ( store -- a ) _SDS-VFS + ;
: STREAMS-DRAFT-STORE.LAST-VREPL  ( store -- a ) _SDS-LAST-VREPL + ;
: STREAMS-DRAFT-STORE.REPLACE     ( store -- replacement )
    _SDS-REPLACE + ;

: STREAMS-DRAFT-STORE-TARGET$  ( -- a u )  \ singleton default only
    S" /streams-draft.bin" ;

: STREAMS-DRAFT-STORE-PATH$  ( store -- a u )
    STREAMS-DRAFT-STORE.REPLACE VREPL-TARGET$ ;

: STREAMS-DRAFT-STORE-VALID?  ( store -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP STREAMS-DRAFT-STORE.MAGIC @ _SDSTORE-MAGIC <> IF
        DROP 0 EXIT
    THEN
    DUP STREAMS-DRAFT-STORE.VFS @ 0= IF DROP 0 EXIT THEN
    DUP STREAMS-DRAFT-STORE.REPLACE VREPL-CONFIGURED? 0= IF
        DROP 0 EXIT
    THEN
    DUP STREAMS-DRAFT-STORE.VFS @ SWAP
        STREAMS-DRAFT-STORE.REPLACE VREPL.VFS @ = ;

: _SDSTORE-VREPL>STATUS  ( vrepl-status -- status )
    CASE
        VREPL-S-OK OF SDSTORE-S-OK ENDOF
        VREPL-S-ROLLED-BACK OF SDSTORE-S-OK ENDOF
        VREPL-S-COMMITTED-CLEANUP OF SDSTORE-S-OK ENDOF
        VREPL-S-INVALID OF SDSTORE-S-INVALID ENDOF
        VREPL-S-CONFLICT OF SDSTORE-S-INVALID ENDOF
        VREPL-S-BUSY OF SDSTORE-S-BUSY ENDOF
        VREPL-S-IO OF SDSTORE-S-IO ENDOF
        VREPL-S-RECOVERY OF SDSTORE-S-RECOVERY ENDOF
        VREPL-S-MARKER-CORRUPT OF SDSTORE-S-RECOVERY ENDOF
        VREPL-S-UNCERTAIN OF SDSTORE-S-RECOVERY ENDOF
        SDSTORE-S-RECOVERY SWAP
    ENDCASE ;

GUARD _streams-draft-store-guard

VARIABLE _SDSI-VFS
VARIABLE _SDSI-STORE
VARIABLE _SDSI-TARGET-A
VARIABLE _SDSI-TARGET-U

: _STREAMS-DRAFT-STORE-INIT-AT  ( target-a target-u vfs store -- status )
    _SDSI-STORE ! _SDSI-VFS ! _SDSI-TARGET-U ! _SDSI-TARGET-A !
    _SDSI-TARGET-A @ 0= _SDSI-TARGET-U @ 0< OR
    _SDSI-VFS @ 0= OR _SDSI-STORE @ 0= OR IF
        SDSTORE-S-INVALID EXIT
    THEN
    _SDSI-STORE @ STREAMS-DRAFT-STORE-SIZE 0 FILL
    _SDSTORE-MAGIC _SDSI-STORE @ STREAMS-DRAFT-STORE.MAGIC !
    _SDSI-VFS @ _SDSI-STORE @ STREAMS-DRAFT-STORE.VFS !
    _SDSI-VFS @ _SDSI-STORE @ STREAMS-DRAFT-STORE.REPLACE
        VREPL-INIT DUP IF _SDSTORE-VREPL>STATUS EXIT THEN DROP
    _SDSI-TARGET-A @ _SDSI-TARGET-U @
        _SDSI-STORE @ STREAMS-DRAFT-STORE.REPLACE
        VREPL-DERIVE-PATHS! _SDSTORE-VREPL>STATUS ;

: _STREAMS-DRAFT-STORE-INIT  ( vfs store -- status )
    STREAMS-DRAFT-STORE-TARGET$ 2SWAP
    _STREAMS-DRAFT-STORE-INIT-AT ;

' _STREAMS-DRAFT-STORE-INIT-AT CONSTANT _sds-init-at-xt
' _STREAMS-DRAFT-STORE-INIT    CONSTANT _sds-init-xt

: STREAMS-DRAFT-STORE-INIT-AT  ( target-a target-u vfs store -- status )
    _sds-init-at-xt _streams-draft-store-guard WITH-GUARD ;

: STREAMS-DRAFT-STORE-INIT  ( vfs store -- status )
    _sds-init-xt _streams-draft-store-guard WITH-GUARD ;

VARIABLE _SDSR-STORE
VARIABLE _SDSR-VSTATUS

: _STREAMS-DRAFT-STORE-RECOVER  ( store -- status )
    DUP STREAMS-DRAFT-STORE-VALID? 0= IF
        DROP SDSTORE-S-INVALID EXIT
    THEN
    _SDSR-STORE !
    _SDSR-STORE @ STREAMS-DRAFT-STORE.REPLACE VREPL-RECOVER
        DUP _SDSR-VSTATUS !
    _SDSR-VSTATUS @ _SDSR-STORE @ STREAMS-DRAFT-STORE.LAST-VREPL !
    _SDSTORE-VREPL>STATUS ;

' _STREAMS-DRAFT-STORE-RECOVER CONSTANT _sds-recover-xt
: STREAMS-DRAFT-STORE-RECOVER  ( store -- status )
    _sds-recover-xt _streams-draft-store-guard WITH-GUARD ;

\ =====================================================================
\  Exception-safe bounded target read
\ =====================================================================

VARIABLE _SDRR-STORE
VARIABLE _SDRR-FD
VARIABLE _SDRR-OLD-VFS
VARIABLE _SDRR-HAVE-OLD-VFS
VARIABLE _SDRR-STATUS
VARIABLE _SDRR-FILE-U
VARIABLE _SDRR-TEXT-U
VARIABLE _SDRR-REVISION
VARIABLE _SDRR-CLEAN-FD
VARIABLE _SDRR-CLEAN-FAILED

: _SDRR-CLOSE-CALL  ( -- ) _SDRR-CLEAN-FD @ VFS-CLOSE ;
: _SDRR-RESTORE-CALL  ( -- ) _SDRR-OLD-VFS @ VFS-USE ;

: _SDRR-CLEANUP  ( -- failed? )
    0 _SDRR-CLEAN-FAILED !
    _SDRR-FD @ ?DUP IF
        _SDRR-CLEAN-FD ! 0 _SDRR-FD !
        ['] _SDRR-CLOSE-CALL CATCH IF -1 _SDRR-CLEAN-FAILED ! THEN
    THEN
    _SDRR-HAVE-OLD-VFS @ IF
        0 _SDRR-HAVE-OLD-VFS !
        ['] _SDRR-RESTORE-CALL CATCH IF -1 _SDRR-CLEAN-FAILED ! THEN
    THEN
    _SDRR-CLEAN-FAILED @ ;

: _SDRR-READ-BODY  ( -- status )
    _SDRR-STORE @ STREAMS-DRAFT-STORE-PATH$
        _SDRR-STORE @ STREAMS-DRAFT-STORE.VFS @ VFS-RESOLVE 0= IF
        SDSTORE-S-ABSENT EXIT
    THEN
    _SDRR-STORE @ STREAMS-DRAFT-STORE-PATH$ VFS-OPEN DUP 0= IF
        DROP SDSTORE-S-IO EXIT
    THEN
    _SDRR-FD !
    _SDRR-FD @ VFS-SIZE DUP _SDRR-FILE-U !
    STREAMS-DRAFT-HEADER-SIZE < IF SDSTORE-S-CORRUPT EXIT THEN
    _SDR-RECORD STREAMS-DRAFT-HEADER-SIZE
        _SDRR-FD @ VFS-READ-EXACT IF SDSTORE-S-IO EXIT THEN
    _SDR-RECORD _SDR-H-MAGIC + 8 _SDR-MAGIC 8 COMPARE 0<> IF
        SDSTORE-S-CORRUPT EXIT
    THEN
    _SDR-RECORD _STREAMS-DRAFT-HEADER-CRC
        _SDR-RECORD _SDR-H-HEADER-CRC + @ <> IF
        SDSTORE-S-CORRUPT EXIT
    THEN
    _SDR-RECORD _SDR-H-FORMAT + @ STREAMS-DRAFT-FORMAT-V1 <> IF
        SDSTORE-S-UNSUPPORTED EXIT
    THEN
    _SDR-RECORD _SDR-H-HEADER-SIZE + @
        STREAMS-DRAFT-HEADER-SIZE <>
    _SDR-RECORD _SDR-H-FLAGS + @ 0<> OR
    _SDR-RECORD _SDR-H-REVISION + @ DUP _SDRR-REVISION ! 0> 0= OR
    _SDR-RECORD _SDR-H-TEXT-SIZE + @ DUP _SDRR-TEXT-U ! 0< OR IF
        SDSTORE-S-CORRUPT EXIT
    THEN
    _SDRR-TEXT-U @ STREAMS-DRAFT-TEXT-MAX > IF
        SDSTORE-S-CORRUPT EXIT
    THEN
    STREAMS-DRAFT-HEADER-SIZE _SDRR-TEXT-U @ +
        _SDRR-FILE-U @ <> IF SDSTORE-S-CORRUPT EXIT THEN
    _SDRR-TEXT-U @ IF
        _SDR-RECORD STREAMS-DRAFT-HEADER-SIZE + _SDRR-TEXT-U @
            _SDRR-FD @ VFS-READ-EXACT IF SDSTORE-S-IO EXIT THEN
    THEN
    _SDR-RECORD STREAMS-DRAFT-HEADER-SIZE + _SDRR-TEXT-U @
        _STREAMS-DRAFT-TEXT-CRC
        _SDR-RECORD _SDR-H-TEXT-CRC + @ <> IF
        SDSTORE-S-CORRUPT EXIT
    THEN
    _SDRR-TEXT-U @ IF
        _SDR-RECORD STREAMS-DRAFT-HEADER-SIZE + _SDRR-TEXT-U @
            UTF8-VALID? 0= IF SDSTORE-S-CORRUPT EXIT THEN
    THEN
    SDSTORE-S-OK ;

: _SDRR-READ-OP  ( -- )
    VFS-CUR _SDRR-OLD-VFS ! -1 _SDRR-HAVE-OLD-VFS !
    _SDRR-STORE @ STREAMS-DRAFT-STORE.VFS @ VFS-USE
    _SDRR-READ-BODY _SDRR-STATUS ! ;

: _SDRR-READ-TRANSACTION  ( -- status )
    0 _SDRR-FD ! 0 _SDRR-HAVE-OLD-VFS !
    SDSTORE-S-IO _SDRR-STATUS !
    ['] _SDRR-READ-OP CATCH IF SDSTORE-S-IO _SDRR-STATUS ! THEN
    _SDRR-CLEANUP IF SDSTORE-S-IO EXIT THEN
    _SDRR-STATUS @ ;

: _SDRR-READ-TRANSACTION-CALL  ( -- status )
    ['] _SDRR-READ-TRANSACTION VFS-TRANSACTION ;

: _SDRR-READ  ( store -- status )
    _SDRR-STORE !
    ['] _SDRR-READ-TRANSACTION-CALL CATCH ?DUP IF
        DROP SDSTORE-S-IO
    THEN ;

\ =====================================================================
\  Transactional load and atomic save
\ =====================================================================

VARIABLE _SDSL-DEST
VARIABLE _SDSL-CAPACITY
VARIABLE _SDSL-STORE
VARIABLE _SDSL-STATUS

: _STREAMS-DRAFT-STORE-LOAD
  ( destination capacity store -- text-u revision status )
    _SDSL-STORE ! _SDSL-CAPACITY ! _SDSL-DEST !
    _SDSL-CAPACITY @ 0<
    _SDSL-CAPACITY @ 0> _SDSL-DEST @ 0= AND OR
    _SDSL-STORE @ STREAMS-DRAFT-STORE-VALID? 0= OR IF
        0 0 SDSTORE-S-INVALID EXIT
    THEN
    _SDSL-STORE @ _STREAMS-DRAFT-STORE-RECOVER DUP IF
        0 0 ROT EXIT
    THEN DROP
    _SDSL-STORE @ _SDRR-READ DUP _SDSL-STATUS !
    _SDSL-STATUS @ SDSTORE-S-OK <> IF
        DROP 0 0 _SDSL-STATUS @ EXIT
    THEN DROP
    _SDRR-TEXT-U @ _SDSL-CAPACITY @ > IF
        0 0 SDSTORE-S-CAPACITY EXIT
    THEN
    _SDRR-TEXT-U @ IF
        _SDR-RECORD STREAMS-DRAFT-HEADER-SIZE +
            _SDSL-DEST @ _SDRR-TEXT-U @ MOVE
    THEN
    _SDRR-TEXT-U @ _SDRR-REVISION @ SDSTORE-S-OK ;

VARIABLE _SDSLP-DEST
VARIABLE _SDSLP-CAPACITY
VARIABLE _SDSLP-STORE

: _STREAMS-DRAFT-STORE-LOAD-CALL  ( -- text-u revision status )
    _SDSLP-DEST @ _SDSLP-CAPACITY @ _SDSLP-STORE @
        _STREAMS-DRAFT-STORE-LOAD ;

: _STREAMS-DRAFT-STORE-LOAD-PUBLIC
  ( destination capacity store -- text-u revision status )
    _SDSLP-STORE ! _SDSLP-CAPACITY ! _SDSLP-DEST !
    ['] _STREAMS-DRAFT-STORE-LOAD-CALL CATCH
    _STREAMS-DRAFT-RECORD-WIPE
    DUP IF THROW THEN DROP ;

' _STREAMS-DRAFT-STORE-LOAD-PUBLIC CONSTANT _sds-load-xt
: STREAMS-DRAFT-STORE-LOAD
  ( destination capacity store -- text-u revision status )
    _sds-load-xt _streams-draft-store-guard WITH-GUARD ;

VARIABLE _SDSS-A
VARIABLE _SDSS-U
VARIABLE _SDSS-REVISION
VARIABLE _SDSS-STORE
VARIABLE _SDSS-LENGTH
VARIABLE _SDSS-STATUS

: _STREAMS-DRAFT-STORE-SAVE  ( text-a text-u revision store -- status )
    _SDSS-STORE ! _SDSS-REVISION ! _SDSS-U ! _SDSS-A !
    _SDSS-STORE @ STREAMS-DRAFT-STORE-VALID? 0= IF
        SDSTORE-S-INVALID EXIT
    THEN
    _SDSS-A @ _SDSS-U @ _SDSS-REVISION @ _STREAMS-DRAFT-ENCODE
        _SDSS-STATUS ! _SDSS-LENGTH !
    _SDSS-STATUS @ IF _SDSS-STATUS @ EXIT THEN
    _SDR-RECORD _SDSS-LENGTH @
        _SDSS-STORE @ STREAMS-DRAFT-STORE.REPLACE VREPL-REPLACE
        DUP _SDSS-STORE @ STREAMS-DRAFT-STORE.LAST-VREPL !
        _SDSTORE-VREPL>STATUS ;

VARIABLE _SDSP-A
VARIABLE _SDSP-U
VARIABLE _SDSP-REVISION
VARIABLE _SDSP-STORE

: _STREAMS-DRAFT-STORE-SAVE-CALL  ( -- status )
    _SDSP-A @ _SDSP-U @ _SDSP-REVISION @ _SDSP-STORE @
        _STREAMS-DRAFT-STORE-SAVE ;

: _STREAMS-DRAFT-STORE-SAVE-PUBLIC  ( text-a text-u revision store -- status )
    _SDSP-STORE ! _SDSP-REVISION ! _SDSP-U ! _SDSP-A !
    ['] _STREAMS-DRAFT-STORE-SAVE-CALL CATCH
    _STREAMS-DRAFT-RECORD-WIPE
    DUP IF THROW THEN DROP ;

' _STREAMS-DRAFT-STORE-SAVE-PUBLIC CONSTANT _sds-save-xt
: STREAMS-DRAFT-STORE-SAVE  ( text-a text-u revision store -- status )
    _sds-save-xt _streams-draft-store-guard WITH-GUARD ;
