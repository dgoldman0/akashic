\ =====================================================================
\  stx1-roles.f -- bounded STX1 framing and typed-grid feature discovery
\ =====================================================================
\
\  This narrow, read-only walk discovers whether one concrete STX1 value
\  needs typed grid cells.  It proves each header/tail is inside the supplied
\  span before reading the next role.  It does not repeat canonical geometry,
\  key, state, selection, or UTF-8 validation owned by the model and terminal.
\  All working state lives on the stacks: there is no scratch to alias,
\  allocate, retain, or expose to an aggregate-only admission callback.

PROVIDED akashic-tui-stx1-roles

REQUIRE ../../utils/memory-span.f

: _STX1R-LE16@  ( a -- u )
    DUP C@ SWAP 1+ C@ 8 LSHIFT OR ;

: _STX1R-LE32@  ( a -- u )
    DUP _STX1R-LE16@ SWAP 2 + _STX1R-LE16@ 16 LSHIFT OR ;

: _STX1R-ADVANCE  ( a u consumed -- a' u' )
    TUCK - >R + R> ;

\ A pair of u32 tail lengths cannot overflow a native cell when the run
\ count is multiplied by twelve.  Compare the complete size before stepping.
: _STX1R-ITEM  ( a remaining -- bytes role valid? )
    DUP 36 U< IF 2DROP 0 0 0 EXIT THEN
    OVER 24 + _STX1R-LE16@
    DUP 1 U< OVER 6 U> OR IF 2DROP DROP 0 0 0 EXIT THEN
    >R
    OVER 28 + _STX1R-LE32@
    2 PICK 32 + _STX1R-LE32@ 12 * + 36 +
    DUP ROT U> IF 2DROP R> DROP 0 0 0 EXIT THEN
    NIP R> -1 ;

: STX1R-ROLES?  ( address bytes -- typed? valid? )
    DUP 72 U< 2 PICK 0= OR IF 2DROP 0 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 0 EXIT THEN
    OVER _STX1R-LE32@ 0x31585453 <> IF 2DROP 0 0 EXIT THEN
    OVER 4 + _STX1R-LE16@ 1 <> IF 2DROP 0 0 EXIT THEN
    OVER 6 + _STX1R-LE16@ IF 2DROP 0 0 EXIT THEN
    OVER 40 + _STX1R-LE32@
    OVER 72 - 36 / OVER U< IF 2DROP DROP 0 0 EXIT THEN
    >R 72 _STX1R-ADVANCE 0 -ROT R> 0 ?DO
        2DUP _STX1R-ITEM 0= IF
            2DROP 2DROP DROP 0 0 UNLOOP EXIT
        THEN
        SWAP >R 3 U> >R ROT R> OR -ROT R> _STX1R-ADVANCE
    LOOP
    0= >R DROP R> ;
