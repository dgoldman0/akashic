\ =====================================================================
\  page-snapshot.f - bounded deterministic watched-page normalization
\ =====================================================================
\  A page snapshot owns a normalized UTF-8 text projection and identity
\  evidence for one admitted, bounded response.  It deliberately does not
\  own the raw response.  HTML is scanned with a fixed-depth tag stack; no
\  DOM is allocated and there is no script execution or active-content path.
\
\  Public API:
\    STREAMS-PAGE-SNAPSHOT-INIT       ( snapshot -- )
\    STREAMS-PAGE-NORMALIZE
\      ( raw-a raw-u media-a media-u snapshot -- status )
\    STREAMS-PAGE-SNAPSHOT-VALID?     ( snapshot -- flag )
\    STREAMS-PAGE-SNAPSHOT-MEDIA@     ( snapshot -- media )
\    STREAMS-PAGE-SNAPSHOT-MEDIA$     ( snapshot -- media-a media-u )
\    STREAMS-PAGE-SNAPSHOT-RAW-SIZE@  ( snapshot -- raw-u )
\    STREAMS-PAGE-SNAPSHOT-TEXT$      ( snapshot -- text-a text-u )
\    STREAMS-PAGE-SNAPSHOT-RAW-DIGEST ( snapshot -- digest-a )
\    STREAMS-PAGE-SNAPSHOT-NORMALIZED-DIGEST
\                                      ( snapshot -- digest-a )
\    STREAMS-PAGE-MEDIA-MAX            maximum admitted field-value bytes
\
\  MEDIA must parse as text/plain or text/html (ASCII case is ignored),
\  with either no parameters or one charset parameter whose value is UTF-8.
\  Other media or parameters are unsupported.  RAW is limited to
\  STREAMS-PAGE-RAW-MAX bytes and must be valid UTF-8.  ASCII whitespace is
\  folded to one U+0020 and trimmed; all other UTF-8 bytes are preserved.
\
\  The HTML subset accepts ordinary start/end tags, quoted attributes,
\  void tags, comments, and a doctype.  It removes script, style, nav,
\  header, footer, and aside subtrees.  The five XML entities, nbsp, and
\  valid numeric Unicode scalar references are decoded.  Other named
\  entities return SPAGE-S-UNSUPPORTED; malformed references or markup
\  return SPAGE-S-INVALID.
\
\  NORMALIZE is transactional with respect to SNAPSHOT: all validation,
\  extraction, and hashing occur in private bounded storage, followed by a
\  single commit.  Every non-OK status leaves SNAPSHOT byte-for-byte
\  unchanged.  VALID? verifies the model seal and normalized digest; it does
\  not claim that a digest authenticates or makes source content trustworthy.
\ =====================================================================

PROVIDED akashic-tui-streams-page-snapshot

REQUIRE ../../../text/utf8.f
REQUIRE ../../../math/sha3.f
REQUIRE ../../../concurrency/guard.f
REQUIRE ../../../markup/readable-text.f
REQUIRE ../../../net/media-type.f
REQUIRE ../../../utils/string.f

\ =====================================================================
\  Public bounds, media discriminators, and exact statuses
\ =====================================================================

131072 CONSTANT STREAMS-PAGE-RAW-MAX
  8192 CONSTANT STREAMS-PAGE-TEXT-MAX
MTYPE-VALUE-MAX CONSTANT STREAMS-PAGE-MEDIA-MAX

1 CONSTANT SPAGE-MEDIA-TEXT-PLAIN
2 CONSTANT SPAGE-MEDIA-TEXT-HTML

0 CONSTANT SPAGE-S-OK
1 CONSTANT SPAGE-S-INVALID
2 CONSTANT SPAGE-S-CAPACITY
3 CONSTANT SPAGE-S-UNSUPPORTED

\ =====================================================================
\  Sealed snapshot model
\ =====================================================================

0x535047534E415031 CONSTANT _SPAGE-MAGIC  \ "SPGSNAP1"
1 CONSTANT STREAMS-PAGE-SNAPSHOT-V1

  0 CONSTANT _SPG-MAGIC
  8 CONSTANT _SPG-VERSION
 16 CONSTANT _SPG-MEDIA
 24 CONSTANT _SPG-RAW-SIZE
 32 CONSTANT _SPG-TEXT-SIZE
 40 CONSTANT _SPG-FLAGS
 48 CONSTANT _SPG-RAW-DIGEST
 80 CONSTANT _SPG-NORMAL-DIGEST
112 CONSTANT _SPG-SEAL
144 CONSTANT _SPG-TEXT

_SPG-TEXT STREAMS-PAGE-TEXT-MAX +
    CONSTANT STREAMS-PAGE-SNAPSHOT-SIZE

: STREAMS-PAGE-SNAPSHOT-INIT  ( snapshot -- )
    DUP 0> IF STREAMS-PAGE-SNAPSHOT-SIZE 0 FILL ELSE DROP THEN ;

: STREAMS-PAGE-SNAPSHOT-MEDIA@  ( snapshot -- media )
    _SPG-MEDIA + @ ;

: STREAMS-PAGE-SNAPSHOT-MEDIA$  ( snapshot -- media-a media-u )
    STREAMS-PAGE-SNAPSHOT-MEDIA@
    DUP SPAGE-MEDIA-TEXT-PLAIN = IF DROP S" text/plain" EXIT THEN
    SPAGE-MEDIA-TEXT-HTML = IF S" text/html" ELSE 0 0 THEN ;

: STREAMS-PAGE-SNAPSHOT-RAW-SIZE@  ( snapshot -- raw-u )
    _SPG-RAW-SIZE + @ ;

: STREAMS-PAGE-SNAPSHOT-TEXT$  ( snapshot -- text-a text-u )
    DUP _SPG-TEXT + SWAP _SPG-TEXT-SIZE + @ ;

: STREAMS-PAGE-SNAPSHOT-RAW-DIGEST  ( snapshot -- digest-a )
    _SPG-RAW-DIGEST + ;

: STREAMS-PAGE-SNAPSHOT-NORMALIZED-DIGEST  ( snapshot -- digest-a )
    _SPG-NORMAL-DIGEST + ;

\ =====================================================================
\  Shared private candidate and validation storage
\ =====================================================================

CREATE _SPN-CANDIDATE STREAMS-PAGE-SNAPSHOT-SIZE ALLOT
CREATE _SPN-CHECK-NORMAL SHA3-256-LEN ALLOT
CREATE _SPN-CHECK-SEAL   SHA3-256-LEN ALLOT
CREATE _SPN-MTYPE MTYPE-SIZE ALLOT

GUARD _streams-page-normalize-guard

: _SPN-SEAL-HASH  ( snapshot destination -- )
    >R
    SHA3-256-BEGIN
    DUP _SPG-VERSION + _SPG-SEAL _SPG-VERSION - SHA3-256-ADD
    DUP _SPG-TEXT + SWAP _SPG-TEXT-SIZE + @ SHA3-256-ADD
    R> SHA3-256-END ;

VARIABLE _SPV-S

: _STREAMS-PAGE-SNAPSHOT-VALID?  ( snapshot -- flag )
    DUP 0> 0= IF DROP 0 EXIT THEN
    DUP _SPV-S !
    DUP _SPG-MAGIC + @ _SPAGE-MAGIC <> IF DROP 0 EXIT THEN
    DUP _SPG-VERSION + @ STREAMS-PAGE-SNAPSHOT-V1 <> IF
        DROP 0 EXIT
    THEN
    DUP _SPG-MEDIA + @ DUP SPAGE-MEDIA-TEXT-PLAIN =
        SWAP SPAGE-MEDIA-TEXT-HTML = OR 0= IF DROP 0 EXIT THEN
    DUP _SPG-RAW-SIZE + @ DUP 0< SWAP STREAMS-PAGE-RAW-MAX > OR IF
        DROP 0 EXIT
    THEN
    DUP _SPG-TEXT-SIZE + @ DUP 0< SWAP STREAMS-PAGE-TEXT-MAX > OR IF
        DROP 0 EXIT
    THEN
    DUP _SPG-FLAGS + @ IF DROP 0 EXIT THEN
    DUP _SPG-TEXT + OVER _SPG-TEXT-SIZE + @ UTF8-VALID? 0= IF
        DROP 0 EXIT
    THEN
    DUP _SPG-TEXT + OVER _SPG-TEXT-SIZE + @ _SPN-CHECK-NORMAL
        SHA3-256-HASH
    DUP _SPG-NORMAL-DIGEST + _SPN-CHECK-NORMAL SHA3-256-COMPARE 0= IF
        DROP 0 EXIT
    THEN
    _SPN-CHECK-SEAL _SPN-SEAL-HASH
    _SPV-S @ _SPG-SEAL + _SPN-CHECK-SEAL SHA3-256-COMPARE ;

' _STREAMS-PAGE-SNAPSHOT-VALID? CONSTANT _spage-valid-q-xt
: STREAMS-PAGE-SNAPSHOT-VALID?  ( snapshot -- flag )
    _spage-valid-q-xt _streams-page-normalize-guard WITH-GUARD ;

\ =====================================================================
\  Transactional public operation
\ =====================================================================

VARIABLE _SPNN-RAW-A
VARIABLE _SPNN-RAW-U
VARIABLE _SPNN-MEDIA-A
VARIABLE _SPNN-MEDIA-U
VARIABLE _SPNN-MEDIA
VARIABLE _SPNN-DEST
VARIABLE _SPNN-TEXT-U
VARIABLE _SPMP-NAME-A
VARIABLE _SPMP-NAME-U
VARIABLE _SPMP-VALUE-A
VARIABLE _SPMP-VALUE-U

: _SPN-MTYPE-STATUS  ( parser-status -- page-status )
    DUP MTYPE-S-INVALID = IF DROP SPAGE-S-INVALID EXIT THEN
    DUP MTYPE-S-CAPACITY = IF DROP SPAGE-S-CAPACITY EXIT THEN
    DROP SPAGE-S-INVALID ;

: _SPN-CLASSIFY-MEDIA  ( -- status )
    _SPNN-MEDIA-A @ _SPNN-MEDIA-U @ _SPN-MTYPE MTYPE-PARSE
    DUP IF _SPN-MTYPE-STATUS EXIT THEN DROP

    _SPN-MTYPE MTYPE-TYPE$ S" text" STR-STRI= 0= IF
        SPAGE-S-UNSUPPORTED EXIT
    THEN
    _SPN-MTYPE MTYPE-SUBTYPE$ S" plain" STR-STRI= IF
        SPAGE-MEDIA-TEXT-PLAIN _SPNN-MEDIA !
    ELSE
        _SPN-MTYPE MTYPE-SUBTYPE$ S" html" STR-STRI= IF
            SPAGE-MEDIA-TEXT-HTML _SPNN-MEDIA !
        ELSE
            SPAGE-S-UNSUPPORTED EXIT
        THEN
    THEN

    _SPN-MTYPE MTYPE-PARAM-COUNT@ DUP 0= IF
        DROP SPAGE-S-OK EXIT
    THEN
    1 <> IF SPAGE-S-UNSUPPORTED EXIT THEN
    0 _SPN-MTYPE MTYPE-PARAM-NTH 0= IF
        2DROP 2DROP SPAGE-S-INVALID EXIT
    THEN
    _SPMP-VALUE-U ! _SPMP-VALUE-A ! _SPMP-NAME-U ! _SPMP-NAME-A !
    _SPMP-NAME-A @ _SPMP-NAME-U @ S" charset" STR-STRI= 0= IF
        SPAGE-S-UNSUPPORTED EXIT
    THEN
    _SPMP-VALUE-A @ _SPMP-VALUE-U @ S" utf-8" STR-STRI= 0= IF
        SPAGE-S-UNSUPPORTED EXIT
    THEN
    SPAGE-S-OK ;

: _SPN-RTEXT-STATUS  ( readable-status -- page-status )
    DUP RTEXT-S-INVALID = IF DROP SPAGE-S-INVALID EXIT THEN
    DUP RTEXT-S-CAPACITY = IF DROP SPAGE-S-CAPACITY EXIT THEN
    DUP RTEXT-S-UNSUPPORTED = IF DROP SPAGE-S-UNSUPPORTED EXIT THEN
    DROP SPAGE-S-INVALID ;

: _STREAMS-PAGE-NORMALIZE
    ( raw-a raw-u media-a media-u snapshot -- status )
    _SPNN-DEST ! _SPNN-MEDIA-U ! _SPNN-MEDIA-A !
    _SPNN-RAW-U ! _SPNN-RAW-A !
    _SPNN-DEST @ 0> 0= IF SPAGE-S-INVALID EXIT THEN
    _SPNN-RAW-U @ 0< _SPNN-MEDIA-U @ 0< OR IF
        SPAGE-S-INVALID EXIT
    THEN
    _SPNN-RAW-A @ 0< _SPNN-MEDIA-A @ 0< OR IF
        SPAGE-S-INVALID EXIT
    THEN
    _SPNN-RAW-U @ STREAMS-PAGE-RAW-MAX > IF SPAGE-S-CAPACITY EXIT THEN
    _SPNN-MEDIA-U @ STREAMS-PAGE-MEDIA-MAX > IF
        SPAGE-S-CAPACITY EXIT
    THEN
    _SPNN-RAW-U @ 0> _SPNN-RAW-A @ 0= AND IF SPAGE-S-INVALID EXIT THEN
    _SPNN-MEDIA-U @ 0> _SPNN-MEDIA-A @ 0= AND IF SPAGE-S-INVALID EXIT THEN
    _SPN-CLASSIFY-MEDIA DUP IF EXIT THEN DROP
    _SPNN-RAW-U @ IF
        _SPNN-RAW-A @ _SPNN-RAW-U @ UTF8-VALID? 0= IF
            SPAGE-S-INVALID EXIT
        THEN
    THEN

    _SPN-CANDIDATE STREAMS-PAGE-SNAPSHOT-SIZE 0 FILL
    STREAMS-PAGE-SNAPSHOT-V1 _SPN-CANDIDATE _SPG-VERSION + !
    _SPNN-MEDIA @ _SPN-CANDIDATE _SPG-MEDIA + !
    _SPNN-RAW-U @ _SPN-CANDIDATE _SPG-RAW-SIZE + !
    _SPNN-RAW-A @ _SPNN-RAW-U @ _SPN-CANDIDATE _SPG-RAW-DIGEST +
        SHA3-256-HASH

    _SPNN-MEDIA @ SPAGE-MEDIA-TEXT-PLAIN = IF
        _SPNN-RAW-A @ _SPNN-RAW-U @
        _SPN-CANDIDATE _SPG-TEXT + STREAMS-PAGE-TEXT-MAX RTEXT-PLAIN
    ELSE
        _SPNN-RAW-A @ _SPNN-RAW-U @
        _SPN-CANDIDATE _SPG-TEXT + STREAMS-PAGE-TEXT-MAX RTEXT-HTML
    THEN
    DUP IF NIP _SPN-RTEXT-STATUS EXIT THEN
    DROP _SPNN-TEXT-U !

    _SPNN-TEXT-U @ _SPN-CANDIDATE _SPG-TEXT-SIZE + !
    _SPN-CANDIDATE _SPG-TEXT + _SPNN-TEXT-U @
        _SPN-CANDIDATE _SPG-NORMAL-DIGEST + SHA3-256-HASH
    _SPN-CANDIDATE DUP _SPG-SEAL + _SPN-SEAL-HASH
    _SPAGE-MAGIC _SPN-CANDIDATE _SPG-MAGIC + !
    _SPN-CANDIDATE _SPNN-DEST @ STREAMS-PAGE-SNAPSHOT-SIZE CMOVE
    SPAGE-S-OK ;

' _STREAMS-PAGE-NORMALIZE CONSTANT _spage-normalize-xt
: STREAMS-PAGE-NORMALIZE
    ( raw-a raw-u media-a media-u snapshot -- status )
    _spage-normalize-xt _streams-page-normalize-guard WITH-GUARD ;
