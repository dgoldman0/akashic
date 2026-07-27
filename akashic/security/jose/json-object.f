\ =====================================================================
\  json-object.f - Strict caller-owned JSON object decoding for JOSE
\ =====================================================================
\  This module is deliberately policy-neutral.  It supplies strict JSON
\  mechanics without transport, authorization, identity, or application
\  field policy.
\
\  A successful parse publishes a compact descriptor and a caller-owned
\  decoded-name buffer.  The descriptor contains offsets, lengths, and
\  type tags only; it never retains an input or output address.  Consumers
\  can therefore enumerate members while borrowing whichever receive
\  buffer owns the document at that moment.
\
\  The complete document is validated before either published output is
\  changed.  Validation includes strict UTF-8, JSON number grammar, escape
\  and UTF-16 surrogate handling, bounded nesting, and duplicate member
\  names after unescaping.  Decoded member names and their aggregate staging
\  have a 4096-byte bound.  Decoded value strings use the document-sized
\  value bound, and unknown nested values are parsed completely.
\  Publication invalidates the descriptor before copying and writes its
\  magic last.  Unexpected validation/staging THROW is mapped to INTERNAL
\  only after admitted outputs and workspace are scrubbed successfully.
\  Publication THROW and mandatory-cleanup THROW propagate unchanged rather
\  than masquerading as an ordinary status.  Ordinary validation rejection
\  leaves the two published outputs unchanged.  The caller workspace is
\  scratch and is cleared on every admitted normal or caught exit.
\
\  Public API:
\    JOSE-JSON-OBJECT-BYTES
\      ( member-capacity -- descriptor-bytes status )
\    JOSE-JSON-OBJECT-PARSE
\      ( source source-u descriptor member-capacity
\        names names-capacity workspace -- status )
\    JOSE-JSON-OBJECT-VALID?
\      ( descriptor -- flag )
\    JOSE-JSON-OBJECT-COUNT@
\      ( descriptor -- count status )
\    JOSE-JSON-OBJECT-NAMES-USED@
\      ( descriptor -- names-u status )
\    JOSE-JSON-OBJECT-MEMBER@
\      ( index descriptor
\        -- name-offset name-u value-offset value-u type status )
\    JOSE-JSON-OBJECT-WORKSPACE-CLEAR
\      ( workspace -- status )
\
\    JOSE-JSON-STRING-MEASURE
\      ( source source-u workspace -- decoded-u status )
\    JOSE-JSON-STRING-DECODE
\      ( source source-u destination capacity workspace
\        -- written status )
\    JOSE-JSON-STRING-WORKSPACE-CLEAR
\      ( workspace -- status )
\
\  MEMBER@ returns offsets rather than resolved pointers.  name-offset is
\  relative to the decoded-name buffer passed to PARSE; value-offset is
\  relative to the source document passed to PARSE.  The value span is the
\  exact JSON token, including quotes for strings and brackets/braces for
\  containers.
\ =====================================================================

PROVIDED akashic-jose-jsonobj

REQUIRE ../../utils/memory-span.f
REQUIRE ../../utils/caller-span.f

\ =====================================================================
\  Public status, type, and bound vocabulary
\ =====================================================================

0  CONSTANT JOSE-JSON-S-OK
1  CONSTANT JOSE-JSON-S-INVALID
2  CONSTANT JOSE-JSON-S-SYNTAX
3  CONSTANT JOSE-JSON-S-UTF8
4  CONSTANT JOSE-JSON-S-CAPACITY
5  CONSTANT JOSE-JSON-S-ALIAS
6  CONSTANT JOSE-JSON-S-DEPTH
7  CONSTANT JOSE-JSON-S-MEMBERS
8  CONSTANT JOSE-JSON-S-STRING
9  CONSTANT JOSE-JSON-S-DUPLICATE
10 CONSTANT JOSE-JSON-S-DOCUMENT
11 CONSTANT JOSE-JSON-S-INTERNAL

1 CONSTANT JOSE-JSON-T-STRING
2 CONSTANT JOSE-JSON-T-NUMBER
3 CONSTANT JOSE-JSON-T-OBJECT
4 CONSTANT JOSE-JSON-T-ARRAY
5 CONSTANT JOSE-JSON-T-BOOL
6 CONSTANT JOSE-JSON-T-NULL

65536 CONSTANT JOSE-JSON-MAX-DOCUMENT-BYTES
32    CONSTANT JOSE-JSON-MAX-DEPTH
64    CONSTANT JOSE-JSON-MAX-MEMBERS
4096  CONSTANT JOSE-JSON-MAX-NAME-BYTES
JOSE-JSON-MAX-DOCUMENT-BYTES
CONSTANT JOSE-JSON-MAX-VALUE-STRING-BYTES

72 CONSTANT JOSE-JSON-STRING-WORKSPACE-SIZE

: JOSE-JSON-STATUS-VALID?  ( status -- flag )
    DUP JOSE-JSON-S-OK >=
    SWAP JOSE-JSON-S-INTERNAL <= AND ;

: JOSE-JSON-TYPE-VALID?  ( type -- flag )
    DUP JOSE-JSON-T-STRING >=
    SWAP JOSE-JSON-T-NULL <= AND ;

\ Preserve the generic caller-boundary distinctions until this module's
\ public status vocabulary forces a mapping.  RANGE is invalid geometry,
\ PROTECTED is a forbidden alias with platform-owned state, and a platform
\ qualification failure is an internal failure.  CALLER-SPAN-STATUS itself
\ normalizes BIOS THROW and undocumented lower results to PLATFORM.
: _JJO-CALLER-SPAN>STATUS  ( address length -- status )
    CALLER-SPAN-STATUS
    DUP CALLER-SPAN-S-OK = IF DROP JOSE-JSON-S-OK EXIT THEN
    DUP CALLER-SPAN-S-RANGE = IF
        DROP JOSE-JSON-S-INVALID EXIT
    THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP JOSE-JSON-S-ALIAS EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP JOSE-JSON-S-INTERNAL EXIT
    THEN
    DROP JOSE-JSON-S-INTERNAL ;

\ =====================================================================
\  Published offset-only descriptor
\ =====================================================================

0x4A4A4F424A454354 CONSTANT _JJO-DESCRIPTOR-MAGIC  \ "JJOBJECT"

 0 CONSTANT _JJD-MAGIC
 8 CONSTANT _JJD-COUNT
16 CONSTANT _JJD-CAPACITY
24 CONSTANT _JJD-NAMES-U
32 CONSTANT _JJD-SOURCE-U
40 CONSTANT _JJD-RESERVED
48 CONSTANT JOSE-JSON-OBJECT-HEADER-SIZE

 0 CONSTANT _JJE-NAME-OFFSET
 8 CONSTANT _JJE-NAME-U
16 CONSTANT _JJE-TYPE
24 CONSTANT _JJE-VALUE-OFFSET
32 CONSTANT _JJE-VALUE-U
40 CONSTANT JOSE-JSON-OBJECT-MEMBER-SIZE

: _JJD.MAGIC       ( descriptor -- a ) _JJD-MAGIC + ;
: _JJD.COUNT       ( descriptor -- a ) _JJD-COUNT + ;
: _JJD.CAPACITY    ( descriptor -- a ) _JJD-CAPACITY + ;
: _JJD.NAMES-U     ( descriptor -- a ) _JJD-NAMES-U + ;
: _JJD.SOURCE-U    ( descriptor -- a ) _JJD-SOURCE-U + ;
: _JJD.RESERVED    ( descriptor -- a ) _JJD-RESERVED + ;

: JOSE-JSON-OBJECT-BYTES
  ( member-capacity -- descriptor-bytes status )
    DUP 0< IF DROP 0 JOSE-JSON-S-INVALID EXIT THEN
    DUP JOSE-JSON-MAX-MEMBERS > IF
        DROP 0 JOSE-JSON-S-INVALID EXIT
    THEN
    JOSE-JSON-OBJECT-MEMBER-SIZE *
    JOSE-JSON-OBJECT-HEADER-SIZE +
    JOSE-JSON-S-OK ;

: _JJO-DESCRIPTOR-ENTRY  ( index descriptor -- entry )
    JOSE-JSON-OBJECT-HEADER-SIZE +
    SWAP JOSE-JSON-OBJECT-MEMBER-SIZE * + ;

: _JJO-OFFSET-SPAN?  ( offset length bound -- flag )
    >R
    DUP 0< IF 2DROP R> DROP 0 EXIT THEN
    OVER 0< IF 2DROP R> DROP 0 EXIT THEN
    OVER R@ U> IF 2DROP R> DROP 0 EXIT THEN
    R@ ROT - U> 0=
    R> DROP ;

: _JJO-DESCRIPTOR-ENTRIES-VALID?  ( descriptor -- flag )
    DUP _JJD.COUNT @ 0 ?DO
        I OVER _JJO-DESCRIPTOR-ENTRY
        DUP _JJE-NAME-OFFSET + @
        OVER _JJE-NAME-U + @
        3 PICK _JJD.NAMES-U @
        _JJO-OFFSET-SPAN? 0= IF
            2DROP 0 UNLOOP EXIT
        THEN
        DUP _JJE-VALUE-OFFSET + @
        OVER _JJE-VALUE-U + @
        3 PICK _JJD.SOURCE-U @
        _JJO-OFFSET-SPAN? 0= IF
            2DROP 0 UNLOOP EXIT
        THEN
        _JJE-TYPE + @ JOSE-JSON-TYPE-VALID? 0= IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: JOSE-JSON-OBJECT-VALID?  ( descriptor -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP JOSE-JSON-OBJECT-HEADER-SIZE
        _JJO-CALLER-SPAN>STATUS IF DROP 0 EXIT THEN
    DUP _JJD.MAGIC @ _JJO-DESCRIPTOR-MAGIC <> IF DROP 0 EXIT THEN
    DUP _JJD.CAPACITY @ DUP 0< IF 2DROP 0 EXIT THEN
    DUP JOSE-JSON-MAX-MEMBERS > IF 2DROP 0 EXIT THEN
    JOSE-JSON-OBJECT-BYTES
    DUP IF 2DROP DROP 0 EXIT THEN
    DROP
    OVER SWAP _JJO-CALLER-SPAN>STATUS IF DROP 0 EXIT THEN
    DUP _JJD.COUNT @ DUP 0< IF 2DROP 0 EXIT THEN
    OVER _JJD.CAPACITY @ > IF DROP 0 EXIT THEN
    DUP _JJD.NAMES-U @ DUP 0< IF 2DROP 0 EXIT THEN
    JOSE-JSON-MAX-NAME-BYTES > IF DROP 0 EXIT THEN
    DUP _JJD.SOURCE-U @ DUP 0< IF 2DROP 0 EXIT THEN
    JOSE-JSON-MAX-DOCUMENT-BYTES > IF DROP 0 EXIT THEN
    DUP _JJD.RESERVED @ IF DROP 0 EXIT THEN
    _JJO-DESCRIPTOR-ENTRIES-VALID? ;

: JOSE-JSON-OBJECT-COUNT@  ( descriptor -- count status )
    DUP JOSE-JSON-OBJECT-VALID? 0= IF
        DROP 0 JOSE-JSON-S-INVALID EXIT
    THEN
    _JJD.COUNT @ JOSE-JSON-S-OK ;

: JOSE-JSON-OBJECT-NAMES-USED@  ( descriptor -- names-u status )
    DUP JOSE-JSON-OBJECT-VALID? 0= IF
        DROP 0 JOSE-JSON-S-INVALID EXIT
    THEN
    _JJD.NAMES-U @ JOSE-JSON-S-OK ;

: _JJO-RETURN-MEMBER  ( entry -- name-o name-u value-o value-u type )
    DUP _JJE-NAME-OFFSET + @
    OVER _JJE-NAME-U + @
    2 PICK _JJE-VALUE-OFFSET + @
    3 PICK _JJE-VALUE-U + @
    4 PICK _JJE-TYPE + @
    >R >R >R >R >R DROP
    R> R> R> R> R> ;

: JOSE-JSON-OBJECT-MEMBER@
  ( index descriptor -- name-offset name-u value-offset value-u type status )
    DUP JOSE-JSON-OBJECT-VALID? 0= IF
        2DROP 0 0 0 0 0 JOSE-JSON-S-INVALID EXIT
    THEN
    OVER 0< IF
        2DROP 0 0 0 0 0 JOSE-JSON-S-INVALID EXIT
    THEN
    OVER OVER _JJD.COUNT @ >= IF
        2DROP 0 0 0 0 0 JOSE-JSON-S-INVALID EXIT
    THEN
    _JJO-DESCRIPTOR-ENTRY _JJO-RETURN-MEMBER
    JOSE-JSON-S-OK ;

\ =====================================================================
\  Caller workspace layout
\ =====================================================================
\  The first 72 bytes form the standalone string-operation workspace.
\  Object parsing extends it with recursion counters, descriptor arguments,
\  per-depth duplicate-name frames, staged descriptor entries, staged
\  nested-name entries, and decoded name bytes.

 0 CONSTANT _JJW-SOURCE
 8 CONSTANT _JJW-SOURCE-U
16 CONSTANT _JJW-POS
24 CONSTANT _JJW-EMIT-A
32 CONSTANT _JJW-EMIT-CAPACITY
40 CONSTANT _JJW-EMIT-USED
48 CONSTANT _JJW-EMIT-MODE
56 CONSTANT _JJW-TMP1
64 CONSTANT _JJW-TMP2

72  CONSTANT _JJW-DEPTH
80  CONSTANT _JJW-TOP-COUNT
88  CONSTANT _JJW-KEY-TOTAL
96  CONSTANT _JJW-DESCRIPTOR
104 CONSTANT _JJW-MEMBER-CAPACITY
112 CONSTANT _JJW-NAMES
120 CONSTANT _JJW-NAMES-CAPACITY
128 CONSTANT _JJW-KEY-NAME-START
136 CONSTANT _JJW-TOP-NAME-START
144 CONSTANT _JJW-TOP-VALUE-START
152 CONSTANT _JJW-TOP-TYPE
160 CONSTANT _JJW-RESERVED0
168 CONSTANT _JJW-RESERVED1
176 CONSTANT _JJW-RESERVED2
184 CONSTANT _JJW-RESERVED3

24 CONSTANT _JJO-FRAME-SIZE
 0 CONSTANT _JJF-KEY-START
 8 CONSTANT _JJF-NAME-START
16 CONSTANT _JJF-COUNT

192 CONSTANT _JJO-FRAMES-OFF
_JJO-FRAMES-OFF
    JOSE-JSON-MAX-DEPTH _JJO-FRAME-SIZE * +
CONSTANT _JJO-ENTRY-STAGE-OFF
_JJO-ENTRY-STAGE-OFF
    JOSE-JSON-MAX-MEMBERS JOSE-JSON-OBJECT-MEMBER-SIZE * +
CONSTANT _JJO-KEY-STAGE-OFF
_JJO-KEY-STAGE-OFF
    JOSE-JSON-MAX-MEMBERS 16 * +
CONSTANT _JJO-NAME-STAGE-OFF
_JJO-NAME-STAGE-OFF
    JOSE-JSON-MAX-NAME-BYTES +
CONSTANT JOSE-JSON-OBJECT-WORKSPACE-SIZE

: _JJW.SOURCE          ( w -- a ) _JJW-SOURCE + ;
: _JJW.SOURCE-U        ( w -- a ) _JJW-SOURCE-U + ;
: _JJW.POS             ( w -- a ) _JJW-POS + ;
: _JJW.EMIT-A          ( w -- a ) _JJW-EMIT-A + ;
: _JJW.EMIT-CAPACITY   ( w -- a ) _JJW-EMIT-CAPACITY + ;
: _JJW.EMIT-USED       ( w -- a ) _JJW-EMIT-USED + ;
: _JJW.EMIT-MODE       ( w -- a ) _JJW-EMIT-MODE + ;
: _JJW.TMP1            ( w -- a ) _JJW-TMP1 + ;
: _JJW.TMP2            ( w -- a ) _JJW-TMP2 + ;
: _JJW.DEPTH           ( w -- a ) _JJW-DEPTH + ;
: _JJW.TOP-COUNT       ( w -- a ) _JJW-TOP-COUNT + ;
: _JJW.KEY-TOTAL       ( w -- a ) _JJW-KEY-TOTAL + ;
: _JJW.DESCRIPTOR      ( w -- a ) _JJW-DESCRIPTOR + ;
: _JJW.MEMBER-CAPACITY ( w -- a ) _JJW-MEMBER-CAPACITY + ;
: _JJW.NAMES           ( w -- a ) _JJW-NAMES + ;
: _JJW.NAMES-CAPACITY  ( w -- a ) _JJW-NAMES-CAPACITY + ;
: _JJW.KEY-NAME-START  ( w -- a ) _JJW-KEY-NAME-START + ;
: _JJW.TOP-NAME-START  ( w -- a ) _JJW-TOP-NAME-START + ;
: _JJW.TOP-VALUE-START ( w -- a ) _JJW-TOP-VALUE-START + ;
: _JJW.TOP-TYPE        ( w -- a ) _JJW-TOP-TYPE + ;
: _JJW.RESERVED0       ( w -- a ) _JJW-RESERVED0 + ;
: _JJW.RESERVED1       ( w -- a ) _JJW-RESERVED1 + ;

: _JJO-FRAME  ( workspace -- frame )
    DUP _JJW.DEPTH @ 1-
    _JJO-FRAME-SIZE * _JJO-FRAMES-OFF + + ;

: _JJO-STAGED-ENTRY  ( index workspace -- entry )
    _JJO-ENTRY-STAGE-OFF +
    SWAP JOSE-JSON-OBJECT-MEMBER-SIZE * + ;

: _JJO-STAGED-KEY  ( index workspace -- key-entry )
    _JJO-KEY-STAGE-OFF +
    SWAP 16 * + ;

: _JJO-STAGED-NAMES  ( workspace -- address )
    _JJO-NAME-STAGE-OFF + ;

: _JJO-OBJECT-WORKSPACE-ZERO  ( workspace -- )
    JOSE-JSON-OBJECT-WORKSPACE-SIZE 0 FILL ;

: _JJO-STRING-WORKSPACE-ZERO  ( workspace -- )
    JOSE-JSON-STRING-WORKSPACE-SIZE 0 FILL ;

\ Execute one admitted workspace operation and then perform its mandatory
\ cleanup.  An operation THROW is rethrown after successful cleanup; a
\ cleanup THROW propagates directly and therefore takes precedence.  Normal
\ results of any arity remain below CATCH's zero and survive cleanup.
: _JJO-CALL-FINALLY  ( workspace operation-xt cleanup-xt -- results... )
    >R
    OVER >R
    CATCH
    DUP IF
        >R DROP
        R> R> R> EXECUTE
        THROW
    THEN
    DROP
    R> R> EXECUTE ;

: JOSE-JSON-OBJECT-WORKSPACE-CLEAR  ( workspace -- status )
    DUP JOSE-JSON-OBJECT-WORKSPACE-SIZE
        _JJO-CALLER-SPAN>STATUS
    DUP IF NIP EXIT THEN DROP
    _JJO-OBJECT-WORKSPACE-ZERO
    JOSE-JSON-S-OK ;

: JOSE-JSON-STRING-WORKSPACE-CLEAR  ( workspace -- status )
    DUP JOSE-JSON-STRING-WORKSPACE-SIZE
        _JJO-CALLER-SPAN>STATUS
    DUP IF NIP EXIT THEN DROP
    _JJO-STRING-WORKSPACE-ZERO
    JOSE-JSON-S-OK ;

\ =====================================================================
\  Cursor, output, and Unicode primitives
\ =====================================================================

: _JJO-LEFT  ( workspace -- bytes-left )
    DUP _JJW.SOURCE-U @ SWAP _JJW.POS @ - ;

: _JJO-CURRENT  ( workspace -- address )
    DUP _JJW.SOURCE @ SWAP _JJW.POS @ + ;

: _JJO-PEEK  ( workspace -- byte|-1 )
    DUP _JJO-LEFT 0= IF DROP -1 EXIT THEN
    _JJO-CURRENT C@ ;

: _JJO-WS-BYTE?  ( byte -- flag )
    DUP 32 = OVER 9 = OR OVER 10 = OR SWAP 13 = OR ;

: _JJO-DIGIT?  ( byte -- flag )
    DUP 48 >= SWAP 57 <= AND ;

: _JJO-CONTINUATION?  ( byte -- flag )
    0xC0 AND 0x80 = ;

: _JJO-SKIP-WS  ( workspace -- )
    BEGIN
        DUP _JJO-LEFT 0> IF
            DUP _JJO-PEEK _JJO-WS-BYTE?
        ELSE
            0
        THEN
    WHILE
        1 OVER _JJW.POS +!
    REPEAT
    DROP ;

: _JJO-EMIT-SPAN  ( source source-u workspace -- status )
    DUP _JJW.EMIT-MODE @ 0= IF
        DROP 2DROP JOSE-JSON-S-OK EXIT
    THEN
    >R
    DUP R@ _JJW.EMIT-CAPACITY @
        R@ _JJW.EMIT-USED @ - U> IF
        2DROP R> DROP JOSE-JSON-S-STRING EXIT
    THEN
    R@ _JJW.EMIT-MODE @ 2 = IF
        OVER R@ _JJW.EMIT-A @ R@ _JJW.EMIT-USED @ +
        2 PICK MOVE
    THEN
    DUP R@ _JJW.EMIT-USED +!
    2DROP R> DROP JOSE-JSON-S-OK ;

: _JJO-EMIT-BYTE  ( byte workspace -- status )
    DUP _JJW.EMIT-MODE @ 0= IF
        2DROP JOSE-JSON-S-OK EXIT
    THEN
    >R
    R@ _JJW.EMIT-USED @ R@ _JJW.EMIT-CAPACITY @ >= IF
        DROP R> DROP JOSE-JSON-S-STRING EXIT
    THEN
    R@ _JJW.EMIT-MODE @ 2 = IF
        DUP R@ _JJW.EMIT-A @ R@ _JJW.EMIT-USED @ + C!
    THEN
    DROP
    1 R@ _JJW.EMIT-USED +!
    R> DROP JOSE-JSON-S-OK ;

: _JJO-EMIT-CP  ( codepoint workspace -- status )
    >R
    DUP 0x80 < IF
        R> _JJO-EMIT-BYTE EXIT
    THEN
    DUP 0x800 < IF
        DUP 6 RSHIFT 0xC0 OR R@ _JJO-EMIT-BYTE
        DUP IF NIP R> DROP EXIT THEN DROP
        0x3F AND 0x80 OR R> _JJO-EMIT-BYTE EXIT
    THEN
    DUP 0x10000 < IF
        DUP 12 RSHIFT 0xE0 OR R@ _JJO-EMIT-BYTE
        DUP IF NIP R> DROP EXIT THEN DROP
        DUP 6 RSHIFT 0x3F AND 0x80 OR R@ _JJO-EMIT-BYTE
        DUP IF NIP R> DROP EXIT THEN DROP
        0x3F AND 0x80 OR R> _JJO-EMIT-BYTE EXIT
    THEN
    DUP 18 RSHIFT 0xF0 OR R@ _JJO-EMIT-BYTE
    DUP IF NIP R> DROP EXIT THEN DROP
    DUP 12 RSHIFT 0x3F AND 0x80 OR R@ _JJO-EMIT-BYTE
    DUP IF NIP R> DROP EXIT THEN DROP
    DUP 6 RSHIFT 0x3F AND 0x80 OR R@ _JJO-EMIT-BYTE
    DUP IF NIP R> DROP EXIT THEN DROP
    0x3F AND 0x80 OR R> _JJO-EMIT-BYTE ;

: _JJO-HEX-VALUE  ( byte -- value|-1 )
    DUP 48 >= OVER 57 <= AND IF 48 - EXIT THEN
    DUP 65 >= OVER 70 <= AND IF 55 - EXIT THEN
    DUP 97 >= OVER 102 <= AND IF 87 - EXIT THEN
    DROP -1 ;

: _JJO-HEX4  ( workspace -- codepoint status )
    0 OVER _JJW.TMP1 !
    4 0 DO
        DUP _JJO-LEFT 0= IF
            DROP 0 JOSE-JSON-S-SYNTAX UNLOOP EXIT
        THEN
        DUP _JJO-PEEK _JJO-HEX-VALUE
        DUP 0< IF
            2DROP 0 JOSE-JSON-S-SYNTAX UNLOOP EXIT
        THEN
        OVER _JJW.TMP1 @ 4 LSHIFT OR
        OVER _JJW.TMP1 !
        1 OVER _JJW.POS +!
    LOOP
    DUP _JJW.TMP1 @ SWAP DROP
    JOSE-JSON-S-OK ;

: _JJO-RAW-UTF8  ( workspace -- status )
    DUP _JJO-PEEK OVER _JJW.TMP1 !

    DUP _JJW.TMP1 @ DUP 0xC2 >= SWAP 0xDF <= AND IF
        DUP _JJO-LEFT 2 < IF DROP JOSE-JSON-S-UTF8 EXIT THEN
        DUP _JJO-CURRENT 1+ C@ _JJO-CONTINUATION? 0= IF
            DROP JOSE-JSON-S-UTF8 EXIT
        THEN
        2 OVER _JJW.TMP2 !
    ELSE
        DUP _JJW.TMP1 @ DUP 0xE0 >= SWAP 0xEF <= AND IF
            DUP _JJO-LEFT 3 < IF DROP JOSE-JSON-S-UTF8 EXIT THEN
            DUP _JJO-CURRENT 1+ C@ OVER _JJW.TMP2 !
            DUP _JJW.TMP1 @ 0xE0 = IF
                DUP _JJW.TMP2 @ DUP 0xA0 >= SWAP 0xBF <= AND
            ELSE
                DUP _JJW.TMP1 @ 0xED = IF
                    DUP _JJW.TMP2 @ DUP 0x80 >= SWAP 0x9F <= AND
                ELSE
                    DUP _JJW.TMP2 @ _JJO-CONTINUATION?
                THEN
            THEN
            OVER _JJO-CURRENT 2 + C@ _JJO-CONTINUATION? AND 0= IF
                DROP JOSE-JSON-S-UTF8 EXIT
            THEN
            3 OVER _JJW.TMP2 !
        ELSE
            DUP _JJW.TMP1 @ DUP 0xF0 >= SWAP 0xF4 <= AND IF
                DUP _JJO-LEFT 4 < IF DROP JOSE-JSON-S-UTF8 EXIT THEN
                DUP _JJO-CURRENT 1+ C@ OVER _JJW.TMP2 !
                DUP _JJW.TMP1 @ 0xF0 = IF
                    DUP _JJW.TMP2 @ DUP 0x90 >= SWAP 0xBF <= AND
                ELSE
                    DUP _JJW.TMP1 @ 0xF4 = IF
                        DUP _JJW.TMP2 @ DUP 0x80 >= SWAP 0x8F <= AND
                    ELSE
                        DUP _JJW.TMP2 @ _JJO-CONTINUATION?
                    THEN
                THEN
                OVER _JJO-CURRENT 2 + C@ _JJO-CONTINUATION? AND
                OVER _JJO-CURRENT 3 + C@ _JJO-CONTINUATION? AND
                0= IF DROP JOSE-JSON-S-UTF8 EXIT THEN
                4 OVER _JJW.TMP2 !
            ELSE
                DROP JOSE-JSON-S-UTF8 EXIT
            THEN
        THEN
    THEN

    DUP _JJO-CURRENT
    OVER _JJW.TMP2 @
    2 PICK _JJO-EMIT-SPAN
    DUP IF NIP EXIT THEN DROP
    DUP _JJW.TMP2 @ OVER _JJW.POS +!
    DROP JOSE-JSON-S-OK ;

\ =====================================================================
\  Exact JSON string parsing and unescaping
\ =====================================================================

: _JJO-EMIT-FROM-WORK  ( workspace codepoint -- status )
    OVER _JJO-EMIT-CP NIP ;

: _JJO-ESCAPE  ( workspace -- status )
    1 OVER _JJW.POS +!                 \ consume backslash
    DUP _JJO-LEFT 0= IF DROP JOSE-JSON-S-SYNTAX EXIT THEN
    DUP _JJO-PEEK CASE
        34 OF 34 OVER _JJO-EMIT-BYTE
              DUP IF NIP EXIT THEN DROP
              1 SWAP _JJW.POS +! JOSE-JSON-S-OK ENDOF
        47 OF 47 OVER _JJO-EMIT-BYTE
              DUP IF NIP EXIT THEN DROP
              1 SWAP _JJW.POS +! JOSE-JSON-S-OK ENDOF
        92 OF 92 OVER _JJO-EMIT-BYTE
              DUP IF NIP EXIT THEN DROP
              1 SWAP _JJW.POS +! JOSE-JSON-S-OK ENDOF
        98 OF 8 OVER _JJO-EMIT-BYTE
              DUP IF NIP EXIT THEN DROP
              1 SWAP _JJW.POS +! JOSE-JSON-S-OK ENDOF
        102 OF 12 OVER _JJO-EMIT-BYTE
               DUP IF NIP EXIT THEN DROP
               1 SWAP _JJW.POS +! JOSE-JSON-S-OK ENDOF
        110 OF 10 OVER _JJO-EMIT-BYTE
               DUP IF NIP EXIT THEN DROP
               1 SWAP _JJW.POS +! JOSE-JSON-S-OK ENDOF
        114 OF 13 OVER _JJO-EMIT-BYTE
               DUP IF NIP EXIT THEN DROP
               1 SWAP _JJW.POS +! JOSE-JSON-S-OK ENDOF
        116 OF 9 OVER _JJO-EMIT-BYTE
               DUP IF NIP EXIT THEN DROP
               1 SWAP _JJW.POS +! JOSE-JSON-S-OK ENDOF
        117 OF
            1 OVER _JJW.POS +!         \ consume "u"
            DUP _JJO-HEX4
            DUP IF
                >R 2DROP R> EXIT
            THEN
            DROP
            OVER _JJW.TMP2 !
            DUP _JJW.TMP2 @
            DUP 0xD800 >= SWAP 0xDBFF <= AND IF
                DUP _JJO-LEFT 2 < IF
                    DROP JOSE-JSON-S-UTF8 EXIT
                THEN
                DUP _JJO-CURRENT C@ 92 <>
                OVER _JJO-CURRENT 1+ C@ 117 <> OR IF
                    DROP JOSE-JSON-S-UTF8 EXIT
                THEN
                2 OVER _JJW.POS +!
                DUP _JJO-HEX4
                DUP IF
                    >R 2DROP R> EXIT
                THEN
                DROP
                DUP 0xDC00 >= OVER 0xDFFF <= AND 0= IF
                    2DROP JOSE-JSON-S-UTF8 EXIT
                THEN
                OVER _JJW.TMP2 @ 0xD800 - 1024 *
                SWAP 0xDC00 - + 0x10000 +
                _JJO-EMIT-FROM-WORK
            ELSE
                DUP _JJW.TMP2 @
                DUP 0xDC00 >= SWAP 0xDFFF <= AND IF
                    DROP JOSE-JSON-S-UTF8 EXIT
                THEN
                DUP _JJW.TMP2 @ OVER _JJO-EMIT-CP NIP
            THEN
        ENDOF
        2DROP JOSE-JSON-S-SYNTAX EXIT
    ENDCASE ;

: _JJO-STRING  ( workspace -- status )
    DUP _JJO-PEEK 34 <> IF DROP JOSE-JSON-S-SYNTAX EXIT THEN
    1 OVER _JJW.POS +!
    BEGIN
        DUP _JJO-LEFT 0= IF DROP JOSE-JSON-S-SYNTAX EXIT THEN
        DUP _JJO-PEEK
        DUP 34 = IF
            DROP 1 OVER _JJW.POS +!
            DROP JOSE-JSON-S-OK EXIT
        THEN
        DUP 92 = IF
            DROP DUP _JJO-ESCAPE
            DUP IF NIP EXIT THEN DROP
        ELSE
            DUP 32 < IF
                2DROP JOSE-JSON-S-SYNTAX EXIT
            THEN
            DUP 0x80 < IF
                OVER _JJO-EMIT-BYTE
                DUP IF NIP EXIT THEN DROP
                1 OVER _JJW.POS +!
            ELSE
                DROP DUP _JJO-RAW-UTF8
                DUP IF NIP EXIT THEN DROP
            THEN
        THEN
    AGAIN ;

\ =====================================================================
\  Scalar JSON grammar
\ =====================================================================

: _JJO-DIGITS  ( workspace -- )
    BEGIN
        DUP _JJO-LEFT 0> IF
            DUP _JJO-PEEK _JJO-DIGIT?
        ELSE
            0
        THEN
    WHILE
        1 OVER _JJW.POS +!
    REPEAT
    DROP ;

: _JJO-NUMBER  ( workspace -- status )
    DUP _JJO-PEEK 45 = IF
        1 OVER _JJW.POS +!
        DUP _JJO-LEFT 0= IF DROP JOSE-JSON-S-SYNTAX EXIT THEN
    THEN

    DUP _JJO-PEEK 48 = IF
        1 OVER _JJW.POS +!
        DUP _JJO-LEFT IF
            DUP _JJO-PEEK _JJO-DIGIT? IF
                DROP JOSE-JSON-S-SYNTAX EXIT
            THEN
        THEN
    ELSE
        DUP _JJO-PEEK DUP 49 >= SWAP 57 <= AND 0= IF
            DROP JOSE-JSON-S-SYNTAX EXIT
        THEN
        DUP _JJO-DIGITS
    THEN

    DUP _JJO-LEFT IF
        DUP _JJO-PEEK 46 =
    ELSE
        0
    THEN IF
        1 OVER _JJW.POS +!
        DUP _JJO-LEFT 0= IF DROP JOSE-JSON-S-SYNTAX EXIT THEN
        DUP _JJO-PEEK _JJO-DIGIT? 0= IF
            DROP JOSE-JSON-S-SYNTAX EXIT
        THEN
        DUP _JJO-DIGITS
    THEN

    DUP _JJO-LEFT IF
        DUP _JJO-PEEK DUP 101 = SWAP 69 = OR
    ELSE
        0
    THEN IF
        1 OVER _JJW.POS +!
        DUP _JJO-LEFT 0= IF DROP JOSE-JSON-S-SYNTAX EXIT THEN
        DUP _JJO-PEEK DUP 43 = SWAP 45 = OR IF
            1 OVER _JJW.POS +!
        THEN
        DUP _JJO-LEFT 0= IF DROP JOSE-JSON-S-SYNTAX EXIT THEN
        DUP _JJO-PEEK _JJO-DIGIT? 0= IF
            DROP JOSE-JSON-S-SYNTAX EXIT
        THEN
        DUP _JJO-DIGITS
    THEN
    DROP JOSE-JSON-S-OK ;

: _JJO-TRUE  ( workspace -- status )
    DUP _JJO-LEFT 4 < IF DROP JOSE-JSON-S-SYNTAX EXIT THEN
    DUP _JJO-CURRENT 4 S" true" COMPARE IF
        DROP JOSE-JSON-S-SYNTAX EXIT
    THEN
    4 SWAP _JJW.POS +! JOSE-JSON-S-OK ;

: _JJO-FALSE  ( workspace -- status )
    DUP _JJO-LEFT 5 < IF DROP JOSE-JSON-S-SYNTAX EXIT THEN
    DUP _JJO-CURRENT 5 S" false" COMPARE IF
        DROP JOSE-JSON-S-SYNTAX EXIT
    THEN
    5 SWAP _JJW.POS +! JOSE-JSON-S-OK ;

: _JJO-NULL  ( workspace -- status )
    DUP _JJO-LEFT 4 < IF DROP JOSE-JSON-S-SYNTAX EXIT THEN
    DUP _JJO-CURRENT 4 S" null" COMPARE IF
        DROP JOSE-JSON-S-SYNTAX EXIT
    THEN
    4 SWAP _JJW.POS +! JOSE-JSON-S-OK ;

\ =====================================================================
\  Nested-object duplicate tracking
\ =====================================================================

: _JJO-DEPTH+  ( workspace -- status )
    DUP _JJW.DEPTH @ JOSE-JSON-MAX-DEPTH >= IF
        DROP JOSE-JSON-S-DEPTH EXIT
    THEN
    1 SWAP _JJW.DEPTH +!
    JOSE-JSON-S-OK ;

: _JJO-DEPTH-  ( workspace -- )
    -1 SWAP _JJW.DEPTH +! ;

: _JJO-NESTED-BEGIN  ( workspace -- status )
    DUP _JJO-DEPTH+
    DUP IF NIP EXIT THEN DROP
    DUP _JJO-FRAME >R
    DUP _JJW.KEY-TOTAL @ R@ _JJF-KEY-START + !
    DUP _JJW.EMIT-USED @ R@ _JJF-NAME-START + !
    0 R@ _JJF-COUNT + !
    DROP R> DROP
    JOSE-JSON-S-OK ;

: _JJO-NESTED-END  ( workspace -- )
    DUP _JJO-FRAME >R
    R@ _JJF-KEY-START + @ OVER _JJW.KEY-TOTAL !
    R@ _JJF-NAME-START + @ OVER _JJW.EMIT-USED !
    0 R@ _JJF-COUNT + !
    DUP _JJO-DEPTH-
    DROP R> DROP ;

: _JJO-CANDIDATE=KEY  ( key-index workspace -- flag )
    >R
    R@ _JJO-STAGED-KEY
    DUP @ R@ _JJO-STAGED-NAMES +
    SWAP 8 + @
    R@ _JJW.KEY-NAME-START @ R@ _JJO-STAGED-NAMES +
    R@ _JJW.EMIT-USED @ R@ _JJW.KEY-NAME-START @ -
    COMPARE 0=
    R> DROP ;

: _JJO-NESTED-DUPLICATE?  ( workspace -- flag )
    DUP _JJO-FRAME _JJF-KEY-START + @
    OVER _JJO-FRAME _JJF-COUNT + @ 0 ?DO
        DUP I + 2 PICK _JJO-CANDIDATE=KEY IF
            2DROP -1 UNLOOP EXIT
        THEN
    LOOP
    2DROP 0 ;

: _JJO-NESTED-KEY  ( workspace -- status )
    DUP _JJO-FRAME _JJF-COUNT + @
        JOSE-JSON-MAX-MEMBERS >= IF
        DROP JOSE-JSON-S-MEMBERS EXIT
    THEN
    DUP _JJW.KEY-TOTAL @ JOSE-JSON-MAX-MEMBERS >= IF
        DROP JOSE-JSON-S-MEMBERS EXIT
    THEN
    DUP _JJW.EMIT-USED @ OVER _JJW.KEY-NAME-START !
    2 OVER _JJW.EMIT-MODE !
    DUP _JJO-STRING
    DUP IF NIP EXIT THEN DROP
    DUP _JJO-NESTED-DUPLICATE? IF
        DROP JOSE-JSON-S-DUPLICATE EXIT
    THEN

    DUP _JJW.KEY-TOTAL @ OVER _JJO-STAGED-KEY >R
    DUP _JJW.KEY-NAME-START @ R@ !
    DUP _JJW.EMIT-USED @
    OVER _JJW.KEY-NAME-START @ - R@ 8 + !
    1 OVER _JJW.KEY-TOTAL +!
    1 OVER _JJO-FRAME _JJF-COUNT + +!
    DROP R> DROP
    JOSE-JSON-S-OK ;

: _JJO-CONTAINER-FAIL  ( workspace status -- type status )
    SWAP DUP _JJO-DEPTH- DROP
    0 SWAP ;

: _JJO-NESTED-FAIL  ( workspace status -- type status )
    SWAP DUP _JJO-NESTED-END DROP
    0 SWAP ;

: _JJO-CONTAINER-OK  ( workspace type -- type status )
    SWAP DUP _JJO-DEPTH- DROP
    JOSE-JSON-S-OK ;

: _JJO-NESTED-OK  ( workspace type -- type status )
    SWAP DUP _JJO-NESTED-END DROP
    JOSE-JSON-S-OK ;

: _JJO-VALUE-STRING  ( workspace -- status )
    \ Object member names share the decoded-name staging cursor.  Save that
    \ cursor while a value string is measured against the document-sized
    \ value bound, then restore the name limit before parsing resumes.
    DUP _JJW.EMIT-USED @ OVER _JJW.RESERVED0 !
    DUP _JJW.EMIT-MODE @ OVER _JJW.RESERVED1 !
    1 OVER _JJW.EMIT-MODE !
    0 OVER _JJW.EMIT-USED !
    JOSE-JSON-MAX-VALUE-STRING-BYTES
        OVER _JJW.EMIT-CAPACITY !
    DUP _JJO-STRING
    >R
    JOSE-JSON-MAX-NAME-BYTES OVER _JJW.EMIT-CAPACITY !
    DUP _JJW.RESERVED1 @ OVER _JJW.EMIT-MODE !
    DUP _JJW.RESERVED0 @ SWAP _JJW.EMIT-USED !
    R> ;

\ =====================================================================
\  Complete recursive value grammar
\ =====================================================================
\  RECURSE is the only recursion mechanism here.  No DEFER slot or other
\  mutable module dispatch state is needed.

: _JJO-VALUE  ( workspace -- type status )
    DUP _JJO-SKIP-WS
    DUP _JJO-LEFT 0= IF
        DROP 0 JOSE-JSON-S-SYNTAX EXIT
    THEN
    DUP _JJO-PEEK CASE
        34 OF
            DUP _JJO-VALUE-STRING
            DUP IF NIP 0 SWAP EXIT THEN
            2DROP JOSE-JSON-T-STRING JOSE-JSON-S-OK
        ENDOF

        123 OF
            DUP _JJO-NESTED-BEGIN
            DUP IF NIP 0 SWAP EXIT THEN DROP
            1 OVER _JJW.POS +!
            DUP _JJO-SKIP-WS
            DUP _JJO-PEEK 125 = IF
                1 OVER _JJW.POS +!
                JOSE-JSON-T-OBJECT _JJO-NESTED-OK EXIT
            THEN
            BEGIN
                DUP _JJO-NESTED-KEY
                DUP IF _JJO-NESTED-FAIL EXIT THEN DROP
                DUP _JJO-SKIP-WS
                DUP _JJO-PEEK 58 <> IF
                    JOSE-JSON-S-SYNTAX _JJO-NESTED-FAIL EXIT
                THEN
                1 OVER _JJW.POS +!
                DUP _JJO-SKIP-WS
                DUP RECURSE
                DUP IF
                    >R DROP R> _JJO-NESTED-FAIL EXIT
                THEN
                2DROP
                DUP _JJO-SKIP-WS
                DUP _JJO-PEEK
                DUP 125 = IF
                    DROP 1 OVER _JJW.POS +!
                    JOSE-JSON-T-OBJECT _JJO-NESTED-OK EXIT
                THEN
                44 <> IF
                    JOSE-JSON-S-SYNTAX _JJO-NESTED-FAIL EXIT
                THEN
                1 OVER _JJW.POS +!
                DUP _JJO-SKIP-WS
            AGAIN
        ENDOF

        91 OF
            DUP _JJO-DEPTH+
            DUP IF NIP 0 SWAP EXIT THEN DROP
            1 OVER _JJW.POS +!
            DUP _JJO-SKIP-WS
            DUP _JJO-PEEK 93 = IF
                1 OVER _JJW.POS +!
                JOSE-JSON-T-ARRAY _JJO-CONTAINER-OK EXIT
            THEN
            BEGIN
                DUP RECURSE
                DUP IF
                    >R DROP R> _JJO-CONTAINER-FAIL EXIT
                THEN
                2DROP
                DUP _JJO-SKIP-WS
                DUP _JJO-PEEK
                DUP 93 = IF
                    DROP 1 OVER _JJW.POS +!
                    JOSE-JSON-T-ARRAY _JJO-CONTAINER-OK EXIT
                THEN
                44 <> IF
                    JOSE-JSON-S-SYNTAX _JJO-CONTAINER-FAIL EXIT
                THEN
                1 OVER _JJW.POS +!
                DUP _JJO-SKIP-WS
            AGAIN
        ENDOF

        116 OF
            DUP _JJO-TRUE
            DUP IF NIP 0 SWAP EXIT THEN
            2DROP JOSE-JSON-T-BOOL JOSE-JSON-S-OK
        ENDOF

        102 OF
            DUP _JJO-FALSE
            DUP IF NIP 0 SWAP EXIT THEN
            2DROP JOSE-JSON-T-BOOL JOSE-JSON-S-OK
        ENDOF

        110 OF
            DUP _JJO-NULL
            DUP IF NIP 0 SWAP EXIT THEN
            2DROP JOSE-JSON-T-NULL JOSE-JSON-S-OK
        ENDOF

        DUP _JJO-DIGIT? OVER 45 = OR IF
            DROP
            DUP _JJO-NUMBER
            DUP IF NIP 0 SWAP EXIT THEN
            2DROP JOSE-JSON-T-NUMBER JOSE-JSON-S-OK EXIT
        ELSE
            2DROP 0 JOSE-JSON-S-SYNTAX EXIT
        THEN
    ENDCASE ;

\ =====================================================================
\  Top-level object capture and duplicate rejection
\ =====================================================================

: _JJO-CANDIDATE=TOP  ( member-index workspace -- flag )
    >R
    R@ _JJO-STAGED-ENTRY
    DUP _JJE-NAME-OFFSET + @ R@ _JJO-STAGED-NAMES +
    SWAP _JJE-NAME-U + @
    R@ _JJW.TOP-NAME-START @ R@ _JJO-STAGED-NAMES +
    R@ _JJW.EMIT-USED @ R@ _JJW.TOP-NAME-START @ -
    COMPARE 0=
    R> DROP ;

: _JJO-TOP-DUPLICATE?  ( workspace -- flag )
    0 OVER _JJW.TOP-COUNT @ 0 ?DO
        DUP I + 2 PICK _JJO-CANDIDATE=TOP IF
            2DROP -1 UNLOOP EXIT
        THEN
    LOOP
    2DROP 0 ;

: _JJO-TOP-STORE  ( workspace -- )
    DUP _JJW.TOP-COUNT @ OVER _JJO-STAGED-ENTRY >R
    DUP _JJW.TOP-NAME-START @
        R@ _JJE-NAME-OFFSET + !
    DUP _JJW.EMIT-USED @ OVER _JJW.TOP-NAME-START @ -
        R@ _JJE-NAME-U + !
    DUP _JJW.TOP-TYPE @
        R@ _JJE-TYPE + !
    DUP _JJW.TOP-VALUE-START @
        R@ _JJE-VALUE-OFFSET + !
    DUP _JJW.POS @ OVER _JJW.TOP-VALUE-START @ -
        R@ _JJE-VALUE-U + !
    1 SWAP _JJW.TOP-COUNT +!
    R> DROP ;

: _JJO-TOP-OBJECT  ( workspace -- status )
    DUP _JJO-SKIP-WS
    DUP _JJO-PEEK 123 <> IF DROP JOSE-JSON-S-SYNTAX EXIT THEN
    1 OVER _JJW.POS +!
    DUP _JJO-SKIP-WS
    DUP _JJO-PEEK 125 = IF
        1 OVER _JJW.POS +!
        DUP _JJO-SKIP-WS
        DUP _JJO-LEFT IF DROP JOSE-JSON-S-SYNTAX EXIT THEN
        DROP JOSE-JSON-S-OK EXIT
    THEN

    BEGIN
        DUP _JJW.TOP-COUNT @ JOSE-JSON-MAX-MEMBERS >= IF
            DROP JOSE-JSON-S-MEMBERS EXIT
        THEN
        DUP _JJW.EMIT-USED @ OVER _JJW.TOP-NAME-START !
        2 OVER _JJW.EMIT-MODE !
        DUP _JJO-STRING
        DUP IF NIP EXIT THEN DROP
        DUP _JJO-TOP-DUPLICATE? IF
            DROP JOSE-JSON-S-DUPLICATE EXIT
        THEN

        DUP _JJO-SKIP-WS
        DUP _JJO-PEEK 58 <> IF DROP JOSE-JSON-S-SYNTAX EXIT THEN
        1 OVER _JJW.POS +!
        DUP _JJO-SKIP-WS
        DUP _JJW.POS @ OVER _JJW.TOP-VALUE-START !
        DUP _JJO-VALUE
        DUP IF
            >R DROP DROP R> EXIT
        THEN
        DROP
        OVER _JJW.TOP-TYPE !
        DUP _JJO-TOP-STORE

        DUP _JJO-SKIP-WS
        DUP _JJO-PEEK
        DUP 125 = IF
            DROP 1 OVER _JJW.POS +!
            DUP _JJO-SKIP-WS
            DUP _JJO-LEFT IF DROP JOSE-JSON-S-SYNTAX EXIT THEN
            DROP JOSE-JSON-S-OK EXIT
        THEN
        44 <> IF DROP JOSE-JSON-S-SYNTAX EXIT THEN
        1 OVER _JJW.POS +!
        DUP _JJO-SKIP-WS
    AGAIN ;

\ =====================================================================
\  Object parse preflight, staging, and transactional publication
\ =====================================================================

: _JJO-DROP6  ( x1 x2 x3 x4 x5 x6 -- ) 2DROP 2DROP 2DROP ;
: _JJO-DROP7  ( x1 x2 x3 x4 x5 x6 x7 -- )
    2DROP 2DROP 2DROP DROP ;

: _JJO-PARSE-PREFLIGHT-RETURN
  \ ( source source-u descriptor member-capacity
  \   names names-capacity status -- status )
    >R _JJO-DROP6 R> ;

: _JJO-OUTPUT-ALIASED?  ( workspace -- flag )
    DUP _JJW.MEMBER-CAPACITY @ JOSE-JSON-OBJECT-BYTES
    DUP IF 2DROP DROP -1 EXIT THEN
    DROP >R
    DUP _JJW.SOURCE @ OVER _JJW.SOURCE-U @
    2 PICK _JJW.DESCRIPTOR @ R@ MSPAN-OVERLAP? IF
        R> DROP DROP -1 EXIT
    THEN
    DUP _JJW.SOURCE @ OVER _JJW.SOURCE-U @
    2 PICK _JJW.NAMES @ 3 PICK _JJW.NAMES-CAPACITY @
        MSPAN-OVERLAP? IF
        R> DROP DROP -1 EXIT
    THEN
    DUP _JJW.DESCRIPTOR @ R@
    2 PICK _JJW.NAMES @ 3 PICK _JJW.NAMES-CAPACITY @
        MSPAN-OVERLAP?
    R> DROP SWAP DROP ;

: _JJO-PUBLISH  ( workspace -- )
    DUP _JJW.MEMBER-CAPACITY @ JOSE-JSON-OBJECT-BYTES
    DROP >R
    \ Invalidate first, independently of the following bulk clear.  Any
    \ publication THROW after this store leaves OBJECT-VALID? false.
    0 OVER _JJW.DESCRIPTOR @ _JJD.MAGIC !
    DUP _JJW.DESCRIPTOR @ R@ 0 FILL
    DUP _JJW.TOP-COUNT @
        OVER _JJW.DESCRIPTOR @ _JJD.COUNT !
    DUP _JJW.MEMBER-CAPACITY @
        OVER _JJW.DESCRIPTOR @ _JJD.CAPACITY !
    DUP _JJW.EMIT-USED @
        OVER _JJW.DESCRIPTOR @ _JJD.NAMES-U !
    DUP _JJW.SOURCE-U @
        OVER _JJW.DESCRIPTOR @ _JJD.SOURCE-U !

    DUP _JJO-STAGED-NAMES
    OVER _JJW.NAMES @
    2 PICK _JJW.EMIT-USED @
    DUP IF MOVE ELSE 2DROP DROP THEN

    DUP _JJO-ENTRY-STAGE-OFF +
    OVER _JJW.DESCRIPTOR @ JOSE-JSON-OBJECT-HEADER-SIZE +
    2 PICK _JJW.TOP-COUNT @ JOSE-JSON-OBJECT-MEMBER-SIZE *
    DUP IF MOVE ELSE 2DROP DROP THEN
    _JJO-DESCRIPTOR-MAGIC
        OVER _JJW.DESCRIPTOR @ _JJD.MAGIC !
    DROP R> DROP ;

: _JJO-BIND
  \ ( source source-u descriptor member-capacity
  \   names names-capacity workspace -- workspace )
    DUP JOSE-JSON-OBJECT-WORKSPACE-SIZE 0 FILL
    6 PICK OVER _JJW.SOURCE !
    5 PICK OVER _JJW.SOURCE-U !
    4 PICK OVER _JJW.DESCRIPTOR !
    3 PICK OVER _JJW.MEMBER-CAPACITY !
    2 PICK OVER _JJW.NAMES !
    1 PICK OVER _JJW.NAMES-CAPACITY !
    >R _JJO-DROP6 R> ;

: _JJO-PARSE-STAGE  ( workspace -- status )
    DUP _JJO-OUTPUT-ALIASED? IF
        DROP JOSE-JSON-S-ALIAS EXIT
    THEN

    DUP _JJO-STAGED-NAMES OVER _JJW.EMIT-A !
    JOSE-JSON-MAX-NAME-BYTES OVER _JJW.EMIT-CAPACITY !
    1 OVER _JJW.DEPTH !

    DUP _JJO-TOP-OBJECT
    DUP IF NIP EXIT THEN
    DROP

    DUP _JJW.TOP-COUNT @ OVER _JJW.MEMBER-CAPACITY @ > IF
        DROP JOSE-JSON-S-CAPACITY EXIT
    THEN
    DUP _JJW.EMIT-USED @ OVER _JJW.NAMES-CAPACITY @ > IF
        DROP JOSE-JSON-S-CAPACITY EXIT
    THEN

    DROP JOSE-JSON-S-OK ;

: _JJO-PARSE-ADMITTED
  \ ( source source-u descriptor member-capacity
  \   names names-capacity workspace -- status )
    _JJO-BIND _JJO-PARSE-STAGE ;

: _JJO-CLEAR-DESCRIPTOR  ( descriptor member-capacity -- )
    0 2 PICK _JJD.MAGIC !
    JOSE-JSON-OBJECT-BYTES DROP 0 FILL ;

: _JJO-CLEAR-NAMES  ( names names-capacity -- )
    JOSE-JSON-MAX-NAME-BYTES MIN 0 FILL ;

: _JJO-PARSE-THROW-CLEAN
  \ ( descriptor member-capacity names names-capacity workspace -- )
    >R
    3 PICK 3 PICK _JJO-CLEAR-DESCRIPTOR
    1 PICK 1 PICK _JJO-CLEAR-NAMES
    2DROP 2DROP
    R> _JJO-OBJECT-WORKSPACE-ZERO ;

: _JJO-PUBLISH-CALL  ( workspace -- )
    ['] _JJO-PUBLISH
    ['] _JJO-OBJECT-WORKSPACE-ZERO
    _JJO-CALL-FINALLY ;

: _JJO-PARSE-CALL
  \ ( source source-u descriptor member-capacity
  \   names names-capacity workspace xt -- status )
    \ KDOS CATCH restores depth after THROW, not the values in cells consumed
    \ by the caught operation.  Preserve authoritative cleanup geometry below
    \ CATCH's return-stack frame.  These R> operations must remain inline:
    \ a called helper would put its own return address above the saved cells.
    1 PICK >R
    2 PICK >R
    3 PICK >R
    4 PICK >R
    5 PICK >R
    CATCH
    DUP IF
        DROP
        _JJO-DROP7
        R> R> R> R> R> _JJO-PARSE-THROW-CLEAN
        JOSE-JSON-S-INTERNAL EXIT
    THEN
    DROP
    R> DROP R> DROP R> DROP R> DROP
    DUP IF
        R@ _JJO-OBJECT-WORKSPACE-ZERO
        R> DROP EXIT
    THEN
    DROP
    R@ _JJO-PUBLISH-CALL
    R> DROP
    JOSE-JSON-S-OK ;

: JOSE-JSON-OBJECT-PARSE
  ( source source-u descriptor member-capacity names names-capacity workspace -- status )
    >R

    \ Qualify every complete public span before _JJO-BIND performs the first
    \ workspace write.  Public aliases are checked only after all four spans
    \ have passed the platform caller-memory boundary.
    R@ JOSE-JSON-OBJECT-WORKSPACE-SIZE
        _JJO-CALLER-SPAN>STATUS ?DUP IF
        _JJO-PARSE-PREFLIGHT-RETURN R> DROP EXIT
    THEN
    5 PICK 5 PICK _JJO-CALLER-SPAN>STATUS ?DUP IF
        _JJO-PARSE-PREFLIGHT-RETURN R> DROP EXIT
    THEN
    4 PICK JOSE-JSON-MAX-DOCUMENT-BYTES > IF
        JOSE-JSON-S-DOCUMENT
        _JJO-PARSE-PREFLIGHT-RETURN R> DROP EXIT
    THEN
    2DUP _JJO-CALLER-SPAN>STATUS ?DUP IF
        _JJO-PARSE-PREFLIGHT-RETURN R> DROP EXIT
    THEN

    2 PICK JOSE-JSON-OBJECT-BYTES
    DUP IF
        NIP _JJO-PARSE-PREFLIGHT-RETURN R> DROP EXIT
    THEN
    DROP
    4 PICK OVER _JJO-CALLER-SPAN>STATUS ?DUP IF
        SWAP DROP _JJO-PARSE-PREFLIGHT-RETURN R> DROP EXIT
    THEN

    4 PICK OVER R@ JOSE-JSON-OBJECT-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        DROP JOSE-JSON-S-ALIAS
        _JJO-PARSE-PREFLIGHT-RETURN R> DROP EXIT
    THEN
    DROP

    5 PICK 5 PICK R@ JOSE-JSON-OBJECT-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        JOSE-JSON-S-ALIAS
        _JJO-PARSE-PREFLIGHT-RETURN R> DROP EXIT
    THEN
    2DUP R@ JOSE-JSON-OBJECT-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        JOSE-JSON-S-ALIAS
        _JJO-PARSE-PREFLIGHT-RETURN R> DROP EXIT
    THEN

    \ Complete source/descriptor/names table alias admission before entering
    \ the guarded operation.  Full declared spans, not eventual used
    \ prefixes, participate in these checks.
    5 PICK 5 PICK 5 PICK 5 PICK
    JOSE-JSON-OBJECT-BYTES DROP MSPAN-OVERLAP? IF
        JOSE-JSON-S-ALIAS
        _JJO-PARSE-PREFLIGHT-RETURN R> DROP EXIT
    THEN
    5 PICK 5 PICK 3 PICK 3 PICK MSPAN-OVERLAP? IF
        JOSE-JSON-S-ALIAS
        _JJO-PARSE-PREFLIGHT-RETURN R> DROP EXIT
    THEN
    3 PICK 3 PICK JOSE-JSON-OBJECT-BYTES DROP
    3 PICK 3 PICK MSPAN-OVERLAP? IF
        JOSE-JSON-S-ALIAS
        _JJO-PARSE-PREFLIGHT-RETURN R> DROP EXIT
    THEN

    R> ['] _JJO-PARSE-ADMITTED _JJO-PARSE-CALL ;

\ =====================================================================
\  Standalone exact JSON-string measurement and decoding
\ =====================================================================

: _JJO-STRING-MEASURE-RUN  ( workspace -- decoded-u status )
    DUP _JJO-STRING
    DUP IF
        NIP 0 SWAP EXIT
    THEN
    DROP
    DUP _JJO-LEFT IF
        DROP 0 JOSE-JSON-S-SYNTAX EXIT
    THEN
    DUP _JJW.EMIT-USED @ SWAP DROP
    JOSE-JSON-S-OK ;

: JOSE-JSON-STRING-MEASURE
  ( source source-u workspace -- decoded-u status )
    >R
    R@ JOSE-JSON-STRING-WORKSPACE-SIZE
        _JJO-CALLER-SPAN>STATUS ?DUP IF
        >R 2DROP 0 R> R> DROP EXIT
    THEN
    2DUP _JJO-CALLER-SPAN>STATUS ?DUP IF
        >R 2DROP 0 R> R> DROP EXIT
    THEN
    DUP JOSE-JSON-MAX-DOCUMENT-BYTES > IF
        2DROP R> DROP 0 JOSE-JSON-S-DOCUMENT EXIT
    THEN
    2DUP R@ JOSE-JSON-STRING-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        2DROP R> DROP 0 JOSE-JSON-S-ALIAS EXIT
    THEN

    R@ _JJO-STRING-WORKSPACE-ZERO
    DUP R@ _JJW.SOURCE-U ! DROP
    DUP R@ _JJW.SOURCE ! DROP
    1 R@ _JJW.EMIT-MODE !
    JOSE-JSON-MAX-VALUE-STRING-BYTES R@ _JJW.EMIT-CAPACITY !

    R>
    ['] _JJO-STRING-MEASURE-RUN
    ['] _JJO-STRING-WORKSPACE-ZERO
    _JJO-CALL-FINALLY ;

: _JJO-DROP4  ( x1 x2 x3 x4 -- ) 2DROP 2DROP ;

: _JJO-STRING-DECODE-RUN  ( workspace -- written status )
    2 OVER _JJW.EMIT-MODE !
    DUP _JJO-STRING
    DUP IF
        NIP 0 SWAP EXIT
    THEN
    DROP
    DUP _JJO-LEFT IF
        DROP 0 JOSE-JSON-S-SYNTAX EXIT
    THEN
    DUP _JJW.EMIT-USED @ SWAP DROP
    JOSE-JSON-S-OK ;

: JOSE-JSON-STRING-DECODE
  ( source source-u destination capacity workspace -- written status )
    >R
    R@ JOSE-JSON-STRING-WORKSPACE-SIZE
        _JJO-CALLER-SPAN>STATUS ?DUP IF
        >R _JJO-DROP4 0 R> R> DROP EXIT
    THEN
    2OVER _JJO-CALLER-SPAN>STATUS ?DUP IF
        >R _JJO-DROP4 0 R> R> DROP EXIT
    THEN
    2DUP _JJO-CALLER-SPAN>STATUS ?DUP IF
        >R _JJO-DROP4 0 R> R> DROP EXIT
    THEN
    2 PICK JOSE-JSON-MAX-DOCUMENT-BYTES > IF
        _JJO-DROP4 R> DROP 0 JOSE-JSON-S-DOCUMENT EXIT
    THEN
    2OVER R@ JOSE-JSON-STRING-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        _JJO-DROP4 R> DROP 0 JOSE-JSON-S-ALIAS EXIT
    THEN
    2DUP R@ JOSE-JSON-STRING-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        _JJO-DROP4 R> DROP 0 JOSE-JSON-S-ALIAS EXIT
    THEN
    2OVER 2OVER MSPAN-OVERLAP? IF
        _JJO-DROP4 R> DROP 0 JOSE-JSON-S-ALIAS EXIT
    THEN

    2OVER R@ JOSE-JSON-STRING-MEASURE
    DUP IF
        >R DROP _JJO-DROP4 0 R> R> DROP EXIT
    THEN
    DROP
    DUP 2 PICK U> IF
        DROP _JJO-DROP4 R> DROP 0 JOSE-JSON-S-CAPACITY EXIT
    THEN

    R@ _JJO-STRING-WORKSPACE-ZERO
    DUP R@ _JJW.TMP1 ! DROP
    DUP R@ _JJW.EMIT-CAPACITY ! DROP
    DUP R@ _JJW.EMIT-A ! DROP
    DUP R@ _JJW.SOURCE-U ! DROP
    DUP R@ _JJW.SOURCE ! DROP

    R>
    ['] _JJO-STRING-DECODE-RUN
    ['] _JJO-STRING-WORKSPACE-ZERO
    _JJO-CALL-FINALLY ;

\ =====================================================================
\  Compile-time geometry assertions
\ =====================================================================

: _JJO-GEOMETRY-ABORT  ( -- )
    ." JOSE JSON object geometry mismatch" CR ABORT ;

1 CELLS 8 <> [IF]
    _JJO-GEOMETRY-ABORT
[THEN]

_JJO-FRAMES-OFF
JOSE-JSON-MAX-DEPTH _JJO-FRAME-SIZE * +
_JJO-ENTRY-STAGE-OFF <> [IF]
    _JJO-GEOMETRY-ABORT
[THEN]

_JJO-ENTRY-STAGE-OFF
JOSE-JSON-MAX-MEMBERS JOSE-JSON-OBJECT-MEMBER-SIZE * +
_JJO-KEY-STAGE-OFF <> [IF]
    _JJO-GEOMETRY-ABORT
[THEN]

_JJO-KEY-STAGE-OFF
JOSE-JSON-MAX-MEMBERS 16 * +
_JJO-NAME-STAGE-OFF <> [IF]
    _JJO-GEOMETRY-ABORT
[THEN]

_JJO-NAME-STAGE-OFF
JOSE-JSON-MAX-NAME-BYTES +
JOSE-JSON-OBJECT-WORKSPACE-SIZE <> [IF]
    _JJO-GEOMETRY-ABORT
[THEN]
