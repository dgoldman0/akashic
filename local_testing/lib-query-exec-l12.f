\ L12 Library query execution contract.  Setup and assertions execute while
\ this file is interpreted so the large public query module and its focused
\ fixture fit in one runtime dictionary without compiling a second test
\ program beside it.

." LIBRARY QUERY L12 EXEC PHASE fixture-load" CR

PROVIDED akashic-lib-query-l12-exec

VARIABLE _LQ12E-checks
VARIABLE _LQ12E-fails
VARIABLE _LQ12E-depth
VARIABLE _LQ12E-arena
VARIABLE _LQ12E-vfs
VARIABLE _LQ12E-ior
VARIABLE _LQ12E-old-read-xt
VARIABLE _LQ12E-read-calls
VARIABLE _LQ12E-read-after-stage
VARIABLE _LQ12E-read-failed-at
VARIABLE _LQ12E-read-staged-n
VARIABLE _LQ12E-physical-before
VARIABLE _LQ12E-logical-before
VARIABLE _LQ12E-mutation-before

\ A current-document exact read performs two bounded segment reads before it
\ can publish even its record, so the second raw read after one query row has
\ been staged is a stable late-failure seam independent of page-cache warmth.
2 CONSTANT _LQ12E-read-fail-n

CREATE _LQ12E-ops VFS-OPS-SIZE ALLOT
CREATE _LQ12E-binding VFS-BINDING-DESC-SIZE ALLOT
CREATE _LQ12E-identity PERSIST-IDENTITY-SIZE ALLOT
CREATE _LQ12E-bootstrap RID-SIZE ALLOT
CREATE _LQ12E-store PSTORE-SIZE ALLOT
CREATE _LQ12E-pwork PSTORE-WORK-SIZE ALLOT
LIBPA-RECORD-MAX PERSIST-RECORD-HEADER-SIZE + CONSTANT _LQ12E-buffer-u
_LQ12E-buffer-u XBUF _LQ12E-buffer
CREATE _LQ12E-adapter LIBPA-SIZE ALLOT
LIBPA-INDEX-WORK-SIZE XBUF _LQ12E-index-work
GUARD _LQ12E-guard

CREATE _LQ12E-entry LIB-ENTRY-SIZE ALLOT
CREATE _LQ12E-entry-out LIB-ENTRY-SIZE ALLOT
CREATE _LQ12E-entry-one LIB-ENTRY-SIZE ALLOT
CREATE _LQ12E-entry-three LIB-ENTRY-SIZE ALLOT
CREATE _LQ12E-entry-restore LIB-ENTRY-SIZE ALLOT
CREATE _LQ12E-entry-sentinel LIB-ENTRY-SIZE ALLOT
CREATE _LQ12E-content LIB-CONTENT-SIZE ALLOT
CREATE _LQ12E-content-next LIB-CONTENT-SIZE ALLOT
CREATE _LQ12E-descriptor LIBPA-CONTENT-DESCRIPTOR-SIZE ALLOT
CREATE _LQ12E-retained-facts
    LIBRARY-RETAINED-CONTENT-FACTS-SIZE ALLOT
CREATE _LQ12E-draft LIBRARY-DOCUMENT-INITIAL-DRAFT-SIZE ALLOT
CREATE _LQ12E-origin LIB-ORIGIN-SIZE ALLOT
CREATE _LQ12E-source 96 ALLOT
70000 XBUF _LQ12E-large-body
CREATE _LQ12E-rid-one RID-SIZE ALLOT
CREATE _LQ12E-rid-two RID-SIZE ALLOT
CREATE _LQ12E-rid-three RID-SIZE ALLOT
CREATE _LQ12E-rid-four RID-SIZE ALLOT
CREATE _LQ12E-collection LIBPA-COLLECTION-SIZE ALLOT
CREATE _LQ12E-collection-out LIBPA-COLLECTION-SIZE ALLOT
CREATE _LQ12E-member-rids RID-SIZE 2 * ALLOT
CREATE _LQ12E-collection-rid-one RID-SIZE ALLOT
CREATE _LQ12E-collection-rid-two RID-SIZE ALLOT
CREATE _LQ12E-collection-rid-three RID-SIZE ALLOT
CREATE _LQ12E-state-prefix 3 ALLOT
CREATE _LQ12E-range-rows LIBPA-RANGE-ROW-SIZE 3 * ALLOT
CREATE _LQ12E-range-continuation LIBPA-CONTINUATION-SIZE ALLOT
CREATE _LQ12E-request LIBRARY-CORPUS-QUERY-REQUEST-SIZE ALLOT
CREATE _LQ12E-request-snapshot
    LIBRARY-CORPUS-QUERY-REQUEST-SIZE ALLOT
CREATE _LQ12E-collection-request
    LIBRARY-COLLECTION-QUERY-REQUEST-SIZE ALLOT
CREATE _LQ12E-history-request
    LIBRARY-HISTORY-QUERY-REQUEST-SIZE ALLOT
CREATE _LQ12E-page LIBRARY-QUERY-PAGE-SIZE ALLOT
CREATE _LQ12E-page-snapshot LIBRARY-QUERY-PAGE-SIZE ALLOT
CREATE _LQ12E-corpus-rows LIBRARY-QUERY-SUMMARY-SIZE 4 * ALLOT
CREATE _LQ12E-corpus-rows-snapshot
    LIBRARY-QUERY-SUMMARY-SIZE 4 * ALLOT
CREATE _LQ12E-collection-rows
    LIBRARY-COLLECTION-SUMMARY-SIZE 3 * ALLOT
CREATE _LQ12E-history-rows LIBRARY-REVISION-SUMMARY-SIZE 3 * ALLOT
LIBRARY-QUERY-WORK-SIZE XBUF _LQ12E-query-work
LIB-METADATA-FACT-HEADER-SIZE LIB-ORIGIN-SIZE +
    CONSTANT _LQ12E-facts-max
CREATE _LQ12E-facts _LQ12E-facts-max ALLOT
CREATE _LQ12E-metadata-summary LIB-METADATA-SUMMARY-SIZE ALLOT
VARIABLE _LQ12E-facts-u

." LIBRARY QUERY L12 EXEC PHASE storage-declarations" CR

: _LQ12E-assert  ( flag -- )
    1 _LQ12E-checks +!
    0= IF
        1 _LQ12E-fails +!
        ." LIBRARY QUERY L12 EXEC ASSERT " _LQ12E-checks @ . CR
    THEN ;

: _LQ12E-stack  ( -- )
    DEPTH DUP _LQ12E-depth @ <> IF
        ." LIBRARY QUERY L12 EXEC STACK "
        _LQ12E-depth @ . ." -> " DUP . CR .S CR
    THEN
    _LQ12E-depth @ = _LQ12E-assert ;

: _LQ12E-status  ( actual expected -- )
    2DUP <> IF
        ." LIBRARY QUERY L12 EXEC STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _LQ12E-assert _LQ12E-stack ;

: _LQ12E-text!  ( source-a source-u destination length-cell -- )
    >R OVER R@ ! SWAP MOVE R> DROP ;

: _LQ12E-entry-tag!  ( tag-a tag-u entry -- )
    >R
    DUP LIB-METADATA-FACT-HEADER-SIZE + _LQ12E-facts-u !
    _LQ12E-facts _LQ12E-facts-max 0 FILL
    LIB-METADATA-FACT-TAG _LQ12E-facts LIBMF.KIND !
    DUP _LQ12E-facts LIBMF.PAYLOAD-U !
    _LQ12E-facts LIBMF.PAYLOAD SWAP MOVE
    _LQ12E-facts _LQ12E-facts-u @ _LQ12E-metadata-summary
        LIB-METADATA-SUMMARIZE LIB-S-OK _LQ12E-status
    _LQ12E-metadata-summary R@
        LIB-METADATA-SUMMARY-APPLY LIB-S-OK _LQ12E-status
    R> DROP ;

: _LQ12E-bytes=  ( a b u -- flag )
    DUP 0< IF DROP 2DROP 0 EXIT THEN
    0 ?DO
        2DUP I + C@ SWAP I + C@ <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _LQ12E-read-wrapper
  ( buffer length offset inode vfs -- actual ior )
    1 _LQ12E-read-calls +!
    _LQ12E-page LIBQP.COUNT @ 0> IF
        1 _LQ12E-read-after-stage +!
        _LQ12E-read-after-stage @ _LQ12E-read-fail-n = IF
            _LQ12E-read-calls @ _LQ12E-read-failed-at !
            _LQ12E-page LIBQP.COUNT @ _LQ12E-read-staged-n !
            2DROP 2DROP DROP 0 VFS-E-IO EXIT
        THEN
    THEN
    _LQ12E-old-read-xt @ EXECUTE ;

: _LQ12E-read-arm  ( -- )
    0 _LQ12E-read-calls !
    0 _LQ12E-read-after-stage !
    0 _LQ12E-read-failed-at !
    0 _LQ12E-read-staged-n !
    ['] _LQ12E-read-wrapper
        _LQ12E-ops VFS-OP-READ CELLS + ! ;

: _LQ12E-read-restore  ( -- )
    _LQ12E-old-read-xt @
        _LQ12E-ops VFS-OP-READ CELLS + ! ;

: _LQ12E-store-init  ( -- )
    S" /l12-query-pages" S" /l12-query-segment"
    S" /l12-query-root-a" S" /l12-query-root-b"
    _LQ12E-identity LIBPA-RECORD-MAX _LQ12E-vfs @ 0 0
    _LQ12E-guard 0 0 _LQ12E-store
        PSTORE-INIT PERSIST-S-OK _LQ12E-status
    _LQ12E-buffer _LQ12E-buffer-u _LQ12E-pwork
        PSTORE-WORK-INIT PERSIST-S-OK _LQ12E-status ;

: _LQ12E-report  ( -- )
    _LQ12E-fails @ IF
        ." LIBRARY QUERY L12 EXEC FAIL " _LQ12E-fails @ .
        ." / " _LQ12E-checks @ . CR
    ELSE
        ." LIBRARY QUERY L12 EXEC PASS " _LQ12E-checks @ . CR
    THEN ;

." LIBRARY QUERY L12 EXEC PHASE execute-contracts" CR

DEPTH _LQ12E-depth !
0 _LQ12E-checks !
0 _LQ12E-fails !
\ Both fresh-dictionary images bind the same public query module.
LIBRARY-QUERY-WORK-SIZE 32768 = _LQ12E-assert

VFS-RAM-OPS _LQ12E-ops VFS-OPS-SIZE MOVE
VFS-RAM-BINDING _LQ12E-binding VFS-BINDING-DESC-SIZE MOVE
_LQ12E-ops VFS-OP-READ CELLS + @ _LQ12E-old-read-xt !
_LQ12E-ops _LQ12E-binding VB.OPS !
67108864 A-XMEM ARENA-NEW
    DUP 0= _LQ12E-assert DROP _LQ12E-arena !
_LQ12E-arena @ _LQ12E-binding 0 VFS-NEW
    _LQ12E-ior ! _LQ12E-vfs !
_LQ12E-ior @ 0= _LQ12E-assert
_LQ12E-vfs @ 0<> _LQ12E-assert
_LQ12E-identity PERSIST-IDENTITY-SIZE 0x71 FILL
_LQ12E-bootstrap RID-SIZE 0xA1 FILL
_LQ12E-rid-one RID-SIZE 0 FILL
0x41 _LQ12E-rid-one C!
_LQ12E-rid-two RID-SIZE 0 FILL
0x42 _LQ12E-rid-two C!
_LQ12E-rid-three RID-SIZE 0 FILL
0x43 _LQ12E-rid-three C!
_LQ12E-rid-four RID-SIZE 0 FILL
0x44 _LQ12E-rid-four C!
_LQ12E-collection-rid-one RID-SIZE 0 FILL
0x61 _LQ12E-collection-rid-one C!
_LQ12E-collection-rid-two RID-SIZE 0 FILL
0x62 _LQ12E-collection-rid-two C!
_LQ12E-collection-rid-three RID-SIZE 0 FILL
0x63 _LQ12E-collection-rid-three C!

_LQ12E-store-init
_LQ12E-store _LQ12E-adapter LIBPA-INIT
    LIBPA-S-OK _LQ12E-status
_LQ12E-pwork _LQ12E-adapter _LQ12E-index-work
    LIBPA-INDEX-WORK-INIT LIBPA-S-OK _LQ12E-status
_LQ12E-store _LQ12E-pwork PSTORE-PROVISION
    PERSIST-S-OK _LQ12E-status
_LQ12E-adapter _LQ12E-index-work LIBPA-INDEX-OPEN
    LIBPA-S-ABSENT _LQ12E-status
_LQ12E-bootstrap _LQ12E-adapter _LQ12E-index-work
    LIBPA-INDEX-PROVISION LIBPA-S-OK _LQ12E-status

_LQ12E-source 96 0 FILL
S" abcdefghijklmnopqrstuvwxyz0123456789Atag"
    _LQ12E-source SWAP MOVE
_LQ12E-content LIB-CONTENT-INIT
_LQ12E-rid-one _LQ12E-content LIBCT.ID RID-COPY
1 _LQ12E-content LIBCT.DOMAIN-REVISION !
1 _LQ12E-content LIBCT.CONTENT-REVISION !
LIB-KIND-MANAGED-DOCUMENT _LQ12E-content LIBCT.KIND !
LIB-MEDIA-TEXT-PLAIN _LQ12E-content LIBCT.MEDIA !
_LQ12E-source _LQ12E-content LIBCT.DATA-A !
40 _LQ12E-content LIBCT.DATA-U !
_LQ12E-content LIB-CONTENT-DIGEST! LIB-S-OK _LQ12E-status

_LQ12E-entry LIB-ENTRY-INIT
_LQ12E-rid-one _LQ12E-entry LIBE.ID RID-COPY
1 _LQ12E-entry LIBE.DOMAIN-REVISION !
LIB-KIND-MANAGED-DOCUMENT _LQ12E-entry LIBE.KIND !
LIB-LIFECYCLE-ACTIVE _LQ12E-entry LIBE.LIFECYCLE !
LIB-MEDIA-TEXT-PLAIN _LQ12E-entry LIBE.MEDIA !
1 _LQ12E-entry LIBE.CURRENT-CONTENT-REVISION !
1 _LQ12E-entry LIBE.OLDEST-CONTENT-REVISION !
40 _LQ12E-entry LIBE.CONTENT-U !
_LQ12E-content LIBCT.DIGEST _LQ12E-entry LIBE.CONTENT-DIGEST RID-COPY
1 _LQ12E-entry LIBE.MUTATION-SEQUENCE !
LIB-CLOCK-MUTATION-SEQUENCE _LQ12E-entry LIBE.CREATED-CLOCK !
1 _LQ12E-entry LIBE.CREATED-VALUE !
LIB-CLOCK-MUTATION-SEQUENCE _LQ12E-entry LIBE.MODIFIED-CLOCK !
1 _LQ12E-entry LIBE.MODIFIED-VALUE !
S" First shared"
    _LQ12E-entry LIBE.TITLE _LQ12E-entry LIBE.TITLE-U _LQ12E-text!
_LQ12E-entry LIBE.RECEIPT DUP LIB-RECEIPT-INIT
DUP LIBR.OPERATION-KEY RID-CLEAR
0x51 OVER LIBR.OPERATION-KEY !
LIB-IMPORT-CREATED OVER LIBR.METHOD !
1 OVER LIBR.INITIAL-CONTENT-REVISION !
40 OVER LIBR.INITIAL-CONTENT-U !
LIB-MEDIA-TEXT-PLAIN OVER LIBR.INITIAL-MEDIA !
_LQ12E-entry LIBE.CONTENT-DIGEST
    OVER LIBR.INITIAL-CONTENT-DIGEST RID-COPY
DROP
S" tag" _LQ12E-entry _LQ12E-entry-tag!
_LQ12E-entry LIB-ENTRY-REQUEST-SEAL! LIB-S-OK _LQ12E-status
_LQ12E-entry LIB-ENTRY-VALID? _LQ12E-assert
_LQ12E-content LIB-CONTENT-VALID? _LQ12E-assert
_LQ12E-entry-out LIB-ENTRY-SIZE 0xA5 FILL
_LQ12E-entry _LQ12E-content _LQ12E-facts _LQ12E-facts-u @
    0 _LQ12E-entry-out
    _LQ12E-adapter _LQ12E-index-work
    LIBPA-DOCUMENT-CREATE-EXACT LIBPA-S-OK _LQ12E-status
_LQ12E-entry-out _LQ12E-entry-one LIB-ENTRY-SIZE MOVE

\ Second managed/plain document.  Its title and exact tag intentionally share
\ one term so the candidate/tag source merge must deduplicate the RID.
_LQ12E-source 96 0 FILL
S" second body shared tag" _LQ12E-source SWAP MOVE
_LQ12E-content LIB-CONTENT-INIT
_LQ12E-rid-two _LQ12E-content LIBCT.ID RID-COPY
1 _LQ12E-content LIBCT.DOMAIN-REVISION !
1 _LQ12E-content LIBCT.CONTENT-REVISION !
LIB-KIND-MANAGED-DOCUMENT _LQ12E-content LIBCT.KIND !
LIB-MEDIA-TEXT-PLAIN _LQ12E-content LIBCT.MEDIA !
_LQ12E-source _LQ12E-content LIBCT.DATA-A !
22 _LQ12E-content LIBCT.DATA-U !
_LQ12E-content LIB-CONTENT-DIGEST! LIB-S-OK _LQ12E-status

_LQ12E-entry-one _LQ12E-entry LIB-ENTRY-SIZE MOVE
_LQ12E-rid-two _LQ12E-entry LIBE.ID RID-COPY
2 _LQ12E-entry LIBE.MUTATION-SEQUENCE !
2 _LQ12E-entry LIBE.CREATED-VALUE !
2 _LQ12E-entry LIBE.MODIFIED-VALUE !
22 _LQ12E-entry LIBE.CONTENT-U !
_LQ12E-content LIBCT.DIGEST
    _LQ12E-entry LIBE.CONTENT-DIGEST RID-COPY
_LQ12E-entry LIBE.TITLE LIB-TITLE-MAX 0 FILL
S" Second shared"
    _LQ12E-entry LIBE.TITLE _LQ12E-entry LIBE.TITLE-U _LQ12E-text!
_LQ12E-entry LIBE.RECEIPT
DUP LIBR.OPERATION-KEY RID-CLEAR
0x52 OVER LIBR.OPERATION-KEY !
22 OVER LIBR.INITIAL-CONTENT-U !
_LQ12E-entry LIBE.CONTENT-DIGEST
    OVER LIBR.INITIAL-CONTENT-DIGEST RID-COPY
DROP
S" shared" _LQ12E-entry _LQ12E-entry-tag!
_LQ12E-entry LIB-ENTRY-REQUEST-SEAL! LIB-S-OK _LQ12E-status
_LQ12E-entry _LQ12E-content _LQ12E-facts _LQ12E-facts-u @
    1 _LQ12E-entry-out
    _LQ12E-adapter _LQ12E-index-work
    LIBPA-DOCUMENT-CREATE-EXACT LIBPA-S-OK _LQ12E-status

\ The third row is a real capture, prepared from a VFS-origin fact rather than
\ a managed entry with a capture-looking title.  It also supplies a persisted
\ multibyte title for the exact byte/case-sensitive term contract below.
_LQ12E-source 96 0 FILL
S" third markdown tag" _LQ12E-source SWAP MOVE
_LQ12E-origin LIB-ORIGIN-INIT
LIB-ORIGIN-VFS-SNAPSHOT _LQ12E-origin LIBO.KIND !
S" /l12/query/capture.md" DUP
    _LQ12E-origin LIBO.VFS LIBV.PATH-U !
    _LQ12E-origin LIBO.VFS LIBV.PATH SWAP MOVE
18 _LQ12E-origin LIBO.VFS LIBV.CONTENT-U !
QLOC-DK-PROJECTION-CONTENT
    _LQ12E-origin LIBO.VFS LIBV.DIGEST-KIND !
_LQ12E-source 18
    _LQ12E-origin LIBO.VFS LIBV.CONTENT-DIGEST SHA3-256-HASH
_LQ12E-origin LIB-ORIGIN-VALID? _LQ12E-assert

_LQ12E-facts _LQ12E-facts-max 0 FILL
LIB-METADATA-FACT-ORIGIN _LQ12E-facts LIBMF.KIND !
LIB-ORIGIN-SIZE _LQ12E-facts LIBMF.PAYLOAD-U !
_LQ12E-origin _LQ12E-facts LIBMF.PAYLOAD
    LIB-ORIGIN-SIZE MOVE
LIB-METADATA-FACT-HEADER-SIZE LIB-ORIGIN-SIZE +
    _LQ12E-facts-u !

_LQ12E-draft LIBRARY-DOCUMENT-INITIAL-DRAFT-INIT
_LQ12E-rid-three _LQ12E-draft LSDID.ID RID-COPY
_LQ12E-draft LSDID.OPERATION-KEY RID-CLEAR
0x53 _LQ12E-draft LSDID.OPERATION-KEY !
LIB-KIND-CAPTURE _LQ12E-draft LSDID.KIND !
LIB-MEDIA-TEXT-MARKDOWN _LQ12E-draft LSDID.MEDIA !
3 _LQ12E-draft LSDID.MUTATION-SEQUENCE !
_LQ12E-source _LQ12E-draft LSDID.CONTENT-A !
18 _LQ12E-draft LSDID.CONTENT-U !
S" Third Café capture"
    _LQ12E-draft LSDID.TITLE _LQ12E-draft LSDID.TITLE-U _LQ12E-text!
_LQ12E-facts _LQ12E-facts-u @ _LQ12E-draft
    LIBRARY-DOCUMENT-INITIAL-DRAFT-FACTS!
    _LIBDV-S-OK _LQ12E-status
_LQ12E-draft LIBRARY-DOCUMENT-INITIAL-DRAFT-VALID? _LQ12E-assert
_LQ12E-draft _LQ12E-entry _LQ12E-content
    LIBRARY-SERVICE-PREPARE-CAPTURE-IMPORT
    _LIBDV-S-OK _LQ12E-status
_LQ12E-entry LIBE.KIND @ LIB-KIND-CAPTURE = _LQ12E-assert
_LQ12E-entry LIBE.ORIGIN-N @ 1 = _LQ12E-assert
_LQ12E-entry LIBE.RECEIPT LIBR.METHOD @
    LIB-IMPORT-VFS-SNAPSHOT = _LQ12E-assert
_LQ12E-entry _LQ12E-content _LQ12E-facts _LQ12E-facts-u @
    2 _LQ12E-entry-out
    _LQ12E-adapter _LQ12E-index-work
    LIBPA-DOCUMENT-CREATE-EXACT LIBPA-S-OK _LQ12E-status
_LQ12E-entry-out _LQ12E-entry-three LIB-ENTRY-SIZE MOVE

\ Prefixed semantic seeds must resume in both directions.  This catches
\ prefix-length/first-order stack confusion in the adapter seeder itself,
\ independently of the public query merger that relies on the same contract.
LIB-LIFECYCLE-ACTIVE _LQ12E-state-prefix C!
LIB-KIND-MANAGED-DOCUMENT _LQ12E-state-prefix 1+ C!
LIB-MEDIA-TEXT-PLAIN _LQ12E-state-prefix 2 + C!
LIBPA-RANGE-DOCUMENT-STATE-CREATION _LQ12E-state-prefix 3
1 _LQ12E-rid-one 1 _LQ12E-rid-one
_LQ12E-range-continuation LIBPA-CONTINUATION-SEED
    LIBPA-S-OK _LQ12E-status
LIBPA-RANGE-DOCUMENT-STATE-CREATION _LQ12E-state-prefix 3
_LQ12E-range-rows 3 _LQ12E-range-continuation
_LQ12E-adapter _LQ12E-index-work LIBPA-RANGE-AFTER
    LIBPA-S-OK = _LQ12E-assert
1 = _LQ12E-assert
_LQ12E-range-rows LIBPA-RANGE-ROW-RID@
    _LQ12E-rid-two RID= _LQ12E-assert

LIBPA-RANGE-DOCUMENT-STATE-CREATION _LQ12E-state-prefix 3
3 _LQ12E-rid-three 3 _LQ12E-rid-three
_LQ12E-range-continuation LIBPA-CONTINUATION-SEED
    LIBPA-S-OK _LQ12E-status
LIBPA-RANGE-DOCUMENT-STATE-CREATION _LQ12E-state-prefix 3
_LQ12E-range-rows 3 _LQ12E-range-continuation
_LQ12E-adapter _LQ12E-index-work LIBPA-RANGE-BEFORE
    LIBPA-S-OK = _LQ12E-assert
2 = _LQ12E-assert
_LQ12E-range-rows LIBPA-RANGE-ROW-RID@
    _LQ12E-rid-one RID= _LQ12E-assert
_LQ12E-range-rows LIBPA-RANGE-ROW-SIZE +
    LIBPA-RANGE-ROW-RID@ _LQ12E-rid-two RID= _LQ12E-assert

_LQ12E-query-work LIBRARY-QUERY-WORK-INIT
    LIBPA-S-OK _LQ12E-status
_LQ12E-corpus-rows 1 _LQ12E-page
    LIBRARY-CORPUS-PAGE-INIT LIBPA-S-OK _LQ12E-status
_LQ12E-request LIBRARY-CORPUS-QUERY-REQUEST-INIT
LIBRARY-CORPUS-KIND-CAPTURE _LQ12E-request LIBCQR.KIND-MASK !
_LQ12E-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-CORPUS-QUERY-FIRST LIBPA-S-OK _LQ12E-status
_LQ12E-page LIBQP.COUNT @ 1 = _LQ12E-assert
0 _LQ12E-page LIBRARY-CORPUS-PAGE-ROW
    DUP LIBQS.KIND @ LIB-KIND-CAPTURE = _LQ12E-assert
    DUP LIBQS.LIFECYCLE @ LIB-LIFECYCLE-ACTIVE = _LQ12E-assert
    LIBQS.REF RREF.ID _LQ12E-rid-three RID= _LQ12E-assert

_LQ12E-corpus-rows 2 _LQ12E-page
    LIBRARY-CORPUS-PAGE-INIT LIBPA-S-OK _LQ12E-status
_LQ12E-request LIBRARY-CORPUS-QUERY-REQUEST-INIT
LIBRARY-CORPUS-LIFECYCLE-ALL
    _LQ12E-request LIBCQR.LIFECYCLE-MASK !

\ FIRST/AFTER/BEFORE retain semantic keysets and reverse pages return in
\ canonical creation order.
_LQ12E-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-CORPUS-QUERY-FIRST LIBPA-S-OK _LQ12E-status
_LQ12E-page LIBRARY-CORPUS-PAGE-VALID? _LQ12E-assert
_LQ12E-page LIBQP.COUNT @ 2 = _LQ12E-assert
0 _LQ12E-page LIBRARY-CORPUS-PAGE-ROW
DUP LIBRARY-QUERY-SUMMARY-VALID? _LQ12E-assert
LIBQS.REF RREF.ID _LQ12E-rid-one RID= _LQ12E-assert
1 _LQ12E-page LIBRARY-CORPUS-PAGE-ROW
    LIBQS.REF RREF.ID _LQ12E-rid-two RID= _LQ12E-assert
_LQ12E-page LIBQP.CONTINUATION
    LIBRARY-QUERY-CONTINUATION-HAS-BEFORE? 0= _LQ12E-assert
_LQ12E-page LIBQP.CONTINUATION
    LIBRARY-QUERY-CONTINUATION-HAS-AFTER? _LQ12E-assert
_LQ12E-page LIBQP.CONTINUATION
    LIBQC.OBSERVED-LOGICAL-GENERATION @ 3 = _LQ12E-assert

\ A corpus keyset is semantic rather than generation-pinned.  Moving the
\ not-yet-returned capture from active to archived leaves this all-lifecycle
\ result set unchanged, and AFTER must resume at its stable creation key.
_LQ12E-entry-three LIB-LIFECYCLE-ARCHIVED 4 _LQ12E-entry
    LIBRARY-SERVICE-PREPARE-LIFECYCLE-NEXT
    _LIBDV-S-OK _LQ12E-status
_LQ12E-entry 3 1 _LQ12E-entry-out
_LQ12E-adapter _LQ12E-index-work
    LIBPA-DOCUMENT-LIFECYCLE-REPLACE-EXACT
    LIBPA-S-OK _LQ12E-status
_LQ12E-entry-out _LQ12E-entry-three LIB-ENTRY-SIZE MOVE
_LQ12E-entry-three LIBE.LIFECYCLE @
    LIB-LIFECYCLE-ARCHIVED = _LQ12E-assert

\ A failed AFTER leaves both the prior rows and continuation usable.
_LQ12E-page _LQ12E-page-snapshot LIBRARY-QUERY-PAGE-SIZE MOVE
_LQ12E-corpus-rows _LQ12E-corpus-rows-snapshot
    LIBRARY-QUERY-SUMMARY-SIZE 2 * MOVE
_LQ12E-request _LQ12E-request-snapshot
    LIBRARY-CORPUS-QUERY-REQUEST-SIZE MOVE
S" mismatch" _LQ12E-request LIBRARY-CORPUS-QUERY-TERM!
    LIBPA-S-OK _LQ12E-status
_LQ12E-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-CORPUS-QUERY-AFTER LIBPA-S-INVALID _LQ12E-status
_LQ12E-page _LQ12E-page-snapshot LIBRARY-QUERY-PAGE-SIZE
    _LQ12E-bytes= _LQ12E-assert
_LQ12E-corpus-rows _LQ12E-corpus-rows-snapshot
    LIBRARY-QUERY-SUMMARY-SIZE 2 * _LQ12E-bytes= _LQ12E-assert
_LQ12E-request-snapshot _LQ12E-request
    LIBRARY-CORPUS-QUERY-REQUEST-SIZE MOVE

_LQ12E-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-CORPUS-QUERY-AFTER LIBPA-S-OK _LQ12E-status
_LQ12E-page LIBQP.COUNT @ 1 = _LQ12E-assert
0 _LQ12E-page LIBRARY-CORPUS-PAGE-ROW
    LIBQS.REF RREF.ID _LQ12E-rid-three RID= _LQ12E-assert
_LQ12E-page LIBQP.CONTINUATION
    LIBRARY-QUERY-CONTINUATION-HAS-BEFORE? _LQ12E-assert
_LQ12E-page LIBQP.CONTINUATION
    LIBRARY-QUERY-CONTINUATION-HAS-AFTER? 0= _LQ12E-assert
_LQ12E-page LIBQP.CONTINUATION
    LIBQC.OBSERVED-LOGICAL-GENERATION @ 4 = _LQ12E-assert

\ A failed BEFORE is equally atomic, and the retained continuation retries.
_LQ12E-page _LQ12E-page-snapshot LIBRARY-QUERY-PAGE-SIZE MOVE
_LQ12E-corpus-rows _LQ12E-corpus-rows-snapshot
    LIBRARY-QUERY-SUMMARY-SIZE 2 * MOVE
_LQ12E-request _LQ12E-request-snapshot
    LIBRARY-CORPUS-QUERY-REQUEST-SIZE MOVE
LIBRARY-CORPUS-MEDIA-PLAIN _LQ12E-request LIBCQR.MEDIA-MASK !
_LQ12E-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-CORPUS-QUERY-BEFORE LIBPA-S-INVALID _LQ12E-status
_LQ12E-page _LQ12E-page-snapshot LIBRARY-QUERY-PAGE-SIZE
    _LQ12E-bytes= _LQ12E-assert
_LQ12E-corpus-rows _LQ12E-corpus-rows-snapshot
    LIBRARY-QUERY-SUMMARY-SIZE 2 * _LQ12E-bytes= _LQ12E-assert
_LQ12E-request-snapshot _LQ12E-request
    LIBRARY-CORPUS-QUERY-REQUEST-SIZE MOVE
_LQ12E-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-CORPUS-QUERY-BEFORE LIBPA-S-OK _LQ12E-status
_LQ12E-page LIBQP.COUNT @ 2 = _LQ12E-assert
0 _LQ12E-page LIBRARY-CORPUS-PAGE-ROW
    LIBQS.REF RREF.ID _LQ12E-rid-one RID= _LQ12E-assert
1 _LQ12E-page LIBRARY-CORPUS-PAGE-ROW
    LIBQS.REF RREF.ID _LQ12E-rid-two RID= _LQ12E-assert
_LQ12E-page LIBQP.CONTINUATION
    LIBRARY-QUERY-CONTINUATION-HAS-BEFORE? 0= _LQ12E-assert
_LQ12E-page LIBQP.CONTINUATION
    LIBRARY-QUERY-CONTINUATION-HAS-AFTER? _LQ12E-assert

\ An exactly-full terminal page must not advertise phantom availability.
\ The persisted multibyte title also makes term matching exact and
\ case-sensitive: uppercase C matches while lowercase C does not.
_LQ12E-corpus-rows 1 _LQ12E-page
    LIBRARY-CORPUS-PAGE-INIT LIBPA-S-OK _LQ12E-status
_LQ12E-request LIBRARY-CORPUS-QUERY-REQUEST-INIT
LIBRARY-CORPUS-LIFECYCLE-ARCHIVED
    _LQ12E-request LIBCQR.LIFECYCLE-MASK !
LIBRARY-CORPUS-KIND-CAPTURE _LQ12E-request LIBCQR.KIND-MASK !
S" Café" _LQ12E-request LIBRARY-CORPUS-QUERY-TERM!
    LIBPA-S-OK _LQ12E-status
LIBRARY-CORPUS-FIELD-TITLE _LQ12E-request LIBCQR.FIELD-MASK !
_LQ12E-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-CORPUS-QUERY-FIRST LIBPA-S-OK _LQ12E-status
_LQ12E-page LIBQP.COUNT @ 1 = _LQ12E-assert
0 _LQ12E-page LIBRARY-CORPUS-PAGE-ROW
    LIBQS.REF RREF.ID _LQ12E-rid-three RID= _LQ12E-assert
_LQ12E-page LIBQP.CONTINUATION
    LIBRARY-QUERY-CONTINUATION-HAS-AFTER? 0= _LQ12E-assert

S" café" _LQ12E-request LIBRARY-CORPUS-QUERY-TERM!
    LIBPA-S-OK _LQ12E-status
_LQ12E-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-CORPUS-QUERY-FIRST LIBPA-S-OK _LQ12E-status
_LQ12E-page LIBQP.COUNT @ 0= _LQ12E-assert

S" First" _LQ12E-request LIBRARY-CORPUS-QUERY-TERM!
    LIBPA-S-OK _LQ12E-status
LIBRARY-CORPUS-LIFECYCLE-ACTIVE
    _LQ12E-request LIBCQR.LIFECYCLE-MASK !
LIBRARY-CORPUS-KIND-ALL _LQ12E-request LIBCQR.KIND-MASK !
LIBRARY-CORPUS-FIELD-TITLE _LQ12E-request LIBCQR.FIELD-MASK !
_LQ12E-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-CORPUS-QUERY-FIRST LIBPA-S-OK _LQ12E-status
_LQ12E-page LIBQP.COUNT @ 1 = _LQ12E-assert

S" mnop" _LQ12E-request LIBRARY-CORPUS-QUERY-TERM!
    LIBPA-S-OK _LQ12E-status
LIBRARY-CORPUS-FIELD-BODY _LQ12E-request LIBCQR.FIELD-MASK !
_LQ12E-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-CORPUS-QUERY-FIRST LIBPA-S-OK _LQ12E-status
_LQ12E-page LIBQP.COUNT @ 1 = _LQ12E-assert

_LQ12E-corpus-rows 4 _LQ12E-page
    LIBRARY-CORPUS-PAGE-INIT LIBPA-S-OK _LQ12E-status
S" tag" _LQ12E-request LIBRARY-CORPUS-QUERY-TERM!
    LIBPA-S-OK _LQ12E-status
LIBRARY-CORPUS-LIFECYCLE-ALL
    _LQ12E-request LIBCQR.LIFECYCLE-MASK !
LIBRARY-CORPUS-FIELD-ALL _LQ12E-request LIBCQR.FIELD-MASK !
_LQ12E-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-CORPUS-QUERY-FIRST LIBPA-S-OK _LQ12E-status
_LQ12E-page LIBQP.COUNT @ 3 = _LQ12E-assert

\ OR semantics and duplicate-source merge: the second RID is both a title
\ candidate and an exact tag posting, but appears once.
_LQ12E-corpus-rows 4 _LQ12E-page
    LIBRARY-CORPUS-PAGE-INIT LIBPA-S-OK _LQ12E-status
S" shared" _LQ12E-request LIBRARY-CORPUS-QUERY-TERM!
    LIBPA-S-OK _LQ12E-status
LIBRARY-CORPUS-FIELD-TITLE LIBRARY-CORPUS-FIELD-TAGS OR
    _LQ12E-request LIBCQR.FIELD-MASK !
_LQ12E-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-CORPUS-QUERY-FIRST LIBPA-S-OK _LQ12E-status
_LQ12E-page LIBQP.COUNT @ 2 = _LQ12E-assert
0 _LQ12E-page LIBRARY-CORPUS-PAGE-ROW
    LIBQS.REF RREF.ID _LQ12E-rid-one RID= _LQ12E-assert
1 _LQ12E-page LIBRARY-CORPUS-PAGE-ROW
    LIBQS.REF RREF.ID _LQ12E-rid-two RID= _LQ12E-assert

\ Lifecycle/kind/media masks are exact even on an empty-term browse.
_LQ12E-request LIBRARY-CORPUS-QUERY-REQUEST-INIT
LIBRARY-CORPUS-MEDIA-PLAIN _LQ12E-request LIBCQR.MEDIA-MASK !
_LQ12E-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-CORPUS-QUERY-FIRST LIBPA-S-OK _LQ12E-status
_LQ12E-page LIBQP.COUNT @ 2 = _LQ12E-assert
LIBRARY-CORPUS-MEDIA-MARKDOWN _LQ12E-request LIBCQR.MEDIA-MASK !
_LQ12E-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-CORPUS-QUERY-FIRST LIBPA-S-OK _LQ12E-status
_LQ12E-page LIBQP.COUNT @ 0= _LQ12E-assert
LIBRARY-CORPUS-LIFECYCLE-ARCHIVED
    _LQ12E-request LIBCQR.LIFECYCLE-MASK !
_LQ12E-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-CORPUS-QUERY-FIRST LIBPA-S-OK _LQ12E-status
_LQ12E-page LIBQP.COUNT @ 1 = _LQ12E-assert
0 _LQ12E-page LIBRARY-CORPUS-PAGE-ROW
    DUP LIBQS.KIND @ LIB-KIND-CAPTURE = _LQ12E-assert
    DUP LIBQS.LIFECYCLE @ LIB-LIFECYCLE-ARCHIVED = _LQ12E-assert
    LIBQS.REF RREF.ID _LQ12E-rid-three RID= _LQ12E-assert
LIBRARY-CORPUS-MEDIA-ALL _LQ12E-request LIBCQR.MEDIA-MASK !
LIBRARY-CORPUS-KIND-CAPTURE _LQ12E-request LIBCQR.KIND-MASK !
_LQ12E-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-CORPUS-QUERY-FIRST LIBPA-S-OK _LQ12E-status
_LQ12E-page LIBQP.COUNT @ 1 = _LQ12E-assert
LIBRARY-CORPUS-KIND-ALL _LQ12E-request LIBCQR.KIND-MASK !
_LQ12E-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-CORPUS-QUERY-FIRST LIBPA-S-OK _LQ12E-status
_LQ12E-page LIBQP.COUNT @ 1 = _LQ12E-assert

S" absent" _LQ12E-request LIBRARY-CORPUS-QUERY-TERM!
    LIBPA-S-OK _LQ12E-status
LIBRARY-CORPUS-FIELD-ALL _LQ12E-request LIBCQR.FIELD-MASK !
_LQ12E-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-CORPUS-QUERY-FIRST LIBPA-S-OK _LQ12E-status
_LQ12E-page LIBQP.COUNT @ 0= _LQ12E-assert
_LQ12E-page LIBRARY-CORPUS-PAGE-VALID? _LQ12E-assert

\ Three exact collections establish relationship filtering and a real
\ multi-page collection range.
_LQ12E-rid-one _LQ12E-member-rids RID-COPY
_LQ12E-rid-two _LQ12E-member-rids RID-SIZE + RID-COPY
_LQ12E-collection LIBPA-COLLECTION-INIT
_LQ12E-collection-rid-one _LQ12E-collection LIBPAC.ID RID-COPY
0x71 _LQ12E-collection LIBPAC.OPERATION-KEY !
1 _LQ12E-collection LIBPAC.REVISION !
5 _LQ12E-collection LIBPAC.MUTATION-SEQUENCE !
5 _LQ12E-collection LIBPAC.CREATED-SEQUENCE !
2 _LQ12E-collection LIBPAC.MEMBER-N !
S" Alpha collection" _LQ12E-collection LIBPAC.TITLE
    _LQ12E-collection LIBPAC.TITLE-U _LQ12E-text!
_LQ12E-collection _LQ12E-member-rids 2
    LIBPA-COLLECTION-REQUEST-SEAL! LIBPA-S-OK _LQ12E-status
_LQ12E-collection _LQ12E-member-rids 2 4 _LQ12E-collection-out
_LQ12E-adapter _LQ12E-index-work
    LIBPA-COLLECTION-CREATE-EXACT LIBPA-S-OK _LQ12E-status

_LQ12E-collection LIBPA-COLLECTION-INIT
_LQ12E-collection-rid-two _LQ12E-collection LIBPAC.ID RID-COPY
0x72 _LQ12E-collection LIBPAC.OPERATION-KEY !
1 _LQ12E-collection LIBPAC.REVISION !
6 _LQ12E-collection LIBPAC.MUTATION-SEQUENCE !
6 _LQ12E-collection LIBPAC.CREATED-SEQUENCE !
0 _LQ12E-collection LIBPAC.MEMBER-N !
S" Beta collection" _LQ12E-collection LIBPAC.TITLE
    _LQ12E-collection LIBPAC.TITLE-U _LQ12E-text!
_LQ12E-collection 0 0
    LIBPA-COLLECTION-REQUEST-SEAL! LIBPA-S-OK _LQ12E-status
_LQ12E-collection 0 0 5 _LQ12E-collection-out
_LQ12E-adapter _LQ12E-index-work
    LIBPA-COLLECTION-CREATE-EXACT LIBPA-S-OK _LQ12E-status

_LQ12E-collection LIBPA-COLLECTION-INIT
_LQ12E-collection-rid-three _LQ12E-collection LIBPAC.ID RID-COPY
0x73 _LQ12E-collection LIBPAC.OPERATION-KEY !
1 _LQ12E-collection LIBPAC.REVISION !
7 _LQ12E-collection LIBPAC.MUTATION-SEQUENCE !
7 _LQ12E-collection LIBPAC.CREATED-SEQUENCE !
0 _LQ12E-collection LIBPAC.MEMBER-N !
S" Gamma collection" _LQ12E-collection LIBPAC.TITLE
    _LQ12E-collection LIBPAC.TITLE-U _LQ12E-text!
_LQ12E-collection 0 0
    LIBPA-COLLECTION-REQUEST-SEAL! LIBPA-S-OK _LQ12E-status
_LQ12E-collection 0 0 6 _LQ12E-collection-out
_LQ12E-adapter _LQ12E-index-work
    LIBPA-COLLECTION-CREATE-EXACT LIBPA-S-OK _LQ12E-status

_LQ12E-collection-request LIBRARY-COLLECTION-QUERY-REQUEST-INIT
_LQ12E-collection-rows 2 _LQ12E-page
    LIBRARY-COLLECTION-PAGE-INIT LIBPA-S-OK _LQ12E-status
_LQ12E-collection-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-COLLECTION-QUERY-FIRST LIBPA-S-OK _LQ12E-status
_LQ12E-page LIBQP.COUNT @ 2 = _LQ12E-assert
0 _LQ12E-page LIBRARY-COLLECTION-PAGE-ROW
    LIBCS.REF RREF.ID _LQ12E-collection-rid-one RID= _LQ12E-assert
1 _LQ12E-page LIBRARY-COLLECTION-PAGE-ROW
    LIBCS.REF RREF.ID _LQ12E-collection-rid-two RID= _LQ12E-assert
_LQ12E-page LIBQP.CONTINUATION
    LIBRARY-QUERY-CONTINUATION-HAS-AFTER? _LQ12E-assert
_LQ12E-page LIBQP.CONTINUATION
    LIBQC.OBSERVED-LOGICAL-GENERATION @ 7 = _LQ12E-assert

\ A content mutation is unrelated to the open collection keyset.  It must
\ neither conflict nor make the continuation physical-generation state.
_LQ12E-source 96 0 FILL
S" rev02" _LQ12E-source SWAP MOVE
_LQ12E-content-next LIB-CONTENT-INIT
_LQ12E-rid-one _LQ12E-content-next LIBCT.ID RID-COPY
2 _LQ12E-content-next LIBCT.DOMAIN-REVISION !
2 _LQ12E-content-next LIBCT.CONTENT-REVISION !
LIB-KIND-MANAGED-DOCUMENT _LQ12E-content-next LIBCT.KIND !
LIB-MEDIA-TEXT-PLAIN _LQ12E-content-next LIBCT.MEDIA !
_LQ12E-source _LQ12E-content-next LIBCT.DATA-A !
5 _LQ12E-content-next LIBCT.DATA-U !
_LQ12E-content-next LIB-CONTENT-DIGEST!
    LIB-S-OK _LQ12E-status
_LQ12E-entry-one _LQ12E-entry LIB-ENTRY-SIZE MOVE
2 _LQ12E-entry LIBE.DOMAIN-REVISION !
2 _LQ12E-entry LIBE.CURRENT-CONTENT-REVISION !
1 _LQ12E-entry LIBE.OLDEST-CONTENT-REVISION !
5 _LQ12E-entry LIBE.CONTENT-U !
_LQ12E-content-next LIBCT.DIGEST
    _LQ12E-entry LIBE.CONTENT-DIGEST RID-COPY
8 _LQ12E-entry LIBE.MUTATION-SEQUENCE !
8 _LQ12E-entry LIBE.MODIFIED-VALUE !
_LQ12E-entry LIB-ENTRY-VALID? _LQ12E-assert
_LQ12E-entry _LQ12E-content-next 7 1 _LQ12E-entry-out
_LQ12E-adapter _LQ12E-index-work
    LIBPA-DOCUMENT-CONTENT-REPLACE-EXACT
    LIBPA-S-OK _LQ12E-status
_LQ12E-entry-out _LQ12E-entry-one LIB-ENTRY-SIZE MOVE

_LQ12E-collection-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-COLLECTION-QUERY-AFTER LIBPA-S-OK _LQ12E-status
_LQ12E-page LIBQP.COUNT @ 1 = _LQ12E-assert
0 _LQ12E-page LIBRARY-COLLECTION-PAGE-ROW
    LIBCS.REF RREF.ID _LQ12E-collection-rid-three RID= _LQ12E-assert
_LQ12E-page LIBQP.CONTINUATION
    LIBQC.OBSERVED-LOGICAL-GENERATION @ 8 = _LQ12E-assert
_LQ12E-collection-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-COLLECTION-QUERY-BEFORE LIBPA-S-OK _LQ12E-status
_LQ12E-page LIBQP.COUNT @ 2 = _LQ12E-assert
0 _LQ12E-page LIBRARY-COLLECTION-PAGE-ROW
    LIBCS.REF RREF.ID _LQ12E-collection-rid-one RID= _LQ12E-assert
1 _LQ12E-page LIBRARY-COLLECTION-PAGE-ROW
    LIBCS.REF RREF.ID _LQ12E-collection-rid-two RID= _LQ12E-assert

\ Collection membership remains an exact relationship filter after the
\ unrelated document mutation.
_LQ12E-request LIBRARY-CORPUS-QUERY-REQUEST-INIT
_LQ12E-collection-rid-one _LQ12E-request
    LIBRARY-CORPUS-QUERY-COLLECTION! LIBPA-S-OK _LQ12E-status
_LQ12E-corpus-rows 4 _LQ12E-page
    LIBRARY-CORPUS-PAGE-INIT LIBPA-S-OK _LQ12E-status
_LQ12E-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-CORPUS-QUERY-FIRST LIBPA-S-OK _LQ12E-status
_LQ12E-page LIBQP.COUNT @ 2 = _LQ12E-assert
0 _LQ12E-page LIBRARY-CORPUS-PAGE-ROW
    LIBQS.REF RREF.ID _LQ12E-rid-one RID= _LQ12E-assert
1 _LQ12E-page LIBRARY-CORPUS-PAGE-ROW
    LIBQS.REF RREF.ID _LQ12E-rid-two RID= _LQ12E-assert

\ A third immutable content revision makes history exercise the same
\ FIRST/AFTER/BEFORE and canonical reverse-page contract.
_LQ12E-source 96 0 FILL
S" rev03" _LQ12E-source SWAP MOVE
_LQ12E-content-next LIB-CONTENT-INIT
_LQ12E-rid-one _LQ12E-content-next LIBCT.ID RID-COPY
3 _LQ12E-content-next LIBCT.DOMAIN-REVISION !
3 _LQ12E-content-next LIBCT.CONTENT-REVISION !
LIB-KIND-MANAGED-DOCUMENT _LQ12E-content-next LIBCT.KIND !
LIB-MEDIA-TEXT-PLAIN _LQ12E-content-next LIBCT.MEDIA !
_LQ12E-source _LQ12E-content-next LIBCT.DATA-A !
5 _LQ12E-content-next LIBCT.DATA-U !
_LQ12E-content-next LIB-CONTENT-DIGEST!
    LIB-S-OK _LQ12E-status
_LQ12E-entry-one _LQ12E-entry LIB-ENTRY-SIZE MOVE
3 _LQ12E-entry LIBE.DOMAIN-REVISION !
3 _LQ12E-entry LIBE.CURRENT-CONTENT-REVISION !
1 _LQ12E-entry LIBE.OLDEST-CONTENT-REVISION !
5 _LQ12E-entry LIBE.CONTENT-U !
_LQ12E-content-next LIBCT.DIGEST
    _LQ12E-entry LIBE.CONTENT-DIGEST RID-COPY
9 _LQ12E-entry LIBE.MUTATION-SEQUENCE !
9 _LQ12E-entry LIBE.MODIFIED-VALUE !
_LQ12E-entry LIB-ENTRY-VALID? _LQ12E-assert
_LQ12E-entry _LQ12E-content-next 8 2 _LQ12E-entry-out
_LQ12E-adapter _LQ12E-index-work
    LIBPA-DOCUMENT-CONTENT-REPLACE-EXACT
    LIBPA-S-OK _LQ12E-status
_LQ12E-entry-out _LQ12E-entry-one LIB-ENTRY-SIZE MOVE

_LQ12E-history-request LIBRARY-HISTORY-QUERY-REQUEST-INIT
_LQ12E-rid-one _LQ12E-history-request
    LIBRARY-HISTORY-QUERY-RID! LIBPA-S-OK _LQ12E-status
_LQ12E-history-rows 2 _LQ12E-page
    LIBRARY-HISTORY-PAGE-INIT LIBPA-S-OK _LQ12E-status
_LQ12E-history-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-HISTORY-QUERY-FIRST LIBPA-S-OK _LQ12E-status
_LQ12E-page LIBQP.COUNT @ 2 = _LQ12E-assert
0 _LQ12E-page LIBRARY-HISTORY-PAGE-ROW
    DUP LIBRARY-REVISION-SUMMARY-VALID? _LQ12E-assert
    LIBRS.DOMAIN-REVISION @ 1 = _LQ12E-assert
1 _LQ12E-page LIBRARY-HISTORY-PAGE-ROW
    LIBRS.DOMAIN-REVISION @ 2 = _LQ12E-assert
_LQ12E-page LIBQP.CONTINUATION
    LIBRARY-QUERY-CONTINUATION-HAS-AFTER? _LQ12E-assert
_LQ12E-history-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-HISTORY-QUERY-AFTER LIBPA-S-OK _LQ12E-status
_LQ12E-page LIBQP.COUNT @ 1 = _LQ12E-assert
0 _LQ12E-page LIBRARY-HISTORY-PAGE-ROW
    LIBRS.DOMAIN-REVISION @ 3 = _LQ12E-assert
_LQ12E-history-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-HISTORY-QUERY-BEFORE LIBPA-S-OK _LQ12E-status
_LQ12E-page LIBQP.COUNT @ 2 = _LQ12E-assert
0 _LQ12E-page LIBRARY-HISTORY-PAGE-ROW
    LIBRS.DOMAIN-REVISION @ 1 = _LQ12E-assert
1 _LQ12E-page LIBRARY-HISTORY-PAGE-ROW
    LIBRS.DOMAIN-REVISION @ 2 = _LQ12E-assert

\ A body larger than the old materialization window is persisted as three
\ immutable chunks.  The exact term starts four bytes before the first PBLOB
\ boundary, so KMP state must survive one streamed callback boundary.
_LQ12E-large-body 70000 0x78 FILL
S" boundary"
    _LQ12E-large-body PBLOB-CHUNK-SIZE 4 - + SWAP MOVE
_LQ12E-content LIB-CONTENT-INIT
_LQ12E-rid-four _LQ12E-content LIBCT.ID RID-COPY
1 _LQ12E-content LIBCT.DOMAIN-REVISION !
1 _LQ12E-content LIBCT.CONTENT-REVISION !
LIB-KIND-MANAGED-DOCUMENT _LQ12E-content LIBCT.KIND !
LIB-MEDIA-TEXT-PLAIN _LQ12E-content LIBCT.MEDIA !
_LQ12E-large-body _LQ12E-content LIBCT.DATA-A !
70000 _LQ12E-content LIBCT.DATA-U !
_LQ12E-content LIB-CONTENT-DIGEST! LIB-S-OK _LQ12E-status

_LQ12E-entry-one _LQ12E-entry LIB-ENTRY-SIZE MOVE
_LQ12E-rid-four _LQ12E-entry LIBE.ID RID-COPY
1 _LQ12E-entry LIBE.DOMAIN-REVISION !
LIB-KIND-MANAGED-DOCUMENT _LQ12E-entry LIBE.KIND !
LIB-LIFECYCLE-ACTIVE _LQ12E-entry LIBE.LIFECYCLE !
LIB-MEDIA-TEXT-PLAIN _LQ12E-entry LIBE.MEDIA !
1 _LQ12E-entry LIBE.CURRENT-CONTENT-REVISION !
1 _LQ12E-entry LIBE.OLDEST-CONTENT-REVISION !
70000 _LQ12E-entry LIBE.CONTENT-U !
_LQ12E-content LIBCT.DIGEST
    _LQ12E-entry LIBE.CONTENT-DIGEST RID-COPY
10 _LQ12E-entry LIBE.MUTATION-SEQUENCE !
LIB-CLOCK-MUTATION-SEQUENCE _LQ12E-entry LIBE.CREATED-CLOCK !
10 _LQ12E-entry LIBE.CREATED-VALUE !
LIB-CLOCK-MUTATION-SEQUENCE _LQ12E-entry LIBE.MODIFIED-CLOCK !
10 _LQ12E-entry LIBE.MODIFIED-VALUE !
_LQ12E-entry LIBE.TITLE LIB-TITLE-MAX 0 FILL
S" L"
    _LQ12E-entry LIBE.TITLE _LQ12E-entry LIBE.TITLE-U _LQ12E-text!
_LQ12E-entry LIBE.RECEIPT
DUP LIBR.OPERATION-KEY RID-CLEAR
0x54 OVER LIBR.OPERATION-KEY !
LIB-IMPORT-CREATED OVER LIBR.METHOD !
1 OVER LIBR.INITIAL-CONTENT-REVISION !
70000 OVER LIBR.INITIAL-CONTENT-U !
LIB-MEDIA-TEXT-PLAIN OVER LIBR.INITIAL-MEDIA !
_LQ12E-entry LIBE.CONTENT-DIGEST
    OVER LIBR.INITIAL-CONTENT-DIGEST RID-COPY
DROP
S" tag" _LQ12E-entry _LQ12E-entry-tag!
_LQ12E-entry LIB-ENTRY-REQUEST-SEAL! LIB-S-OK _LQ12E-status
_LQ12E-entry LIB-ENTRY-VALID? _LQ12E-assert
_LQ12E-content LIB-CONTENT-VALID? _LQ12E-assert
_LQ12E-entry _LQ12E-content _LQ12E-facts _LQ12E-facts-u @
    9 _LQ12E-entry-out
_LQ12E-adapter _LQ12E-index-work
    LIBPA-DOCUMENT-CREATE-EXACT LIBPA-S-OK _LQ12E-status

_LQ12E-request LIBRARY-CORPUS-QUERY-REQUEST-INIT
S" boundary" _LQ12E-request LIBRARY-CORPUS-QUERY-TERM!
    LIBPA-S-OK _LQ12E-status
LIBRARY-CORPUS-FIELD-BODY _LQ12E-request LIBCQR.FIELD-MASK !
_LQ12E-corpus-rows 4 _LQ12E-page
    LIBRARY-CORPUS-PAGE-INIT LIBPA-S-OK _LQ12E-status
_LQ12E-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-CORPUS-QUERY-FIRST LIBPA-S-OK _LQ12E-status
_LQ12E-page LIBQP.COUNT @ 1 = _LQ12E-assert
0 _LQ12E-page LIBRARY-CORPUS-PAGE-ROW
    DUP LIBQS.CONTENT-U @ 70000 = _LQ12E-assert
    LIBQS.REF RREF.ID _LQ12E-rid-four RID= _LQ12E-assert

\ Publish a full four-row page before fault injection.  On the retry the first
\ matching row is staged, then exact verification of the second document must
\ perform another bounded segment read.  Failing the second raw read after that
\ staged row proves both earlier read progress and late output atomicity without
\ depending on how warm the page caches happen to be.
_LQ12E-request LIBRARY-CORPUS-QUERY-REQUEST-INIT
S" tag" _LQ12E-request LIBRARY-CORPUS-QUERY-TERM!
    LIBPA-S-OK _LQ12E-status
LIBRARY-CORPUS-LIFECYCLE-ALL
    _LQ12E-request LIBCQR.LIFECYCLE-MASK !
LIBRARY-CORPUS-FIELD-ALL _LQ12E-request LIBCQR.FIELD-MASK !
_LQ12E-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-CORPUS-QUERY-FIRST LIBPA-S-OK _LQ12E-status
_LQ12E-page LIBQP.COUNT @ 4 = _LQ12E-assert
_LQ12E-page LIBQP.CONTINUATION
    LIBRARY-QUERY-CONTINUATION-HAS-AFTER? 0= _LQ12E-assert

\ The RAM binding's public read operation is the narrow fault seam; snapshot
\ the complete descriptor and all four caller-owned rows before the retry.
_LQ12E-page _LQ12E-page-snapshot LIBRARY-QUERY-PAGE-SIZE MOVE
_LQ12E-corpus-rows _LQ12E-corpus-rows-snapshot
    LIBRARY-QUERY-SUMMARY-SIZE 4 * MOVE
_LQ12E-read-arm
_LQ12E-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-CORPUS-QUERY-FIRST
_LQ12E-read-restore
    LIBPA-S-IO _LQ12E-status
_LQ12E-read-after-stage @
    _LQ12E-read-fail-n = _LQ12E-assert
_LQ12E-read-staged-n @ 1 = _LQ12E-assert
_LQ12E-read-failed-at @ _LQ12E-read-calls @ = _LQ12E-assert
_LQ12E-read-calls @ _LQ12E-read-fail-n > _LQ12E-assert
_LQ12E-page _LQ12E-page-snapshot LIBRARY-QUERY-PAGE-SIZE
    _LQ12E-bytes= _LQ12E-assert
_LQ12E-corpus-rows _LQ12E-corpus-rows-snapshot
    LIBRARY-QUERY-SUMMARY-SIZE 4 * _LQ12E-bytes= _LQ12E-assert

\ Tombstones remain durable point values but are outside every public corpus
\ lifecycle mask.  Use the domain preparer and exact adapter mutation rather
\ than manufacturing a state-index row in the fixture.
_LQ12E-entry-three 11 _LQ12E-entry
    LIBRARY-SERVICE-PREPARE-TOMBSTONE-NEXT
    _LIBDV-S-OK _LQ12E-status
_LQ12E-entry 10 2 _LQ12E-entry-out
_LQ12E-adapter _LQ12E-index-work
    LIBPA-DOCUMENT-TOMBSTONE-EXACT LIBPA-S-OK _LQ12E-status
_LQ12E-entry-out LIBE.LIFECYCLE @
    LIB-LIFECYCLE-TOMBSTONED = _LQ12E-assert
_LQ12E-request LIBRARY-CORPUS-QUERY-REQUEST-INIT
LIBRARY-CORPUS-LIFECYCLE-ALL
    _LQ12E-request LIBCQR.LIFECYCLE-MASK !
LIBRARY-CORPUS-KIND-CAPTURE _LQ12E-request LIBCQR.KIND-MASK !
_LQ12E-request _LQ12E-page
_LQ12E-adapter _LQ12E-index-work _LQ12E-query-work
    LIBRARY-CORPUS-QUERY-FIRST LIBPA-S-OK _LQ12E-status
_LQ12E-page LIBQP.COUNT @ 0= _LQ12E-assert

\ Retained restore is a managed-document operation, so exercise resurrection
\ rejection on a second real tombstone rather than letting the capture kind
\ fail restore argument validation.  Preserve exact revision-one facts and
\ prepare an otherwise-valid active same-RID candidate before destruction.
_LQ12E-rid-one 1 _LQ12E-descriptor
_LQ12E-adapter _LQ12E-index-work
    LIBPA-HISTORY-READ LIBPA-S-OK _LQ12E-status
_LQ12E-descriptor _LQ12E-retained-facts
    _LIBPA-DESCRIPTOR>RETAINED-FACTS
    LIBPA-S-OK _LQ12E-status
_LQ12E-retained-facts
    LIBRARY-RETAINED-CONTENT-FACTS-VALID? _LQ12E-assert
_LQ12E-entry-one _LQ12E-retained-facts
_LQ12E-index-work LIBPA-INDEX-MUTATION-SEQUENCE@ 2 +
_LQ12E-entry-restore
    LIBRARY-SERVICE-PREPARE-RETAINED-RESTORE
    _LIBDV-S-OK _LQ12E-status

\ Commit the managed tombstone at the intervening global mutation.  The
\ retained candidate's domain revision is then advanced to the only plausible
\ next revision; it remains a structurally valid, active managed entry and
\ passes the exact restore call's argument gate.
_LQ12E-entry-one
_LQ12E-index-work LIBPA-INDEX-MUTATION-SEQUENCE@ 1+
_LQ12E-entry
    LIBRARY-SERVICE-PREPARE-TOMBSTONE-NEXT
    _LIBDV-S-OK _LQ12E-status
_LQ12E-entry
_LQ12E-index-work LIBPA-INDEX-LOGICAL-GENERATION@
_LQ12E-entry-one LIBE.DOMAIN-REVISION @
_LQ12E-entry-out _LQ12E-adapter _LQ12E-index-work
    LIBPA-DOCUMENT-TOMBSTONE-EXACT
    LIBPA-S-OK _LQ12E-status
_LQ12E-entry-out _LQ12E-entry-one LIB-ENTRY-SIZE MOVE
_LQ12E-entry-one LIBE.DOMAIN-REVISION @ 1+
    _LQ12E-entry-restore LIBE.DOMAIN-REVISION !
_LQ12E-entry-restore LIB-ENTRY-VALID? _LQ12E-assert
_LQ12E-entry-restore LIBE.ID
    _LQ12E-entry-one LIBE.ID RID= _LQ12E-assert
_LQ12E-entry-restore LIBE.LIFECYCLE @
    LIB-LIFECYCLE-ACTIVE = _LQ12E-assert
_LQ12E-entry-restore LIBE.KIND @
    LIB-KIND-MANAGED-DOCUMENT = _LQ12E-assert
_LQ12E-entry-restore LIBE.MUTATION-SEQUENCE @
_LQ12E-index-work LIBPA-INDEX-MUTATION-SEQUENCE@ 1+
    = _LQ12E-assert
_LQ12E-entry-one LIBE.LIFECYCLE @
    LIB-LIFECYCLE-TOMBSTONED = _LQ12E-assert

\ The pure value preparer rejects the actual current tombstone.  The exact
\ owner must reject the same resurrection without publishing or advancing
\ either physical or semantic authority state.
_LQ12E-entry-one _LQ12E-retained-facts
_LQ12E-index-work LIBPA-INDEX-MUTATION-SEQUENCE@ 1+
_LQ12E-entry
    LIBRARY-SERVICE-PREPARE-RETAINED-RESTORE
    _LIBDV-S-INVALID _LQ12E-status
_LQ12E-entry-out LIB-ENTRY-SIZE 0xA5 FILL
_LQ12E-entry-out _LQ12E-entry-sentinel LIB-ENTRY-SIZE MOVE
_LQ12E-store PSTORE-GENERATION@ _LQ12E-physical-before !
_LQ12E-index-work LIBPA-INDEX-LOGICAL-GENERATION@
    _LQ12E-logical-before !
_LQ12E-index-work LIBPA-INDEX-MUTATION-SEQUENCE@
    _LQ12E-mutation-before !
_LQ12E-entry-restore 1
_LQ12E-logical-before @
_LQ12E-entry-one LIBE.DOMAIN-REVISION @
_LQ12E-entry-out _LQ12E-adapter _LQ12E-index-work
    LIBPA-DOCUMENT-RESTORE-RETAINED-EXACT
    LIBPA-S-INVALID _LQ12E-status
_LQ12E-entry-out _LQ12E-entry-sentinel LIB-ENTRY-SIZE
    _LQ12E-bytes= _LQ12E-assert
_LQ12E-store PSTORE-GENERATION@
    _LQ12E-physical-before @ = _LQ12E-assert
_LQ12E-index-work LIBPA-INDEX-LOGICAL-GENERATION@
    _LQ12E-logical-before @ = _LQ12E-assert
_LQ12E-index-work LIBPA-INDEX-MUTATION-SEQUENCE@
    _LQ12E-mutation-before @ = _LQ12E-assert

_LQ12E-stack
_LQ12E-report
