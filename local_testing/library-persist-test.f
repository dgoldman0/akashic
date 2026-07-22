\ RAM-VFS contracts for the L10 Library-owned persistence vertical slice.

PROVIDED akashic-persistence-library-slice-contracts

VARIABLE _LPSC-fails
VARIABLE _LPSC-checks
VARIABLE _LPSC-depth
VARIABLE _LPSC-arena
VARIABLE _LPSC-vfs
VARIABLE _LPSC-old-vfs
VARIABLE _LPSC-ior
VARIABLE _LPSC-e
VARIABLE _LPSC-c
VARIABLE _LPSC-r
VARIABLE _LPSC-ta
VARIABLE _LPSC-tu
VARIABLE _LPSC-td
VARIABLE _LPSC-tl
VARIABLE _LPSC-si-store
VARIABLE _LPSC-si-pwork
VARIABLE _LPSC-si-buffer
VARIABLE _LPSC-si-guard
VARIABLE _LPSC-fault-point
VARIABLE _LPSC-fault-ordinal
VARIABLE _LPSC-root-page
VARIABLE _LPSC-g-store
VARIABLE _LPSC-g-pwork
VARIABLE _LPSC-g-buffer
VARIABLE _LPSC-g-guard
VARIABLE _LPSC-pair-entry
VARIABLE _LPSC-pair-content
VARIABLE _LPSC-read-entry
VARIABLE _LPSC-read-content
VARIABLE _LPSC-read-adapter
VARIABLE _LPSC-read-work

CREATE _LPSC-ops VFS-OPS-SIZE ALLOT
CREATE _LPSC-binding VFS-BINDING-DESC-SIZE ALLOT
CREATE _LPSC-identity PERSIST-IDENTITY-SIZE ALLOT
CREATE _LPSC-store PSTORE-SIZE ALLOT
CREATE _LPSC-store-cold PSTORE-SIZE ALLOT
CREATE _LPSC-pwork PSTORE-WORK-SIZE ALLOT
CREATE _LPSC-pwork-cold PSTORE-WORK-SIZE ALLOT
LIB-CONTENT-RECORD-MAX PERSIST-RECORD-HEADER-SIZE +
    CONSTANT _LPSC-record-buffer-size
_LPSC-record-buffer-size XBUF _LPSC-record-buffer
_LPSC-record-buffer-size XBUF _LPSC-record-buffer-cold
CREATE _LPSC-adapter LIBPA-SIZE ALLOT
CREATE _LPSC-adapter-cold LIBPA-SIZE ALLOT
CREATE _LPSC-work LIBPA-WORK-SIZE ALLOT
CREATE _LPSC-work-cold LIBPA-WORK-SIZE ALLOT
LIBPA-INDEX-WORK-SIZE XBUF _LPSC-index-work
LIBPA-INDEX-WORK-SIZE XBUF _LPSC-index-work-cold
LIB-CONTENT-RECORD-MAX XBUF _LPSC-stage
LIB-CONTENT-RECORD-MAX XBUF _LPSC-stage-cold
CREATE _LPSC-entry LIB-ENTRY-SIZE ALLOT
CREATE _LPSC-content LIB-CONTENT-SIZE ALLOT
CREATE _LPSC-content-bad LIB-CONTENT-SIZE ALLOT
CREATE _LPSC-source 8 ALLOT
CREATE _LPSC-entry-out LIB-ENTRY-SIZE ALLOT
CREATE _LPSC-content-out LIB-CONTENT-SIZE ALLOT
CREATE _LPSC-data-out 64 ALLOT
CREATE _LPSC-ref-snapshot PERSIST-REF-SIZE 2 * ALLOT
PERSIST-PAGE-PAYLOAD-SIZE XBUF _LPSC-root-snapshot
GUARD _LPSC-guard
GUARD _LPSC-guard-cold

CREATE _LPSC-id-a PERSIST-IDENTITY-SIZE ALLOT
CREATE _LPSC-id-b PERSIST-IDENTITY-SIZE ALLOT
CREATE _LPSC-id-c PERSIST-IDENTITY-SIZE ALLOT
CREATE _LPSC-id-d PERSIST-IDENTITY-SIZE ALLOT
CREATE _LPSC-store-a PSTORE-SIZE ALLOT
CREATE _LPSC-store-b PSTORE-SIZE ALLOT
CREATE _LPSC-store-c PSTORE-SIZE ALLOT
CREATE _LPSC-store-d PSTORE-SIZE ALLOT
CREATE _LPSC-pwork-a PSTORE-WORK-SIZE ALLOT
CREATE _LPSC-pwork-b PSTORE-WORK-SIZE ALLOT
CREATE _LPSC-pwork-c PSTORE-WORK-SIZE ALLOT
CREATE _LPSC-pwork-d PSTORE-WORK-SIZE ALLOT
_LPSC-record-buffer-size XBUF _LPSC-record-a
_LPSC-record-buffer-size XBUF _LPSC-record-b
_LPSC-record-buffer-size XBUF _LPSC-record-c
_LPSC-record-buffer-size XBUF _LPSC-record-d
CREATE _LPSC-adapter-a LIBPA-SIZE ALLOT
CREATE _LPSC-adapter-b LIBPA-SIZE ALLOT
CREATE _LPSC-adapter-c LIBPA-SIZE ALLOT
CREATE _LPSC-adapter-d LIBPA-SIZE ALLOT
CREATE _LPSC-work-a LIBPA-WORK-SIZE ALLOT
CREATE _LPSC-work-b LIBPA-WORK-SIZE ALLOT
CREATE _LPSC-work-c LIBPA-WORK-SIZE ALLOT
CREATE _LPSC-work-d LIBPA-WORK-SIZE ALLOT
LIBPA-INDEX-WORK-SIZE XBUF _LPSC-index-work-a
LIBPA-INDEX-WORK-SIZE XBUF _LPSC-index-work-b
LIBPA-INDEX-WORK-SIZE XBUF _LPSC-index-work-c
LIBPA-INDEX-WORK-SIZE XBUF _LPSC-index-work-d
LIB-CONTENT-RECORD-MAX XBUF _LPSC-stage-a
LIB-CONTENT-RECORD-MAX XBUF _LPSC-stage-b
LIB-CONTENT-RECORD-MAX XBUF _LPSC-stage-c
LIB-CONTENT-RECORD-MAX XBUF _LPSC-stage-d
CREATE _LPSC-entry-a LIB-ENTRY-SIZE ALLOT
CREATE _LPSC-entry-b LIB-ENTRY-SIZE ALLOT
CREATE _LPSC-entry-c LIB-ENTRY-SIZE ALLOT
CREATE _LPSC-entry-d LIB-ENTRY-SIZE ALLOT
CREATE _LPSC-content-a LIB-CONTENT-SIZE ALLOT
CREATE _LPSC-content-b LIB-CONTENT-SIZE ALLOT
CREATE _LPSC-content-c LIB-CONTENT-SIZE ALLOT
CREATE _LPSC-content-d LIB-CONTENT-SIZE ALLOT
GUARD _LPSC-guard-a
GUARD _LPSC-guard-b
GUARD _LPSC-guard-c
GUARD _LPSC-guard-d

\ One authority dedicated to the indexed proving workload and one genuinely
\ fresh descriptor/work graph for its cold reopen.  The PSTORE work, record
\ buffer, and cache remain separate from LIBPA-INDEX-WORK-SIZE by contract.
CREATE _LPSC-ix-identity PERSIST-IDENTITY-SIZE ALLOT
CREATE _LPSC-ix-store PSTORE-SIZE ALLOT
CREATE _LPSC-ix-store-cold PSTORE-SIZE ALLOT
CREATE _LPSC-ix-pwork PSTORE-WORK-SIZE ALLOT
CREATE _LPSC-ix-pwork-cold PSTORE-WORK-SIZE ALLOT
_LPSC-record-buffer-size XBUF _LPSC-ix-record
_LPSC-record-buffer-size XBUF _LPSC-ix-record-cold
CREATE _LPSC-ix-adapter LIBPA-SIZE ALLOT
CREATE _LPSC-ix-adapter-cold LIBPA-SIZE ALLOT
LIBPA-INDEX-WORK-SIZE XBUF _LPSC-ix-work
LIBPA-INDEX-WORK-SIZE XBUF _LPSC-ix-work-cold
GUARD _LPSC-ix-guard
GUARD _LPSC-ix-guard-cold

CREATE _LPSC-ix-entry-a LIB-ENTRY-SIZE ALLOT
CREATE _LPSC-ix-entry-b LIB-ENTRY-SIZE ALLOT
CREATE _LPSC-ix-entry-c LIB-ENTRY-SIZE ALLOT
CREATE _LPSC-ix-entry-d LIB-ENTRY-SIZE ALLOT
CREATE _LPSC-ix-content-a LIB-CONTENT-SIZE ALLOT
CREATE _LPSC-ix-content-b LIB-CONTENT-SIZE ALLOT
CREATE _LPSC-ix-content-c LIB-CONTENT-SIZE ALLOT
CREATE _LPSC-ix-content-d LIB-CONTENT-SIZE ALLOT
CREATE _LPSC-ix-collection RID-SIZE ALLOT
CREATE _LPSC-ix-distractor RID-SIZE ALLOT
CREATE _LPSC-ix-rids LIBPA-INDEX-SLICE-MAX RID-SIZE * ALLOT
CREATE _LPSC-ix-entry-out LIB-ENTRY-SIZE ALLOT
CREATE _LPSC-ix-history LIBPA-CONTENT-DESCRIPTOR-SIZE ALLOT
CREATE _LPSC-ix-zero-rid RID-SIZE ALLOT
CREATE _LPSC-ix-rids-snapshot LIBPA-INDEX-SLICE-MAX RID-SIZE * ALLOT

VARIABLE _LPSC-ix-id
VARIABLE _LPSC-ix-operation
VARIABLE _LPSC-ix-created
VARIABLE _LPSC-ix-title-a
VARIABLE _LPSC-ix-title-u
VARIABLE _LPSC-ix-entry
VARIABLE _LPSC-ix-content
VARIABLE _LPSC-ix-read-before
VARIABLE _LPSC-ix-sink-bytes
VARIABLE _LPSC-ix-sink-calls
VARIABLE _LPSC-ix-sink-errors
VARIABLE _LPSC-ix-sink-sum
VARIABLE _LPSC-ix-root-before
VARIABLE _LPSC-ix-page-warm
VARIABLE _LPSC-ix-page-final
VARIABLE _LPSC-fault-skip
VARIABLE _LPSC-ix-pattern-seed

PBLOB-CHUNK-SIZE 2 * 17 + CONSTANT _LPSC-ix-raw-size

: _LPSC-assert  ( flag -- )
    1 _LPSC-checks +!
    0= IF 1 _LPSC-fails +! ." LIBRARY PERSISTENCE SLICE ASSERT " _LPSC-checks @ . CR THEN ;

: _LPSC-stack  ( -- )
    DEPTH DUP _LPSC-depth @ <> IF
        ." LIBRARY PERSISTENCE SLICE STACK " _LPSC-depth @ . ." -> " DUP . CR .S CR
    THEN
    _LPSC-depth @ = _LPSC-assert ;

: _LPSC-status  ( actual expected -- )
    2DUP <> IF ." LIBRARY PERSISTENCE SLICE STATUS actual/expected " 2DUP . . CR THEN
    = _LPSC-assert _LPSC-stack ;

: _LPSC-bytes=  ( a b u -- flag )
    DUP 0< IF DROP 2DROP 0 EXIT THEN
    0 ?DO
        2DUP I + C@ SWAP I + C@ <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _LPSC-pair?  ( entry content -- flag )
    DUP LIB-CONTENT-VALID? 0= IF 2DROP 0 EXIT THEN
    OVER LIB-ENTRY-VALID? 0= IF 2DROP 0 EXIT THEN
    >R
    DUP LIBE.ID R@ LIBCT.ID RID= 0= IF DROP R> DROP 0 EXIT THEN
    DUP LIBE.DOMAIN-REVISION @ R@ LIBCT.DOMAIN-REVISION @ <> IF
        DROP R> DROP 0 EXIT
    THEN
    DUP LIBE.KIND @ R@ LIBCT.KIND @ <> IF DROP R> DROP 0 EXIT THEN
    DUP LIBE.MEDIA @ R@ LIBCT.MEDIA @ <> IF DROP R> DROP 0 EXIT THEN
    DUP LIBE.CURRENT-CONTENT-REVISION @
        R@ LIBCT.CONTENT-REVISION @ <> IF DROP R> DROP 0 EXIT THEN
    DUP LIBE.CONTENT-U @ R@ LIBCT.DATA-U @ <> IF DROP R> DROP 0 EXIT THEN
    LIBE.CONTENT-DIGEST R@ LIBCT.DIGEST SHA3-256-COMPARE
    R> DROP ;

: _LPSC-content=  ( a b -- flag )
    DUP LIB-CONTENT-VALID? 0= IF 2DROP 0 EXIT THEN
    OVER LIB-CONTENT-VALID? 0= IF 2DROP 0 EXIT THEN
    >R
    DUP LIBCT.ID R@ LIBCT.ID RID= 0= IF DROP R> DROP 0 EXIT THEN
    DUP LIBCT.DOMAIN-REVISION @ R@ LIBCT.DOMAIN-REVISION @ <> IF
        DROP R> DROP 0 EXIT
    THEN
    DUP LIBCT.CONTENT-REVISION @ R@ LIBCT.CONTENT-REVISION @ <> IF
        DROP R> DROP 0 EXIT
    THEN
    DUP LIBCT.KIND @ R@ LIBCT.KIND @ <> IF DROP R> DROP 0 EXIT THEN
    DUP LIBCT.MEDIA @ R@ LIBCT.MEDIA @ <> IF DROP R> DROP 0 EXIT THEN
    DUP LIBCT.DATA-U @ R@ LIBCT.DATA-U @ <> IF DROP R> DROP 0 EXIT THEN
    DUP LIBCT.DIGEST R@ LIBCT.DIGEST SHA3-256-COMPARE 0= IF
        DROP R> DROP 0 EXIT
    THEN
    DUP LIBCT-DATA$ R@ LIBCT.DATA-A @ SWAP _LPSC-bytes= NIP
    R> DROP ;

: _LPSC-id!  ( value id -- ) DUP RID-CLEAR ! ;

: _LPSC-fault  ( point ordinal context -- status )
    @ ROT = 0= IF DROP PERSIST-S-OK EXIT THEN
    _LPSC-fault-ordinal @ DUP 0>= IF
        = IF PERSIST-S-FAULT ELSE PERSIST-S-OK THEN EXIT
    THEN
    2DROP
    _LPSC-fault-skip @ DUP 0> IF
        -1 _LPSC-fault-skip +! DROP PERSIST-S-OK EXIT
    THEN
    DROP PERSIST-S-FAULT ;

: _LPSC-text!  ( source-a source-u destination length-cell -- )
    _LPSC-tl ! _LPSC-td ! _LPSC-tu ! _LPSC-ta !
    _LPSC-tu @ _LPSC-tl @ !
    _LPSC-ta @ _LPSC-td @ _LPSC-tu @ CMOVE ;

: _LPSC-content!  ( content -- )
    DUP LIB-CONTENT-INIT _LPSC-c !
    0x11 _LPSC-c @ LIBCT.ID _LPSC-id!
    1 _LPSC-c @ LIBCT.DOMAIN-REVISION !
    1 _LPSC-c @ LIBCT.CONTENT-REVISION !
    LIB-KIND-MANAGED-DOCUMENT _LPSC-c @ LIBCT.KIND !
    LIB-MEDIA-TEXT-PLAIN _LPSC-c @ LIBCT.MEDIA !
    S" hello" _LPSC-source SWAP MOVE
    _LPSC-source _LPSC-c @ LIBCT.DATA-A !
    5 _LPSC-c @ LIBCT.DATA-U !
    _LPSC-c @ LIB-CONTENT-DIGEST! LIB-S-OK _LPSC-status ;

: _LPSC-entry!  ( entry -- )
    DUP LIB-ENTRY-INIT _LPSC-e !
    0x11 _LPSC-e @ LIBE.ID _LPSC-id!
    1 _LPSC-e @ LIBE.DOMAIN-REVISION !
    LIB-KIND-MANAGED-DOCUMENT _LPSC-e @ LIBE.KIND !
    LIB-LIFECYCLE-ACTIVE _LPSC-e @ LIBE.LIFECYCLE !
    LIB-MEDIA-TEXT-PLAIN _LPSC-e @ LIBE.MEDIA !
    1 _LPSC-e @ LIBE.CURRENT-CONTENT-REVISION !
    1 _LPSC-e @ LIBE.OLDEST-CONTENT-REVISION !
    5 _LPSC-e @ LIBE.CONTENT-U !
    _LPSC-content LIBCT.DIGEST _LPSC-e @ LIBE.CONTENT-DIGEST RID-COPY
    1 _LPSC-e @ LIBE.MUTATION-SEQUENCE !
    LIB-CLOCK-MUTATION-SEQUENCE _LPSC-e @ LIBE.CREATED-CLOCK !
    1 _LPSC-e @ LIBE.CREATED-VALUE !
    LIB-CLOCK-MUTATION-SEQUENCE _LPSC-e @ LIBE.MODIFIED-CLOCK !
    1 _LPSC-e @ LIBE.MODIFIED-VALUE !
    S" First note" _LPSC-e @ LIBE.TITLE _LPSC-e @ LIBE.TITLE-U _LPSC-text!
    _LPSC-e @ LIBE.RECEIPT _LPSC-r !
    0xA1 _LPSC-r @ LIBR.OPERATION-KEY _LPSC-id!
    LIB-IMPORT-CREATED _LPSC-r @ LIBR.METHOD !
    1 _LPSC-r @ LIBR.INITIAL-CONTENT-REVISION !
    5 _LPSC-r @ LIBR.INITIAL-CONTENT-U !
    LIB-MEDIA-TEXT-PLAIN _LPSC-r @ LIBR.INITIAL-MEDIA !
    _LPSC-e @ LIBE.CONTENT-DIGEST
        _LPSC-r @ LIBR.INITIAL-CONTENT-DIGEST RID-COPY
    _LPSC-e @ LIB-ENTRY-REQUEST-SEAL! LIB-S-OK _LPSC-status ;

: _LPSC-store-init  ( store pwork buffer guard -- status )
    _LPSC-si-guard ! _LPSC-si-buffer ! _LPSC-si-pwork ! _LPSC-si-store !
    S" /lp-pages" S" /lp-segment" S" /lp-root-a" S" /lp-root-b"
    _LPSC-identity LIB-CONTENT-RECORD-MAX _LPSC-vfs @ 0 0 _LPSC-si-guard @
    ['] _LPSC-fault _LPSC-fault-point _LPSC-si-store @ PSTORE-INIT
    DUP IF EXIT THEN DROP
    _LPSC-si-buffer @ _LPSC-record-buffer-size _LPSC-si-pwork @ PSTORE-WORK-INIT ;

: _LPSC-generic-store-init
  ( paths[8] identity store pwork buffer guard -- status )
    _LPSC-g-guard ! _LPSC-g-buffer ! _LPSC-g-pwork ! _LPSC-g-store !
    LIB-CONTENT-RECORD-MAX _LPSC-vfs @ 0 0 _LPSC-g-guard @ 0 0
        _LPSC-g-store @ PSTORE-INIT
    DUP IF EXIT THEN DROP
    _LPSC-g-buffer @ _LPSC-record-buffer-size _LPSC-g-pwork @ PSTORE-WORK-INIT ;

: _LPSC-indexed-store-init
  ( paths[8] identity store pwork buffer guard -- status )
    _LPSC-g-guard ! _LPSC-g-buffer ! _LPSC-g-pwork ! _LPSC-g-store !
    LIB-CONTENT-RECORD-MAX _LPSC-vfs @ 0 0 _LPSC-g-guard @
        ['] _LPSC-fault _LPSC-fault-point _LPSC-g-store @ PSTORE-INIT
    DUP IF EXIT THEN DROP
    _LPSC-g-buffer @ _LPSC-record-buffer-size _LPSC-g-pwork @ PSTORE-WORK-INIT ;

: _LPSC-pair!  ( id-byte operation-byte entry content -- )
    _LPSC-pair-content ! _LPSC-pair-entry !
    _LPSC-content _LPSC-pair-content @ LIB-CONTENT-SIZE MOVE
    OVER _LPSC-pair-content @ LIBCT.ID _LPSC-id!
    _LPSC-entry _LPSC-pair-entry @ LIB-ENTRY-SIZE MOVE
    OVER _LPSC-pair-entry @ LIBE.ID _LPSC-id!
    DUP _LPSC-pair-entry @ LIBE.RECEIPT LIBR.OPERATION-KEY _LPSC-id!
    2DROP
    _LPSC-pair-entry @ LIB-ENTRY-REQUEST-SEAL! LIB-S-OK _LPSC-status
    _LPSC-pair-entry @ _LPSC-pair-content @ _LPSC-pair? _LPSC-assert ;

: _LPSC-ix-pair!
  ( id-byte operation-byte created-value title-a title-u entry content -- )
    _LPSC-ix-content ! _LPSC-ix-entry !
    _LPSC-ix-title-u ! _LPSC-ix-title-a !
    _LPSC-ix-created ! _LPSC-ix-operation ! _LPSC-ix-id !
    _LPSC-content _LPSC-ix-content @ LIB-CONTENT-SIZE MOVE
    _LPSC-ix-id @ _LPSC-ix-content @ LIBCT.ID _LPSC-id!
    _LPSC-entry _LPSC-ix-entry @ LIB-ENTRY-SIZE MOVE
    _LPSC-ix-id @ _LPSC-ix-entry @ LIBE.ID _LPSC-id!
    _LPSC-ix-operation @
        _LPSC-ix-entry @ LIBE.RECEIPT LIBR.OPERATION-KEY _LPSC-id!
    _LPSC-ix-created @ _LPSC-ix-entry @ LIBE.MUTATION-SEQUENCE !
    _LPSC-ix-created @ _LPSC-ix-entry @ LIBE.CREATED-VALUE !
    _LPSC-ix-created @ _LPSC-ix-entry @ LIBE.MODIFIED-VALUE !
    _LPSC-ix-entry @ LIBE.TITLE LIB-TITLE-MAX 0 FILL
    _LPSC-ix-title-a @ _LPSC-ix-title-u @
        _LPSC-ix-entry @ LIBE.TITLE _LPSC-ix-entry @ LIBE.TITLE-U
        _LPSC-text!
    _LPSC-ix-entry @ LIB-ENTRY-REQUEST-SEAL! LIB-S-OK _LPSC-status
    _LPSC-ix-entry @ _LPSC-ix-content @ _LPSC-pair? _LPSC-assert ;

: _LPSC-ix-source
  ( logical-offset destination-a requested-u seed -- actual-u status )
    SWAP DUP >R
    0 ?DO
        1 PICK I +
        3 PICK I + 2 PICK + 255 AND
        SWAP C!
    LOOP
    2DROP DROP R> PERSIST-S-OK ;

: _LPSC-ix-sink
  ( logical-offset payload-a payload-u seed -- status )
    SWAP DUP >R
    0 ?DO
        1 PICK I + C@ DUP _LPSC-ix-sink-sum +!
        3 PICK I + 2 PICK + 255 AND
        <> IF 1 _LPSC-ix-sink-errors +! THEN
    LOOP
    2DROP DROP
    R> DUP _LPSC-ix-sink-bytes +! DROP
    1 _LPSC-ix-sink-calls +!
    PERSIST-S-OK ;

: _LPSC-ix-pattern-sum  ( total-u seed -- sum )
    _LPSC-ix-pattern-seed ! 0 SWAP
    0 ?DO I _LPSC-ix-pattern-seed @ + 255 AND + LOOP ;

: _LPSC-ix-sink-reset  ( -- )
    0 _LPSC-ix-sink-bytes !
    0 _LPSC-ix-sink-calls !
    0 _LPSC-ix-sink-errors !
    0 _LPSC-ix-sink-sum ! ;

: _LPSC-ix-rid=  ( index rid -- flag )
    SWAP RID-SIZE * _LPSC-ix-rids + RID= ;

: _LPSC-ix-output-mark  ( -- )
    _LPSC-ix-rids LIBPA-INDEX-SLICE-MAX RID-SIZE * 0xA5 FILL
    _LPSC-ix-rids _LPSC-ix-rids-snapshot
        LIBPA-INDEX-SLICE-MAX RID-SIZE * MOVE ;

: _LPSC-ix-output-unchanged?  ( -- flag )
    _LPSC-ix-rids _LPSC-ix-rids-snapshot
        LIBPA-INDEX-SLICE-MAX RID-SIZE * _LPSC-bytes= ;

: _LPSC-ix-read-start  ( index-work -- )
    LIBPA-INDEX-PAGE-READS@ _LPSC-ix-read-before ! ;

: _LPSC-ix-read-bounded  ( max-pages index-work -- )
    LIBPA-INDEX-PAGE-READS@ _LPSC-ix-read-before @ -
    DUP 0> >R SWAP <= R> AND _LPSC-assert ;

: _LPSC-ix-page-count  ( store -- u )
    PSTORE-CURRENT-ROOT@ DUP IF PROOTV.PAGE-COUNT @ ELSE DROP 0 THEN ;

: _LPSC-read-exact  ( entry content adapter work -- )
    _LPSC-read-work ! _LPSC-read-adapter !
    _LPSC-read-content ! _LPSC-read-entry !
    _LPSC-read-work @ _LIBPA-W.CONTENT-REF _LPSC-ref-snapshot
        PERSIST-REF-SIZE 2 * MOVE
    _LPSC-read-entry @ LIBE.ID _LPSC-entry-out _LPSC-content-out _LPSC-data-out 64
        _LPSC-read-adapter @ _LPSC-read-work @ LIBPA-READ
        LIBPA-S-OK = SWAP 5 = AND _LPSC-assert _LPSC-stack
    _LPSC-read-work @ _LIBPA-W.CONTENT-REF _LPSC-ref-snapshot
        PERSIST-REF-SIZE 2 * _LPSC-bytes= _LPSC-assert
    _LPSC-read-entry @ _LPSC-entry-out LIB-ENTRY-SIZE
        _LPSC-bytes= _LPSC-assert
    _LPSC-read-content @ _LPSC-content-out _LPSC-content= _LPSC-assert
    _LPSC-stack ;

: _LPSC-setup  ( -- )
    VFS-CUR _LPSC-old-vfs !
    VFS-RAM-OPS _LPSC-ops VFS-OPS-SIZE MOVE
    VFS-RAM-BINDING _LPSC-binding VFS-BINDING-DESC-SIZE MOVE
    _LPSC-ops _LPSC-binding VB.OPS !
    8388608 A-XMEM ARENA-NEW DUP 0= _LPSC-assert DROP _LPSC-arena !
    _LPSC-arena @ _LPSC-binding 0 VFS-NEW _LPSC-ior ! _LPSC-vfs !
    _LPSC-ior @ 0= _LPSC-assert
    _LPSC-vfs @ 0<> _LPSC-assert
    _LPSC-identity PERSIST-IDENTITY-SIZE 61 FILL
    0 _LPSC-fault-point !
    -1 _LPSC-fault-ordinal !
    0 _LPSC-fault-skip !
    _LPSC-content _LPSC-content!
    _LPSC-entry _LPSC-entry!
    _LPSC-entry LIB-ENTRY-VALID? _LPSC-assert
    _LPSC-content LIB-CONTENT-VALID? _LPSC-assert
    _LPSC-id-a PERSIST-IDENTITY-SIZE 65 FILL
    _LPSC-id-b PERSIST-IDENTITY-SIZE 66 FILL
    _LPSC-id-c PERSIST-IDENTITY-SIZE 67 FILL
    _LPSC-id-d PERSIST-IDENTITY-SIZE 68 FILL
    0x21 0xB1 _LPSC-entry-a _LPSC-content-a _LPSC-pair!
    0x22 0xB2 _LPSC-entry-b _LPSC-content-b _LPSC-pair!
    0x23 0xB3 _LPSC-entry-c _LPSC-content-c _LPSC-pair!
    0x24 0xB4 _LPSC-entry-d _LPSC-content-d _LPSC-pair!
    _LPSC-stack ;

: _LPSC-negative-contracts  ( -- )
    _LPSC-content _LPSC-content-bad LIB-CONTENT-SIZE MOVE
    2 _LPSC-content-bad LIBCT.DOMAIN-REVISION !
    _LPSC-content-bad LIB-CONTENT-VALID? _LPSC-assert
    _LPSC-entry _LPSC-content-bad _LPSC-adapter _LPSC-work LIBPA-CREATE
        LIBPA-S-INVALID _LPSC-status
    _LPSC-adapter LIBPA-GENERATION@ 1 = _LPSC-assert
    _LPSC-entry LIBE.ID DUP @ 1+ SWAP !
    _LPSC-entry LIBE.ID _LPSC-entry-out _LPSC-content-out _LPSC-data-out 64
        _LPSC-adapter _LPSC-work LIBPA-READ
        LIBPA-S-NOT-FOUND = SWAP 0= AND _LPSC-assert _LPSC-stack
    _LPSC-entry LIBE.ID DUP @ 1- SWAP !
    \ Legacy read outputs are caller memory, never scratch space borrowed by
    \ the bound indexed authority.
    _LPSC-entry LIBE.ID _LPSC-index-work _LIBPIX.PAGE
        _LPSC-content-out _LPSC-data-out 64
        _LPSC-adapter _LPSC-work LIBPA-READ
        LIBPA-S-INVALID = SWAP 0= AND _LPSC-assert
    _LPSC-entry LIBE.ID _LPSC-entry-out _LPSC-index-work _LIBPIX.PAGE
        _LPSC-data-out 64 _LPSC-adapter _LPSC-work LIBPA-READ
        LIBPA-S-INVALID = SWAP 0= AND _LPSC-assert
    _LPSC-entry LIBE.ID _LPSC-entry-out _LPSC-content-out
        _LPSC-index-work _LIBPIX.PAGE 64
        _LPSC-adapter _LPSC-work LIBPA-READ
        LIBPA-S-INVALID = SWAP 0= AND _LPSC-assert
    _LPSC-index-work LIBPA-INDEX-WORK-VALID? _LPSC-assert
    _LPSC-stack ;

: _LPSC-reinit-cold  ( -- )
    _LPSC-store-cold _LPSC-pwork-cold _LPSC-record-buffer-cold _LPSC-guard-cold
        _LPSC-store-init PERSIST-S-OK _LPSC-status
    _LPSC-store-cold _LPSC-adapter-cold LIBPA-INIT LIBPA-S-OK _LPSC-status
    _LPSC-pwork-cold _LPSC-stage-cold LIB-CONTENT-RECORD-MAX _LPSC-work-cold
        LIBPA-WORK-INIT LIBPA-S-OK _LPSC-status
    _LPSC-pwork-cold _LPSC-adapter-cold _LPSC-index-work-cold
        LIBPA-INDEX-WORK-INIT LIBPA-S-OK _LPSC-status
    _LPSC-index-work-cold _LPSC-work-cold LIBPA-WORK-INDEX-BIND
        LIBPA-S-OK _LPSC-status
    _LPSC-adapter-cold _LPSC-work-cold LIBPA-PROVISION LIBPA-S-OK _LPSC-status
    _LPSC-adapter-cold _LPSC-work-cold LIBPA-OPEN LIBPA-S-OK _LPSC-status ;

: _LPSC-root-snapshot!  ( store pstore-work -- )
    >R
    DUP PSTORE-CURRENT-ROOT@ PROOTV.APPLICATION-ROOT @
    DUP _LPSC-root-page !
    SWAP R@ PSTORE-READ-PAGE PERSIST-S-OK _LPSC-status
    R@ PSTORE-PAGE-PAYLOAD$
    DUP PERSIST-PAGE-PAYLOAD-SIZE = _LPSC-assert
    DROP _LPSC-root-snapshot PERSIST-PAGE-PAYLOAD-SIZE MOVE
    R> DROP _LPSC-stack ;

: _LPSC-root-snapshot-unchanged?  ( store pstore-work -- )
    >R
    DUP PSTORE-CURRENT-ROOT@ PROOTV.APPLICATION-ROOT @
        _LPSC-root-page @ = _LPSC-assert
    _LPSC-root-page @ SWAP R@ PSTORE-READ-PAGE
        PERSIST-S-OK _LPSC-status
    R@ PSTORE-PAGE-PAYLOAD$
    DUP PERSIST-PAGE-PAYLOAD-SIZE = _LPSC-assert
    DROP _LPSC-root-snapshot PERSIST-PAGE-PAYLOAD-SIZE
        _LPSC-bytes= _LPSC-assert
    R> DROP _LPSC-stack ;

: _LPSC-fault-contracts  ( -- )
    _LPSC-store _LPSC-pwork _LPSC-root-snapshot!

    \ The application-root allocation is claimed by a checked page write
    \ before reclaim metadata is finalized.  Fault at that exact page id,
    \ after verification, and prove abort preserves the committed root bytes.
    _LPSC-adapter _LPSC-index-work LIBPA-INDEX-BEGIN
        LIBPA-S-OK _LPSC-status
    _LPSC-entry-b _LPSC-content-b _LPSC-adapter _LPSC-index-work
        LIBPA-INDEX-DOCUMENT LIBPA-S-OK _LPSC-status
    _LPSC-pwork PSTORE-PROPOSED-ROOT@ PROOTV.PAGE-COUNT @
        _LPSC-fault-ordinal !
    PERSIST-FAULT-PAGE-VERIFIED _LPSC-fault-point !
    _LPSC-adapter _LPSC-index-work LIBPA-INDEX-COMMIT
        LIBPA-S-FAULT _LPSC-status
    0 _LPSC-fault-point !
    -1 _LPSC-fault-ordinal !
    _LPSC-reinit-cold
    _LPSC-adapter-cold LIBPA-GENERATION@ 1 = _LPSC-assert
    _LPSC-store-cold _LPSC-pwork-cold _LPSC-root-snapshot-unchanged?

    PERSIST-FAULT-DATA-SYNCED _LPSC-fault-point !
    _LPSC-entry-b _LPSC-content-b _LPSC-adapter-cold _LPSC-work-cold LIBPA-CREATE
        LIBPA-S-FAULT _LPSC-status
    0 _LPSC-fault-point !
    _LPSC-reinit-cold
    _LPSC-adapter-cold LIBPA-GENERATION@ 1 = _LPSC-assert
    _LPSC-store-cold _LPSC-pwork-cold _LPSC-root-snapshot-unchanged?
    _LPSC-entry LIBE.ID _LPSC-entry-out _LPSC-content-out _LPSC-data-out 64
        _LPSC-adapter-cold _LPSC-work-cold LIBPA-READ
        LIBPA-S-OK = SWAP 5 = AND _LPSC-assert _LPSC-stack

    PERSIST-FAULT-ROOT-PUBLISHED _LPSC-fault-point !
    _LPSC-entry-b _LPSC-content-b _LPSC-adapter-cold _LPSC-work-cold LIBPA-CREATE
        LIBPA-S-FAULT _LPSC-status
    0 _LPSC-fault-point !
    _LPSC-index-work-cold _LIBPIX.APP-ROOT-PAGE @
    _LPSC-store-cold PSTORE-CURRENT-ROOT@ PROOTV.APPLICATION-ROOT @ =
        _LPSC-assert
    _LPSC-reinit-cold
    _LPSC-adapter-cold LIBPA-GENERATION@ 2 = _LPSC-assert
    _LPSC-entry-b LIBE.ID _LPSC-entry-out _LPSC-content-out _LPSC-data-out 64
        _LPSC-adapter-cold _LPSC-work-cold LIBPA-READ
        LIBPA-S-OK = SWAP 5 = AND _LPSC-assert
    _LPSC-entry-b _LPSC-entry-out LIB-ENTRY-SIZE _LPSC-bytes= _LPSC-assert
    _LPSC-content-b _LPSC-content-out _LPSC-content= _LPSC-assert
    _LPSC-stack ;

: _LPSC-four-store-init  ( -- )
    S" /la-p" S" /la-s" S" /la-ra" S" /la-rb" _LPSC-id-a
        _LPSC-store-a _LPSC-pwork-a _LPSC-record-a _LPSC-guard-a
        _LPSC-generic-store-init PERSIST-S-OK _LPSC-status
    S" /lb-p" S" /lb-s" S" /lb-ra" S" /lb-rb" _LPSC-id-b
        _LPSC-store-b _LPSC-pwork-b _LPSC-record-b _LPSC-guard-b
        _LPSC-generic-store-init PERSIST-S-OK _LPSC-status
    S" /lc-p" S" /lc-s" S" /lc-ra" S" /lc-rb" _LPSC-id-c
        _LPSC-store-c _LPSC-pwork-c _LPSC-record-c _LPSC-guard-c
        _LPSC-generic-store-init PERSIST-S-OK _LPSC-status
    S" /ld-p" S" /ld-s" S" /ld-ra" S" /ld-rb" _LPSC-id-d
        _LPSC-store-d _LPSC-pwork-d _LPSC-record-d _LPSC-guard-d
        _LPSC-generic-store-init PERSIST-S-OK _LPSC-status

    _LPSC-store-a _LPSC-adapter-a LIBPA-INIT LIBPA-S-OK _LPSC-status
    _LPSC-pwork-a _LPSC-stage-a LIB-CONTENT-RECORD-MAX _LPSC-work-a
        LIBPA-WORK-INIT LIBPA-S-OK _LPSC-status
    _LPSC-pwork-a _LPSC-adapter-a _LPSC-index-work-a
        LIBPA-INDEX-WORK-INIT LIBPA-S-OK _LPSC-status
    _LPSC-index-work-a _LPSC-work-a LIBPA-WORK-INDEX-BIND
        LIBPA-S-OK _LPSC-status
    _LPSC-store-b _LPSC-adapter-b LIBPA-INIT LIBPA-S-OK _LPSC-status
    _LPSC-pwork-b _LPSC-stage-b LIB-CONTENT-RECORD-MAX _LPSC-work-b
        LIBPA-WORK-INIT LIBPA-S-OK _LPSC-status
    _LPSC-pwork-b _LPSC-adapter-b _LPSC-index-work-b
        LIBPA-INDEX-WORK-INIT LIBPA-S-OK _LPSC-status
    _LPSC-index-work-b _LPSC-work-b LIBPA-WORK-INDEX-BIND
        LIBPA-S-OK _LPSC-status
    _LPSC-store-c _LPSC-adapter-c LIBPA-INIT LIBPA-S-OK _LPSC-status
    _LPSC-pwork-c _LPSC-stage-c LIB-CONTENT-RECORD-MAX _LPSC-work-c
        LIBPA-WORK-INIT LIBPA-S-OK _LPSC-status
    _LPSC-pwork-c _LPSC-adapter-c _LPSC-index-work-c
        LIBPA-INDEX-WORK-INIT LIBPA-S-OK _LPSC-status
    _LPSC-index-work-c _LPSC-work-c LIBPA-WORK-INDEX-BIND
        LIBPA-S-OK _LPSC-status
    _LPSC-store-d _LPSC-adapter-d LIBPA-INIT LIBPA-S-OK _LPSC-status
    _LPSC-pwork-d _LPSC-stage-d LIB-CONTENT-RECORD-MAX _LPSC-work-d
        LIBPA-WORK-INIT LIBPA-S-OK _LPSC-status
    _LPSC-pwork-d _LPSC-adapter-d _LPSC-index-work-d
        LIBPA-INDEX-WORK-INIT LIBPA-S-OK _LPSC-status
    _LPSC-index-work-d _LPSC-work-d LIBPA-WORK-INDEX-BIND
        LIBPA-S-OK _LPSC-status

    _LPSC-adapter-a _LPSC-work-a LIBPA-PROVISION LIBPA-S-OK _LPSC-status
    _LPSC-adapter-b _LPSC-work-b LIBPA-PROVISION LIBPA-S-OK _LPSC-status
    _LPSC-adapter-c _LPSC-work-c LIBPA-PROVISION LIBPA-S-OK _LPSC-status
    _LPSC-adapter-d _LPSC-work-d LIBPA-PROVISION LIBPA-S-OK _LPSC-status
    _LPSC-adapter-a _LPSC-work-a LIBPA-OPEN LIBPA-S-ABSENT _LPSC-status
    _LPSC-adapter-b _LPSC-work-b LIBPA-OPEN LIBPA-S-ABSENT _LPSC-status
    _LPSC-adapter-c _LPSC-work-c LIBPA-OPEN LIBPA-S-ABSENT _LPSC-status
    _LPSC-adapter-d _LPSC-work-d LIBPA-OPEN LIBPA-S-ABSENT _LPSC-status
    _LPSC-stack ;

: _LPSC-four-store-contracts  ( -- )
    _LPSC-four-store-init
    _LPSC-entry-a _LPSC-content-a _LPSC-adapter-a _LPSC-work-a LIBPA-CREATE
        LIBPA-S-OK _LPSC-status
    _LPSC-entry-b _LPSC-content-b _LPSC-adapter-b _LPSC-work-b LIBPA-CREATE
        LIBPA-S-OK _LPSC-status
    _LPSC-entry-a _LPSC-content-a _LPSC-adapter-a _LPSC-work-a _LPSC-read-exact
    _LPSC-entry-c _LPSC-content-c _LPSC-adapter-c _LPSC-work-c LIBPA-CREATE
        LIBPA-S-OK _LPSC-status
    _LPSC-entry-a LIBE.ID _LPSC-entry-out _LPSC-content-out _LPSC-data-out 64
        _LPSC-adapter-b _LPSC-work-b LIBPA-READ
        LIBPA-S-NOT-FOUND = SWAP 0= AND _LPSC-assert _LPSC-stack
    _LPSC-entry-d _LPSC-content-d _LPSC-adapter-d _LPSC-work-d LIBPA-CREATE
        LIBPA-S-OK _LPSC-status
    _LPSC-entry-b _LPSC-content-b _LPSC-adapter-b _LPSC-work-b _LPSC-read-exact
    _LPSC-entry-c _LPSC-content-c _LPSC-adapter-c _LPSC-work-c _LPSC-read-exact
    _LPSC-entry-d _LPSC-content-d _LPSC-adapter-d _LPSC-work-d _LPSC-read-exact
    _LPSC-adapter-a LIBPA-GENERATION@ 1 = _LPSC-assert
    _LPSC-adapter-b LIBPA-GENERATION@ 1 = _LPSC-assert
    _LPSC-adapter-c LIBPA-GENERATION@ 1 = _LPSC-assert
    _LPSC-adapter-d LIBPA-GENERATION@ 1 = _LPSC-assert
    _LPSC-stack ;

: _LPSC-first-authority  ( -- )
    _LPSC-store _LPSC-pwork _LPSC-record-buffer _LPSC-guard _LPSC-store-init
        PERSIST-S-OK _LPSC-status
    _LPSC-store _LPSC-vfs @ LIBPA-INIT LIBPA-S-INVALID _LPSC-status
    _LPSC-store PSTORE-VALID? _LPSC-assert _LPSC-stack
    _LPSC-store _LPSC-guard LIBPA-INIT LIBPA-S-INVALID _LPSC-status
    _LPSC-store PSTORE-VALID? _LPSC-assert _LPSC-stack
    _LPSC-store _LPSC-adapter LIBPA-INIT LIBPA-S-OK _LPSC-status
    _LPSC-pwork _LPSC-stage LIB-CONTENT-RECORD-MAX _LPSC-work
        LIBPA-WORK-INIT LIBPA-S-OK _LPSC-status
    _LPSC-pwork _LPSC-adapter _LPSC-index-work
        LIBPA-INDEX-WORK-INIT LIBPA-S-OK _LPSC-status
    _LPSC-index-work _LPSC-work LIBPA-WORK-INDEX-BIND
        LIBPA-S-OK _LPSC-status
    _LPSC-adapter LIBPA-VALID? _LPSC-assert
    _LPSC-work LIBPA-WORK-VALID? _LPSC-assert _LPSC-stack
    _LPSC-guard _LPSC-work _LIBPA-W.STAGE-A !
    _LPSC-adapter _LPSC-work LIBPA-PROVISION LIBPA-S-INVALID _LPSC-status
    _LPSC-store PSTORE-VALID? _LPSC-assert _LPSC-stack
    _LPSC-stage _LPSC-work _LIBPA-W.STAGE-A !
    _LPSC-adapter _LPSC-work LIBPA-PROVISION LIBPA-S-OK _LPSC-status
    _LPSC-adapter _LPSC-work LIBPA-OPEN LIBPA-S-ABSENT _LPSC-status
    _LPSC-entry _LPSC-content _LPSC-adapter _LPSC-work LIBPA-CREATE
        LIBPA-S-OK _LPSC-status
    _LPSC-adapter LIBPA-GENERATION@ 1 = _LPSC-assert _LPSC-stack
    _LPSC-entry LIBE.ID _LPSC-entry-out _LPSC-content-out _LPSC-data-out 64
        _LPSC-adapter _LPSC-work LIBPA-READ
        LIBPA-S-OK = SWAP 5 = AND _LPSC-assert _LPSC-stack
    _LPSC-entry _LPSC-entry-out LIB-ENTRY-SIZE _LPSC-bytes= _LPSC-assert
    _LPSC-content _LPSC-content-out _LPSC-content= _LPSC-assert
    _LPSC-stack ;

: _LPSC-cold-reopen  ( -- )
    _LPSC-store-cold _LPSC-pwork-cold _LPSC-record-buffer-cold _LPSC-guard-cold
        _LPSC-store-init PERSIST-S-OK _LPSC-status
    _LPSC-store-cold _LPSC-adapter-cold LIBPA-INIT LIBPA-S-OK _LPSC-status
    _LPSC-pwork-cold _LPSC-stage-cold LIB-CONTENT-RECORD-MAX _LPSC-work-cold
        LIBPA-WORK-INIT LIBPA-S-OK _LPSC-status
    _LPSC-pwork-cold _LPSC-adapter-cold _LPSC-index-work-cold
        LIBPA-INDEX-WORK-INIT LIBPA-S-OK _LPSC-status
    _LPSC-index-work-cold _LPSC-work-cold LIBPA-WORK-INDEX-BIND
        LIBPA-S-OK _LPSC-status
    _LPSC-adapter-cold _LPSC-work-cold LIBPA-PROVISION LIBPA-S-OK _LPSC-status
    _LPSC-adapter-cold _LPSC-work-cold LIBPA-OPEN LIBPA-S-OK _LPSC-status
    _LPSC-adapter-cold LIBPA-GENERATION@ 1 = _LPSC-assert
    _LPSC-entry LIBE.ID _LPSC-entry-out _LPSC-content-out _LPSC-data-out 64
        _LPSC-adapter-cold _LPSC-work-cold LIBPA-READ
        LIBPA-S-OK = SWAP 5 = AND _LPSC-assert
    _LPSC-entry _LPSC-entry-out LIB-ENTRY-SIZE _LPSC-bytes= _LPSC-assert
    _LPSC-content _LPSC-content-out _LPSC-content= _LPSC-assert
    _LPSC-stack ;

\ ---------------------------------------------------------------------
\ L11 indexed proving consumer
\ ---------------------------------------------------------------------

: _LPSC-indexed-init  ( -- )
    _LPSC-ix-identity PERSIST-IDENTITY-SIZE 73 FILL
    S" /lix-p" S" /lix-s" S" /lix-ra" S" /lix-rb"
    _LPSC-ix-identity _LPSC-ix-store _LPSC-ix-pwork _LPSC-ix-record
        _LPSC-ix-guard _LPSC-indexed-store-init PERSIST-S-OK _LPSC-status
    _LPSC-ix-store _LPSC-ix-adapter LIBPA-INIT LIBPA-S-OK _LPSC-status
    _LPSC-ix-pwork _LPSC-ix-adapter _LPSC-ix-work
        LIBPA-INDEX-WORK-INIT LIBPA-S-OK _LPSC-status
    _LPSC-ix-store _LPSC-ix-pwork PSTORE-PROVISION
        PERSIST-S-OK _LPSC-status
    _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-OPEN
        LIBPA-S-ABSENT _LPSC-status

    LIBPA-INDEX-WORK-SIZE 84624 = _LPSC-assert
    _LPSC-ix-work LIBPA-INDEX-WORKING-BYTES@ 84624 = _LPSC-assert

    \ Cleanup failure dominates the initiating status.  Manufacture only the
    \ ownership mismatch needed to make PSTORE-ABORT reject, then restore the
    \ owner and cleanly release the live proposal.
    _LPSC-ix-store _LPSC-ix-pwork PSTORE-BEGIN PERSIST-S-OK _LPSC-status
    0 _LPSC-ix-store _PST.TRANSACTION-WORK !
    LIBPA-S-CORRUPT _LPSC-ix-work _LIBPIX-ABORT-STORE-PRIMARY
        LIBPA-S-BUSY _LPSC-status
    _LPSC-ix-pwork _LPSC-ix-store _PST.TRANSACTION-WORK !
    _LPSC-ix-store _LPSC-ix-pwork PSTORE-ABORT PERSIST-S-OK _LPSC-status

    \ A busy reclaimer makes RECLAIM-TX-BEGIN fail after PSTORE-BEGIN.  The
    \ adapter must return that exact primary failure and leave no proposal.
    _LPSC-ix-store _LPSC-ix-pwork PSTORE-BEGIN PERSIST-S-OK _LPSC-status
    _LPSC-ix-store _LPSC-ix-pwork _LPSC-ix-work _LIBPIX.RECLAIM
        _LPSC-ix-work _LIBPIX.RECLAIM-WORK RECLAIM-TX-BEGIN
        PERSIST-S-OK _LPSC-status
    _LPSC-ix-store _LPSC-ix-pwork PSTORE-ABORT PERSIST-S-OK _LPSC-status
    _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-BEGIN
        LIBPA-S-BUSY _LPSC-status
    _LPSC-ix-pwork PSTORE-PROPOSED-ROOT@ 0= _LPSC-assert
    _LPSC-ix-work _LIBPIX.RECLAIM-WORK RECLAIM-ABORT
        PERSIST-S-OK _LPSC-status

    _LPSC-ix-work _LPSC-ix-store _LPSC-ix-pwork _LIBPIX-ALLOCATE
        PERSIST-S-BUSY = SWAP -1 = AND _LPSC-assert
    _LPSC-ix-work LIBPA-RECLAIM-STEP-CALLS@ 1 = _LPSC-assert
    _LPSC-ix-work LIBPA-RECLAIM-MOVED@ 0= _LPSC-assert

    _LPSC-ix-collection RID-CLEAR 0x90 _LPSC-ix-collection !
    _LPSC-ix-distractor RID-CLEAR 0x91 _LPSC-ix-distractor !
    0x31 0xC1 10 S" Alpha"
        _LPSC-ix-entry-a _LPSC-ix-content-a _LPSC-ix-pair!
    0x32 0xC2 20 S" Bravo"
        _LPSC-ix-entry-b _LPSC-ix-content-b _LPSC-ix-pair!
    0x33 0xC3 30 S" Charlie"
        _LPSC-ix-entry-c _LPSC-ix-content-c _LPSC-ix-pair!
    0x34 0xC4 40 S" Delta"
        _LPSC-ix-entry-d _LPSC-ix-content-d _LPSC-ix-pair!
    _LPSC-stack ;

: _LPSC-indexed-first-commit  ( -- )
    _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-BEGIN
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-entry-a _LPSC-ix-content-a _LPSC-ix-adapter _LPSC-ix-work
        LIBPA-INDEX-DOCUMENT LIBPA-S-OK _LPSC-status
    _LPSC-ix-entry-c _LPSC-ix-content-c _LPSC-ix-adapter _LPSC-ix-work
        LIBPA-INDEX-DOCUMENT LIBPA-S-OK _LPSC-status
    _LPSC-ix-entry-d _LPSC-ix-content-d _LPSC-ix-adapter _LPSC-ix-work
        LIBPA-INDEX-DOCUMENT LIBPA-S-OK _LPSC-status
    _LPSC-ix-collection _LPSC-ix-entry-a LIBE.ID
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-MEMBERSHIP
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-collection _LPSC-ix-entry-c LIBE.ID
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-MEMBERSHIP
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-collection _LPSC-ix-entry-d LIBE.ID
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-MEMBERSHIP
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-distractor _LPSC-ix-entry-b LIBE.ID
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-MEMBERSHIP
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-entry-a LIBE.ID 2 _LPSC-ix-raw-size
        ['] _LPSC-ix-source 7 _LPSC-ix-adapter _LPSC-ix-work
        LIBPA-INDEX-RAW-CONTENT LIBPA-S-OK _LPSC-status
    _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-COMMIT
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-adapter LIBPA-GENERATION@ 1 = _LPSC-assert
    \ Three height-one documents touch four trees each, four edges touch the
    \ membership tree, raw revision two touches history once, and the sole
    \ application root is the eighteenth consumer allocation.
    _LPSC-ix-work LIBPA-RECLAIM-STEP-CALLS@ 18 = _LPSC-assert
    _LPSC-stack ;

: _LPSC-indexed-first-queries  ( -- )
    _LPSC-ix-work _LPSC-ix-read-start
    _LPSC-ix-entry-a LIBE.ID _LPSC-ix-entry-out
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-RID-LOOKUP
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-entry-a _LPSC-ix-entry-out LIB-ENTRY-SIZE
        _LPSC-bytes= _LPSC-assert
    9 _LPSC-ix-work _LPSC-ix-read-bounded

    _LPSC-ix-work _LPSC-ix-read-start
    _LPSC-ix-entry-a LIBE.ID 1 _LPSC-ix-history
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-HISTORY
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-history LIBPA-CONTENT-RAW? 0= _LPSC-assert
    _LPSC-ix-history LIBPA-CONTENT-SIZE@ 5 = _LPSC-assert
    9 _LPSC-ix-work _LPSC-ix-read-bounded

    _LPSC-ix-entry-a LIBE.ID 2 _LPSC-ix-history
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-HISTORY
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-history LIBPA-CONTENT-RAW? _LPSC-assert
    _LPSC-ix-history LIBPA-CONTENT-SIZE@ _LPSC-ix-raw-size = _LPSC-assert
    _LPSC-ix-history _LIBPAC.BLOB PBLOB-CHUNK-COUNT@ 3 = _LPSC-assert

    _LPSC-ix-work _LPSC-ix-read-start
    _LPSC-ix-collection _LPSC-ix-entry-a LIBE.ID
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-MEMBER?
        LIBPA-S-OK = SWAP 0<> AND _LPSC-assert
    9 _LPSC-ix-work _LPSC-ix-read-bounded
    _LPSC-ix-collection _LPSC-ix-entry-b LIBE.ID
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-MEMBER?
        LIBPA-S-OK = SWAP 0= AND _LPSC-assert
    _LPSC-ix-distractor _LPSC-ix-entry-b LIBE.ID
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-MEMBER?
        LIBPA-S-OK = SWAP 0<> AND _LPSC-assert

    _LPSC-ix-work _LPSC-ix-read-start
    _LPSC-ix-collection 0 _LPSC-ix-rids 8
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-MEMBERSHIP-SLICE
        LIBPA-S-OK = SWAP 3 = AND _LPSC-assert
    0 _LPSC-ix-entry-a LIBE.ID _LPSC-ix-rid= _LPSC-assert
    1 _LPSC-ix-entry-c LIBE.ID _LPSC-ix-rid= _LPSC-assert
    2 _LPSC-ix-entry-d LIBE.ID _LPSC-ix-rid= _LPSC-assert
    9 _LPSC-ix-work _LPSC-ix-read-bounded

    _LPSC-ix-work _LPSC-ix-read-start
    0 0 _LPSC-ix-rids 2
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-CREATION-SLICE
        LIBPA-S-OK = SWAP 2 = AND _LPSC-assert
    0 _LPSC-ix-entry-a LIBE.ID _LPSC-ix-rid= _LPSC-assert
    1 _LPSC-ix-entry-c LIBE.ID _LPSC-ix-rid= _LPSC-assert
    9 _LPSC-ix-work _LPSC-ix-read-bounded

    _LPSC-ix-work _LPSC-ix-read-start
    0 0 0 _LPSC-ix-rids 2
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-TITLE-SLICE
        LIBPA-S-OK = SWAP 2 = AND _LPSC-assert
    0 _LPSC-ix-entry-a LIBE.ID _LPSC-ix-rid= _LPSC-assert
    1 _LPSC-ix-entry-c LIBE.ID _LPSC-ix-rid= _LPSC-assert
    9 _LPSC-ix-work _LPSC-ix-read-bounded

    _LPSC-ix-sink-reset
    _LPSC-ix-history PBLOB-CHUNK-SIZE 8 - 32
        ['] _LPSC-ix-sink 7 _LPSC-ix-adapter _LPSC-ix-work
        LIBPA-CONTENT-RANGE
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-sink-bytes @ 32 = _LPSC-assert
    _LPSC-ix-sink-calls @ 2 = _LPSC-assert
    _LPSC-ix-sink-errors @ 0= _LPSC-assert

    _LPSC-ix-sink-reset
    _LPSC-ix-history 0 ['] _LPSC-ix-sink 7
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-CONTENT-STREAM
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-sink-bytes @ _LPSC-ix-raw-size = _LPSC-assert
    _LPSC-ix-sink-calls @ 3 = _LPSC-assert
    _LPSC-ix-sink-errors @ 0= _LPSC-assert
    _LPSC-ix-sink-sum @
        _LPSC-ix-raw-size 7 _LPSC-ix-pattern-sum = _LPSC-assert
    _LPSC-stack ;

: _LPSC-indexed-insert-b  ( -- )
    _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-BEGIN
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-entry-b _LPSC-ix-content-b _LPSC-ix-adapter _LPSC-ix-work
        LIBPA-INDEX-DOCUMENT LIBPA-S-OK _LPSC-status
    _LPSC-ix-collection _LPSC-ix-entry-b LIBE.ID
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-MEMBERSHIP
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-COMMIT
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-adapter LIBPA-GENERATION@ 2 = _LPSC-assert
    _LPSC-ix-work LIBPA-RECLAIM-STEP-CALLS@ 6 = _LPSC-assert

    30 _LPSC-ix-entry-c LIBE.ID _LPSC-ix-rids 4
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-CREATION-SLICE
        LIBPA-S-OK = SWAP 1 = AND _LPSC-assert
    0 _LPSC-ix-entry-d LIBE.ID _LPSC-ix-rid= _LPSC-assert
    S" Charlie" _LPSC-ix-entry-c LIBE.ID _LPSC-ix-rids 4
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-TITLE-SLICE
        LIBPA-S-OK = SWAP 1 = AND _LPSC-assert
    0 _LPSC-ix-entry-d LIBE.ID _LPSC-ix-rid= _LPSC-assert
    _LPSC-ix-collection _LPSC-ix-entry-c LIBE.ID _LPSC-ix-rids 4
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-MEMBERSHIP-SLICE
        LIBPA-S-OK = SWAP 1 = AND _LPSC-assert
    0 _LPSC-ix-entry-d LIBE.ID _LPSC-ix-rid= _LPSC-assert

    0 0 _LPSC-ix-rids 4
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-CREATION-SLICE
        LIBPA-S-OK = SWAP 4 = AND _LPSC-assert
    0 _LPSC-ix-entry-a LIBE.ID _LPSC-ix-rid= _LPSC-assert
    1 _LPSC-ix-entry-b LIBE.ID _LPSC-ix-rid= _LPSC-assert
    2 _LPSC-ix-entry-c LIBE.ID _LPSC-ix-rid= _LPSC-assert
    3 _LPSC-ix-entry-d LIBE.ID _LPSC-ix-rid= _LPSC-assert
    0 0 0 _LPSC-ix-rids 4
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-TITLE-SLICE
        LIBPA-S-OK = SWAP 4 = AND _LPSC-assert
    0 _LPSC-ix-entry-a LIBE.ID _LPSC-ix-rid= _LPSC-assert
    1 _LPSC-ix-entry-b LIBE.ID _LPSC-ix-rid= _LPSC-assert
    2 _LPSC-ix-entry-c LIBE.ID _LPSC-ix-rid= _LPSC-assert
    3 _LPSC-ix-entry-d LIBE.ID _LPSC-ix-rid= _LPSC-assert
    _LPSC-ix-collection 0 _LPSC-ix-rids 4
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-MEMBERSHIP-SLICE
        LIBPA-S-OK = SWAP 4 = AND _LPSC-assert
    0 _LPSC-ix-entry-a LIBE.ID _LPSC-ix-rid= _LPSC-assert
    1 _LPSC-ix-entry-b LIBE.ID _LPSC-ix-rid= _LPSC-assert
    2 _LPSC-ix-entry-c LIBE.ID _LPSC-ix-rid= _LPSC-assert
    3 _LPSC-ix-entry-d LIBE.ID _LPSC-ix-rid= _LPSC-assert
    _LPSC-stack ;

: _LPSC-indexed-input-contracts  ( -- )
    _LPSC-ix-zero-rid RID-CLEAR

    \ Mutating borrowed RIDs are rejected before key or tree scratch is
    \ touched.  Each rejection must also unwind the active proposal.
    _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-BEGIN
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-work _LIBPIX.PAGE 3 0 0 0
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-RAW-CONTENT
        LIBPA-S-INVALID _LPSC-status
    _LPSC-ix-pwork PSTORE-PROPOSED-ROOT@ 0= _LPSC-assert
    _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-OPEN
        LIBPA-S-OK _LPSC-status

    _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-BEGIN
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-work _LIBPIX.PAGE _LPSC-ix-entry-a LIBE.ID
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-MEMBERSHIP
        LIBPA-S-INVALID _LPSC-status
    _LPSC-ix-pwork PSTORE-PROPOSED-ROOT@ 0= _LPSC-assert
    _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-OPEN
        LIBPA-S-OK _LPSC-status

    _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-BEGIN
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-collection _LPSC-ix-work _LIBPIX.PAGE
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-MEMBERSHIP
        LIBPA-S-INVALID _LPSC-status
    _LPSC-ix-pwork PSTORE-PROPOSED-ROOT@ 0= _LPSC-assert
    _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-OPEN
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-adapter LIBPA-GENERATION@ 1 = _LPSC-assert

    \ Point APIs reject borrowed RIDs that alias the current index work.
    _LPSC-ix-work _LIBPIX.PAGE _LPSC-ix-entry-out
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-RID-LOOKUP
        LIBPA-S-INVALID _LPSC-status
    _LPSC-ix-work _LIBPIX.PAGE 1 _LPSC-ix-history
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-HISTORY
        LIBPA-S-INVALID _LPSC-status
    _LPSC-ix-work _LIBPIX.PAGE _LPSC-ix-entry-a LIBE.ID
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-MEMBER?
        LIBPA-S-INVALID = SWAP 0= AND _LPSC-assert
    _LPSC-ix-collection _LPSC-ix-work _LIBPIX.PAGE
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-MEMBER?
        LIBPA-S-INVALID = SWAP 0= AND _LPSC-assert

    \ A successful page leaves a deliberately stale nonzero result count.
    \ Every malformed continuation must return zero and leave output intact.
    _LPSC-ix-collection 0 _LPSC-ix-rids 2
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-MEMBERSHIP-SLICE
        LIBPA-S-OK = SWAP 2 = AND _LPSC-assert
    _LPSC-ix-output-mark
    _LPSC-ix-collection _LPSC-ix-zero-rid _LPSC-ix-rids 2
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-MEMBERSHIP-SLICE
        LIBPA-S-INVALID = SWAP 0= AND _LPSC-assert
    _LPSC-ix-output-unchanged? _LPSC-assert
    _LPSC-ix-output-mark
    _LPSC-ix-work _LIBPIX.PAGE 0 _LPSC-ix-rids 2
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-MEMBERSHIP-SLICE
        LIBPA-S-INVALID = SWAP 0= AND _LPSC-assert
    _LPSC-ix-output-unchanged? _LPSC-assert
    _LPSC-ix-output-mark
    _LPSC-ix-collection _LPSC-ix-work _LIBPIX.PAGE _LPSC-ix-rids 2
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-MEMBERSHIP-SLICE
        LIBPA-S-INVALID = SWAP 0= AND _LPSC-assert
    _LPSC-ix-output-unchanged? _LPSC-assert
    _LPSC-ix-output-mark
    _LPSC-ix-collection _LPSC-ix-entry-d LIBE.ID _LPSC-ix-rids 2
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-MEMBERSHIP-SLICE
        LIBPA-S-OK = SWAP 0= AND _LPSC-assert
    _LPSC-ix-output-unchanged? _LPSC-assert

    0 0 _LPSC-ix-rids 2
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-CREATION-SLICE
        LIBPA-S-OK = SWAP 2 = AND _LPSC-assert
    _LPSC-ix-output-mark
    0 _LPSC-ix-entry-a LIBE.ID _LPSC-ix-rids 2
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-CREATION-SLICE
        LIBPA-S-INVALID = SWAP 0= AND _LPSC-assert
    _LPSC-ix-output-unchanged? _LPSC-assert
    _LPSC-ix-output-mark
    10 0 _LPSC-ix-rids 2
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-CREATION-SLICE
        LIBPA-S-INVALID = SWAP 0= AND _LPSC-assert
    _LPSC-ix-output-unchanged? _LPSC-assert
    _LPSC-ix-output-mark
    10 _LPSC-ix-work _LIBPIX.PAGE _LPSC-ix-rids 2
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-CREATION-SLICE
        LIBPA-S-INVALID = SWAP 0= AND _LPSC-assert
    _LPSC-ix-output-unchanged? _LPSC-assert
    _LPSC-ix-output-mark
    40 _LPSC-ix-entry-d LIBE.ID _LPSC-ix-rids 2
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-CREATION-SLICE
        LIBPA-S-OK = SWAP 0= AND _LPSC-assert
    _LPSC-ix-output-unchanged? _LPSC-assert

    0 0 0 _LPSC-ix-rids 2
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-TITLE-SLICE
        LIBPA-S-OK = SWAP 2 = AND _LPSC-assert
    _LPSC-ix-output-mark
    0 0 _LPSC-ix-zero-rid _LPSC-ix-rids 2
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-TITLE-SLICE
        LIBPA-S-INVALID = SWAP 0= AND _LPSC-assert
    _LPSC-ix-output-unchanged? _LPSC-assert
    _LPSC-ix-output-mark
    S" Alpha" 0 _LPSC-ix-rids 2
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-TITLE-SLICE
        LIBPA-S-INVALID = SWAP 0= AND _LPSC-assert
    _LPSC-ix-output-unchanged? _LPSC-assert
    _LPSC-ix-output-mark
    _LPSC-ix-entry-a LIBE.TITLE 0 _LPSC-ix-entry-a LIBE.ID
        _LPSC-ix-rids 2 _LPSC-ix-adapter _LPSC-ix-work
        LIBPA-INDEX-TITLE-SLICE
        LIBPA-S-INVALID = SWAP 0= AND _LPSC-assert
    _LPSC-ix-output-unchanged? _LPSC-assert
    _LPSC-ix-output-mark
    _LPSC-ix-work _LIBPIX.PAGE 1 _LPSC-ix-entry-a LIBE.ID
        _LPSC-ix-rids 2 _LPSC-ix-adapter _LPSC-ix-work
        LIBPA-INDEX-TITLE-SLICE
        LIBPA-S-INVALID = SWAP 0= AND _LPSC-assert
    _LPSC-ix-output-unchanged? _LPSC-assert
    _LPSC-ix-output-mark
    S" Alpha" _LPSC-ix-work _LIBPIX.PAGE _LPSC-ix-rids 2
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-TITLE-SLICE
        LIBPA-S-INVALID = SWAP 0= AND _LPSC-assert
    _LPSC-ix-output-unchanged? _LPSC-assert
    _LPSC-ix-output-mark
    S" Delta" _LPSC-ix-entry-d LIBE.ID _LPSC-ix-rids 2
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-TITLE-SLICE
        LIBPA-S-OK = SWAP 0= AND _LPSC-assert
    _LPSC-ix-output-unchanged? _LPSC-assert

    \ Active transactions make every read slice busy; stale result counts
    \ still normalize to zero and no staged output is copied.
    0 0 0 _LPSC-ix-rids 2
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-TITLE-SLICE
        LIBPA-S-OK = SWAP 2 = AND _LPSC-assert
    _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-BEGIN
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-output-mark
    _LPSC-ix-collection 0 _LPSC-ix-rids 2
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-MEMBERSHIP-SLICE
        LIBPA-S-BUSY = SWAP 0= AND _LPSC-assert
    _LPSC-ix-output-unchanged? _LPSC-assert
    _LPSC-ix-output-mark
    0 0 _LPSC-ix-rids 2
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-CREATION-SLICE
        LIBPA-S-BUSY = SWAP 0= AND _LPSC-assert
    _LPSC-ix-output-unchanged? _LPSC-assert
    _LPSC-ix-output-mark
    0 0 0 _LPSC-ix-rids 2
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-TITLE-SLICE
        LIBPA-S-BUSY = SWAP 0= AND _LPSC-assert
    _LPSC-ix-output-unchanged? _LPSC-assert
    _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-ABORT
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-OPEN
        LIBPA-S-OK _LPSC-status
    _LPSC-stack ;

: _LPSC-indexed-reclaim-fault  ( -- )
    _LPSC-ix-store PSTORE-CURRENT-ROOT@ PROOTV.APPLICATION-ROOT @
        _LPSC-ix-root-before !
    _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-BEGIN
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-collection _LPSC-ix-entry-a LIBE.ID
        _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-MEMBERSHIP
        LIBPA-S-OK _LPSC-status
    -1 _LPSC-fault-ordinal !
    1 _LPSC-fault-skip !
    PERSIST-FAULT-PAGE-VERIFIED _LPSC-fault-point !
    _LPSC-ix-adapter _LPSC-ix-work LIBPA-INDEX-COMMIT
        LIBPA-S-FAULT _LPSC-status
    0 _LPSC-fault-point !
    0 _LPSC-fault-skip !
    _LPSC-ix-adapter LIBPA-GENERATION@ 2 = _LPSC-assert
    _LPSC-ix-store PSTORE-CURRENT-ROOT@ PROOTV.APPLICATION-ROOT @
        _LPSC-ix-root-before @ = _LPSC-assert
    _LPSC-stack ;

: _LPSC-indexed-cold-open  ( -- )
    S" /lix-p" S" /lix-s" S" /lix-ra" S" /lix-rb"
    _LPSC-ix-identity _LPSC-ix-store-cold _LPSC-ix-pwork-cold
        _LPSC-ix-record-cold _LPSC-ix-guard-cold
        _LPSC-indexed-store-init PERSIST-S-OK _LPSC-status
    _LPSC-ix-store-cold _LPSC-ix-adapter-cold LIBPA-INIT
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-pwork-cold _LPSC-ix-adapter-cold _LPSC-ix-work-cold
        LIBPA-INDEX-WORK-INIT LIBPA-S-OK _LPSC-status
    _LPSC-ix-store-cold _LPSC-ix-pwork-cold PSTORE-PROVISION
        PERSIST-S-OK _LPSC-status
    _LPSC-ix-adapter-cold _LPSC-ix-work-cold LIBPA-INDEX-OPEN
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-adapter-cold LIBPA-GENERATION@ 2 = _LPSC-assert
    _LPSC-ix-store-cold PSTORE-CURRENT-ROOT@ PROOTV.APPLICATION-ROOT @
        _LPSC-ix-root-before @ = _LPSC-assert

    _LPSC-ix-work-cold _LPSC-ix-read-start
    _LPSC-ix-entry-b LIBE.ID _LPSC-ix-entry-out
        _LPSC-ix-adapter-cold _LPSC-ix-work-cold LIBPA-INDEX-RID-LOOKUP
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-entry-b _LPSC-ix-entry-out LIB-ENTRY-SIZE
        _LPSC-bytes= _LPSC-assert
    9 _LPSC-ix-work-cold _LPSC-ix-read-bounded
    _LPSC-ix-collection 0 _LPSC-ix-rids 4
        _LPSC-ix-adapter-cold _LPSC-ix-work-cold
        LIBPA-INDEX-MEMBERSHIP-SLICE
        LIBPA-S-OK = SWAP 4 = AND _LPSC-assert
    _LPSC-ix-entry-a LIBE.ID 2 _LPSC-ix-history
        _LPSC-ix-adapter-cold _LPSC-ix-work-cold LIBPA-INDEX-HISTORY
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-sink-reset
    _LPSC-ix-history 0 ['] _LPSC-ix-sink 7
        _LPSC-ix-adapter-cold _LPSC-ix-work-cold LIBPA-CONTENT-STREAM
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-sink-bytes @ _LPSC-ix-raw-size = _LPSC-assert
    _LPSC-ix-sink-errors @ 0= _LPSC-assert
    _LPSC-ix-sink-sum @
        _LPSC-ix-raw-size 7 _LPSC-ix-pattern-sum = _LPSC-assert
    _LPSC-stack ;

: _LPSC-indexed-churn-one  ( -- )
    _LPSC-ix-adapter-cold _LPSC-ix-work-cold LIBPA-INDEX-BEGIN
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-collection _LPSC-ix-entry-a LIBE.ID
        _LPSC-ix-adapter-cold _LPSC-ix-work-cold LIBPA-INDEX-MEMBERSHIP
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-adapter-cold _LPSC-ix-work-cold LIBPA-INDEX-COMMIT
        LIBPA-S-OK _LPSC-status
    _LPSC-ix-work-cold LIBPA-RECLAIM-STEP-CALLS@ 2 = _LPSC-assert ;

: _LPSC-indexed-reclaim-churn  ( -- )
    32 0 DO _LPSC-indexed-churn-one LOOP
    _LPSC-ix-store-cold _LPSC-ix-page-count _LPSC-ix-page-warm !
    32 0 DO _LPSC-indexed-churn-one LOOP
    _LPSC-ix-store-cold _LPSC-ix-page-count _LPSC-ix-page-final !
    _LPSC-ix-page-final @ _LPSC-ix-page-warm @
    = _LPSC-assert
    _LPSC-ix-collection _LPSC-ix-entry-a LIBE.ID
        _LPSC-ix-adapter-cold _LPSC-ix-work-cold LIBPA-INDEX-MEMBER?
        LIBPA-S-OK = SWAP 0<> AND _LPSC-assert
    _LPSC-ix-collection 0 _LPSC-ix-rids 8
        _LPSC-ix-adapter-cold _LPSC-ix-work-cold
        LIBPA-INDEX-MEMBERSHIP-SLICE
        LIBPA-S-OK = SWAP 4 = AND _LPSC-assert
    0 _LPSC-ix-entry-a LIBE.ID _LPSC-ix-rid= _LPSC-assert
    1 _LPSC-ix-entry-b LIBE.ID _LPSC-ix-rid= _LPSC-assert
    2 _LPSC-ix-entry-c LIBE.ID _LPSC-ix-rid= _LPSC-assert
    3 _LPSC-ix-entry-d LIBE.ID _LPSC-ix-rid= _LPSC-assert
    _LPSC-stack ;

: _LPSC-indexed-contracts  ( -- )
    _LPSC-indexed-init
    _LPSC-indexed-first-commit
    _LPSC-indexed-first-queries
    _LPSC-indexed-input-contracts
    _LPSC-indexed-insert-b
    _LPSC-indexed-reclaim-fault
    _LPSC-indexed-cold-open
    _LPSC-indexed-reclaim-churn ;

: _LPSC-RUN  ( -- )
    0 _LPSC-fails ! 0 _LPSC-checks ! DEPTH _LPSC-depth !
    _LPSC-setup
    _LPSC-first-authority
    _LPSC-cold-reopen
    _LPSC-negative-contracts
    _LPSC-fault-contracts
    _LPSC-four-store-contracts
    _LPSC-indexed-contracts
    _LPSC-old-vfs @ VFS-USE
    _LPSC-vfs @ VFS-DESTROY
    _LPSC-stack
    _LPSC-fails @ 0= IF
        ." LIBRARY PERSISTENCE SLICE PASS " _LPSC-checks @ . CR
    ELSE
        ." LIBRARY PERSISTENCE SLICE FAIL " _LPSC-fails @ . ." /" _LPSC-checks @ . CR
    THEN ;
