\ =====================================================================
\  dns-txt.f - Caller-owned bounded DNS TXT wire messages
\ =====================================================================
\  This protocol-neutral module builds one recursive IN/TXT query and
\  parses one matching DNS response.  It performs no I/O, retry, cache,
\  resolver selection, alias chase, application decoding, or trust policy.
\
\  Query bytes, parser scratch, response evidence, and the TXT destination
\  are caller-owned.  The module owns no mutable state.  A successful parse
\  requires exactly one direct IN/TXT answer at the queried owner.  One RR
\  may contain several RFC character-strings; their binary payloads are
\  concatenated in wire order.  Multiple matching RRs are reported as an
\  explicit discovery ambiguity rather than silently choosing one.
\
\  Public API:
\    DNS-TXT-NAME-VALIDATE  ( name-a name-u -- status )
\    DNS-TXT-QUERY-BUILD    ( name-a name-u id query -- status )
\    DNS-TXT-QUERY-VALID?   ( query -- flag )
\    DNS-TXT-QUERY$         ( query -- packet-a packet-u status )
\    DNS-TXT-QUERY-ID@      ( query -- id status )
\    DNS-TXT-QUERY-WIPE     ( query -- status )
\    DNS-TXT-RESULT-INIT    ( value-a value-cap result -- status )
\    DNS-TXT-RESULT-VALID?  ( result -- flag )
\    DNS-TXT-PARSE          ( response-a response-u query result -- status )
\    DNS-TXT-STATUS@        ( result -- status )
\    DNS-TXT-VALUE$         ( result -- value-a value-u )
\    DNS-TXT-RCODE@         ( result -- rcode )
\    DNS-TXT-FLAGS@         ( result -- header-flags )
\    DNS-TXT-EVIDENCE@      ( result -- evidence )
\    DNS-TXT-ANSWER-COUNT@  ( result -- count )
\    DNS-TXT-MATCHED-COUNT@ ( result -- count )
\    DNS-TXT-STRING-COUNT@  ( result -- count )
\    DNS-TXT-TTL@           ( result -- ttl )
\    DNS-TXT-RESULT-WIPE    ( result -- status )
\ =====================================================================

PROVIDED akashic-dns-txt

REQUIRE ../utils/memory-span.f
REQUIRE ../utils/caller-span.f

\ =====================================================================
\  Public bounds, status, and evidence vocabulary
\ =====================================================================

  63 CONSTANT DNS-TXT-LABEL-MAX
 253 CONSTANT DNS-TXT-NAME-MAX
 255 CONSTANT DNS-TXT-WIRE-NAME-MAX
 271 CONSTANT DNS-TXT-QUERY-MAX
4096 CONSTANT DNS-TXT-VALUE-MAX
65535 CONSTANT DNS-TXT-MESSAGE-MAX
 128 CONSTANT DNS-TXT-COMPRESSION-HOPS-MAX

0  CONSTANT DNS-TXT-S-OK
1  CONSTANT DNS-TXT-S-INVALID
2  CONSTANT DNS-TXT-S-CAPACITY
3  CONSTANT DNS-TXT-S-ALIAS
4  CONSTANT DNS-TXT-S-RANGE
5  CONSTANT DNS-TXT-S-PROTECTED
6  CONSTANT DNS-TXT-S-PLATFORM
7  CONSTANT DNS-TXT-S-EMPTY
8  CONSTANT DNS-TXT-S-MALFORMED
9  CONSTANT DNS-TXT-S-MISMATCH
10 CONSTANT DNS-TXT-S-TRUNCATED
11 CONSTANT DNS-TXT-S-RCODE
12 CONSTANT DNS-TXT-S-NODATA
13 CONSTANT DNS-TXT-S-DUPLICATE

: DNS-TXT-STATUS-VALID?  ( status -- flag )
    DUP DNS-TXT-S-OK >=
    SWAP DNS-TXT-S-DUPLICATE <= AND ;

1  CONSTANT DNS-TXT-E-RESPONSE
2  CONSTANT DNS-TXT-E-ID
4  CONSTANT DNS-TXT-E-QUESTION
8  CONSTANT DNS-TXT-E-TRUNCATED
16 CONSTANT DNS-TXT-E-RCODE
32 CONSTANT DNS-TXT-E-VALUE

\ =====================================================================
\  Wire constants and caller-owned geometry
\ =====================================================================

16 CONSTANT _DNT-TYPE-TXT
1  CONSTANT _DNT-CLASS-IN

0x444E545152593031 CONSTANT _DNTQ-MAGIC-VALUE  \ "DNTQRY01"

 0 CONSTANT _DNTQ-MAGIC
 8 CONSTANT _DNTQ-LENGTH
16 CONSTANT _DNTQ-ID
24 CONSTANT _DNTQ-NAME-U
32 CONSTANT _DNTQ-PACKET
304 CONSTANT DNS-TXT-QUERY-SIZE

: _DNTQ.MAGIC   ( query -- address ) _DNTQ-MAGIC + ;
: _DNTQ.LENGTH  ( query -- address ) _DNTQ-LENGTH + ;
: _DNTQ.ID      ( query -- address ) _DNTQ-ID + ;
: _DNTQ.NAME-U  ( query -- address ) _DNTQ-NAME-U + ;
: _DNTQ.PACKET  ( query -- address ) _DNTQ-PACKET + ;

0x444E545245533031 CONSTANT _DNTR-MAGIC-VALUE  \ "DNTRES01"

  0 CONSTANT _DNTR-MAGIC
  8 CONSTANT _DNTR-BUFFER
 16 CONSTANT _DNTR-CAPACITY
 24 CONSTANT _DNTR-LENGTH
 32 CONSTANT _DNTR-STATUS
 40 CONSTANT _DNTR-RCODE
 48 CONSTANT _DNTR-FLAGS
 56 CONSTANT _DNTR-EVIDENCE
 64 CONSTANT _DNTR-ANSWER-COUNT
 72 CONSTANT _DNTR-MATCHED-COUNT
 80 CONSTANT _DNTR-STRING-COUNT
 88 CONSTANT _DNTR-TTL

\ All fields below this line are caller-owned parse scratch.
 96 CONSTANT _DNTR-MESSAGE
104 CONSTANT _DNTR-MESSAGE-U
112 CONSTANT _DNTR-QUERY
120 CONSTANT _DNTR-CURSOR
128 CONSTANT _DNTR-NAME-NEXT
136 CONSTANT _DNTR-NAME-U
144 CONSTANT _DNTR-NAME-POS
152 CONSTANT _DNTR-NAME-HOPS
160 CONSTANT _DNTR-NAME-JUMPED
168 CONSTANT _DNTR-LABEL-U
176 CONSTANT _DNTR-RDATA-END
184 CONSTANT _DNTR-OWNER-MATCH
192 CONSTANT _DNTR-RR-TYPE
200 CONSTANT _DNTR-RR-CLASS
208 CONSTANT _DNTR-RR-TTL
216 CONSTANT _DNTR-RR-RDLENGTH
224 CONSTANT _DNTR-SECTION-LEFT
232 CONSTANT _DNTR-INSPECT
240 CONSTANT _DNTR-RDATA-POS
248 CONSTANT _DNTR-COPY
256 CONSTANT _DNTR-NAME
512 CONSTANT DNS-TXT-RESULT-SIZE

: _DNTR.MAGIC          ( result -- address ) _DNTR-MAGIC + ;
: _DNTR.BUFFER         ( result -- address ) _DNTR-BUFFER + ;
: _DNTR.CAPACITY       ( result -- address ) _DNTR-CAPACITY + ;
: _DNTR.LENGTH         ( result -- address ) _DNTR-LENGTH + ;
: _DNTR.STATUS         ( result -- address ) _DNTR-STATUS + ;
: _DNTR.RCODE          ( result -- address ) _DNTR-RCODE + ;
: _DNTR.FLAGS          ( result -- address ) _DNTR-FLAGS + ;
: _DNTR.EVIDENCE       ( result -- address ) _DNTR-EVIDENCE + ;
: _DNTR.ANSWER-COUNT   ( result -- address ) _DNTR-ANSWER-COUNT + ;
: _DNTR.MATCHED-COUNT  ( result -- address ) _DNTR-MATCHED-COUNT + ;
: _DNTR.STRING-COUNT   ( result -- address ) _DNTR-STRING-COUNT + ;
: _DNTR.TTL            ( result -- address ) _DNTR-TTL + ;
: _DNTR.MESSAGE        ( result -- address ) _DNTR-MESSAGE + ;
: _DNTR.MESSAGE-U      ( result -- address ) _DNTR-MESSAGE-U + ;
: _DNTR.QUERY          ( result -- address ) _DNTR-QUERY + ;
: _DNTR.CURSOR         ( result -- address ) _DNTR-CURSOR + ;
: _DNTR.NAME-NEXT      ( result -- address ) _DNTR-NAME-NEXT + ;
: _DNTR.NAME-U         ( result -- address ) _DNTR-NAME-U + ;
: _DNTR.NAME-POS       ( result -- address ) _DNTR-NAME-POS + ;
: _DNTR.NAME-HOPS      ( result -- address ) _DNTR-NAME-HOPS + ;
: _DNTR.NAME-JUMPED    ( result -- address ) _DNTR-NAME-JUMPED + ;
: _DNTR.LABEL-U        ( result -- address ) _DNTR-LABEL-U + ;
: _DNTR.RDATA-END      ( result -- address ) _DNTR-RDATA-END + ;
: _DNTR.OWNER-MATCH    ( result -- address ) _DNTR-OWNER-MATCH + ;
: _DNTR.RR-TYPE        ( result -- address ) _DNTR-RR-TYPE + ;
: _DNTR.RR-CLASS       ( result -- address ) _DNTR-RR-CLASS + ;
: _DNTR.RR-TTL         ( result -- address ) _DNTR-RR-TTL + ;
: _DNTR.RR-RDLENGTH    ( result -- address ) _DNTR-RR-RDLENGTH + ;
: _DNTR.SECTION-LEFT   ( result -- address ) _DNTR-SECTION-LEFT + ;
: _DNTR.INSPECT        ( result -- address ) _DNTR-INSPECT + ;
: _DNTR.RDATA-POS      ( result -- address ) _DNTR-RDATA-POS + ;
: _DNTR.COPY           ( result -- address ) _DNTR-COPY + ;
: _DNTR.NAME           ( result -- address ) _DNTR-NAME + ;

\ =====================================================================
\  Generic admission and stack helpers
\ =====================================================================

: _DNT-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF DROP DNS-TXT-S-OK EXIT THEN
    DUP CALLER-SPAN-S-RANGE = IF DROP DNS-TXT-S-RANGE EXIT THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP DNS-TXT-S-PROTECTED EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP DNS-TXT-S-PLATFORM EXIT
    THEN
    DROP DNS-TXT-S-PLATFORM ;

: _DNT-SPAN-STATUS  ( address length -- status )
    DUP 0< IF 2DROP DNS-TXT-S-INVALID EXIT THEN
    DUP 0= IF 2DROP DNS-TXT-S-OK EXIT THEN
    OVER 0= IF 2DROP DNS-TXT-S-INVALID EXIT THEN
    CALLER-SPAN-STATUS _DNT-CALLER>STATUS ;

: _DNT-FIXED-STATUS  ( address size -- status )
    OVER 0= IF 2DROP DNS-TXT-S-INVALID EXIT THEN
    OVER 7 AND IF 2DROP DNS-TXT-S-INVALID EXIT THEN
    _DNT-SPAN-STATUS ;

: _DNT-QUERY-STATUS  ( query -- status )
    DNS-TXT-QUERY-SIZE _DNT-FIXED-STATUS ;

: _DNT-RESULT-STATUS  ( result -- status )
    DNS-TXT-RESULT-SIZE _DNT-FIXED-STATUS ;

: _DNT-DROP3  ( x1 x2 x3 -- )
    2DROP DROP ;

: _DNT-DROP4  ( x1 x2 x3 x4 -- )
    2DROP 2DROP ;

: _DNT-RETURN3  ( x1 x2 x3 status -- status )
    >R _DNT-DROP3 R> ;

: _DNT-RETURN4  ( x1 x2 x3 x4 status -- status )
    >R _DNT-DROP4 R> ;

: _DNT-/STRING  ( address length prefix-u -- address' length' )
    >R SWAP R@ + SWAP R> - ;

: _DNT-U16@  ( address -- value )
    DUP C@ 8 LSHIFT
    SWAP 1+ C@ OR ;

: _DNT-U16!  ( value address -- )
    >R
    DUP 8 RSHIFT R@ C!
    0xFF AND R> 1+ C! ;

: _DNT-U32@  ( address -- value )
    DUP _DNT-U16@ 16 LSHIFT
    SWAP 2 + _DNT-U16@ OR ;

: _DNT-EVIDENCE+  ( bit result -- )
    _DNTR.EVIDENCE DUP @ ROT OR SWAP ! ;

\ =====================================================================
\  Bounded dotted presentation names
\ =====================================================================

: _DNT-NAME-CHAR?  ( byte -- flag )
    DUP 33 < OVER 126 > OR IF DROP 0 EXIT THEN
    [CHAR] . <> ;

: _DNT-NAME-SYNTAX?  ( address length -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    0
    BEGIN
        OVER
    WHILE
        2 PICK C@
        DUP [CHAR] . = IF
            DROP
            DUP 0= OVER DNS-TXT-LABEL-MAX > OR IF
                _DNT-DROP3 0 EXIT
            THEN
            DROP 0
        ELSE
            _DNT-NAME-CHAR? 0= IF
                _DNT-DROP3 0 EXIT
            THEN
            1+ DUP DNS-TXT-LABEL-MAX > IF
                _DNT-DROP3 0 EXIT
            THEN
        THEN
        >R 1 _DNT-/STRING R>
    REPEAT
    NIP NIP
    DUP 0<> SWAP DNS-TXT-LABEL-MAX <= AND ;

: DNS-TXT-NAME-VALIDATE  ( name-a name-u -- status )
    DUP 0< IF 2DROP DNS-TXT-S-INVALID EXIT THEN
    DUP DNS-TXT-NAME-MAX U> IF
        2DROP DNS-TXT-S-CAPACITY EXIT
    THEN
    DUP 0= IF 2DROP DNS-TXT-S-INVALID EXIT THEN
    OVER 0= IF 2DROP DNS-TXT-S-INVALID EXIT THEN
    2DUP _DNT-SPAN-STATUS ?DUP IF
        >R 2DROP R> EXIT
    THEN
    _DNT-NAME-SYNTAX? IF
        DNS-TXT-S-OK
    ELSE
        DNS-TXT-S-INVALID
    THEN ;

: _DNT-FIND-DOT  ( address length -- prefix-u found? )
    0
    BEGIN
        DUP 2 PICK U<
    WHILE
        2 PICK OVER + C@ [CHAR] . = IF
            NIP NIP -1 EXIT
        THEN
        1+
    REPEAT
    NIP NIP 0 ;

: _DNT-COPY-LABEL  ( source label-u destination -- )
    >R
    DUP R@ C!
    R> 1+ SWAP CMOVE ;

: _DNT-AFTER-LABEL
  ( source source-u label-u destination -- source' source-u' destination' )
    OVER + 1+ >R
    >R
    R@ 1+ _DNT-/STRING
    R> DROP
    R> ;

: _DNT-ENCODE-NAME  ( source source-u destination -- after )
    >R
    2DUP _DNT-FIND-DOT
    IF
        2 PICK OVER R@ _DNT-COPY-LABEL
        R> _DNT-AFTER-LABEL
        RECURSE EXIT
    THEN

    2 PICK OVER R@ _DNT-COPY-LABEL
    >R 2DROP R> R> + 1+
    DUP 0 SWAP C!
    1+ ;

: _DNT-WIRE-NAME?  ( address length -- flag )
    DUP 2 < OVER DNS-TXT-WIRE-NAME-MAX > OR IF
        2DROP 0 EXIT
    THEN
    BEGIN
        DUP
    WHILE
        OVER C@
        DUP 0= IF
            DROP
            DUP 1 = >R
            2DROP R> EXIT
        THEN
        DUP DNS-TXT-LABEL-MAX > IF
            DROP 2DROP 0 EXIT
        THEN
        1+ DUP 2 PICK U> IF
            DROP 2DROP 0 EXIT
        THEN
        >R R@ _DNT-/STRING R> DROP
    REPEAT
    2DROP 0 ;

\ =====================================================================
\  Query construction and lifecycle
\ =====================================================================

: _DNT-QUERY-WRITE  ( name-a name-u id query -- )
    >R
    R@ DNS-TXT-QUERY-SIZE 0 FILL

    DUP R@ _DNTQ.ID !
    OVER 2 + R@ _DNTQ.NAME-U !
    OVER 18 + R@ _DNTQ.LENGTH !

    DUP R@ _DNTQ.PACKET _DNT-U16!
    0x0100 R@ _DNTQ.PACKET 2 + _DNT-U16!
    1 R@ _DNTQ.PACKET 4 + _DNT-U16!
    0 R@ _DNTQ.PACKET 6 + _DNT-U16!
    0 R@ _DNTQ.PACKET 8 + _DNT-U16!
    0 R@ _DNTQ.PACKET 10 + _DNT-U16!

    2 PICK 2 PICK
    R@ _DNTQ.PACKET 12 +
    _DNT-ENCODE-NAME DROP

    R@ _DNTQ.PACKET
    R@ _DNTQ.LENGTH @ + 4 -
    DUP _DNT-TYPE-TXT SWAP _DNT-U16!
    2 + _DNT-CLASS-IN SWAP _DNT-U16!

    _DNTQ-MAGIC-VALUE R@ _DNTQ.MAGIC !
    DROP 2DROP
    R> DROP ;

: DNS-TXT-QUERY-BUILD  ( name-a name-u id query -- status )
    DUP _DNT-QUERY-STATUS ?DUP IF
        _DNT-RETURN4 EXIT
    THEN
    3 PICK 3 PICK DNS-TXT-NAME-VALIDATE ?DUP IF
        _DNT-RETURN4 EXIT
    THEN
    OVER 0< 2 PICK 65535 U> OR IF
        DNS-TXT-S-INVALID _DNT-RETURN4 EXIT
    THEN
    3 PICK 3 PICK
    2 PICK DNS-TXT-QUERY-SIZE
    MSPAN-OVERLAP? IF
        DNS-TXT-S-ALIAS _DNT-RETURN4 EXIT
    THEN
    _DNT-QUERY-WRITE
    DNS-TXT-S-OK ;

: DNS-TXT-QUERY-VALID?  ( query -- flag )
    DUP _DNT-QUERY-STATUS ?DUP IF
        2DROP 0 EXIT
    THEN
    DUP _DNTQ.MAGIC @ _DNTQ-MAGIC-VALUE <> IF
        DROP 0 EXIT
    THEN
    DUP _DNTQ.LENGTH @
    DUP 19 < OVER DNS-TXT-QUERY-MAX > OR IF
        2DROP 0 EXIT
    THEN
    DROP
    DUP _DNTQ.ID @ DUP 0< SWAP 65535 U> OR IF
        DROP 0 EXIT
    THEN
    DUP _DNTQ.NAME-U @
    DUP 3 < OVER DNS-TXT-WIRE-NAME-MAX > OR IF
        2DROP 0 EXIT
    THEN
    DROP
    DUP _DNTQ.LENGTH @
    OVER _DNTQ.NAME-U @ 16 + <> IF
        DROP 0 EXIT
    THEN

    DUP _DNTQ.PACKET _DNT-U16@
    OVER _DNTQ.ID @ <> IF DROP 0 EXIT THEN
    DUP _DNTQ.PACKET 2 + _DNT-U16@ 0x0100 <> IF
        DROP 0 EXIT
    THEN
    DUP _DNTQ.PACKET 4 + _DNT-U16@ 1 <> IF
        DROP 0 EXIT
    THEN
    DUP _DNTQ.PACKET 6 + _DNT-U16@ IF DROP 0 EXIT THEN
    DUP _DNTQ.PACKET 8 + _DNT-U16@ IF DROP 0 EXIT THEN
    DUP _DNTQ.PACKET 10 + _DNT-U16@ IF DROP 0 EXIT THEN
    DUP _DNTQ.PACKET 12 +
    OVER _DNTQ.NAME-U @ _DNT-WIRE-NAME? 0= IF
        DROP 0 EXIT
    THEN

    DUP _DNTQ.PACKET 12 +
    OVER _DNTQ.NAME-U @ +
    DUP _DNT-U16@ _DNT-TYPE-TXT <> IF
        2DROP 0 EXIT
    THEN
    2 + _DNT-U16@ _DNT-CLASS-IN <> IF
        DROP 0 EXIT
    THEN
    DROP -1 ;

: DNS-TXT-QUERY$  ( query -- packet-a packet-u status )
    DUP DNS-TXT-QUERY-VALID? 0= IF
        DROP 0 0 DNS-TXT-S-INVALID EXIT
    THEN
    DUP _DNTQ.PACKET
    SWAP _DNTQ.LENGTH @
    DNS-TXT-S-OK ;

: DNS-TXT-QUERY-ID@  ( query -- id status )
    DUP DNS-TXT-QUERY-VALID? 0= IF
        DROP 0 DNS-TXT-S-INVALID EXIT
    THEN
    _DNTQ.ID @ DNS-TXT-S-OK ;

: DNS-TXT-QUERY-WIPE  ( query -- status )
    DUP DNS-TXT-QUERY-VALID? 0= IF
        DROP DNS-TXT-S-INVALID EXIT
    THEN
    DNS-TXT-QUERY-SIZE 0 FILL
    DNS-TXT-S-OK ;

\ =====================================================================
\  Result initialization, validation, and public evidence
\ =====================================================================

: _DNT-RESULT-STORED-STATUS?  ( status -- flag )
    DUP DNS-TXT-S-OK = IF DROP -1 EXIT THEN
    DUP DNS-TXT-S-CAPACITY = IF DROP -1 EXIT THEN
    DUP DNS-TXT-S-EMPTY >=
    SWAP DNS-TXT-S-DUPLICATE <= AND ;

: _DNT-RESULT-EVIDENCE?  ( result bit -- flag )
    SWAP _DNTR.EVIDENCE @ AND 0<> ;

: _DNT-RESULT-QUESTION?  ( result -- flag )
    DNS-TXT-E-QUESTION _DNT-RESULT-EVIDENCE? ;

: _DNT-RESULT-TC?  ( result -- flag )
    _DNTR.FLAGS @ 0x0200 AND 0<> ;

: _DNT-RESULT-NO-MATCH?  ( result -- flag )
    DUP _DNTR.MATCHED-COUNT @ IF DROP 0 EXIT THEN
    DUP _DNTR.STRING-COUNT @ IF DROP 0 EXIT THEN
    _DNTR.TTL @ 0= ;

: _DNT-RESULT-ONE-MATCH?  ( result -- flag )
    DUP _DNTR.MATCHED-COUNT @ 1 <> IF DROP 0 EXIT THEN
    _DNTR.STRING-COUNT @ 0> ;

: _DNT-RESULT-MULTIPLE-MATCHES?  ( result -- flag )
    DUP _DNTR.MATCHED-COUNT @
    DUP 1 <= IF 2DROP 0 EXIT THEN
    SWAP _DNTR.STRING-COUNT @ <= ;

: _DNT-RESULT-RESPONSE-FLAGS?  ( result -- flag )
    _DNTR.FLAGS @
    DUP 0x8000 AND 0= IF DROP 0 EXIT THEN
    DUP 0x7800 AND IF DROP 0 EXIT THEN
    0x0040 AND 0= ;

: _DNT-RESULT-RCODE-FLAGS?  ( result -- flag )
    DUP _DNTR.FLAGS @ 0x0F AND
    SWAP _DNTR.RCODE @ = ;

: _DNT-RESULT-EMPTY-STATE?  ( result -- flag )
    DUP _DNTR.LENGTH @ IF DROP 0 EXIT THEN
    DUP _DNTR.RCODE @ IF DROP 0 EXIT THEN
    DUP _DNTR.FLAGS @ IF DROP 0 EXIT THEN
    DUP _DNTR.EVIDENCE @ IF DROP 0 EXIT THEN
    DUP _DNTR.ANSWER-COUNT @ IF DROP 0 EXIT THEN
    _DNT-RESULT-NO-MATCH? ;

: _DNT-RESULT-DIRECT-STATE?  ( result -- flag )
    DUP _DNT-RESULT-QUESTION? 0= IF DROP 0 EXIT THEN
    DUP _DNTR.RCODE @ IF DROP 0 EXIT THEN
    DUP _DNT-RESULT-TC? IF DROP 0 EXIT THEN
    _DNT-RESULT-ONE-MATCH? ;

: _DNT-RESULT-NODATA-STATE?  ( result -- flag )
    DUP _DNT-RESULT-QUESTION? 0= IF DROP 0 EXIT THEN
    DUP _DNTR.RCODE @ IF DROP 0 EXIT THEN
    DUP _DNT-RESULT-TC? IF DROP 0 EXIT THEN
    _DNT-RESULT-NO-MATCH? ;

: _DNT-RESULT-DUPLICATE-STATE?  ( result -- flag )
    DUP _DNT-RESULT-QUESTION? 0= IF DROP 0 EXIT THEN
    DUP _DNTR.RCODE @ IF DROP 0 EXIT THEN
    DUP _DNT-RESULT-TC? IF DROP 0 EXIT THEN
    _DNT-RESULT-MULTIPLE-MATCHES? ;

: _DNT-RESULT-TRUNCATED-STATE?  ( result -- flag )
    DUP _DNT-RESULT-QUESTION? 0= IF DROP 0 EXIT THEN
    DUP _DNT-RESULT-TC? 0= IF DROP 0 EXIT THEN
    _DNT-RESULT-NO-MATCH? ;

: _DNT-RESULT-RCODE-STATE?  ( result -- flag )
    DUP _DNT-RESULT-QUESTION? 0= IF DROP 0 EXIT THEN
    DUP _DNTR.RCODE @ 0= IF DROP 0 EXIT THEN
    DUP _DNT-RESULT-TC? IF DROP 0 EXIT THEN
    _DNT-RESULT-NO-MATCH? ;

: _DNT-RESULT-MISMATCH-STATE?  ( result -- flag )
    DUP _DNT-RESULT-QUESTION? IF DROP 0 EXIT THEN
    _DNT-RESULT-NO-MATCH? ;

: _DNT-RESULT-MALFORMED-STATE?  ( result -- flag )
    DUP _DNT-RESULT-QUESTION? IF
        DUP _DNTR.RCODE @ IF DROP 0 EXIT THEN
        DUP _DNT-RESULT-TC? IF DROP 0 EXIT THEN
    THEN
    DROP -1 ;

\ Validate only completed externally observable lifecycle states.  Admission
\ failures never overwrite a live result.  MALFORMED deliberately retains the
\ widest partial-evidence shape because parsing may stop at any wire boundary.
: _DNT-RESULT-LIFECYCLE?  ( result -- flag )
    DUP _DNTR.STATUS @ _DNT-RESULT-STORED-STATUS? 0= IF
        DROP 0 EXIT
    THEN
    DUP _DNTR.STATUS @ DNS-TXT-S-OK <> IF
        DUP _DNTR.LENGTH @ IF DROP 0 EXIT THEN
    THEN

    DUP _DNTR.RCODE @ 0<>
    OVER DNS-TXT-E-RCODE _DNT-RESULT-EVIDENCE? <> IF
        DROP 0 EXIT
    THEN
    DUP _DNTR.STATUS @ DNS-TXT-S-OK =
    OVER DNS-TXT-E-VALUE _DNT-RESULT-EVIDENCE? <> IF
        DROP 0 EXIT
    THEN
    DUP _DNTR.STATUS @ DNS-TXT-S-TRUNCATED =
    OVER DNS-TXT-E-TRUNCATED _DNT-RESULT-EVIDENCE? <> IF
        DROP 0 EXIT
    THEN

    DUP DNS-TXT-E-RESPONSE _DNT-RESULT-EVIDENCE? IF
        DUP DNS-TXT-E-ID _DNT-RESULT-EVIDENCE? 0= IF
            DROP 0 EXIT
        THEN
        DUP _DNT-RESULT-RESPONSE-FLAGS? 0= IF
            DROP 0 EXIT
        THEN
    THEN
    DUP _DNT-RESULT-QUESTION? IF
        DUP DNS-TXT-E-RESPONSE _DNT-RESULT-EVIDENCE? 0= IF
            DROP 0 EXIT
        THEN
        DUP _DNT-RESULT-RCODE-FLAGS? 0= IF
            DROP 0 EXIT
        THEN
    THEN
    DUP DNS-TXT-E-RCODE _DNT-RESULT-EVIDENCE? IF
        DUP _DNT-RESULT-QUESTION? 0= IF
            DROP 0 EXIT
        THEN
    THEN
    DUP _DNTR.MATCHED-COUNT @ IF
        DUP _DNT-RESULT-QUESTION? 0= IF DROP 0 EXIT THEN
    THEN
    DUP _DNTR.STRING-COUNT @ IF
        DUP _DNTR.MATCHED-COUNT @ 0= IF DROP 0 EXIT THEN
    THEN
    DUP _DNTR.MATCHED-COUNT @ 0= IF
        DUP _DNT-RESULT-NO-MATCH? 0= IF DROP 0 EXIT THEN
    THEN
    DUP _DNTR.RCODE @ IF
        DUP _DNT-RESULT-NO-MATCH? 0= IF DROP 0 EXIT THEN
    THEN

    DUP _DNTR.STATUS @ DNS-TXT-S-EMPTY = IF
        _DNT-RESULT-EMPTY-STATE? EXIT
    THEN
    DUP _DNTR.STATUS @ DNS-TXT-S-OK = IF
        _DNT-RESULT-DIRECT-STATE? EXIT
    THEN
    DUP _DNTR.STATUS @ DNS-TXT-S-CAPACITY = IF
        _DNT-RESULT-DIRECT-STATE? EXIT
    THEN
    DUP _DNTR.STATUS @ DNS-TXT-S-MALFORMED = IF
        _DNT-RESULT-MALFORMED-STATE? EXIT
    THEN
    DUP _DNTR.STATUS @ DNS-TXT-S-MISMATCH = IF
        _DNT-RESULT-MISMATCH-STATE? EXIT
    THEN
    DUP _DNTR.STATUS @ DNS-TXT-S-TRUNCATED = IF
        _DNT-RESULT-TRUNCATED-STATE? EXIT
    THEN
    DUP _DNTR.STATUS @ DNS-TXT-S-RCODE = IF
        _DNT-RESULT-RCODE-STATE? EXIT
    THEN
    DUP _DNTR.STATUS @ DNS-TXT-S-NODATA = IF
        _DNT-RESULT-NODATA-STATE? EXIT
    THEN
    _DNT-RESULT-DUPLICATE-STATE? ;

: DNS-TXT-RESULT-VALID?  ( result -- flag )
    DUP _DNT-RESULT-STATUS ?DUP IF
        2DROP 0 EXIT
    THEN
    DUP _DNTR.MAGIC @ _DNTR-MAGIC-VALUE <> IF
        DROP 0 EXIT
    THEN
    DUP _DNTR.CAPACITY @
    DUP 1 < OVER DNS-TXT-VALUE-MAX > OR IF
        2DROP 0 EXIT
    THEN
    DROP
    DUP _DNTR.BUFFER @
    OVER _DNTR.CAPACITY @
    _DNT-SPAN-STATUS DNS-TXT-S-OK <> IF
        DROP 0 EXIT
    THEN
    DUP _DNTR.BUFFER @
    OVER _DNTR.CAPACITY @
    2 PICK DNS-TXT-RESULT-SIZE
    MSPAN-OVERLAP? IF
        DROP 0 EXIT
    THEN
    DUP _DNTR.LENGTH @
    DUP 0< IF 2DROP 0 EXIT THEN
    OVER _DNTR.CAPACITY @ U> IF DROP 0 EXIT THEN
    DUP _DNTR.STATUS @ DNS-TXT-STATUS-VALID? 0= IF
        DROP 0 EXIT
    THEN
    DUP _DNTR.RCODE @ DUP 0< SWAP 15 > OR IF
        DROP 0 EXIT
    THEN
    DUP _DNTR.FLAGS @ DUP 0< SWAP 65535 > OR IF
        DROP 0 EXIT
    THEN
    DUP _DNTR.EVIDENCE @ DUP 0< SWAP 63 > OR IF
        DROP 0 EXIT
    THEN
    DUP _DNTR.ANSWER-COUNT @ DUP 0< SWAP 65535 > OR IF
        DROP 0 EXIT
    THEN
    DUP _DNTR.MATCHED-COUNT @ DUP 0< SWAP 65535 > OR IF
        DROP 0 EXIT
    THEN
    DUP _DNTR.MATCHED-COUNT @
    OVER _DNTR.ANSWER-COUNT @ > IF
        DROP 0 EXIT
    THEN
    DUP _DNTR.STRING-COUNT @
    DUP 0< SWAP 65535 > OR IF
        DROP 0 EXIT
    THEN
    DUP _DNTR.TTL @
    DUP 0< SWAP 0x7FFFFFFF > OR IF
        DROP 0 EXIT
    THEN
    _DNT-RESULT-LIFECYCLE? ;

: DNS-TXT-RESULT-INIT  ( value-a value-cap result -- status )
    DUP _DNT-RESULT-STATUS ?DUP IF
        _DNT-RETURN3 EXIT
    THEN
    OVER 1 < 2 PICK DNS-TXT-VALUE-MAX > OR IF
        DNS-TXT-S-CAPACITY _DNT-RETURN3 EXIT
    THEN
    2 PICK 2 PICK _DNT-SPAN-STATUS ?DUP IF
        _DNT-RETURN3 EXIT
    THEN
    2 PICK 2 PICK
    2 PICK DNS-TXT-RESULT-SIZE
    MSPAN-OVERLAP? IF
        DNS-TXT-S-ALIAS _DNT-RETURN3 EXIT
    THEN

    \ Rebinding a valid live result clears its complete previous arena.
    DUP _DNTR.MAGIC @ _DNTR-MAGIC-VALUE = IF
        DUP DNS-TXT-RESULT-VALID? 0= IF
            DNS-TXT-S-INVALID _DNT-RETURN3 EXIT
        THEN
        DUP _DNTR.BUFFER @ OVER _DNTR.CAPACITY @ 0 FILL
    THEN

    >R
    2DUP 0 FILL
    R@ DNS-TXT-RESULT-SIZE 0 FILL
    OVER R@ _DNTR.BUFFER !
    DUP R@ _DNTR.CAPACITY !
    DNS-TXT-S-EMPTY R@ _DNTR.STATUS !
    _DNTR-MAGIC-VALUE R@ _DNTR.MAGIC !
    2DROP
    R> DROP
    DNS-TXT-S-OK ;

: DNS-TXT-STATUS@  ( result -- status )
    DUP DNS-TXT-RESULT-VALID? 0= IF
        DROP DNS-TXT-S-INVALID EXIT
    THEN
    _DNTR.STATUS @ ;

: DNS-TXT-VALUE$  ( result -- value-a value-u )
    DUP DNS-TXT-RESULT-VALID? 0= IF
        DROP 0 0 EXIT
    THEN
    DUP _DNTR.STATUS @ DNS-TXT-S-OK <> IF
        DROP 0 0 EXIT
    THEN
    DUP _DNTR.BUFFER @
    SWAP _DNTR.LENGTH @ ;

: DNS-TXT-RCODE@  ( result -- rcode )
    DUP DNS-TXT-RESULT-VALID? IF
        _DNTR.RCODE @
    ELSE
        DROP 0
    THEN ;

: DNS-TXT-FLAGS@  ( result -- header-flags )
    DUP DNS-TXT-RESULT-VALID? IF
        _DNTR.FLAGS @
    ELSE
        DROP 0
    THEN ;

: DNS-TXT-EVIDENCE@  ( result -- evidence )
    DUP DNS-TXT-RESULT-VALID? IF
        _DNTR.EVIDENCE @
    ELSE
        DROP 0
    THEN ;

: DNS-TXT-ANSWER-COUNT@  ( result -- count )
    DUP DNS-TXT-RESULT-VALID? IF
        _DNTR.ANSWER-COUNT @
    ELSE
        DROP 0
    THEN ;

: DNS-TXT-MATCHED-COUNT@  ( result -- count )
    DUP DNS-TXT-RESULT-VALID? IF
        _DNTR.MATCHED-COUNT @
    ELSE
        DROP 0
    THEN ;

: DNS-TXT-STRING-COUNT@  ( result -- count )
    DUP DNS-TXT-RESULT-VALID? IF
        _DNTR.STRING-COUNT @
    ELSE
        DROP 0
    THEN ;

: DNS-TXT-TTL@  ( result -- ttl )
    DUP DNS-TXT-RESULT-VALID? IF
        _DNTR.TTL @
    ELSE
        DROP 0
    THEN ;

: _DNT-RESULT-RESET  ( result -- )
    DUP _DNTR.BUFFER @
    OVER _DNTR.CAPACITY @
    2DUP 0 FILL
    ROT >R
    R@ DNS-TXT-RESULT-SIZE 0 FILL
    OVER R@ _DNTR.BUFFER !
    DUP R@ _DNTR.CAPACITY !
    DNS-TXT-S-EMPTY R@ _DNTR.STATUS !
    _DNTR-MAGIC-VALUE R@ _DNTR.MAGIC !
    2DROP
    R> DROP ;

: _DNT-RESULT-FAIL  ( status result -- status )
    >R
    DUP R@ _DNTR.STATUS !
    0 R@ _DNTR.LENGTH !
    R@ _DNTR.BUFFER @
    R@ _DNTR.CAPACITY @ 0 FILL
    R> DROP ;

: DNS-TXT-RESULT-WIPE  ( result -- status )
    DUP DNS-TXT-RESULT-VALID? 0= IF
        DROP DNS-TXT-S-INVALID EXIT
    THEN
    DUP _DNTR.BUFFER @ OVER _DNTR.CAPACITY @ 0 FILL
    DNS-TXT-RESULT-SIZE 0 FILL
    DNS-TXT-S-OK ;

\ =====================================================================
\  Safe DNS name decompression
\ =====================================================================

: _DNT-NAME-DECODE  ( offset result -- status )
    >R
    DUP 0< IF
        DROP R> DROP DNS-TXT-S-MALFORMED EXIT
    THEN
    DUP R@ _DNTR.MESSAGE-U @ U< 0= IF
        DROP R> DROP DNS-TXT-S-MALFORMED EXIT
    THEN
    R@ _DNTR.NAME-POS !
    0 R@ _DNTR.NAME-NEXT !
    0 R@ _DNTR.NAME-U !
    0 R@ _DNTR.NAME-HOPS !
    0 R@ _DNTR.NAME-JUMPED !

    BEGIN
        R@ _DNTR.NAME-POS @
        R@ _DNTR.MESSAGE-U @ U< 0= IF
            R> DROP DNS-TXT-S-MALFORMED EXIT
        THEN
        R@ _DNTR.MESSAGE @
        R@ _DNTR.NAME-POS @ + C@

        DUP 0xC0 AND 0xC0 = IF
            DROP
            R@ _DNTR.NAME-POS @ 1+
            R@ _DNTR.MESSAGE-U @ U< 0= IF
                R> DROP DNS-TXT-S-MALFORMED EXIT
            THEN
            R@ _DNTR.NAME-JUMPED @ 0= IF
                R@ _DNTR.NAME-POS @ 2 +
                R@ _DNTR.NAME-NEXT !
                -1 R@ _DNTR.NAME-JUMPED !
            THEN
            1 R@ _DNTR.NAME-HOPS +!
            R@ _DNTR.NAME-HOPS @
            DNS-TXT-COMPRESSION-HOPS-MAX > IF
                R> DROP DNS-TXT-S-MALFORMED EXIT
            THEN
            R@ _DNTR.MESSAGE @
            R@ _DNTR.NAME-POS @ +
            DUP C@ 0x3F AND 8 LSHIFT
            SWAP 1+ C@ OR
            DUP R@ _DNTR.MESSAGE-U @ U< 0= IF
                DROP R> DROP DNS-TXT-S-MALFORMED EXIT
            THEN
            DUP R@ _DNTR.NAME-POS @ U< 0= IF
                DROP R> DROP DNS-TXT-S-MALFORMED EXIT
            THEN
            R@ _DNTR.NAME-POS !
        ELSE
            DUP 0xC0 AND IF
                DROP R> DROP DNS-TXT-S-MALFORMED EXIT
            THEN
            DUP 0= IF
                DROP
                R@ _DNTR.NAME-U @
                DNS-TXT-WIRE-NAME-MAX >= IF
                    R> DROP DNS-TXT-S-MALFORMED EXIT
                THEN
                0 R@ _DNTR.NAME
                R@ _DNTR.NAME-U @ + C!
                1 R@ _DNTR.NAME-U +!
                R@ _DNTR.NAME-JUMPED @ 0= IF
                    R@ _DNTR.NAME-POS @ 1+
                    R@ _DNTR.NAME-NEXT !
                THEN
                R> DROP DNS-TXT-S-OK EXIT
            THEN

            DUP DNS-TXT-LABEL-MAX > IF
                DROP R> DROP DNS-TXT-S-MALFORMED EXIT
            THEN
            R@ _DNTR.LABEL-U !
            R@ _DNTR.NAME-POS @ 1+
            R@ _DNTR.LABEL-U @ +
            R@ _DNTR.MESSAGE-U @ U> IF
                R> DROP DNS-TXT-S-MALFORMED EXIT
            THEN
            R@ _DNTR.NAME-U @ 1+
            R@ _DNTR.LABEL-U @ +
            DNS-TXT-WIRE-NAME-MAX > IF
                R> DROP DNS-TXT-S-MALFORMED EXIT
            THEN

            R@ _DNTR.LABEL-U @
            R@ _DNTR.NAME
            R@ _DNTR.NAME-U @ + C!
            R@ _DNTR.MESSAGE @
            R@ _DNTR.NAME-POS @ + 1+
            R@ _DNTR.NAME
            R@ _DNTR.NAME-U @ + 1+
            R@ _DNTR.LABEL-U @ CMOVE
            R@ _DNTR.LABEL-U @ 1+
            R@ _DNTR.NAME-U +!
            R@ _DNTR.LABEL-U @ 1+
            R@ _DNTR.NAME-POS +!
        THEN
    AGAIN ;

: _DNT-ASCII-FOLD  ( byte -- byte' )
    DUP [CHAR] A [CHAR] Z 1+ WITHIN IF
        32 +
    THEN ;

: _DNT-NAME=QUERY?  ( result -- flag )
    DUP _DNTR.NAME-U @
    OVER _DNTR.QUERY @ _DNTQ.NAME-U @ <> IF
        DROP 0 EXIT
    THEN
    DUP _DNTR.NAME-U @ 0 ?DO
        DUP _DNTR.NAME I + C@ _DNT-ASCII-FOLD
        OVER _DNTR.QUERY @ _DNTQ.PACKET 12 + I + C@
        _DNT-ASCII-FOLD <> IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

\ =====================================================================
\  Question, RR, and TXT parsing
\ =====================================================================

: _DNT-PARSE-QUESTION  ( result -- status )
    >R
    12 R@ _DNT-NAME-DECODE ?DUP IF
        R> DROP EXIT
    THEN
    R@ _DNT-NAME=QUERY? 0= IF
        R> DROP DNS-TXT-S-MISMATCH EXIT
    THEN
    R@ _DNTR.NAME-NEXT @ 4 +
    R@ _DNTR.MESSAGE-U @ U> IF
        R> DROP DNS-TXT-S-MALFORMED EXIT
    THEN
    R@ _DNTR.MESSAGE @
    R@ _DNTR.NAME-NEXT @ +
    DUP _DNT-U16@ _DNT-TYPE-TXT <> IF
        DROP R> DROP DNS-TXT-S-MISMATCH EXIT
    THEN
    2 + _DNT-U16@ _DNT-CLASS-IN <> IF
        R> DROP DNS-TXT-S-MISMATCH EXIT
    THEN
    R@ _DNTR.NAME-NEXT @ 4 +
    R@ _DNTR.CURSOR !
    DNS-TXT-E-QUESTION R@ _DNT-EVIDENCE+
    R> DROP DNS-TXT-S-OK ;

: _DNT-PARSE-RR-HEADER  ( result -- status )
    >R
    R@ _DNTR.CURSOR @
    R@ _DNT-NAME-DECODE ?DUP IF
        R> DROP EXIT
    THEN
    R@ _DNT-NAME=QUERY?
    R@ _DNTR.OWNER-MATCH !
    R@ _DNTR.NAME-NEXT @
    R@ _DNTR.CURSOR !
    R@ _DNTR.CURSOR @ 10 +
    R@ _DNTR.MESSAGE-U @ U> IF
        R> DROP DNS-TXT-S-MALFORMED EXIT
    THEN

    R@ _DNTR.MESSAGE @ R@ _DNTR.CURSOR @ +
    DUP _DNT-U16@ R@ _DNTR.RR-TYPE !
    DUP 2 + _DNT-U16@ R@ _DNTR.RR-CLASS !
    DUP 4 + _DNT-U32@
    DUP 0x7FFFFFFF U> IF
        2DROP R> DROP DNS-TXT-S-MALFORMED EXIT
    THEN
    R@ _DNTR.RR-TTL !
    8 + _DNT-U16@ R@ _DNTR.RR-RDLENGTH !

    R@ _DNTR.CURSOR @ 10 +
    R@ _DNTR.RR-RDLENGTH @ +
    DUP R@ _DNTR.MESSAGE-U @ U> IF
        DROP R> DROP DNS-TXT-S-MALFORMED EXIT
    THEN
    DUP R@ _DNTR.RDATA-END !
    R@ _DNTR.CURSOR !
    R@ _DNTR.CURSOR @
    R@ _DNTR.RR-RDLENGTH @ -
    R@ _DNTR.RDATA-POS !
    R> DROP DNS-TXT-S-OK ;

: _DNT-PARSE-TXT-RDATA  ( copy? result -- status )
    >R
    R@ _DNTR.COPY !
    R@ _DNTR.RDATA-POS @
    R@ _DNTR.RDATA-END @ = IF
        R> DROP DNS-TXT-S-MALFORMED EXIT
    THEN
    BEGIN
        R@ _DNTR.RDATA-POS @
        R@ _DNTR.RDATA-END @ U<
    WHILE
        R@ _DNTR.MESSAGE @
        R@ _DNTR.RDATA-POS @ + C@
        R@ _DNTR.LABEL-U !
        R@ _DNTR.RDATA-POS @ 1+
        R@ _DNTR.LABEL-U @ +
        R@ _DNTR.RDATA-END @ U> IF
            R> DROP DNS-TXT-S-MALFORMED EXIT
        THEN
        1 R@ _DNTR.STRING-COUNT +!

        R@ _DNTR.COPY @ IF
            R@ _DNTR.LENGTH @
            R@ _DNTR.LABEL-U @ +
            R@ _DNTR.CAPACITY @ U> IF
                R> DROP DNS-TXT-S-CAPACITY EXIT
            THEN
            R@ _DNTR.MESSAGE @
            R@ _DNTR.RDATA-POS @ + 1+
            R@ _DNTR.BUFFER @
            R@ _DNTR.LENGTH @ +
            R@ _DNTR.LABEL-U @ CMOVE
            R@ _DNTR.LABEL-U @
            R@ _DNTR.LENGTH +!
        THEN
        R@ _DNTR.LABEL-U @ 1+
        R@ _DNTR.RDATA-POS +!
    REPEAT
    R> DROP DNS-TXT-S-OK ;

: _DNT-PARSE-RR  ( result -- status )
    >R
    R@ _DNT-PARSE-RR-HEADER ?DUP IF
        R> DROP EXIT
    THEN
    R@ _DNTR.INSPECT @ 0= IF
        R> DROP DNS-TXT-S-OK EXIT
    THEN
    R@ _DNTR.OWNER-MATCH @ 0= IF
        R> DROP DNS-TXT-S-OK EXIT
    THEN
    R@ _DNTR.RR-TYPE @ _DNT-TYPE-TXT <> IF
        R> DROP DNS-TXT-S-OK EXIT
    THEN
    R@ _DNTR.RR-CLASS @ _DNT-CLASS-IN <> IF
        R> DROP DNS-TXT-S-OK EXIT
    THEN

    1 R@ _DNTR.MATCHED-COUNT +!
    R@ _DNTR.MATCHED-COUNT @ 1 = IF
        R@ _DNTR.RR-TTL @ R@ _DNTR.TTL !
        -1
    ELSE
        0
    THEN
    R@ _DNT-PARSE-TXT-RDATA
    R> DROP ;

: _DNT-PARSE-SECTION  ( count inspect? result -- status )
    >R
    R@ _DNTR.INSPECT !
    R@ _DNTR.SECTION-LEFT !
    BEGIN
        R@ _DNTR.SECTION-LEFT @
    WHILE
        R@ _DNT-PARSE-RR ?DUP IF
            R> DROP EXIT
        THEN
        -1 R@ _DNTR.SECTION-LEFT +!
    REPEAT
    R> DROP DNS-TXT-S-OK ;

: _DNT-PARSE-BODY  ( result -- status )
    >R
    R@ _DNTR.MESSAGE @ _DNT-U16@
    R@ _DNTR.QUERY @ _DNTQ.ID @ <> IF
        R> DROP DNS-TXT-S-MISMATCH EXIT
    THEN
    DNS-TXT-E-ID R@ _DNT-EVIDENCE+

    R@ _DNTR.MESSAGE @ 2 + _DNT-U16@
    DUP R@ _DNTR.FLAGS !
    DUP 0x8000 AND 0= IF
        DROP R> DROP DNS-TXT-S-MISMATCH EXIT
    THEN
    DUP 0x7800 AND IF
        DROP R> DROP DNS-TXT-S-MISMATCH EXIT
    THEN
    DUP 0x0040 AND IF
        DROP R> DROP DNS-TXT-S-MALFORMED EXIT
    THEN
    DNS-TXT-E-RESPONSE R@ _DNT-EVIDENCE+

    R@ _DNTR.MESSAGE @ 4 + _DNT-U16@ 1 <> IF
        DROP R> DROP DNS-TXT-S-MISMATCH EXIT
    THEN
    R@ _DNTR.MESSAGE @ 6 + _DNT-U16@
    R@ _DNTR.ANSWER-COUNT !
    DROP

    R@ _DNT-PARSE-QUESTION ?DUP IF
        R> DROP EXIT
    THEN
    R@ _DNTR.FLAGS @ 0x0F AND
    DUP R@ _DNTR.RCODE !
    IF DNS-TXT-E-RCODE R@ _DNT-EVIDENCE+ THEN
    R@ _DNTR.FLAGS @ 0x0200 AND IF
        DNS-TXT-E-TRUNCATED R@ _DNT-EVIDENCE+
        R> DROP DNS-TXT-S-TRUNCATED EXIT
    THEN
    R@ _DNTR.RCODE @ IF
        R> DROP DNS-TXT-S-RCODE EXIT
    THEN

    R@ _DNTR.ANSWER-COUNT @ -1
    R@ _DNT-PARSE-SECTION ?DUP IF
        R> DROP EXIT
    THEN
    R@ _DNTR.MESSAGE @ 8 + _DNT-U16@ 0
    R@ _DNT-PARSE-SECTION ?DUP IF
        R> DROP EXIT
    THEN
    R@ _DNTR.MESSAGE @ 10 + _DNT-U16@ 0
    R@ _DNT-PARSE-SECTION ?DUP IF
        R> DROP EXIT
    THEN
    R@ _DNTR.CURSOR @
    R@ _DNTR.MESSAGE-U @ <> IF
        R> DROP DNS-TXT-S-MALFORMED EXIT
    THEN

    R@ _DNTR.MATCHED-COUNT @ DUP 0= IF
        DROP R> DROP DNS-TXT-S-NODATA EXIT
    THEN
    1 <> IF
        R> DROP DNS-TXT-S-DUPLICATE EXIT
    THEN
    DNS-TXT-E-VALUE R@ _DNT-EVIDENCE+
    R> DROP DNS-TXT-S-OK ;

\ =====================================================================
\  Public response parse
\ =====================================================================

: _DNT-PARSE-ALIASES?  ( response-a response-u query result -- flag )
    >R
    2 PICK 2 PICK
    R@ DNS-TXT-RESULT-SIZE MSPAN-OVERLAP? IF
        _DNT-DROP3 R> DROP -1 EXIT
    THEN
    2 PICK 2 PICK
    R@ _DNTR.BUFFER @
    R@ _DNTR.CAPACITY @ MSPAN-OVERLAP? IF
        _DNT-DROP3 R> DROP -1 EXIT
    THEN
    DUP DNS-TXT-QUERY-SIZE
    R@ DNS-TXT-RESULT-SIZE MSPAN-OVERLAP? IF
        _DNT-DROP3 R> DROP -1 EXIT
    THEN
    DUP DNS-TXT-QUERY-SIZE
    R@ _DNTR.BUFFER @
    R@ _DNTR.CAPACITY @ MSPAN-OVERLAP? IF
        _DNT-DROP3 R> DROP -1 EXIT
    THEN
    _DNT-DROP3 R> DROP 0 ;

: DNS-TXT-PARSE  ( response-a response-u query result -- status )
    DUP DNS-TXT-RESULT-VALID? 0= IF
        DNS-TXT-S-INVALID _DNT-RETURN4 EXIT
    THEN
    OVER DNS-TXT-QUERY-VALID? 0= IF
        DNS-TXT-S-INVALID _DNT-RETURN4 EXIT
    THEN
    2 PICK 0< IF
        DNS-TXT-S-INVALID _DNT-RETURN4 EXIT
    THEN
    2 PICK DNS-TXT-MESSAGE-MAX U> IF
        DNS-TXT-S-CAPACITY _DNT-RETURN4 EXIT
    THEN
    3 PICK 3 PICK _DNT-SPAN-STATUS ?DUP IF
        _DNT-RETURN4 EXIT
    THEN
    3 PICK 3 PICK 3 PICK 3 PICK
    _DNT-PARSE-ALIASES? IF
        DNS-TXT-S-ALIAS _DNT-RETURN4 EXIT
    THEN

    DUP _DNT-RESULT-RESET
    >R
    DUP R@ _DNTR.QUERY !
    2 PICK R@ _DNTR.MESSAGE !
    OVER R@ _DNTR.MESSAGE-U !
    DROP 2DROP

    R@ _DNTR.MESSAGE-U @ 12 < IF
        DNS-TXT-S-MALFORMED R@ _DNT-RESULT-FAIL
        R> DROP EXIT
    THEN
    R@ _DNT-PARSE-BODY
    DUP IF
        R@ _DNT-RESULT-FAIL
        R> DROP EXIT
    THEN
    DUP R@ _DNTR.STATUS !
    R> DROP ;

\ =====================================================================
\  Compile-time geometry assertions
\ =====================================================================

: _DNT-GEOMETRY-ABORT  ( -- )
    ." DNS TXT geometry mismatch" CR ABORT ;

1 CELLS 8 <> [IF]
    _DNT-GEOMETRY-ABORT
[THEN]

DNS-TXT-QUERY-SIZE 304 <> [IF]
    _DNT-GEOMETRY-ABORT
[THEN]

DNS-TXT-RESULT-SIZE 512 <> [IF]
    _DNT-GEOMETRY-ABORT
[THEN]
