\ =====================================================================
\  caller-span.f - Checked caller-managed physical span qualification
\ =====================================================================
\  This protocol-neutral wrapper captures the BIOS CALLER-SPAN-STATUS word
\  and publishes a validated Akashic boundary.  It owns no mutable state and
\  neither reads nor writes the named bytes.
\
\  Public API:
\    CALLER-SPAN-STATUS        ( address length -- status )
\    CALLER-SPAN-STATUS-VALID? ( status -- flag )
\
\  Status:
\    0 OK, 2 RANGE, 3 PROTECTED, 4 PLATFORM.
\ =====================================================================

PROVIDED akashic-caller-span

0 CONSTANT CALLER-SPAN-S-OK
2 CONSTANT CALLER-SPAN-S-RANGE
3 CONSTANT CALLER-SPAN-S-PROTECTED
4 CONSTANT CALLER-SPAN-S-PLATFORM

: CALLER-SPAN-STATUS-VALID?  ( status -- flag )
    DUP CALLER-SPAN-S-OK = IF DROP -1 EXIT THEN
    DUP CALLER-SPAN-S-RANGE = IF DROP -1 EXIT THEN
    DUP CALLER-SPAN-S-PROTECTED = IF DROP -1 EXIT THEN
    CALLER-SPAN-S-PLATFORM = ;

\ Capture the architectural word before replacing its public name with the
\ Akashic wrapper.  A CONSTANT is immutable dictionary data, not operation
\ state shared between calls.
' CALLER-SPAN-STATUS CONSTANT _caller-span-bios-xt

: _CALLER-SPAN-DROP3  ( x1 x2 x3 -- )
    2DROP DROP ;

: _CALLER-SPAN-BIOS-CALL  ( address length -- bios-status )
    _caller-span-bios-xt EXECUTE ;

: _CALLER-SPAN-BIOS>STATUS  ( bios-status -- status )
    DUP CALLER-SPAN-S-OK = IF EXIT THEN
    DUP CALLER-SPAN-S-RANGE = IF EXIT THEN
    DUP CALLER-SPAN-S-PROTECTED = IF EXIT THEN
    DROP CALLER-SPAN-S-PLATFORM ;

: CALLER-SPAN-STATUS  ( address length -- status )
    ['] _CALLER-SPAN-BIOS-CALL CATCH
    ?DUP IF
        _CALLER-SPAN-DROP3
        CALLER-SPAN-S-PLATFORM EXIT
    THEN
    _CALLER-SPAN-BIOS>STATUS ;
