\ binimg.f -- relocatable MF64 dictionary images
\
\ Version 2 adds named exports and makes the in-memory image the
\ authority.  File words at the end of this file are compatibility
\ wrappers for the KDOS raw filesystem; VFS users should use the
\ buffer APIs directly.
\
\ Public prefix: IMG-
\ Private prefix: _IMG- / _img- / _IMV- / _imv-

PROVIDED akashic-binimg

\ =====================================================================
\ Format and status values
\ =====================================================================

64 CONSTANT _IMG-HDR-SZ
1  CONSTANT _IMG-VERSION-V1
2  CONSTANT _IMG-VERSION

32 CONSTANT _IMG-EXPORT-ENTRY-SZ
32 CONSTANT _IMG-IMPORT-ENTRY-SZ
16 CONSTANT _IMG-EXPORT-CAP
1024 CONSTANT _IMG-IMPORT-CAP

1024 CONSTANT _IMG-RELOCS-SMALL
8192 CONSTANT _IMG-RELOCS-LARGE
1024 CONSTANT _IMG-EXT-CAP

1 CONSTANT _IMG-FLAG-JIT
2 CONSTANT _IMG-FLAG-XMEM
4 CONSTANT _IMG-FLAG-EXEC
8 CONSTANT _IMG-FLAG-LIB
15 CONSTANT _IMG-FLAG-MASK

0   CONSTANT IMG-E-OK
-1  CONSTANT IMG-E-IO
-2  CONSTANT IMG-E-FORMAT
-3  CONSTANT IMG-E-IMPORT
-5  CONSTANT IMG-E-RELOC
-6  CONSTANT IMG-E-NOEXEC
-7  CONSTANT IMG-E-EXPORT
-8  CONSTANT IMG-E-STATE
-9  CONSTANT IMG-E-CAPACITY
-10 CONSTANT IMG-E-SHORT
-11 CONSTANT IMG-E-NOMEM

\ Old private spellings are retained for source compatibility.
IMG-E-IO       CONSTANT _IMG-ERR-IO
IMG-E-FORMAT   CONSTANT _IMG-ERR-MAGIC
IMG-E-IMPORT   CONSTANT _IMG-ERR-IMPORT
IMG-E-RELOC    CONSTANT _IMG-ERR-RELOC
IMG-E-NOEXEC   CONSTANT _IMG-ERR-NOEXEC

\ Header, version 2 (all integer fields are little-endian):
\   +0  magic "MF64"          +4  u16 version
\   +6  u16 flags             +8  u64 segment size
\   +16 u64 reloc count       +24 u64 export count
\   +32 u64 import count      +40 i64 dictionary-head offset
\   +48 i64 PROVIDED offset   +56 i64 default-entry offset
\ Body:
\   segment, reloc[u64], export[32], import[32]
\ Export: u64 code offset, char name[24] (NUL padded, length 1..23)
\ Import: u64 fixup offset, char name[24] (NUL padded, length 1..23)

\ =====================================================================
\ Build state
\ =====================================================================

VARIABLE _img-mark-base
VARIABLE _img-mark-latest
VARIABLE _img-reloc-buf
VARIABLE _img-reloc-cap
VARIABLE _img-seg-size
VARIABLE _img-chain-head
VARIABLE _img-tail-slot
VARIABLE _img-marked
VARIABLE _img-finalized
VARIABLE _img-build-error

VARIABLE _img-flags
VARIABLE _img-prov-offset
VARIABLE _img-entry-offset

VARIABLE _img-ext-count
VARIABLE _img-import-count
VARIABLE _img-original-relocs
VARIABLE _img-internal-relocs
\ Build-time external (slot,value) pairs.  Validation reuses the first
\ cell of each pair to cache a resolved import XT before loading.
CREATE _img-ext-buf _IMG-EXT-CAP 16 * ALLOT

VARIABLE _img-export-count
CREATE _img-export-buf _IMG-EXPORT-CAP _IMG-EXPORT-ENTRY-SZ * ALLOT

CREATE _img-find-buf 24 ALLOT

\ General private scratch.  The module is serialized by its optional
\ guard, so these cells are deliberately shared instead of using the
\ return stack across deep validation walks.
VARIABLE _img-a0
VARIABLE _img-a1
VARIABLE _img-u0
VARIABLE _img-u1
VARIABLE _img-n0
VARIABLE _img-i0
VARIABLE _img-register-xt
VARIABLE _img-build-dst
VARIABLE _img-build-cap
VARIABLE _img-build-used
VARIABLE _img-request-name
VARIABLE _img-request-len
VARIABLE _img-selected-offset
VARIABLE _img-import-dest
VARIABLE _img-import-entry

: _IMG-LATCH  ( ior -- ior )
    DUP 0<> IF
        _img-build-error @ 0= IF DUP _img-build-error ! THEN
    THEN ;

: _IMG-SAME?  ( a1 u1 a2 u2 -- flag )
    _img-u0 !  _img-a1 !             ( a1 u1 )
    DUP _img-u0 @ <> IF 2DROP 0 EXIT THEN
    DROP _img-a0 !
    _img-u0 @ 0 ?DO
        _img-a0 @ I + C@ _img-a1 @ I + C@ <> IF
            0 UNLOOP EXIT
        THEN
    LOOP
    -1 ;

: _IMG-RANGE-OVERLAP?  ( a1 u1 a2 u2 -- flag )
    _img-u1 ! _img-a1 ! _img-u0 ! _img-a0 !
    _img-a0 @ _img-u0 @ + _img-a1 @ >
    _img-a1 @ _img-u1 @ + _img-a0 @ > AND ;

: _IMG-DICT-ROOM?  ( u -- flag )
    DUP 0< IF DROP 0 EXIT THEN
    ULAND @ IF
        HERE +  U-DICT-BASE @ U-ZONE-SIZE + <= EXIT
    THEN
    HERE + 256 +
    DUP SP@ >= IF DROP 0 EXIT THEN
    HEAP-INIT @ IF HEAP-BASE @ < ELSE DROP -1 THEN ;

: _IMG-RESET-BUILD  ( -- )
    0 _img-finalized !
    0 _img-build-error !
    0 _img-seg-size !
    0 _img-chain-head !
    0 _img-tail-slot !
    0 _img-ext-count !
    0 _img-import-count !
    0 _img-original-relocs !
    0 _img-internal-relocs !
    0 _img-export-count !
    0 _img-flags !
    -1 _img-prov-offset !
    -1 _img-entry-offset ! ;

\ =====================================================================
\ Marking and export registration
\ =====================================================================

: IMG-MARK  ( -- )
    \ A second mark commits the previous undiscarded region and begins
    \ another one, preserving the historical IMG-MARK behaviour.
    0 _RELOC-ACTIVE !
    _IMG-RESET-BUILD
    ULAND @ IF _IMG-RELOCS-LARGE ELSE _IMG-RELOCS-SMALL THEN
    _img-reloc-cap !
    HERE _img-reloc-buf !
    _img-reloc-cap @ 8 * ALLOT
    _img-reloc-buf @ _RELOC-BUF !
    0 _RELOC-COUNT !
    1 _RELOC-ACTIVE !
    HERE _img-mark-base !
    LATEST _img-mark-latest !
    -1 _img-marked ! ;

: IMG-DISCARD  ( -- ior )
    _img-marked @ 0= IF IMG-E-STATE EXIT THEN
    0 _RELOC-ACTIVE !
    _img-mark-latest @ LATEST!
    _img-reloc-buf @ HERE - ALLOT
    0 _img-marked !
    _IMG-RESET-BUILD
    0 ;

: IMG-PROVIDED  ( "token" -- )
    PARSE-NAME
    _img-marked @ 0= IF IMG-E-STATE _IMG-LATCH DROP EXIT THEN
    PN-LEN @ DUP 0= OVER 23 > OR IF
        DROP IMG-E-FORMAT _IMG-LATCH DROP EXIT
    THEN
    HERE _img-mark-base @ - _img-prov-offset !
    DUP >R NAMEBUF HERE R@ CMOVE R> ALLOT
    0 C, ;

: _IMG-SEG-XT>ENTRY  ( xt -- entry | 0 )
    _img-a0 !
    LATEST
    BEGIN DUP _img-mark-latest @ <> WHILE
        DUP 8 + C@ 127 AND OVER 9 + + _img-a0 @ = IF EXIT THEN
        @
    REPEAT
    DROP 0 ;

: _IMG-XT>ENTRY  ( xt -- entry | 0 )
    _img-a0 !
    _img-mark-latest @
    BEGIN DUP WHILE
        DUP 8 + C@ 127 AND OVER 9 + + _img-a0 @ = IF EXIT THEN
        @
    REPEAT ;

\ Compiled calls normally target dictionary XTs and become imports.
\ A small set of BIOS runtime helpers (notably the helper compiled by S")
\ are fixed ABI addresses despite having no reachable dictionary entry.
\ Trusted-local images retain such low addresses verbatim; unknown
\ non-XT references into userland remain rejected.
: _IMG-FIXED-ABI?  ( value -- flag )
    DUP 0> 0= IF DROP 0 EXIT THEN
    U-DICT-BASE @ DUP 0= IF DROP MEM-SIZE THEN < ;

: _IMG-EXPORT-REC  ( i -- a )
    _IMG-EXPORT-ENTRY-SZ * _img-export-buf + ;

: _IMG-EXPORT  ( xt name-a name-u -- ior )
    _img-u0 ! _img-a1 ! _img-a0 !
    _img-marked @ 0= IF IMG-E-STATE EXIT THEN
    _img-u0 @ 0= _img-u0 @ 23 > OR IF IMG-E-EXPORT EXIT THEN
    _img-a0 @ _IMG-SEG-XT>ENTRY DUP 0= IF DROP IMG-E-EXPORT EXIT THEN
    DUP ENTRY>NAME _img-a1 @ _img-u0 @ _IMG-SAME? 0= IF
        DROP IMG-E-EXPORT EXIT
    THEN
    DUP 8 + C@ 127 AND SWAP 9 + + _img-mark-base @ - _img-n0 !

    _img-export-count @ 0 ?DO
        I _IMG-EXPORT-REC 8 + _img-u0 @ _img-a1 @ _img-u0 @ _IMG-SAME? IF
            I _IMG-EXPORT-REC @ _img-n0 @ = IF 0 ELSE IMG-E-EXPORT THEN
            UNLOOP EXIT
        THEN
        I _IMG-EXPORT-REC @ _img-n0 @ = IF
            IMG-E-EXPORT UNLOOP EXIT
        THEN
    LOOP

    _img-export-count @ _IMG-EXPORT-CAP >= IF IMG-E-CAPACITY EXIT THEN
    _img-export-count @ _IMG-EXPORT-REC DUP _IMG-EXPORT-ENTRY-SZ 0 FILL
    DUP _img-n0 @ SWAP !
    8 + _img-a1 @ SWAP _img-u0 @ CMOVE
    1 _img-export-count +!
    _img-flags @ _IMG-FLAG-LIB OR _img-flags !
    0 ;

: IMG-EXPORT  ( xt name-a name-u -- ior )
    _IMG-EXPORT _IMG-LATCH ;

: _IMG-ENTRY-NAMED  ( xt name-a name-u -- ior )
    _img-u0 ! _img-a1 ! _img-register-xt !
    _img-register-xt @ _img-a1 @ _img-u0 @ _IMG-EXPORT DUP 0<> IF EXIT THEN
    DROP
    _img-register-xt @ _img-mark-base @ - _img-entry-offset !
    _img-flags @ _IMG-FLAG-EXEC OR _img-flags !
    0 ;

: IMG-ENTRY-NAMED  ( xt name-a name-u -- ior )
    _IMG-ENTRY-NAMED _IMG-LATCH ;

: IMG-ENTRY  ( xt -- )
    DUP _img-a0 !
    _IMG-SEG-XT>ENTRY DUP 0= IF
        DROP IMG-E-EXPORT _IMG-LATCH DROP EXIT
    THEN
    ENTRY>NAME _img-a0 @ -ROT _IMG-ENTRY-NAMED _IMG-LATCH DROP ;

: IMG-XMEM  ( -- )
    _img-marked @ 0= IF IMG-E-STATE _IMG-LATCH DROP EXIT THEN
    _img-flags @ _IMG-FLAG-XMEM OR _img-flags ! ;

\ =====================================================================
\ Finalization, normalization, and serialization
\ =====================================================================

: _IMG-APPEND-LINK  ( entry -- )
    DUP _img-tail-slot !
    _RELOC-COUNT @ _img-reloc-cap @ >= IF
        DROP IMG-E-CAPACITY _IMG-LATCH DROP EXIT
    THEN
    _RELOC-COUNT @ 8 * _img-reloc-buf @ + !
    1 _RELOC-COUNT +! ;

: _IMG-FINALIZE  ( -- ior )
    _img-marked @ 0= IF IMG-E-STATE EXIT THEN
    _img-finalized @ IF _img-build-error @ EXIT THEN
    0 _RELOC-ACTIVE !
    HERE _img-mark-base @ - _img-seg-size !
    _RELOC-COUNT @ _img-reloc-cap @ > IF
        IMG-E-CAPACITY _IMG-LATCH DROP
    THEN
    LATEST _img-mark-latest @ = IF
        IMG-E-STATE _IMG-LATCH DROP
    ELSE
        LATEST _img-mark-base @ - _img-chain-head !
        LATEST
        BEGIN DUP _img-mark-latest @ <> WHILE
            DUP _IMG-APPEND-LINK
            @
        REPEAT
        DROP
    THEN
    -1 _img-finalized !
    _img-build-error @ ;

: _IMG-RELOC-SLOT  ( i -- abs-slot )
    8 * _img-reloc-buf @ + @ ;

: _IMG-RELOC-DUP?  ( i -- flag )
    DUP _IMG-RELOC-SLOT _img-a0 !
    0 ?DO
        I _IMG-RELOC-SLOT _img-a0 @ = IF -1 UNLOOP EXIT THEN
    LOOP
    0 ;

: _IMG-PRECHECK-RELOCS  ( -- ior )
    0 _img-import-count !
    0 _img-ext-count !
    0 _img-internal-relocs !
    _RELOC-COUNT @ _img-original-relocs !
    _img-seg-size @ 8 < IF IMG-E-RELOC EXIT THEN
    _RELOC-COUNT @ _img-reloc-cap @ > IF IMG-E-CAPACITY EXIT THEN
    _RELOC-COUNT @ 0 ?DO
        I _IMG-RELOC-DUP? IF IMG-E-RELOC UNLOOP EXIT THEN
        I _IMG-RELOC-SLOT DUP _img-mark-base @ <
        OVER _img-mark-base @ _img-seg-size @ + 8 - > OR IF
            DROP IMG-E-RELOC UNLOOP EXIT
        THEN
        DUP @ _img-n0 !
        _img-n0 @ _img-mark-base @ >=
        _img-n0 @ _img-mark-base @ _img-seg-size @ + < AND 0= IF
            _img-ext-count @ _IMG-EXT-CAP >= IF
                DROP IMG-E-CAPACITY UNLOOP EXIT
            THEN
            DUP _img-tail-slot @ = IF
                _img-n0 @ _img-mark-latest @ <> IF
                    DROP IMG-E-RELOC UNLOOP EXIT
                THEN
            ELSE
                _img-n0 @ _IMG-XT>ENTRY DUP 0= IF
                    DROP _img-n0 @ _IMG-FIXED-ABI? 0= IF
                        DROP IMG-E-IMPORT UNLOOP EXIT
                    THEN
                    \ Fixed ABI immediate: retained, not an import.
                ELSE
                    ENTRY>NAME NIP DUP 0= SWAP 23 > OR IF
                        DROP IMG-E-IMPORT UNLOOP EXIT
                    THEN
                    1 _img-import-count +!
                THEN
            THEN
            DROP
            1 _img-ext-count +!
        ELSE
            DROP
            1 _img-internal-relocs +!
        THEN
    LOOP
    _img-import-count @ _IMG-IMPORT-CAP > IF IMG-E-CAPACITY EXIT THEN

    \ Version 2 executable entries are always named exports.
    _img-flags @ _IMG-FLAG-EXEC AND IF
        _img-entry-offset @ -1 = IF IMG-E-NOEXEC EXIT THEN
        0 _img-i0 !
        _img-export-count @ 0 ?DO
            I _IMG-EXPORT-REC @ _img-entry-offset @ = IF -1 _img-i0 ! THEN
        LOOP
        _img-i0 @ 0= IF IMG-E-EXPORT EXIT THEN
    ELSE
        _img-entry-offset @ -1 <> IF IMG-E-FORMAT EXIT THEN
    THEN
    0 ;

: _IMG-PREPARE  ( -- ior )
    _IMG-FINALIZE DUP 0<> IF EXIT THEN DROP
    _img-build-error @ DUP 0<> IF EXIT THEN DROP
    _IMG-PRECHECK-RELOCS DUP 0<> IF _IMG-LATCH THEN ;

: _IMG-IMAGE-SIZE  ( -- u )
    _IMG-HDR-SZ _img-seg-size @ +
    _img-internal-relocs @ 8 * +
    _img-export-count @ _IMG-EXPORT-ENTRY-SZ * +
    _img-import-count @ _IMG-IMPORT-ENTRY-SZ * + ;

: IMG-BUFFER-MAX  ( -- max-u ior )
    _IMG-PREPARE DUP 0<> IF 0 SWAP EXIT THEN
    DROP _IMG-IMAGE-SIZE 0 ;

: _IMG-RECORD-EXT  ( abs-slot value -- )
    _img-ext-count @ 16 * _img-ext-buf + >R
    SWAP _img-mark-base @ - R@ !
    R> 8 + !
    1 _img-ext-count +! ;

: _IMG-NORMALIZE  ( -- )
    0 _img-ext-count !
    0 _img-i0 !
    _img-original-relocs @ 0 ?DO
        I _IMG-RELOC-SLOT DUP @ _img-n0 !
        _img-n0 @ _img-mark-base @ >=
        _img-n0 @ _img-mark-base @ _img-seg-size @ + < AND IF
            DUP _img-n0 @ _img-mark-base @ - SWAP !
            _img-mark-base @ -
            _img-i0 @ 8 * _img-reloc-buf @ + !
            1 _img-i0 +!
        ELSE
            DUP _img-n0 @ _IMG-RECORD-EXT
            DUP _img-tail-slot @ = IF
                0 SWAP !
            ELSE
                _img-n0 @ _IMG-XT>ENTRY IF 0 SWAP ! ELSE DROP THEN
            THEN
        THEN
    LOOP
    _img-i0 @ DUP _img-internal-relocs ! _RELOC-COUNT ! ;

: _IMG-DENORMALIZE  ( -- )
    _img-internal-relocs @ 0 ?DO
        I 8 * _img-reloc-buf @ + DUP @ _img-mark-base @ + _img-a0 !
        _img-a0 @ DUP @ _img-mark-base @ + SWAP !
        _img-a0 @ SWAP !
    LOOP
    _img-ext-count @ 0 ?DO
        I 16 * _img-ext-buf + DUP @ _img-mark-base @ + _img-a0 !
        DUP 8 + @ _img-a0 @ !
        _img-a0 @
        _img-internal-relocs @ I + 8 * _img-reloc-buf @ + !
        DROP
    LOOP
    _img-internal-relocs @ _img-ext-count @ + _RELOC-COUNT ! ;

VARIABLE _img-out-base
VARIABLE _img-out-size
VARIABLE _img-out-rel
VARIABLE _img-out-exp
VARIABLE _img-out-imp

: _IMG-WRITE-HEADER  ( -- )
    _img-out-base @ DUP
    77 OVER C! 70 OVER 1 + C! 54 OVER 2 + C! 52 OVER 3 + C!
    _IMG-VERSION OVER 4 + W!
    _img-flags @ OVER 6 + W!
    _img-seg-size @ OVER 8 + !
    _img-internal-relocs @ OVER 16 + !
    _img-export-count @ OVER 24 + !
    _img-import-count @ OVER 32 + !
    _img-chain-head @ OVER 40 + !
    _img-prov-offset @ OVER 48 + !
    _img-entry-offset @ SWAP 56 + !
    DROP ;

: _IMG-WRITE-IMPORTS  ( -- )
    0 _img-i0 !
    _img-ext-count @ 0 ?DO
        I 16 * _img-ext-buf + DUP @ _img-mark-base @ +
        _img-tail-slot @ <> IF
            DUP 8 + @ _IMG-XT>ENTRY DUP IF
                _img-import-entry !
                _img-i0 @ _IMG-IMPORT-ENTRY-SZ * _img-out-imp @ +
                _img-import-dest !
                DUP @ _img-import-dest @ !
                DROP
                _img-import-entry @ ENTRY>NAME
                _img-import-dest @ 8 + SWAP CMOVE
                1 _img-i0 +!
            ELSE
                DROP DROP
            THEN
        ELSE
            DROP
        THEN
    LOOP ;

: _IMG-SERIALIZE-V2  ( dst used -- )
    _img-out-size ! _img-out-base !
    _img-out-base @ _img-out-size @ 0 FILL
    _img-out-base @ _IMG-HDR-SZ + _img-seg-size @ + _img-out-rel !
    _img-out-rel @ _img-internal-relocs @ 8 * + _img-out-exp !
    _img-out-exp @ _img-export-count @ _IMG-EXPORT-ENTRY-SZ * +
    _img-out-imp !
    _IMG-WRITE-HEADER
    _img-mark-base @ _img-out-base @ _IMG-HDR-SZ +
    _img-seg-size @ CMOVE
    _img-internal-relocs @ 0<> IF
        _img-reloc-buf @ _img-out-rel @ _img-internal-relocs @ 8 * CMOVE
    THEN
    _img-export-count @ 0<> IF
        _img-export-buf _img-out-exp @
        _img-export-count @ _IMG-EXPORT-ENTRY-SZ * CMOVE
    THEN
    _IMG-WRITE-IMPORTS ;

\ =====================================================================
\ Non-mutating memory validator
\ =====================================================================

VARIABLE _imv-image
VARIABLE _imv-size
VARIABLE _imv-version
VARIABLE _imv-flags
VARIABLE _imv-seg
VARIABLE _imv-nrel
VARIABLE _imv-nexp
VARIABLE _imv-nimp
VARIABLE _imv-head
VARIABLE _imv-prov
VARIABLE _imv-entry
VARIABLE _imv-seg-base
VARIABLE _imv-rel-base
VARIABLE _imv-exp-base
VARIABLE _imv-imp-base
VARIABLE _imv-used
VARIABLE _imv-rem
VARIABLE _imv-name-len
VARIABLE _imv-name-error
VARIABLE _imv-cur
VARIABLE _imv-guard
VARIABLE _imv-target-off
VARIABLE _imv-target-name
VARIABLE _imv-target-len
VARIABLE _imv-loop
VARIABLE _imv-inner
VARIABLE _imv-scan
VARIABLE _imv-rec
VARIABLE _imv-name-a
VARIABLE _imv-name-u

: _IMV-NAME  ( name24 -- len ior )
    _img-a0 !
    -1 _imv-name-len !
    0 _imv-name-error !
    24 0 DO
        _img-a0 @ I + C@ DUP 0= IF
            DROP _imv-name-len @ -1 = IF I _imv-name-len ! THEN
        ELSE
            DROP _imv-name-len @ -1 <> IF IMG-E-FORMAT _imv-name-error ! THEN
        THEN
    LOOP
    _imv-name-error @ DUP 0<> IF 0 SWAP EXIT THEN DROP
    _imv-name-len @ DUP 1 < OVER 23 > OR IF DROP 0 IMG-E-FORMAT EXIT THEN
    0 ;

: _IMV-FIND  ( name-a name-u -- xt ior )
    DUP 0= OVER 23 > OR IF 2DROP 0 IMG-E-IMPORT EXIT THEN
    DUP _img-find-buf C!
    _img-find-buf 1+ SWAP CMOVE
    _img-find-buf FIND IF 0 ELSE DROP 0 IMG-E-IMPORT THEN ;

: _IMV-BOUNDS  ( need -- flag )
    DUP 0< IF DROP 0 EXIT THEN
    _imv-rem @ <= ;

: _IMV-CONSUME  ( u -- )
    NEGATE _imv-rem +! ;

: _IMV-PARSE  ( image-a image-u -- ior )
    _imv-size ! _imv-image !
    _imv-image @ 0= _imv-size @ _IMG-HDR-SZ < OR IF IMG-E-FORMAT EXIT THEN
    _imv-image @ _imv-size @ + _imv-image @ < IF IMG-E-FORMAT EXIT THEN
    _imv-image @ C@ 77 <>
    _imv-image @ 1+ C@ 70 <> OR
    _imv-image @ 2 + C@ 54 <> OR
    _imv-image @ 3 + C@ 52 <> OR IF IMG-E-FORMAT EXIT THEN
    _imv-image @ 4 + W@ DUP _IMG-VERSION-V1 < OVER _IMG-VERSION > OR IF
        DROP IMG-E-FORMAT EXIT
    THEN _imv-version !
    _imv-image @ 6 + W@ DUP _IMG-FLAG-MASK AND OVER <> IF
        DROP IMG-E-FORMAT EXIT
    THEN _imv-flags !
    _imv-image @ 8 + @ _imv-seg !
    _imv-image @ 16 + @ _imv-nrel !
    _imv-image @ 24 + @ _imv-nexp !
    _imv-image @ 32 + @ _imv-nimp !
    _imv-image @ 40 + @ _imv-head !
    _imv-image @ 48 + @ _imv-prov !
    _imv-image @ 56 + @ _imv-entry !

    _imv-seg @ 0< _imv-nrel @ 0< OR _imv-nexp @ 0< OR
    _imv-nimp @ 0< OR IF IMG-E-FORMAT EXIT THEN
    _imv-nrel @ _IMG-RELOCS-LARGE > IF IMG-E-CAPACITY EXIT THEN
    _imv-nexp @ _IMG-EXPORT-CAP > IF IMG-E-CAPACITY EXIT THEN
    _imv-nimp @ _IMG-IMPORT-CAP > IF IMG-E-CAPACITY EXIT THEN
    _imv-version @ _IMG-VERSION-V1 = _imv-nexp @ 0<> AND IF
        IMG-E-FORMAT EXIT
    THEN

    _imv-size @ _IMG-HDR-SZ - _imv-rem !
    _imv-seg @ _IMV-BOUNDS 0= IF IMG-E-SHORT EXIT THEN
    _imv-image @ _IMG-HDR-SZ + _imv-seg-base !
    _imv-seg @ _IMV-CONSUME

    _imv-nrel @ 8 * DUP _IMV-BOUNDS 0= IF DROP IMG-E-SHORT EXIT THEN
    _imv-seg-base @ _imv-seg @ + _imv-rel-base !
    _IMV-CONSUME

    _imv-version @ _IMG-VERSION = IF
        _imv-nexp @ _IMG-EXPORT-ENTRY-SZ *
    ELSE 0 THEN
    DUP _IMV-BOUNDS 0= IF DROP IMG-E-SHORT EXIT THEN
    _imv-rel-base @ _imv-nrel @ 8 * + _imv-exp-base !
    _IMV-CONSUME

    _imv-nimp @ _IMG-IMPORT-ENTRY-SZ *
    DUP _IMV-BOUNDS 0= IF DROP IMG-E-SHORT EXIT THEN
    _imv-exp-base @
    _imv-version @ _IMG-VERSION = IF
        _imv-nexp @ _IMG-EXPORT-ENTRY-SZ * +
    THEN _imv-imp-base !
    _IMV-CONSUME

    _imv-size @ _imv-rem @ - _imv-used !
    _imv-rem @ 0<> IF IMG-E-FORMAT EXIT THEN
    0 ;

: _IMV-RELOC-OFF  ( i -- off )
    8 * _imv-rel-base @ + @ ;

: _IMV-IMPORT-REC  ( i -- a )
    _IMG-IMPORT-ENTRY-SZ * _imv-imp-base @ + ;

: _IMV-EXPORT-REC  ( i -- a )
    _IMG-EXPORT-ENTRY-SZ * _imv-exp-base @ + ;

: _IMV-IS-RELOC?  ( slot-off -- flag )
    _img-n0 !
    0 _imv-scan !
    BEGIN _imv-scan @ _imv-nrel @ < WHILE
        _imv-scan @ _IMV-RELOC-OFF _img-n0 @ = IF -1 EXIT THEN
        1 _imv-scan +!
    REPEAT 0 ;

: _IMV-IS-IMPORT?  ( slot-off -- flag )
    _img-n0 !
    0 _imv-scan !
    BEGIN _imv-scan @ _imv-nimp @ < WHILE
        _imv-scan @ _IMV-IMPORT-REC @ _img-n0 @ = IF -1 EXIT THEN
        1 _imv-scan +!
    REPEAT 0 ;

: _IMV-VALIDATE-RELOCS  ( -- ior )
    _imv-nrel @ 0= IF 0 EXIT THEN
    _imv-seg @ 8 < IF IMG-E-RELOC EXIT THEN
    0 _imv-loop !
    BEGIN _imv-loop @ _imv-nrel @ < WHILE
        _imv-loop @ _IMV-RELOC-OFF DUP 0< IF DROP IMG-E-RELOC EXIT THEN
        DUP _imv-seg @ 8 - > IF DROP IMG-E-RELOC EXIT THEN
        _imv-seg-base @ + @ DUP 0< SWAP _imv-seg @ >= OR IF
            IMG-E-RELOC EXIT
        THEN
        0 _imv-inner !
        BEGIN _imv-inner @ _imv-loop @ < WHILE
            _imv-loop @ _IMV-RELOC-OFF
            _imv-inner @ _IMV-RELOC-OFF = IF
                IMG-E-RELOC EXIT
            THEN
            1 _imv-inner +!
        REPEAT
        1 _imv-loop +!
    REPEAT 0 ;

: _IMV-VALIDATE-IMPORTS  ( -- ior )
    _imv-seg @ 8 < _imv-nimp @ 0<> AND IF IMG-E-RELOC EXIT THEN
    0 _imv-loop !
    BEGIN _imv-loop @ _imv-nimp @ < WHILE
        _imv-loop @ _IMV-IMPORT-REC DUP _imv-rec ! @ _img-n0 !
        _img-n0 @ 0< _img-n0 @ _imv-seg @ 8 - > OR IF
            IMG-E-RELOC EXIT
        THEN
        _img-n0 @ _IMV-IS-RELOC? IF IMG-E-RELOC EXIT THEN
        _imv-seg-base @ _img-n0 @ + @ 0<> IF
            IMG-E-RELOC EXIT
        THEN
        _imv-rec @ 8 + DUP _imv-name-a ! _IMV-NAME
        DUP 0<> IF NIP EXIT THEN
        DROP _imv-name-u !
        _imv-name-a @ _imv-name-u @ _IMV-FIND
        DUP 0<> IF NIP EXIT THEN
        DROP
        _imv-loop @ 8 * _img-ext-buf + !

        0 _imv-inner !
        BEGIN _imv-inner @ _imv-loop @ < WHILE
            _imv-loop @ _IMV-IMPORT-REC @
            _imv-inner @ _IMV-IMPORT-REC @ = IF
                IMG-E-RELOC EXIT
            THEN
            1 _imv-inner +!
        REPEAT
        1 _imv-loop +!
    REPEAT 0 ;

: _IMV-VALIDATE-EXPORTS  ( -- ior )
    _imv-version @ _IMG-VERSION-V1 = IF 0 EXIT THEN
    0 _imv-loop !
    BEGIN _imv-loop @ _imv-nexp @ < WHILE
        _imv-loop @ _IMV-EXPORT-REC DUP _imv-rec ! @
        DUP 0< SWAP _imv-seg @ >= OR IF IMG-E-EXPORT EXIT THEN
        _imv-rec @ 8 + DUP _imv-name-a ! _IMV-NAME
        DUP 0<> IF NIP EXIT THEN
        DROP _imv-name-u !

        0 _imv-inner !
        BEGIN _imv-inner @ _imv-loop @ < WHILE
            _imv-loop @ _IMV-EXPORT-REC @
            _imv-inner @ _IMV-EXPORT-REC @ = IF IMG-E-EXPORT EXIT THEN
            _imv-inner @ _IMV-EXPORT-REC 8 + DUP _IMV-NAME DROP
            _imv-name-a @ _imv-name-u @ _IMG-SAME? IF
                IMG-E-EXPORT EXIT
            THEN
            1 _imv-inner +!
        REPEAT
        1 _imv-loop +!
    REPEAT 0 ;

: _IMV-ENTRY-AT  ( off -- entry-a name-u code-off ior )
    _img-n0 !
    _imv-seg @ 10 < IF 0 0 0 IMG-E-FORMAT EXIT THEN
    _img-n0 @ 0< _img-n0 @ _imv-seg @ 9 - > OR IF
        0 0 0 IMG-E-FORMAT EXIT
    THEN
    _imv-seg-base @ _img-n0 @ + DUP 8 + C@ 127 AND _img-u0 !
    _img-u0 @ 0= IF 0 0 0 IMG-E-FORMAT EXIT THEN
    _img-n0 @ 9 + _img-u0 @ + DUP _imv-seg @ >= IF
        2DROP 0 0 0 IMG-E-FORMAT EXIT
    THEN
    _img-u0 @ SWAP 0 ;

: _IMV-VALIDATE-CHAIN  ( -- ior )
    _imv-head @ _imv-cur !
    _imv-seg @ 9 / 1+ _imv-guard !
    BEGIN
        _imv-guard @ 0= IF IMG-E-FORMAT EXIT THEN
        -1 _imv-guard +!
        _imv-cur @ _IMV-ENTRY-AT DUP 0<> IF
            >R 2DROP DROP R> EXIT
        THEN
        DROP 2DROP                    ( entry-a )
        _imv-cur @ _IMV-IS-IMPORT? IF DROP IMG-E-RELOC EXIT THEN
        _imv-cur @ _IMV-IS-RELOC? IF
            @ DUP 0< OVER _imv-cur @ >= OR IF DROP IMG-E-FORMAT EXIT THEN
            _imv-cur !
        ELSE
            @ 0<> IF IMG-E-FORMAT EXIT THEN
            0 EXIT
        THEN
    AGAIN ;

: _IMV-BINDING?  ( code-off name-a name-u -- flag )
    _imv-target-len ! _imv-target-name ! _imv-target-off !
    _imv-head @ _imv-cur !
    _imv-seg @ 9 / 1+ _imv-guard !
    BEGIN _imv-guard @ 0<> WHILE
        -1 _imv-guard +!
        _imv-cur @ _IMV-ENTRY-AT DUP 0<> IF
            DROP 2DROP DROP 0 EXIT
        THEN
        DROP                           ( entry-a name-u code-off )
        DUP _imv-target-off @ = IF
            DROP OVER 9 + SWAP
            _imv-target-name @ _imv-target-len @ _IMG-SAME? NIP EXIT
        THEN
        2DROP                          ( entry-a )
        _imv-cur @ _IMV-IS-RELOC? IF
            @ _imv-cur !
        ELSE
            DROP 0 EXIT
        THEN
    REPEAT 0 ;

: _IMV-CODE-REACHABLE?  ( code-off -- flag )
    _imv-target-off !
    _imv-head @ _imv-cur !
    _imv-seg @ 9 / 1+ _imv-guard !
    BEGIN _imv-guard @ 0<> WHILE
        -1 _imv-guard +!
        _imv-cur @ _IMV-ENTRY-AT DUP 0<> IF
            DROP 2DROP DROP 0 EXIT
        THEN
        DROP                           ( entry-a name-u code-off )
        _imv-target-off @ = IF 2DROP -1 EXIT THEN
        2DROP
        _imv-cur @ _IMV-IS-RELOC? IF @ _imv-cur ! ELSE DROP 0 EXIT THEN
    REPEAT 0 ;

: _IMV-VALIDATE-BINDINGS  ( -- ior )
    _imv-version @ _IMG-VERSION = IF
        _imv-nexp @ 0 ?DO
            I _IMV-EXPORT-REC DUP @ SWAP 8 + DUP _IMV-NAME
            DUP 0<> IF >R 2DROP DROP R> UNLOOP EXIT THEN
            DROP _IMV-BINDING? 0= IF IMG-E-EXPORT UNLOOP EXIT THEN
        LOOP
    THEN

    _imv-flags @ _IMG-FLAG-EXEC AND IF
        _imv-entry @ -1 = IF IMG-E-NOEXEC EXIT THEN
        _imv-entry @ 0< _imv-entry @ _imv-seg @ >= OR IF
            IMG-E-RELOC EXIT
        THEN
        _imv-version @ _IMG-VERSION = IF
            0 _img-i0 !
            _imv-nexp @ 0 ?DO
                I _IMV-EXPORT-REC @ _imv-entry @ = IF -1 _img-i0 ! THEN
            LOOP
            _img-i0 @ 0= IF IMG-E-EXPORT EXIT THEN
        ELSE
            _imv-entry @ _IMV-CODE-REACHABLE? 0= IF IMG-E-RELOC EXIT THEN
        THEN
    ELSE
        _imv-entry @ -1 <> IF IMG-E-FORMAT EXIT THEN
    THEN

    _imv-version @ _IMG-VERSION = IF
        _imv-nexp @ 0<> _imv-flags @ _IMG-FLAG-LIB AND 0= AND IF
            IMG-E-FORMAT EXIT
        THEN
        _imv-nexp @ 0= _imv-flags @ _IMG-FLAG-LIB AND 0<> AND IF
            IMG-E-FORMAT EXIT
        THEN
    THEN
    0 ;

: _IMV-VALIDATE-PROVIDED  ( -- ior )
    _imv-prov @ -1 = IF 0 EXIT THEN
    _imv-prov @ 0< _imv-prov @ _imv-seg @ >= OR IF IMG-E-FORMAT EXIT THEN
    _imv-seg @ _imv-prov @ - _img-u0 !
    _imv-seg-base @ _imv-prov @ + _img-a0 !
    _img-u0 @ 0 ?DO
        _img-a0 @ I + C@ 0= IF
            I 0= IF IMG-E-FORMAT ELSE 0 THEN UNLOOP EXIT
        THEN
    LOOP
    IMG-E-FORMAT ;

: _IMG-VERIFY-MEM  ( image-a image-u -- ior )
    _IMV-PARSE DUP 0<> IF EXIT THEN DROP
    _IMV-VALIDATE-RELOCS DUP 0<> IF EXIT THEN DROP
    _IMV-VALIDATE-IMPORTS DUP 0<> IF EXIT THEN DROP
    _IMV-VALIDATE-EXPORTS DUP 0<> IF EXIT THEN DROP
    _IMV-VALIDATE-CHAIN DUP 0<> IF EXIT THEN DROP
    _IMV-VALIDATE-BINDINGS DUP 0<> IF EXIT THEN DROP
    _IMV-VALIDATE-PROVIDED ;

: IMG-VERIFY-MEM  ( image-a image-u -- ior )
    _IMG-VERIFY-MEM ;

: IMG-BUILD-INTO  ( dst cap -- used ior )
    _img-build-cap ! _img-build-dst !
    _IMG-PREPARE DUP 0<> IF 0 SWAP EXIT THEN DROP
    _IMG-IMAGE-SIZE _img-build-used !
    _img-build-dst @ 0=
    _img-build-cap @ _img-build-used @ < OR IF 0 IMG-E-CAPACITY EXIT THEN
    _img-build-dst @ _img-build-used @ + _img-build-dst @ < IF
        0 IMG-E-CAPACITY EXIT
    THEN
    _img-build-dst @ _img-build-used @
    _img-reloc-buf @ HERE _img-reloc-buf @ -
    _IMG-RANGE-OVERLAP? IF 0 IMG-E-STATE EXIT THEN

    _IMG-NORMALIZE
    _img-build-dst @ _img-build-used @ _IMG-SERIALIZE-V2
    _IMG-DENORMALIZE
    _img-build-dst @ _img-build-used @ _IMG-VERIFY-MEM
    DUP 0<> IF 0 SWAP EXIT THEN
    DROP _img-build-used @ 0 ;

\ =====================================================================
\ Verified memory loading and exact export lookup
\ =====================================================================

VARIABLE _img-load-base
VARIABLE _img-load-flags
VARIABLE _img-load-seg
VARIABLE _img-load-nrel
VARIABLE _img-load-nimp
VARIABLE _img-load-head
VARIABLE _img-load-prov
VARIABLE _img-load-entry

: _IMG-EXPORT-FIND-PARSED  ( name-a name-u -- offset ior )
    _img-request-len ! _img-request-name !
    _imv-version @ _IMG-VERSION <> IF 0 IMG-E-EXPORT EXIT THEN
    _img-request-len @ 0= _img-request-len @ 23 > OR IF
        0 IMG-E-EXPORT EXIT
    THEN
    _imv-nexp @ 0 ?DO
        I _IMV-EXPORT-REC DUP 8 + DUP _IMV-NAME
        DUP 0<> IF >R 2DROP DROP R> UNLOOP 0 SWAP EXIT THEN
        DROP _img-request-name @ _img-request-len @ _IMG-SAME? IF
            @ 0 UNLOOP EXIT
        THEN
        DROP
    LOOP
    0 IMG-E-EXPORT ;

: IMG-EXPORT-FIND  ( image-a image-u name-a name-u -- offset ior )
    _img-request-len ! _img-request-name ! _img-u1 ! _img-a1 !
    _img-a1 @ _img-u1 @ _IMG-VERIFY-MEM DUP 0<> IF 0 SWAP EXIT THEN DROP
    _img-request-name @ _img-request-len @ _IMG-EXPORT-FIND-PARSED ;

: _IMG-RELOCATE  ( reloc-a count base -- )
    _img-a0 ! _img-n0 ! _img-a1 !
    _img-n0 @ 0 ?DO
        _img-a1 @ I 8 * + @ _img-a0 @ + DUP @ _img-a0 @ + SWAP !
    LOOP ;

: _IMG-PATCH-IMPORTS  ( -- )
    _imv-nimp @ 0 ?DO
        I _IMV-IMPORT-REC @ _img-load-base @ +
        I 8 * _img-ext-buf + @ SWAP !
    LOOP ;

: _IMG-SPLICE-VALID  ( -- )
    _img-load-base @ _imv-head @ + DUP _img-a0 !
    BEGIN DUP @ DUP WHILE NIP REPEAT DROP
    LATEST SWAP !
    _img-a0 @ LATEST! ;

: _IMG-STRLEN  ( c-addr max -- len )
    SWAP OVER 0 ?DO
        DUP I + C@ 0= IF 2DROP I UNLOOP EXIT THEN
    LOOP DROP ;

: _IMG-REGISTER-PROVIDED  ( -- )
    _imv-prov @ -1 = IF EXIT THEN
    NAMEBUF 24 0 FILL
    _img-load-base @ _imv-prov @ + DUP
    _imv-seg @ _imv-prov @ - 23 MIN _IMG-STRLEN
    NAMEBUF SWAP CMOVE
    _MOD-MARK ;

: _IMG-LOAD-VERIFIED  ( -- base ior )
    _imv-flags @ _IMG-FLAG-XMEM AND IF
        _imv-seg @ XMEM-ALLOT? DUP 0<> IF
            >R DROP 0 R> DROP IMG-E-NOMEM EXIT
        THEN
        DROP _img-load-base !
    ELSE
        _imv-seg @ _IMG-DICT-ROOM? 0= IF 0 IMG-E-NOMEM EXIT THEN
        HERE _img-load-base !
    THEN

    _imv-seg-base @ _img-load-base @ _imv-seg @ MOVE
    _imv-flags @ _IMG-FLAG-XMEM AND 0= IF _imv-seg @ ALLOT THEN
    _imv-nrel @ 0<> IF
        _imv-rel-base @ _imv-nrel @ _img-load-base @ _IMG-RELOCATE
    THEN
    _IMG-PATCH-IMPORTS
    _IMG-SPLICE-VALID
    _IMG-REGISTER-PROVIDED

    _imv-flags @ _img-load-flags !
    _imv-seg @ _img-load-seg !
    _imv-nrel @ _img-load-nrel !
    _imv-nimp @ _img-load-nimp !
    _imv-head @ _img-load-head !
    _imv-prov @ _img-load-prov !
    _imv-entry @ _img-load-entry !
    _img-load-base @ 0 ;

: IMG-LOAD-MEM  ( image-a image-u -- ior )
    _IMG-VERIFY-MEM DUP 0<> IF EXIT THEN DROP
    _IMG-LOAD-VERIFIED NIP ;

: IMG-LOAD-EXEC-MEM  ( image-a image-u -- xt ior )
    _IMG-VERIFY-MEM DUP 0<> IF 0 SWAP EXIT THEN DROP
    _imv-flags @ _IMG-FLAG-EXEC AND 0= IF 0 IMG-E-NOEXEC EXIT THEN
    _imv-entry @ _img-selected-offset !
    _IMG-LOAD-VERIFIED DUP 0<> IF NIP 0 SWAP EXIT THEN
    DROP _img-selected-offset @ + 0 ;

: IMG-LOAD-EXPORT  ( image-a image-u name-a name-u -- xt ior )
    _img-request-len ! _img-request-name ! _img-u1 ! _img-a1 !
    _img-a1 @ _img-u1 @ _IMG-VERIFY-MEM DUP 0<> IF 0 SWAP EXIT THEN DROP
    _img-request-name @ _img-request-len @ _IMG-EXPORT-FIND-PARSED
    DUP 0<> IF
        >R DROP 0 R> EXIT
    THEN
    DROP _img-selected-offset !
    _IMG-LOAD-VERIFIED DUP 0<> IF NIP 0 SWAP EXIT THEN
    DROP _img-selected-offset @ + 0 ;

\ =====================================================================
\ Optional guard: memory/state APIs only.  Raw file operations below
\ never retain a guard across KDOS I/O.
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _binimg-guard

' IMG-MARK            CONSTANT _img-mark-xt
' IMG-DISCARD         CONSTANT _img-discard-xt
' IMG-PROVIDED        CONSTANT _img-provided-xt
' IMG-EXPORT          CONSTANT _img-export-xt
' IMG-ENTRY-NAMED     CONSTANT _img-entry-named-xt
' IMG-ENTRY           CONSTANT _img-entry-xt
' IMG-XMEM            CONSTANT _img-xmem-xt
' IMG-BUFFER-MAX      CONSTANT _img-buffer-max-xt
' IMG-BUILD-INTO      CONSTANT _img-build-into-xt
' IMG-VERIFY-MEM      CONSTANT _img-verify-mem-xt
' IMG-EXPORT-FIND     CONSTANT _img-export-find-xt
' IMG-LOAD-MEM        CONSTANT _img-load-mem-xt
' IMG-LOAD-EXEC-MEM   CONSTANT _img-load-exec-mem-xt
' IMG-LOAD-EXPORT     CONSTANT _img-load-export-xt

: IMG-MARK            _img-mark-xt _binimg-guard WITH-GUARD ;
: IMG-DISCARD         _img-discard-xt _binimg-guard WITH-GUARD ;
: IMG-PROVIDED        _img-provided-xt _binimg-guard WITH-GUARD ;
: IMG-EXPORT          _img-export-xt _binimg-guard WITH-GUARD ;
: IMG-ENTRY-NAMED     _img-entry-named-xt _binimg-guard WITH-GUARD ;
: IMG-ENTRY           _img-entry-xt _binimg-guard WITH-GUARD ;
: IMG-XMEM            _img-xmem-xt _binimg-guard WITH-GUARD ;
: IMG-BUFFER-MAX      _img-buffer-max-xt _binimg-guard WITH-GUARD ;
: IMG-BUILD-INTO      _img-build-into-xt _binimg-guard WITH-GUARD ;
: IMG-VERIFY-MEM      _img-verify-mem-xt _binimg-guard WITH-GUARD ;
: IMG-EXPORT-FIND     _img-export-find-xt _binimg-guard WITH-GUARD ;
: IMG-LOAD-MEM        _img-load-mem-xt _binimg-guard WITH-GUARD ;
: IMG-LOAD-EXEC-MEM   _img-load-exec-mem-xt _binimg-guard WITH-GUARD ;
: IMG-LOAD-EXPORT     _img-load-export-xt _binimg-guard WITH-GUARD ;
[THEN] [THEN]

\ =====================================================================
\ Legacy KDOS raw-file wrappers
\ =====================================================================

VARIABLE _img-file-fd
VARIABLE _img-file-size
VARIABLE _img-file-buffer
VARIABLE _img-file-actual
VARIABLE _img-file-result
VARIABLE _img-file-status

: _IMG-READ-FILE  ( "filename" -- image-a image-u ior )
    PARSE-NAME
    FIND-BY-NAME DUP -1 = IF DROP 0 0 IMG-E-IO EXIT THEN
    OPEN-BY-SLOT DUP 0= IF DROP 0 0 IMG-E-IO EXIT THEN
    _img-file-fd !
    _img-file-fd @ FSIZE DUP _img-file-size !
    _IMG-HDR-SZ < IF _img-file-fd @ FCLOSE 0 0 IMG-E-SHORT EXIT THEN
    _img-file-size @ DMA-ALLOCATE DUP 0<> IF
        2DROP
        _img-file-fd @ FCLOSE 0 0 IMG-E-NOMEM EXIT
    THEN
    DROP _img-file-buffer !
    _img-file-buffer @ _img-file-size @ _img-file-fd @ FREAD
    _img-file-actual !
    _img-file-fd @ FCLOSE
    _img-file-actual @ _img-file-size @ <> IF
        _img-file-buffer @ DMA-FREE 0 0 IMG-E-SHORT EXIT
    THEN
    _img-file-buffer @ _img-file-size @ 0 ;

: IMG-SAVE  ( "filename" -- ior )
    IMG-BUFFER-MAX DUP 0<> IF NIP EXIT THEN DROP _img-file-size !
    PARSE-NAME
    FIND-BY-NAME DUP -1 = IF DROP IMG-E-IO EXIT THEN
    OPEN-BY-SLOT DUP 0= IF DROP IMG-E-IO EXIT THEN
    _img-file-fd !
    _img-file-fd @ F.MAX SECTOR * _img-file-size @ < IF
        _img-file-fd @ FCLOSE IMG-E-CAPACITY EXIT
    THEN

    _img-file-size @ DMA-ALLOCATE DUP 0<> IF
        >R DROP _img-file-fd @ FCLOSE R> DROP IMG-E-NOMEM EXIT
    THEN
    DROP _img-file-buffer !
    _img-file-buffer @ _img-file-size @ IMG-BUILD-INTO
    DUP 0<> IF
        _img-file-status ! DROP
        _img-file-buffer @ DMA-FREE
        _img-file-fd @ FCLOSE
        _img-file-status @ EXIT
    THEN
    DROP _img-file-size !

    0 _img-file-fd @ FTRUNCATE
    0 _img-file-fd @ FSEEK
    _img-file-buffer @ _img-file-size @ _img-file-fd @ FWRITE
    _img-file-fd @ F.CURSOR _img-file-size @ =
    _img-file-fd @ FSIZE _img-file-size @ = AND _img-i0 !
    _img-file-fd @ FFLUSH
    _img-file-fd @ FCLOSE
    _img-file-buffer @ DMA-FREE
    _img-i0 @ IF 0 ELSE IMG-E-IO THEN ;

: IMG-SAVE-EXEC  ( xt "filename" -- ior )
    IMG-ENTRY IMG-SAVE ;

: IMG-LOAD  ( "filename" -- ior )
    _IMG-READ-FILE DUP 0<> IF >R 2DROP R> EXIT THEN
    DROP IMG-LOAD-MEM _img-file-status !
    _img-file-buffer @ DMA-FREE
    _img-file-status @ ;

: IMG-LOAD-EXEC  ( "filename" -- xt ior )
    _IMG-READ-FILE DUP 0<> IF >R 2DROP 0 R> EXIT THEN
    DROP IMG-LOAD-EXEC-MEM
    _img-file-status ! _img-file-result !
    _img-file-buffer @ DMA-FREE
    _img-file-result @ _img-file-status @ ;

: IMG-VERIFY  ( "filename" -- ior )
    _IMG-READ-FILE DUP 0<> IF >R 2DROP R> EXIT THEN
    DROP IMG-VERIFY-MEM _img-file-status !
    _img-file-buffer @ DMA-FREE
    _img-file-status @ ;

: IMG-INFO  ( "filename" -- )
    _IMG-READ-FILE DUP 0<> IF >R 2DROP R> . EXIT THEN
    DROP 2DUP IMG-VERIFY-MEM DUP 0<> IF
        >R 2DROP _img-file-buffer @ DMA-FREE R> . EXIT
    THEN DROP
    2DROP
    ." MF64 v" _imv-version @ . CR
    ."   Flags:     "
    _imv-flags @ DUP _IMG-FLAG-EXEC AND IF ." EXEC " THEN
    DUP _IMG-FLAG-LIB AND IF ." LIB " THEN
    DUP _IMG-FLAG-XMEM AND IF ." XMEM " THEN
    DUP _IMG-FLAG-JIT AND IF ." JIT " THEN
    DUP 0= IF ." (none)" THEN DROP CR
    ."   Segment:   " _imv-seg @ . ." bytes" CR
    ."   Relocs:    " _imv-nrel @ . CR
    ."   Exports:   " _imv-nexp @ . CR
    ."   Imports:   " _imv-nimp @ . CR
    ."   Provided:  " _imv-prov @ -1 = IF
        ." (none)"
    ELSE
        _imv-seg-base @ _imv-prov @ + DUP
        _imv-seg @ _imv-prov @ - _IMG-STRLEN TYPE
    THEN CR
    ."   Entry:     " _imv-entry @ -1 = IF ." (none)" ELSE _imv-entry @ . THEN CR
    ."   File size: " _imv-size @ . ." bytes" CR
    _img-file-buffer @ DMA-FREE ;

: _IMG-HASH-BODY  ( -- u )
    2166136261
    _imv-seg-base @ _imv-used @ _IMG-HDR-SZ -
    0 ?DO
        DUP I + C@ ROT XOR 16777619 * SWAP
    LOOP DROP ;

: IMG-CHECKSUM  ( "filename" -- u )
    _IMG-READ-FILE DUP 0<> IF >R 2DROP R> DROP 0 EXIT THEN
    DROP 2DUP IMG-VERIFY-MEM DUP 0<> IF
        >R 2DROP _img-file-buffer @ DMA-FREE R> DROP 0 EXIT
    THEN
    DROP 2DROP _IMG-HASH-BODY _img-file-result !
    _img-file-buffer @ DMA-FREE
    _img-file-result @ ;
