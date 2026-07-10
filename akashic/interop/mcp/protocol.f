\ =====================================================================
\  protocol.f - Native MCP 2025-11-25 contracts and descriptors
\ =====================================================================
\  This is the protocol boundary, not Akashic's internal application bus.
\  It defines lifecycle state, catalog descriptors, calls, resource reads,
\  and validation shared by native MCP clients, servers, and adapters.
\ =====================================================================

PROVIDED akashic-mcp-protocol-core

REQUIRE ../jsonrpc/message.f
REQUIRE ../codecs/json-schema.f

: MCP-PROTOCOL-VERSION  ( -- addr len ) S" 2025-11-25" ;

0 CONSTANT MCP-STATE-NEW
1 CONSTANT MCP-STATE-INITIALIZING
2 CONSTANT MCP-STATE-READY
3 CONSTANT MCP-STATE-CLOSED
4 CONSTANT MCP-STATE-FAILED

0 CONSTANT MCP-S-OK
1 CONSTANT MCP-S-INVALID
2 CONSTANT MCP-S-NOT-FOUND
3 CONSTANT MCP-S-DENIED
4 CONSTANT MCP-S-APPROVAL
5 CONSTANT MCP-S-BUSY
6 CONSTANT MCP-S-TIMEOUT
7 CONSTANT MCP-S-CANCELLED
8 CONSTANT MCP-S-FAILED
9 CONSTANT MCP-S-CAPACITY
10 CONSTANT MCP-S-TRANSPORT
11 CONSTANT MCP-S-PROTOCOL

1 CONSTANT MCP-CAP-TOOLS
2 CONSTANT MCP-CAP-RESOURCES
4 CONSTANT MCP-CAP-RESOURCE-TEMPLATES

1 CONSTANT MCP-TOOL-F-READ-ONLY
2 CONSTANT MCP-TOOL-F-DESTRUCTIVE
4 CONSTANT MCP-TOOL-F-IDEMPOTENT
8 CONSTANT MCP-TOOL-F-OPEN-WORLD

128 CONSTANT MCP-MAX-NAME
512 CONSTANT MCP-MAX-URI
160 CONSTANT MCP-MAX-ERROR

\ Tool descriptor. Names and metadata are borrowed immutable spans; schemas
\ and callback context must outlive registration.
 0 CONSTANT _MTD-NAME-A
 8 CONSTANT _MTD-NAME-U
16 CONSTANT _MTD-TITLE-A
24 CONSTANT _MTD-TITLE-U
32 CONSTANT _MTD-DESC-A
40 CONSTANT _MTD-DESC-U
48 CONSTANT _MTD-IN-SCHEMA
56 CONSTANT _MTD-OUT-SCHEMA
64 CONSTANT _MTD-FLAGS
72 CONSTANT _MTD-EFFECTS
80 CONSTANT _MTD-CALL-XT          \ ( call context -- status )
88 CONSTANT _MTD-CONTEXT
96 CONSTANT _MTD-RESERVED
104 CONSTANT MCP-TOOL-DESC-SIZE

: MTOOL.NAME-A      ( tool -- a ) _MTD-NAME-A + ;
: MTOOL.NAME-U      ( tool -- a ) _MTD-NAME-U + ;
: MTOOL.TITLE-A     ( tool -- a ) _MTD-TITLE-A + ;
: MTOOL.TITLE-U     ( tool -- a ) _MTD-TITLE-U + ;
: MTOOL.DESC-A      ( tool -- a ) _MTD-DESC-A + ;
: MTOOL.DESC-U      ( tool -- a ) _MTD-DESC-U + ;
: MTOOL.IN-SCHEMA   ( tool -- a ) _MTD-IN-SCHEMA + ;
: MTOOL.OUT-SCHEMA  ( tool -- a ) _MTD-OUT-SCHEMA + ;
: MTOOL.FLAGS       ( tool -- a ) _MTD-FLAGS + ;
: MTOOL.EFFECTS     ( tool -- a ) _MTD-EFFECTS + ;
: MTOOL.CALL-XT     ( tool -- a ) _MTD-CALL-XT + ;
: MTOOL.CONTEXT     ( tool -- a ) _MTD-CONTEXT + ;

: MCP-TOOL-INIT  ( tool -- ) MCP-TOOL-DESC-SIZE 0 FILL ;
: MCP-TOOL-NAME  ( tool -- addr len )
    DUP MTOOL.NAME-A @ SWAP MTOOL.NAME-U @ ;

\ Tool call descriptor with an owned result and inline copied error text.
  0 CONSTANT _MCALL-ARGS-A
  8 CONSTANT _MCALL-ARGS-U
 16 CONSTANT _MCALL-RESULT
 56 CONSTANT _MCALL-ERROR-A
 64 CONSTANT _MCALL-ERROR-U
 72 CONSTANT _MCALL-FLAGS
 80 CONSTANT _MCALL-ERROR-BUF
240 CONSTANT _MCALL-RESERVED
248 CONSTANT MCP-CALL-SIZE

: MCALL.ARGS-A       ( call -- a ) _MCALL-ARGS-A + ;
: MCALL.ARGS-U       ( call -- a ) _MCALL-ARGS-U + ;
: MCALL.RESULT       ( call -- value ) _MCALL-RESULT + ;
: MCALL.ERROR-A      ( call -- a ) _MCALL-ERROR-A + ;
: MCALL.ERROR-U      ( call -- a ) _MCALL-ERROR-U + ;
: MCALL.FLAGS        ( call -- a ) _MCALL-FLAGS + ;
: MCALL.ERROR-BUF    ( call -- a ) _MCALL-ERROR-BUF + ;

: MCP-CALL-INIT  ( call -- )
    DUP MCP-CALL-SIZE 0 FILL
    DUP MCALL.RESULT CV-INIT
    DUP MCALL.ERROR-BUF OVER MCALL.ERROR-A !
    0 SWAP MCALL.ERROR-U ! ;

: MCP-CALL-FREE  ( call -- )
    MCALL.RESULT CV-FREE ;

VARIABLE _MCERR-A
VARIABLE _MCERR-U
VARIABLE _MCERR-C
VARIABLE _MCERR-N

: MCP-CALL-ERROR!  ( addr len call -- )
    _MCERR-C ! _MCERR-U ! _MCERR-A !
    _MCERR-U @ MCP-MAX-ERROR MIN DUP _MCERR-N !
    _MCERR-A @ _MCERR-C @ MCALL.ERROR-BUF _MCERR-N @ CMOVE
    _MCERR-C @ MCALL.ERROR-BUF _MCERR-C @ MCALL.ERROR-A !
    _MCERR-N @ _MCERR-C @ MCALL.ERROR-U ! ;

\ Resource descriptor and read result. A read callback returns a CV value;
\ the server owns conversion to MCP text content.
 0 CONSTANT _MRD-URI-A
 8 CONSTANT _MRD-URI-U
16 CONSTANT _MRD-NAME-A
24 CONSTANT _MRD-NAME-U
32 CONSTANT _MRD-TITLE-A
40 CONSTANT _MRD-TITLE-U
48 CONSTANT _MRD-DESC-A
56 CONSTANT _MRD-DESC-U
64 CONSTANT _MRD-MIME-A
72 CONSTANT _MRD-MIME-U
80 CONSTANT _MRD-READ-XT          \ ( read context -- status )
88 CONSTANT _MRD-CONTEXT
96 CONSTANT _MRD-FLAGS
104 CONSTANT MCP-RESOURCE-DESC-SIZE

: MRES.URI-A       ( resource -- a ) _MRD-URI-A + ;
: MRES.URI-U       ( resource -- a ) _MRD-URI-U + ;
: MRES.NAME-A      ( resource -- a ) _MRD-NAME-A + ;
: MRES.NAME-U      ( resource -- a ) _MRD-NAME-U + ;
: MRES.TITLE-A     ( resource -- a ) _MRD-TITLE-A + ;
: MRES.TITLE-U     ( resource -- a ) _MRD-TITLE-U + ;
: MRES.DESC-A      ( resource -- a ) _MRD-DESC-A + ;
: MRES.DESC-U      ( resource -- a ) _MRD-DESC-U + ;
: MRES.MIME-A      ( resource -- a ) _MRD-MIME-A + ;
: MRES.MIME-U      ( resource -- a ) _MRD-MIME-U + ;
: MRES.READ-XT     ( resource -- a ) _MRD-READ-XT + ;
: MRES.CONTEXT     ( resource -- a ) _MRD-CONTEXT + ;
: MRES.FLAGS       ( resource -- a ) _MRD-FLAGS + ;

: MCP-RESOURCE-INIT  ( resource -- ) MCP-RESOURCE-DESC-SIZE 0 FILL ;
: MCP-RESOURCE-URI  ( resource -- addr len )
    DUP MRES.URI-A @ SWAP MRES.URI-U @ ;

  0 CONSTANT _MREAD-URI-A
  8 CONSTANT _MREAD-URI-U
 16 CONSTANT _MREAD-CONTENT
 56 CONSTANT _MREAD-MIME-A
 64 CONSTANT _MREAD-MIME-U
 72 CONSTANT _MREAD-ERROR-A
 80 CONSTANT _MREAD-ERROR-U
 88 CONSTANT _MREAD-ERROR-BUF
248 CONSTANT _MREAD-RESERVED
256 CONSTANT MCP-READ-SIZE

: MREAD.URI-A       ( read -- a ) _MREAD-URI-A + ;
: MREAD.URI-U       ( read -- a ) _MREAD-URI-U + ;
: MREAD.CONTENT     ( read -- value ) _MREAD-CONTENT + ;
: MREAD.MIME-A      ( read -- a ) _MREAD-MIME-A + ;
: MREAD.MIME-U      ( read -- a ) _MREAD-MIME-U + ;
: MREAD.ERROR-A     ( read -- a ) _MREAD-ERROR-A + ;
: MREAD.ERROR-U     ( read -- a ) _MREAD-ERROR-U + ;
: MREAD.ERROR-BUF   ( read -- a ) _MREAD-ERROR-BUF + ;

: MCP-READ-INIT  ( read -- )
    DUP MCP-READ-SIZE 0 FILL
    DUP MREAD.CONTENT CV-INIT
    DUP MREAD.ERROR-BUF OVER MREAD.ERROR-A !
    0 SWAP MREAD.ERROR-U ! ;

: MCP-READ-FREE  ( read -- ) MREAD.CONTENT CV-FREE ;

VARIABLE _MRERR-A
VARIABLE _MRERR-U
VARIABLE _MRERR-R
VARIABLE _MRERR-N

: MCP-READ-ERROR!  ( addr len read -- )
    _MRERR-R ! _MRERR-U ! _MRERR-A !
    _MRERR-U @ MCP-MAX-ERROR MIN DUP _MRERR-N !
    _MRERR-A @ _MRERR-R @ MREAD.ERROR-BUF _MRERR-N @ CMOVE
    _MRERR-R @ MREAD.ERROR-BUF _MRERR-R @ MREAD.ERROR-A !
    _MRERR-N @ _MRERR-R @ MREAD.ERROR-U ! ;

\ Resource template descriptor.
 0 CONSTANT _MRT-URI-A
 8 CONSTANT _MRT-URI-U
16 CONSTANT _MRT-NAME-A
24 CONSTANT _MRT-NAME-U
32 CONSTANT _MRT-TITLE-A
40 CONSTANT _MRT-TITLE-U
48 CONSTANT _MRT-DESC-A
56 CONSTANT _MRT-DESC-U
64 CONSTANT _MRT-MIME-A
72 CONSTANT _MRT-MIME-U
80 CONSTANT MCP-RESOURCE-TEMPLATE-SIZE

: MRT.URI-A       ( template -- a ) _MRT-URI-A + ;
: MRT.URI-U       ( template -- a ) _MRT-URI-U + ;
: MRT.NAME-A      ( template -- a ) _MRT-NAME-A + ;
: MRT.NAME-U      ( template -- a ) _MRT-NAME-U + ;
: MRT.TITLE-A     ( template -- a ) _MRT-TITLE-A + ;
: MRT.TITLE-U     ( template -- a ) _MRT-TITLE-U + ;
: MRT.DESC-A      ( template -- a ) _MRT-DESC-A + ;
: MRT.DESC-U      ( template -- a ) _MRT-DESC-U + ;
: MRT.MIME-A      ( template -- a ) _MRT-MIME-A + ;
: MRT.MIME-U      ( template -- a ) _MRT-MIME-U + ;

: MCP-RESOURCE-TEMPLATE-INIT  ( template -- )
    MCP-RESOURCE-TEMPLATE-SIZE 0 FILL ;

: MCP-METHOD?  ( message method-a method-u -- flag )
    2>R JRPC-METHOD 2R> STR-STR= ;

: MCP-TOOL-NAME-CHAR?  ( char -- flag )
    DUP 65 >= OVER 90 <= AND IF DROP -1 EXIT THEN
    DUP 97 >= OVER 122 <= AND IF DROP -1 EXIT THEN
    DUP 48 >= OVER 57 <= AND IF DROP -1 EXIT THEN
    DUP 95 = OVER 45 = OR SWAP 46 = OR ;

: MCP-TOOL-NAME-VALID?  ( addr len -- flag )
    DUP 0= OVER MCP-MAX-NAME > OR IF 2DROP 0 EXIT THEN
    0 DO
        DUP I + C@ MCP-TOOL-NAME-CHAR? 0= IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: MCP-URI-VALID?  ( addr len -- flag )
    DUP 0= OVER MCP-MAX-URI > OR IF 2DROP 0 EXIT THEN
    2DUP UTF8-VALID? 0= IF 2DROP 0 EXIT THEN
    0 DO
        DUP I + C@ 58 = IF DROP -1 UNLOOP EXIT THEN
    LOOP
    DROP 0 ;

