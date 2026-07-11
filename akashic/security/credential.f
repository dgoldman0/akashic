\ =====================================================================
\  credential.f - Bounded in-memory credential ownership
\ =====================================================================
\  Credentials are opaque secret containers. Callers may replace, clear, or
\  borrow a credential through a callback; there is deliberately no pointer
\  getter. This module does not persist, encrypt, prompt for, or transmit data.
\ =====================================================================

PROVIDED akashic-credential

0 CONSTANT CRED-STATE-EMPTY
1 CONSTANT CRED-STATE-PRESENT

0 CONSTANT CRED-S-OK
1 CONSTANT CRED-S-INVALID
2 CONSTANT CRED-S-TOO-LONG
3 CONSTANT CRED-S-ABSENT
4 CONSTANT CRED-S-OVERLAP
5 CONSTANT CRED-S-CALLBACK

512 CONSTANT CRED-SECRET-CAPACITY

 0 CONSTANT _CRED-STATE
 8 CONSTANT _CRED-LENGTH
16 CONSTANT _CRED-GENERATION
24 CONSTANT _CRED-FLAGS
32 CONSTANT _CRED-USES
40 CONSTANT _CRED-LAST-STATUS
48 CONSTANT _CRED-SECRET
_CRED-SECRET CRED-SECRET-CAPACITY + CONSTANT CREDENTIAL-SIZE

: CRED.STATE       ( credential -- a ) _CRED-STATE + ;
: CRED.LENGTH      ( credential -- a ) _CRED-LENGTH + ;
: CRED.GENERATION  ( credential -- a ) _CRED-GENERATION + ;
: CRED.FLAGS       ( credential -- a ) _CRED-FLAGS + ;
: CRED.USES        ( credential -- a ) _CRED-USES + ;
: CRED.LAST-STATUS ( credential -- a ) _CRED-LAST-STATUS + ;
: _CRED-SECRET-A   ( credential -- a ) _CRED-SECRET + ;

: CRED-INIT  ( credential -- )
    CREDENTIAL-SIZE 0 FILL ;

: CRED-NEW  ( -- credential ior )
    CREDENTIAL-SIZE ALLOCATE
    DUP IF EXIT THEN
    DROP DUP CRED-INIT 0 ;

: CRED-FREE  ( credential -- )
    ?DUP IF DUP CREDENTIAL-SIZE 0 FILL FREE THEN ;

: CRED-PRESENT?  ( credential -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    CRED.STATE @ CRED-STATE-PRESENT = ;

VARIABLE _CREDR-P

: _CRED-RESULT  ( status credential -- status )
    _CREDR-P ! DUP _CREDR-P @ CRED.LAST-STATUS ! ;

VARIABLE _CREDS-A
VARIABLE _CREDS-U
VARIABLE _CREDS-P

: _CRED-SOURCE-OVERLAP?  ( -- flag )
    _CREDS-A @ _CREDS-P @ _CRED-SECRET-A CRED-SECRET-CAPACITY + <
    _CREDS-A @ _CREDS-U @ + _CREDS-P @ _CRED-SECRET-A > AND ;

: CRED-SET  ( source length credential -- status )
    _CREDS-P ! _CREDS-U ! _CREDS-A !
    _CREDS-P @ 0= IF CRED-S-INVALID EXIT THEN
    _CREDS-A @ 0= _CREDS-U @ 0> 0= OR IF
        CRED-S-INVALID _CREDS-P @ _CRED-RESULT EXIT
    THEN
    _CREDS-U @ CRED-SECRET-CAPACITY > IF
        CRED-S-TOO-LONG _CREDS-P @ _CRED-RESULT EXIT
    THEN
    _CRED-SOURCE-OVERLAP? IF CRED-S-OVERLAP _CREDS-P @ _CRED-RESULT EXIT THEN
    _CREDS-P @ _CRED-SECRET-A CRED-SECRET-CAPACITY 0 FILL
    _CREDS-A @ _CREDS-P @ _CRED-SECRET-A _CREDS-U @ CMOVE
    _CREDS-U @ _CREDS-P @ CRED.LENGTH !
    CRED-STATE-PRESENT _CREDS-P @ CRED.STATE !
    1 _CREDS-P @ CRED.GENERATION +!
    CRED-S-OK _CREDS-P @ _CRED-RESULT ;

: CRED-CLEAR  ( credential -- )
    DUP 0= IF DROP EXIT THEN
    DUP _CRED-SECRET-A CRED-SECRET-CAPACITY 0 FILL
    DUP 0 SWAP CRED.LENGTH !
    DUP CRED-STATE-EMPTY SWAP CRED.STATE !
    DUP CRED-S-OK SWAP CRED.LAST-STATUS !
    1 SWAP CRED.GENERATION +! ;

VARIABLE _CREDW-P
VARIABLE _CREDW-XT
VARIABLE _CREDW-CONTEXT
VARIABLE _CREDW-RESULT

: _CRED-WITH-INNER  ( -- )
    _CREDW-P @ _CRED-SECRET-A _CREDW-P @ CRED.LENGTH @
    _CREDW-CONTEXT @ _CREDW-XT @ EXECUTE _CREDW-RESULT ! ;

: CRED-WITH  ( callback context credential -- status )
    _CREDW-P ! _CREDW-CONTEXT ! _CREDW-XT !
    _CREDW-P @ 0= IF CRED-S-INVALID EXIT THEN
    _CREDW-P @ CRED-PRESENT? 0= IF
        CRED-S-ABSENT _CREDW-P @ _CRED-RESULT EXIT
    THEN
    0 _CREDW-RESULT !
    1 _CREDW-P @ CRED.USES +!
    ['] _CRED-WITH-INNER CATCH IF
        CRED-S-CALLBACK _CREDW-P @ _CRED-RESULT EXIT
    THEN
    _CREDW-RESULT @ _CREDW-P @ _CRED-RESULT ;

\ The descriptor owns persistent secret bytes, but callback scratch is shared.
\ Cooperative callers may switch between calls; preemptive callers must
\ serialize mutation and CRED-WITH.
