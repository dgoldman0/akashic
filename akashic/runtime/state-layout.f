\ =====================================================================
\  state-layout.f - Instance-relative runtime state layouts
\ =====================================================================
\  Defines fields whose storage lives in a component instance rather
\  than in the Forth dictionary.  The caller supplies the address of a
\  module-local "current state" cell when declaring each field.
\
\  Example:
\    VARIABLE _MY-STATE
\    CMP-LAYOUT-BEGIN
\    _MY-STATE CMP-CELL:       _MY-COUNT
\    _MY-STATE 256 CMP-FIELD:  _MY-BUFFER
\    CMP-LAYOUT-SIZE CONSTANT _MY-STATE-SIZE
\
\  At runtime, store an allocated state base in _MY-STATE.  Executing
\  _MY-COUNT or _MY-BUFFER then returns the instance-relative address.
\ =====================================================================

PROVIDED akashic-runtime-state-layout

VARIABLE _CMP-LAYOUT-OFF
0 _CMP-LAYOUT-OFF !

: _CMP-ALIGN8  ( bytes -- aligned )
    7 + -8 AND ;

: CMP-LAYOUT-BEGIN  ( -- )
    0 _CMP-LAYOUT-OFF ! ;

: CMP-LAYOUT-SIZE  ( -- bytes )
    _CMP-LAYOUT-OFF @ ;

: CMP-FIELD:  ( current-state-cell bytes "name" -- )
    CREATE
        SWAP ,                    \ current-state cell address
        _CMP-LAYOUT-OFF @ ,       \ byte offset in instance state
        _CMP-ALIGN8 _CMP-LAYOUT-OFF +!
    DOES>                         ( body -- field-addr )
        DUP @ @                   ( body state-base )
        SWAP 8 + @ + ;

: CMP-CELL:  ( current-state-cell "name" -- )
    8 CMP-FIELD: ;
