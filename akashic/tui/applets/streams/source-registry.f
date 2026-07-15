\ =====================================================================
\  source-registry.f - Bounded, pointer-free Streams source registry
\ =====================================================================
\  The registry owns source configuration only.  Acquisition cursors,
\  observations, credentials, capability authority, and Practice bindings
\  have no representation here.
\
\  A source has one stable caller-supplied 32-byte RID and a positive
\  optimistic configuration revision.  CREATE changes revision 0 to 1;
\  REPLACE and ENABLE require the exact current revision and advance it.
\  REMOVE also requires the exact current revision.  A freshly initialized
\  in-memory registry has generation 0; its first semantic mutation advances
\  it to the first persistable generation, 1.  Every later successful
\  semantic mutation advances the generation exactly once.
\
\  Strings are exact UTF-8 byte sequences.  They are not normalized or
\  interpreted as network authority by this module.  Provider code must
\  separately admit schemes, hosts, redirects, and provider-specific
\  configuration before an external operation begins.
\
\  Public construction and access API:
\    STREAMS-SOURCE-INIT             ( source -- )
\    STREAMS-SOURCE-ID!              ( rid source -- status )
\    STREAMS-SOURCE-LABEL!           ( a u source -- status )
\    STREAMS-SOURCE-ENDPOINT!        ( a u source -- status )
\    STREAMS-SOURCE-CONFIG!          ( a u source -- status )
\    STREAMS-SOURCE-VALID?           ( source -- flag )
\    STREAMS-SOURCE-LABEL$           ( source -- a u )
\    STREAMS-SOURCE-ENDPOINT$        ( source -- a u )
\    STREAMS-SOURCE-CONFIG$          ( source -- a u )
\
\  Public registry API:
\    STREAMS-SOURCE-REGISTRY-INIT    ( registry -- )
\    STREAMS-SOURCE-REGISTRY-VALID?  ( registry -- flag )
\    STREAMS-SOURCE-COUNT            ( registry -- count )
\    STREAMS-SOURCE-NTH              ( index registry -- source|0 )
\    STREAMS-SOURCE-FIND             ( rid registry -- source|0 )
\    STREAMS-SOURCE-CREATE           ( candidate registry -- status )
\    STREAMS-SOURCE-READ             ( rid destination registry -- status )
\    STREAMS-SOURCE-REPLACE
\      ( candidate expected-revision registry -- status )
\    STREAMS-SOURCE-ENABLE
\      ( rid expected-revision enabled? registry -- status )
\    STREAMS-SOURCE-REMOVE
\      ( rid expected-revision registry -- status )
\
\  NTH and FIND return borrowed records.  A mutation candidate or READ
\  destination must not alias registry storage.  Use READ into a separate
\  STREAMS-SOURCE-SIZE buffer, edit that candidate, and pass its original
\  revision to REPLACE.
\ =====================================================================

PROVIDED akashic-streams-srcreg

REQUIRE ../../../runtime/identity.f
REQUIRE ../../../text/utf8.f
REQUIRE ../../../concurrency/guard.f

\ =====================================================================
\  Public statuses, kinds, formats, policy, and hard bounds
\ =====================================================================

0 CONSTANT SSREG-S-OK
1 CONSTANT SSREG-S-INVALID
2 CONSTANT SSREG-S-NOT-FOUND
3 CONSTANT SSREG-S-FULL
4 CONSTANT SSREG-S-DUPLICATE
5 CONSTANT SSREG-S-STALE
6 CONSTANT SSREG-S-CAPACITY
7 CONSTANT SSREG-S-UNSUPPORTED

1 CONSTANT SSOURCE-KIND-SYNDICATION
2 CONSTANT SSOURCE-KIND-PAGE
3 CONSTANT SSOURCE-KIND-NOTIFICATION
4 CONSTANT SSOURCE-KIND-BLUESKY-PUBLIC

1 CONSTANT SSOURCE-FORMAT-AUTO
2 CONSTANT SSOURCE-FORMAT-RSS
3 CONSTANT SSOURCE-FORMAT-ATOM
4 CONSTANT SSOURCE-FORMAT-JSON-FEED
5 CONSTANT SSOURCE-FORMAT-HTML
6 CONSTANT SSOURCE-FORMAT-TEXT
7 CONSTANT SSOURCE-FORMAT-NTFY-JSON
8 CONSTANT SSOURCE-FORMAT-ATPROTO-JSON

0 CONSTANT SSOURCE-REFRESH-MANUAL
1 CONSTANT SSOURCE-REFRESH-INTERVAL

1 CONSTANT SSOURCE-F-ENABLED

16     CONSTANT STREAMS-SOURCE-MAX
96     CONSTANT STREAMS-SOURCE-LABEL-MAX
1024   CONSTANT STREAMS-SOURCE-ENDPOINT-MAX
1024   CONSTANT STREAMS-SOURCE-CONFIG-MAX
3      CONSTANT STREAMS-SOURCE-REDIRECT-MAX
131072 CONSTANT STREAMS-SOURCE-RESPONSE-MAX
2      CONSTANT STREAMS-SOURCE-PAGE-MAX
16     CONSTANT STREAMS-SOURCE-OBSERVATION-MAX
4      CONSTANT STREAMS-SOURCE-REVISION-MAX
60000  CONSTANT STREAMS-SOURCE-INTERVAL-MIN-MS
604800000 CONSTANT STREAMS-SOURCE-INTERVAL-MAX-MS

\ =====================================================================
\  Pointer-free fixed source record
\ =====================================================================

   0 CONSTANT _SSO-ID                    \ RID-SIZE bytes
  32 CONSTANT _SSO-REVISION
  40 CONSTANT _SSO-KIND
  48 CONSTANT _SSO-FORMAT
  56 CONSTANT _SSO-FLAGS
  64 CONSTANT _SSO-REDIRECT-MAX
  72 CONSTANT _SSO-RESPONSE-MAX
  80 CONSTANT _SSO-PAGE-MAX
  88 CONSTANT _SSO-OBSERVATION-MAX
  96 CONSTANT _SSO-REVISION-MAX
 104 CONSTANT _SSO-REFRESH-POLICY
 112 CONSTANT _SSO-INTERVAL-MS
 120 CONSTANT _SSO-LABEL-U
 128 CONSTANT _SSO-ENDPOINT-U
 136 CONSTANT _SSO-CONFIG-U
 144 CONSTANT _SSO-LABEL
 240 CONSTANT _SSO-ENDPOINT
1264 CONSTANT _SSO-CONFIG
2288 CONSTANT STREAMS-SOURCE-SIZE

: SSOURCE.ID               ( source -- id ) _SSO-ID + ;
: SSOURCE.REVISION         ( source -- a ) _SSO-REVISION + ;
: SSOURCE.KIND             ( source -- a ) _SSO-KIND + ;
: SSOURCE.FORMAT           ( source -- a ) _SSO-FORMAT + ;
: SSOURCE.FLAGS            ( source -- a ) _SSO-FLAGS + ;
: SSOURCE.REDIRECT-MAX     ( source -- a ) _SSO-REDIRECT-MAX + ;
: SSOURCE.RESPONSE-MAX     ( source -- a ) _SSO-RESPONSE-MAX + ;
: SSOURCE.PAGE-MAX         ( source -- a ) _SSO-PAGE-MAX + ;
: SSOURCE.OBSERVATION-MAX  ( source -- a ) _SSO-OBSERVATION-MAX + ;
: SSOURCE.REVISION-MAX     ( source -- a ) _SSO-REVISION-MAX + ;
: SSOURCE.REFRESH-POLICY   ( source -- a ) _SSO-REFRESH-POLICY + ;
: SSOURCE.INTERVAL-MS      ( source -- a ) _SSO-INTERVAL-MS + ;
: SSOURCE.LABEL-U          ( source -- a ) _SSO-LABEL-U + ;
: SSOURCE.ENDPOINT-U       ( source -- a ) _SSO-ENDPOINT-U + ;
: SSOURCE.CONFIG-U         ( source -- a ) _SSO-CONFIG-U + ;
: SSOURCE.LABEL            ( source -- a ) _SSO-LABEL + ;
: SSOURCE.ENDPOINT         ( source -- a ) _SSO-ENDPOINT + ;
: SSOURCE.CONFIG           ( source -- a ) _SSO-CONFIG + ;

: STREAMS-SOURCE-LABEL$  ( source -- a u )
    DUP SSOURCE.LABEL SWAP SSOURCE.LABEL-U @ ;

: STREAMS-SOURCE-ENDPOINT$  ( source -- a u )
    DUP SSOURCE.ENDPOINT SWAP SSOURCE.ENDPOINT-U @ ;

: STREAMS-SOURCE-CONFIG$  ( source -- a u )
    DUP SSOURCE.CONFIG SWAP SSOURCE.CONFIG-U @ ;

: STREAMS-SOURCE-INIT  ( source -- )
    DUP STREAMS-SOURCE-SIZE 0 FILL
    DUP SSOURCE-F-ENABLED SWAP SSOURCE.FLAGS !
    DUP STREAMS-SOURCE-REDIRECT-MAX SWAP SSOURCE.REDIRECT-MAX !
    DUP STREAMS-SOURCE-RESPONSE-MAX SWAP SSOURCE.RESPONSE-MAX !
    DUP 1 SWAP SSOURCE.PAGE-MAX !
    DUP STREAMS-SOURCE-OBSERVATION-MAX SWAP SSOURCE.OBSERVATION-MAX !
    DUP STREAMS-SOURCE-REVISION-MAX SWAP SSOURCE.REVISION-MAX !
    SSOURCE-REFRESH-MANUAL SWAP SSOURCE.REFRESH-POLICY ! ;

\ =====================================================================
\  Checked candidate construction
\ =====================================================================

GUARD _streams-source-registry-guard

VARIABLE _SSID-SOURCE
VARIABLE _SSID-RID

: _STREAMS-SOURCE-ID!  ( rid source -- status )
    _SSID-SOURCE ! _SSID-RID !
    _SSID-SOURCE @ 0= _SSID-RID @ RID-PRESENT? 0= OR IF
        SSREG-S-INVALID EXIT
    THEN
    _SSID-RID @ _SSID-SOURCE @ SSOURCE.ID RID-COPY
    SSREG-S-OK ;

' _STREAMS-SOURCE-ID! CONSTANT _ssource-id-set-xt
: STREAMS-SOURCE-ID!  ( rid source -- status )
    _ssource-id-set-xt _streams-source-registry-guard WITH-GUARD ;

VARIABLE _SST-A
VARIABLE _SST-U
VARIABLE _SST-D
VARIABLE _SST-CAP

: _SSOURCE-TEXT!  ( a u destination capacity -- status )
    _SST-CAP ! _SST-D ! _SST-U ! _SST-A !
    _SST-U @ 0< _SST-U @ _SST-CAP @ > OR IF
        SSREG-S-CAPACITY EXIT
    THEN
    _SST-U @ 0> _SST-A @ 0= AND IF SSREG-S-INVALID EXIT THEN
    _SST-U @ IF
        _SST-A @ _SST-U @ UTF8-VALID? 0= IF SSREG-S-INVALID EXIT THEN
    THEN
    \ MOVE preserves an exact value when a caller feeds a public string
    \ accessor back to its setter.  Copy before clearing the unused tail so
    \ other overlapping spans are safe as well.
    _SST-U @ IF _SST-A @ _SST-D @ _SST-U @ MOVE THEN
    _SST-D @ _SST-U @ + _SST-CAP @ _SST-U @ - 0 FILL
    SSREG-S-OK ;

VARIABLE _SSTS-A
VARIABLE _SSTS-U
VARIABLE _SSTS-SOURCE

: _STREAMS-SOURCE-LABEL!  ( a u source -- status )
    _SSTS-SOURCE ! _SSTS-U ! _SSTS-A !
    _SSTS-SOURCE @ 0= IF SSREG-S-INVALID EXIT THEN
    _SSTS-A @ _SSTS-U @ _SSTS-SOURCE @ SSOURCE.LABEL
        STREAMS-SOURCE-LABEL-MAX _SSOURCE-TEXT! DUP IF EXIT THEN DROP
    _SSTS-U @ _SSTS-SOURCE @ SSOURCE.LABEL-U !
    SSREG-S-OK ;

: _STREAMS-SOURCE-ENDPOINT!  ( a u source -- status )
    _SSTS-SOURCE ! _SSTS-U ! _SSTS-A !
    _SSTS-SOURCE @ 0= IF SSREG-S-INVALID EXIT THEN
    _SSTS-A @ _SSTS-U @ _SSTS-SOURCE @ SSOURCE.ENDPOINT
        STREAMS-SOURCE-ENDPOINT-MAX _SSOURCE-TEXT! DUP IF EXIT THEN DROP
    _SSTS-U @ _SSTS-SOURCE @ SSOURCE.ENDPOINT-U !
    SSREG-S-OK ;

: _STREAMS-SOURCE-CONFIG!  ( a u source -- status )
    _SSTS-SOURCE ! _SSTS-U ! _SSTS-A !
    _SSTS-SOURCE @ 0= IF SSREG-S-INVALID EXIT THEN
    _SSTS-A @ _SSTS-U @ _SSTS-SOURCE @ SSOURCE.CONFIG
        STREAMS-SOURCE-CONFIG-MAX _SSOURCE-TEXT! DUP IF EXIT THEN DROP
    _SSTS-U @ _SSTS-SOURCE @ SSOURCE.CONFIG-U !
    SSREG-S-OK ;

' _STREAMS-SOURCE-LABEL! CONSTANT _ssource-label-set-xt
' _STREAMS-SOURCE-ENDPOINT! CONSTANT _ssource-endpoint-set-xt
' _STREAMS-SOURCE-CONFIG! CONSTANT _ssource-config-set-xt

: STREAMS-SOURCE-LABEL!  ( a u source -- status )
    _ssource-label-set-xt _streams-source-registry-guard WITH-GUARD ;

: STREAMS-SOURCE-ENDPOINT!  ( a u source -- status )
    _ssource-endpoint-set-xt _streams-source-registry-guard WITH-GUARD ;

: STREAMS-SOURCE-CONFIG!  ( a u source -- status )
    _ssource-config-set-xt _streams-source-registry-guard WITH-GUARD ;

\ =====================================================================
\  Complete semantic validation
\ =====================================================================

VARIABLE _SSKF-KIND
VARIABLE _SSKF-FORMAT

: _SSOURCE-KIND-FORMAT?  ( kind format -- flag )
    _SSKF-FORMAT ! _SSKF-KIND !
    _SSKF-KIND @ SSOURCE-KIND-SYNDICATION = IF
        _SSKF-FORMAT @ SSOURCE-FORMAT-AUTO =
        _SSKF-FORMAT @ SSOURCE-FORMAT-RSS = OR
        _SSKF-FORMAT @ SSOURCE-FORMAT-ATOM = OR
        _SSKF-FORMAT @ SSOURCE-FORMAT-JSON-FEED = OR EXIT
    THEN
    _SSKF-KIND @ SSOURCE-KIND-PAGE = IF
        _SSKF-FORMAT @ SSOURCE-FORMAT-AUTO =
        _SSKF-FORMAT @ SSOURCE-FORMAT-HTML = OR
        _SSKF-FORMAT @ SSOURCE-FORMAT-TEXT = OR EXIT
    THEN
    _SSKF-KIND @ SSOURCE-KIND-NOTIFICATION = IF
        _SSKF-FORMAT @ SSOURCE-FORMAT-NTFY-JSON = EXIT
    THEN
    _SSKF-KIND @ SSOURCE-KIND-BLUESKY-PUBLIC = IF
        _SSKF-FORMAT @ SSOURCE-FORMAT-ATPROTO-JSON = EXIT
    THEN
    0 ;

: _SSOURCE-ZERO?  ( a u -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

VARIABLE _SSFV-A
VARIABLE _SSFV-U
VARIABLE _SSFV-CAP
VARIABLE _SSFV-REQUIRED

: _SSOURCE-FIELD-VALID?  ( a u capacity required? -- flag )
    _SSFV-REQUIRED ! _SSFV-CAP ! _SSFV-U ! _SSFV-A !
    _SSFV-U @ 0< _SSFV-U @ _SSFV-CAP @ > OR IF 0 EXIT THEN
    _SSFV-REQUIRED @ _SSFV-U @ 0= AND IF 0 EXIT THEN
    _SSFV-U @ IF
        _SSFV-A @ _SSFV-U @ UTF8-VALID? 0= IF 0 EXIT THEN
    THEN
    _SSFV-A @ _SSFV-U @ + _SSFV-CAP @ _SSFV-U @ -
        _SSOURCE-ZERO? ;

VARIABLE _SSCV-S

: _SSOURCE-CONFIG-VALID?  ( source -- flag )
    DUP 0= IF DROP 0 EXIT THEN _SSCV-S !
    _SSCV-S @ SSOURCE.ID RID-PRESENT? 0= IF 0 EXIT THEN
    _SSCV-S @ SSOURCE.KIND @ _SSCV-S @ SSOURCE.FORMAT @
        _SSOURCE-KIND-FORMAT? 0= IF 0 EXIT THEN
    _SSCV-S @ SSOURCE.FLAGS @
        SSOURCE-F-ENABLED INVERT AND IF 0 EXIT THEN
    _SSCV-S @ SSOURCE.REDIRECT-MAX @ DUP 0<
        SWAP STREAMS-SOURCE-REDIRECT-MAX > OR IF 0 EXIT THEN
    _SSCV-S @ SSOURCE.RESPONSE-MAX @ DUP 0<
        SWAP STREAMS-SOURCE-RESPONSE-MAX > OR IF 0 EXIT THEN
    _SSCV-S @ SSOURCE.RESPONSE-MAX @ 0= IF 0 EXIT THEN
    _SSCV-S @ SSOURCE.PAGE-MAX @ DUP 1 <
        SWAP STREAMS-SOURCE-PAGE-MAX > OR IF 0 EXIT THEN
    _SSCV-S @ SSOURCE.OBSERVATION-MAX @ DUP 1 <
        SWAP STREAMS-SOURCE-OBSERVATION-MAX > OR IF 0 EXIT THEN
    _SSCV-S @ SSOURCE.REVISION-MAX @ DUP 1 <
        SWAP STREAMS-SOURCE-REVISION-MAX > OR IF 0 EXIT THEN
    _SSCV-S @ SSOURCE.REFRESH-POLICY @ SSOURCE-REFRESH-MANUAL = IF
        _SSCV-S @ SSOURCE.INTERVAL-MS @ IF 0 EXIT THEN
    ELSE
        _SSCV-S @ SSOURCE.REFRESH-POLICY @
            SSOURCE-REFRESH-INTERVAL <> IF 0 EXIT THEN
        _SSCV-S @ SSOURCE.INTERVAL-MS @ DUP
            STREAMS-SOURCE-INTERVAL-MIN-MS <
        SWAP STREAMS-SOURCE-INTERVAL-MAX-MS > OR IF 0 EXIT THEN
    THEN
    _SSCV-S @ SSOURCE.LABEL _SSCV-S @ SSOURCE.LABEL-U @
        STREAMS-SOURCE-LABEL-MAX -1 _SSOURCE-FIELD-VALID? 0= IF
        0 EXIT
    THEN
    _SSCV-S @ SSOURCE.ENDPOINT _SSCV-S @ SSOURCE.ENDPOINT-U @
        STREAMS-SOURCE-ENDPOINT-MAX -1 _SSOURCE-FIELD-VALID? 0= IF
        0 EXIT
    THEN
    _SSCV-S @ SSOURCE.CONFIG _SSCV-S @ SSOURCE.CONFIG-U @
        STREAMS-SOURCE-CONFIG-MAX 0 _SSOURCE-FIELD-VALID? ;

: _STREAMS-SOURCE-VALID?  ( source -- flag )
    DUP _SSOURCE-CONFIG-VALID? 0= IF DROP 0 EXIT THEN
    SSOURCE.REVISION @ 0> ;

' _STREAMS-SOURCE-VALID? CONSTANT _ssource-valid-xt
: STREAMS-SOURCE-VALID?  ( source -- flag )
    _ssource-valid-xt _streams-source-registry-guard WITH-GUARD ;

\ =====================================================================
\  Registry representation and validation
\ =====================================================================

0x5352435245473031 CONSTANT _SSREG-MAGIC  \ "SRCREG01"
1 CONSTANT STREAMS-SOURCE-REGISTRY-ABI

 0 CONSTANT _SSR-MAGIC
 8 CONSTANT _SSR-ABI
16 CONSTANT _SSR-SIZE
24 CONSTANT _SSR-GENERATION
32 CONSTANT _SSR-COUNT
40 CONSTANT _SSR-RECORDS
_SSR-RECORDS STREAMS-SOURCE-MAX STREAMS-SOURCE-SIZE * +
    CONSTANT STREAMS-SOURCE-REGISTRY-SIZE

: SSREG.MAGIC       ( registry -- a ) _SSR-MAGIC + ;
: SSREG.ABI         ( registry -- a ) _SSR-ABI + ;
: SSREG.SIZE        ( registry -- a ) _SSR-SIZE + ;
: SSREG.GENERATION  ( registry -- a ) _SSR-GENERATION + ;
: SSREG.COUNT       ( registry -- a ) _SSR-COUNT + ;
: SSREG.RECORDS     ( registry -- a ) _SSR-RECORDS + ;

: STREAMS-SOURCE-REGISTRY-INIT  ( registry -- )
    DUP STREAMS-SOURCE-REGISTRY-SIZE 0 FILL
    _SSREG-MAGIC OVER SSREG.MAGIC !
    STREAMS-SOURCE-REGISTRY-ABI OVER SSREG.ABI !
    STREAMS-SOURCE-REGISTRY-SIZE SWAP SSREG.SIZE ! ;

: STREAMS-SOURCE-COUNT  ( registry -- count )
    DUP 0= IF DROP 0 EXIT THEN SSREG.COUNT @ ;

: STREAMS-SOURCE-NTH  ( index registry -- source|0 )
    >R DUP 0< OVER R@ SSREG.COUNT @ >= OR IF
        DROP R> DROP 0 EXIT
    THEN
    STREAMS-SOURCE-SIZE * R> SSREG.RECORDS + ;

VARIABLE _SSRF-ID
VARIABLE _SSRF-R
VARIABLE _SSRF-I

: _STREAMS-SOURCE-FIND  ( rid registry -- source|0 )
    _SSRF-R ! _SSRF-ID !
    _SSRF-ID @ RID-PRESENT? 0= IF 0 EXIT THEN
    0 _SSRF-I !
    BEGIN _SSRF-I @ _SSRF-R @ SSREG.COUNT @ < WHILE
        _SSRF-I @ _SSRF-R @ STREAMS-SOURCE-NTH
        DUP SSOURCE.ID _SSRF-ID @ RID= IF EXIT THEN DROP
        1 _SSRF-I +!
    REPEAT
    0 ;

' _STREAMS-SOURCE-FIND CONSTANT _ssource-find-xt
: STREAMS-SOURCE-FIND  ( rid registry -- source|0 )
    _ssource-find-xt _streams-source-registry-guard WITH-GUARD ;

VARIABLE _SSRV-R
VARIABLE _SSRV-I
VARIABLE _SSRV-J
VARIABLE _SSRV-S

: _STREAMS-SOURCE-REGISTRY-VALID?  ( registry -- flag )
    DUP 0= IF DROP 0 EXIT THEN _SSRV-R !
    _SSRV-R @ SSREG.MAGIC @ _SSREG-MAGIC <> IF 0 EXIT THEN
    _SSRV-R @ SSREG.ABI @ STREAMS-SOURCE-REGISTRY-ABI <> IF 0 EXIT THEN
    _SSRV-R @ SSREG.SIZE @ STREAMS-SOURCE-REGISTRY-SIZE <> IF 0 EXIT THEN
    _SSRV-R @ SSREG.GENERATION @ 0< IF 0 EXIT THEN
    _SSRV-R @ SSREG.COUNT @ DUP 0<
        SWAP STREAMS-SOURCE-MAX > OR IF 0 EXIT THEN
    0 _SSRV-I !
    BEGIN _SSRV-I @ _SSRV-R @ SSREG.COUNT @ < WHILE
        _SSRV-I @ _SSRV-R @ STREAMS-SOURCE-NTH DUP _SSRV-S !
        _STREAMS-SOURCE-VALID? 0= IF 0 EXIT THEN
        0 _SSRV-J !
        BEGIN _SSRV-J @ _SSRV-I @ < WHILE
            _SSRV-J @ _SSRV-R @ STREAMS-SOURCE-NTH SSOURCE.ID
            _SSRV-S @ SSOURCE.ID RID= IF 0 EXIT THEN
            1 _SSRV-J +!
        REPEAT
        1 _SSRV-I +!
    REPEAT
    \ Unused fixed slots are semantically outside COUNT.  INIT and REMOVE
    \ wipe them, and the persistence encoder emits them as zero without
    \ scanning tens of kilobytes on every owner-side registry operation.
    -1 ;

' _STREAMS-SOURCE-REGISTRY-VALID? CONSTANT _ssreg-valid-xt
: STREAMS-SOURCE-REGISTRY-VALID?  ( registry -- flag )
    _ssreg-valid-xt _streams-source-registry-guard WITH-GUARD ;

: _SSREG-CAN-TOUCH?  ( registry -- flag )
    SSREG.GENERATION @ 1+ 0> ;

: _SSREG-TOUCH  ( registry -- )
    1 SWAP SSREG.GENERATION +! ;

VARIABLE _SSRA-P
VARIABLE _SSRA-R

: _SSREG-ALIASES?  ( pointer registry -- flag )
    _SSRA-R ! _SSRA-P !
    \ Compare the complete caller-owned source span with the complete
    \ registry, including its header.  A start address just outside either
    \ boundary can still overlap, while an exact end-to-start touch is safe.
    \ Distance comparisons avoid forming POINTER + STREAMS-SOURCE-SIZE.
    _SSRA-P @ _SSRA-R @ < IF
        _SSRA-R @ _SSRA-P @ - STREAMS-SOURCE-SIZE < EXIT
    THEN
    _SSRA-P @ _SSRA-R @ - STREAMS-SOURCE-REGISTRY-SIZE < ;

\ =====================================================================
\  Transactional registry operations
\ =====================================================================

VARIABLE _SSRC-CANDIDATE
VARIABLE _SSRC-REGISTRY
VARIABLE _SSRC-DESTINATION

: _STREAMS-SOURCE-CREATE  ( candidate registry -- status )
    _SSRC-REGISTRY ! _SSRC-CANDIDATE !
    _SSRC-REGISTRY @ _STREAMS-SOURCE-REGISTRY-VALID? 0= IF
        SSREG-S-INVALID EXIT
    THEN
    _SSRC-CANDIDATE @ 0= IF SSREG-S-INVALID EXIT THEN
    _SSRC-CANDIDATE @ _SSRC-REGISTRY @ _SSREG-ALIASES? IF
        SSREG-S-INVALID EXIT
    THEN
    _SSRC-CANDIDATE @ SSOURCE.REVISION @ IF SSREG-S-INVALID EXIT THEN
    _SSRC-CANDIDATE @ _SSOURCE-CONFIG-VALID? 0= IF
        SSREG-S-INVALID EXIT
    THEN
    _SSRC-CANDIDATE @ SSOURCE.ID _SSRC-REGISTRY @
        _STREAMS-SOURCE-FIND IF SSREG-S-DUPLICATE EXIT THEN
    _SSRC-REGISTRY @ SSREG.COUNT @ STREAMS-SOURCE-MAX >= IF
        SSREG-S-FULL EXIT
    THEN
    _SSRC-REGISTRY @ _SSREG-CAN-TOUCH? 0= IF SSREG-S-CAPACITY EXIT THEN
    _SSRC-REGISTRY @ SSREG.COUNT @ STREAMS-SOURCE-SIZE *
        _SSRC-REGISTRY @ SSREG.RECORDS + _SSRC-DESTINATION !
    _SSRC-CANDIDATE @ _SSRC-DESTINATION @ STREAMS-SOURCE-SIZE CMOVE
    1 _SSRC-DESTINATION @ SSOURCE.REVISION !
    1 _SSRC-REGISTRY @ SSREG.COUNT +!
    _SSRC-REGISTRY @ _SSREG-TOUCH
    SSREG-S-OK ;

VARIABLE _SSRR-ID
VARIABLE _SSRR-DESTINATION
VARIABLE _SSRR-REGISTRY
VARIABLE _SSRR-SOURCE

: _STREAMS-SOURCE-READ  ( rid destination registry -- status )
    _SSRR-REGISTRY ! _SSRR-DESTINATION ! _SSRR-ID !
    _SSRR-REGISTRY @ _STREAMS-SOURCE-REGISTRY-VALID? 0= IF
        SSREG-S-INVALID EXIT
    THEN
    _SSRR-DESTINATION @ 0= IF SSREG-S-INVALID EXIT THEN
    _SSRR-DESTINATION @ _SSRR-REGISTRY @ _SSREG-ALIASES? IF
        SSREG-S-INVALID EXIT
    THEN
    _SSRR-ID @ _SSRR-REGISTRY @ _STREAMS-SOURCE-FIND
        DUP 0= IF DROP SSREG-S-NOT-FOUND EXIT THEN
    _SSRR-SOURCE !
    _SSRR-SOURCE @ _SSRR-DESTINATION @ STREAMS-SOURCE-SIZE CMOVE
    SSREG-S-OK ;

VARIABLE _SSRP-CANDIDATE
VARIABLE _SSRP-EXPECTED
VARIABLE _SSRP-REGISTRY
VARIABLE _SSRP-CURRENT
VARIABLE _SSRP-NEXT

: _STREAMS-SOURCE-REPLACE
  ( candidate expected-revision registry -- status )
    _SSRP-REGISTRY ! _SSRP-EXPECTED ! _SSRP-CANDIDATE !
    _SSRP-REGISTRY @ _STREAMS-SOURCE-REGISTRY-VALID? 0= IF
        SSREG-S-INVALID EXIT
    THEN
    _SSRP-CANDIDATE @ 0= _SSRP-EXPECTED @ 0> 0= OR IF
        SSREG-S-INVALID EXIT
    THEN
    _SSRP-CANDIDATE @ _SSRP-REGISTRY @ _SSREG-ALIASES? IF
        SSREG-S-INVALID EXIT
    THEN
    _SSRP-CANDIDATE @ SSOURCE.REVISION @
        _SSRP-EXPECTED @ <> IF SSREG-S-INVALID EXIT THEN
    _SSRP-CANDIDATE @ _SSOURCE-CONFIG-VALID? 0= IF
        SSREG-S-INVALID EXIT
    THEN
    _SSRP-CANDIDATE @ SSOURCE.ID _SSRP-REGISTRY @
        _STREAMS-SOURCE-FIND DUP 0= IF
        DROP SSREG-S-NOT-FOUND EXIT
    THEN
    _SSRP-CURRENT !
    _SSRP-CURRENT @ SSOURCE.REVISION @ _SSRP-EXPECTED @ <> IF
        SSREG-S-STALE EXIT
    THEN
    _SSRP-EXPECTED @ 1+ DUP _SSRP-NEXT ! 0> 0= IF
        SSREG-S-CAPACITY EXIT
    THEN
    _SSRP-REGISTRY @ _SSREG-CAN-TOUCH? 0= IF SSREG-S-CAPACITY EXIT THEN
    _SSRP-CANDIDATE @ _SSRP-CURRENT @ STREAMS-SOURCE-SIZE CMOVE
    _SSRP-NEXT @ _SSRP-CURRENT @ SSOURCE.REVISION !
    _SSRP-REGISTRY @ _SSREG-TOUCH
    SSREG-S-OK ;

VARIABLE _SSRE-ID
VARIABLE _SSRE-EXPECTED
VARIABLE _SSRE-ENABLED
VARIABLE _SSRE-REGISTRY
VARIABLE _SSRE-CURRENT
VARIABLE _SSRE-WANTED
VARIABLE _SSRE-NEXT

: _STREAMS-SOURCE-ENABLE
  ( rid expected-revision enabled? registry -- status )
    _SSRE-REGISTRY ! _SSRE-ENABLED ! _SSRE-EXPECTED ! _SSRE-ID !
    _SSRE-REGISTRY @ _STREAMS-SOURCE-REGISTRY-VALID? 0= IF
        SSREG-S-INVALID EXIT
    THEN
    _SSRE-EXPECTED @ 0> 0= IF SSREG-S-INVALID EXIT THEN
    _SSRE-ID @ _SSRE-REGISTRY @ _STREAMS-SOURCE-FIND DUP 0= IF
        DROP SSREG-S-NOT-FOUND EXIT
    THEN
    _SSRE-CURRENT !
    _SSRE-CURRENT @ SSOURCE.REVISION @ _SSRE-EXPECTED @ <> IF
        SSREG-S-STALE EXIT
    THEN
    _SSRE-ENABLED @ 0<> _SSRE-WANTED !
    _SSRE-CURRENT @ SSOURCE.FLAGS @ SSOURCE-F-ENABLED AND 0<>
        _SSRE-WANTED @ = IF SSREG-S-OK EXIT THEN
    _SSRE-EXPECTED @ 1+ DUP _SSRE-NEXT ! 0> 0= IF
        SSREG-S-CAPACITY EXIT
    THEN
    _SSRE-REGISTRY @ _SSREG-CAN-TOUCH? 0= IF SSREG-S-CAPACITY EXIT THEN
    _SSRE-WANTED @ IF
        SSOURCE-F-ENABLED _SSRE-CURRENT @ SSOURCE.FLAGS !
    ELSE
        0 _SSRE-CURRENT @ SSOURCE.FLAGS !
    THEN
    _SSRE-NEXT @ _SSRE-CURRENT @ SSOURCE.REVISION !
    _SSRE-REGISTRY @ _SSREG-TOUCH
    SSREG-S-OK ;

VARIABLE _SSRD-ID
VARIABLE _SSRD-EXPECTED
VARIABLE _SSRD-REGISTRY
VARIABLE _SSRD-CURRENT
VARIABLE _SSRD-INDEX
VARIABLE _SSRD-MOVE-N

: _STREAMS-SOURCE-REMOVE  ( rid expected-revision registry -- status )
    _SSRD-REGISTRY ! _SSRD-EXPECTED ! _SSRD-ID !
    _SSRD-REGISTRY @ _STREAMS-SOURCE-REGISTRY-VALID? 0= IF
        SSREG-S-INVALID EXIT
    THEN
    _SSRD-EXPECTED @ 0> 0= IF SSREG-S-INVALID EXIT THEN
    _SSRD-ID @ _SSRD-REGISTRY @ _STREAMS-SOURCE-FIND DUP 0= IF
        DROP SSREG-S-NOT-FOUND EXIT
    THEN
    _SSRD-CURRENT !
    _SSRD-CURRENT @ SSOURCE.REVISION @ _SSRD-EXPECTED @ <> IF
        SSREG-S-STALE EXIT
    THEN
    _SSRD-REGISTRY @ _SSREG-CAN-TOUCH? 0= IF SSREG-S-CAPACITY EXIT THEN
    _SSRD-CURRENT @ _SSRD-REGISTRY @ SSREG.RECORDS -
        STREAMS-SOURCE-SIZE / _SSRD-INDEX !
    _SSRD-REGISTRY @ SSREG.COUNT @ _SSRD-INDEX @ - 1-
        DUP _SSRD-MOVE-N ! DROP
    _SSRD-MOVE-N @ IF
        _SSRD-CURRENT @ STREAMS-SOURCE-SIZE +
        _SSRD-CURRENT @
        _SSRD-MOVE-N @ STREAMS-SOURCE-SIZE * MOVE
    THEN
    _SSRD-REGISTRY @ SSREG.COUNT @ 1-
        STREAMS-SOURCE-SIZE * _SSRD-REGISTRY @ SSREG.RECORDS +
        STREAMS-SOURCE-SIZE 0 FILL
    -1 _SSRD-REGISTRY @ SSREG.COUNT +!
    _SSRD-REGISTRY @ _SSREG-TOUCH
    SSREG-S-OK ;

' _STREAMS-SOURCE-CREATE CONSTANT _ssource-create-xt
' _STREAMS-SOURCE-READ CONSTANT _ssource-read-xt
' _STREAMS-SOURCE-REPLACE CONSTANT _ssource-replace-xt
' _STREAMS-SOURCE-ENABLE CONSTANT _ssource-enable-xt
' _STREAMS-SOURCE-REMOVE CONSTANT _ssource-remove-xt

: STREAMS-SOURCE-CREATE  ( candidate registry -- status )
    _ssource-create-xt _streams-source-registry-guard WITH-GUARD ;

: STREAMS-SOURCE-READ  ( rid destination registry -- status )
    _ssource-read-xt _streams-source-registry-guard WITH-GUARD ;

: STREAMS-SOURCE-REPLACE
  ( candidate expected-revision registry -- status )
    _ssource-replace-xt _streams-source-registry-guard WITH-GUARD ;

: STREAMS-SOURCE-ENABLE
  ( rid expected-revision enabled? registry -- status )
    _ssource-enable-xt _streams-source-registry-guard WITH-GUARD ;

: STREAMS-SOURCE-REMOVE  ( rid expected-revision registry -- status )
    _ssource-remove-xt _streams-source-registry-guard WITH-GUARD ;
