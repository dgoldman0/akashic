\ itc.f — General-purpose ITC compiler + interpreter for Megapad-64
\
\ Indirect-Threaded Code overlay.  Compiles Forth source text into
\ a cell-stream of whitelist indices + pseudo-ops, then executes
\ that stream via a table-dispatch inner interpreter.
\
\ No native code enters the compiled body — every cell is an integer.
\ Consumers supply a whitelist of safe host XTs; the ITC layer adds
\ controlled indirection so untrusted source can be sandboxed.
\
\ Depends on:
\   string.f — STR>NUM, STR-PARSE-TOKEN, COMPARE, /STRING
\
\ Prefix: ITC-   (public API)
\         _ITC-  (internal helpers)
\
\ Load with:   REQUIRE utils/itc.f

REQUIRE string.f
PROVIDED akashic-itc

\ =====================================================================
\  1. Pseudo-op Constants
\ =====================================================================
\
\ Indices 0–7 in the compiled body are pseudo-ops handled directly
\ by the inner interpreter.  Whitelist words are offset by 8.

0 CONSTANT ITC-OP-LIT       \ next cell = literal value
1 CONSTANT ITC-OP-BRANCH    \ next cell = absolute target addr
2 CONSTANT ITC-OP-0BRANCH   \ pop flag; branch if 0
3 CONSTANT ITC-OP-DO        \ ( limit index -- ) push to R-stack
4 CONSTANT ITC-OP-LOOP      \ increment index, branch or continue
5 CONSTANT ITC-OP-PLOOP     \ +LOOP variant
6 CONSTANT ITC-OP-EXIT      \ return from colon def
7 CONSTANT ITC-OP-CALL      \ next cell = target addr; push return

8 CONSTANT _ITC-WL-OFFSET   \ first whitelist word = index 8

\ =====================================================================
\  2. Fault Codes
\ =====================================================================

0 CONSTANT ITC-OK
1 CONSTANT ITC-FAULT-BAD-OP
2 CONSTANT ITC-FAULT-STACK
3 CONSTANT ITC-FAULT-ABORT
4 CONSTANT ITC-FAULT-COMPILE

\ =====================================================================
\  3. Whitelist Table
\ =====================================================================
\
\ Flat array of entries.  Each entry = 40 bytes:
\   [0]       name-len (low 5 bits) | flags (bit 7 = IMMEDIATE)
\   [1..31]   name (padded with 0)
\   [32..39]  XT (1 cell = 8 bytes)
\
\ Max 256 entries.  Index 0 is the first user-registered word.
\ In the compiled body, user words appear as (index + 8).

256 CONSTANT ITC-WL-MAX
 40 CONSTANT _ITC-WL-ESZ
CREATE _ITC-WL  ITC-WL-MAX _ITC-WL-ESZ * ALLOT
VARIABLE _ITC-WL-COUNT

\ _ITC-WL-ENTRY ( index -- entry-addr )
: _ITC-WL-ENTRY  ( idx -- addr )
    _ITC-WL-ESZ * _ITC-WL + ;

\ ITC-WL-ADD ( xt flags c-addr u -- )
\   Register a word.  flags: 1 = IMMEDIATE.  u <= 31.
: ITC-WL-ADD  ( xt flags c-addr u -- )
    _ITC-WL-COUNT @ ITC-WL-MAX >= IF 2DROP 2DROP EXIT THEN
    _ITC-WL-COUNT @ _ITC-WL-ENTRY  ( xt flags c-addr u entry )
    >R
    \ store name-len | flags into byte 0
    DUP 31 MIN                      ( xt flags c-addr u min-u )
    3 PICK 7 LSHIFT OR              ( xt flags c-addr u byte0 )
    R@ C!
    \ copy name — CMOVE ( src dst count )
    DUP 31 MIN                      ( xt flags c-addr u min-u )
    -ROT                            ( xt flags min-u c-addr u )
    DROP                            ( xt flags min-u c-addr )
    R@ 1+                           ( xt flags min-u c-addr entry+1 )
    ROT                             ( xt flags c-addr entry+1 min-u )
    CMOVE                           ( xt flags )
    \ store XT at offset 32
    DROP                            ( xt )
    R> 32 + !
    1 _ITC-WL-COUNT +! ;

\ _ITC-WL-MATCH ( c-addr u entry -- flag )
\   True if entry's name matches (c-addr u).
: _ITC-WL-MATCH  ( c-addr u entry -- flag )
    DUP C@ 31 AND                   ( c-addr u entry nlen )
    2 PICK <> IF DROP 2DROP 0 EXIT THEN
    1+                              ( c-addr u entry+1 )
    OVER                            ( c-addr u entry+1 u )
    COMPARE 0= ;                    \ COMPARE( c-addr u entry+1 u )

\ ITC-WL-FIND ( c-addr u -- index -1 | 0 )
\   Lookup by name.  Returns whitelist index + true, or just false.
: ITC-WL-FIND  ( c-addr u -- index -1 | 0 )
    _ITC-WL-COUNT @ 0 ?DO
        2DUP I _ITC-WL-ENTRY _ITC-WL-MATCH IF
            2DROP I -1 UNLOOP EXIT
        THEN
    LOOP
    2DROP 0 ;

\ ITC-WL-XT@ ( index -- xt )
: ITC-WL-XT@  ( index -- xt )
    _ITC-WL-ENTRY 32 + @ ;

\ ITC-WL-IMM? ( index -- flag )
: ITC-WL-IMM?  ( index -- flag )
    _ITC-WL-ENTRY C@ 128 AND 0<> ;

\ ITC-WL-RESET ( -- )
: ITC-WL-RESET  ( -- )
    _ITC-WL ITC-WL-MAX _ITC-WL-ESZ * 0 FILL
    0 _ITC-WL-COUNT ! ;

\ =====================================================================
\  4. Symbol Table (CONSTANT / VARIABLE support)
\ =====================================================================
\
\ Stores (name, value) pairs.  CONSTANT records literal values.
\ VARIABLE records addresses allocated from a caller-supplied data
\ region.  Max 64 symbols per compilation.

64 CONSTANT _ITC-SYM-MAX
32 CONSTANT _ITC-SYM-NSZ    \ name slot: [1B len][31B name]
CREATE _ITC-SYM-NAMES  _ITC-SYM-MAX _ITC-SYM-NSZ * ALLOT
CREATE _ITC-SYM-VALS   _ITC-SYM-MAX CELLS ALLOT
VARIABLE _ITC-SYM-COUNT

\ _ITC-SYM-NSLOT ( idx -- addr )
: _ITC-SYM-NSLOT  ( idx -- addr )
    _ITC-SYM-NSZ * _ITC-SYM-NAMES + ;

\ _ITC-SYM-ADD ( value c-addr u -- )
: _ITC-SYM-ADD  ( value c-addr u -- )
    _ITC-SYM-COUNT @ _ITC-SYM-MAX >= IF 2DROP DROP EXIT THEN
    _ITC-SYM-COUNT @ _ITC-SYM-NSLOT  ( value c-addr u slot )
    >R
    DUP 31 MIN DUP R@ C!           ( value c-addr u min-u )
    -ROT                            ( value min-u c-addr u )
    DROP                            ( value min-u c-addr )
    R> 1+                           ( value min-u c-addr slot+1 )
    ROT                             ( value c-addr slot+1 min-u )
    CMOVE                           ( value )
    _ITC-SYM-COUNT @ CELLS _ITC-SYM-VALS + !
    1 _ITC-SYM-COUNT +! ;

\ _ITC-SYM-FIND ( c-addr u -- value -1 | 0 )
: _ITC-SYM-FIND  ( c-addr u -- value -1 | 0 )
    _ITC-SYM-COUNT @ 0 ?DO
        2DUP I _ITC-SYM-NSLOT _ITC-WL-MATCH IF
            2DROP I CELLS _ITC-SYM-VALS + @ -1
            UNLOOP EXIT
        THEN
    LOOP
    2DROP 0 ;

\ =====================================================================
\  5. Entry Table (colon definitions)
\ =====================================================================
\
\ Records the name and body-offset of each : definition so that
\ words can reference each other and ITC-ENTRY@ can find them.

32 CONSTANT ITC-MAX-ENTRIES
CREATE _ITC-ENT-NAMES  ITC-MAX-ENTRIES _ITC-SYM-NSZ * ALLOT
CREATE _ITC-ENT-OFFS   ITC-MAX-ENTRIES CELLS ALLOT
VARIABLE _ITC-ENT-COUNT

\ _ITC-ENT-NSLOT ( idx -- addr )
: _ITC-ENT-NSLOT  ( idx -- addr )
    _ITC-SYM-NSZ * _ITC-ENT-NAMES + ;

\ _ITC-ENT-ADD ( offset c-addr u -- )
: _ITC-ENT-ADD  ( offset c-addr u -- )
    _ITC-ENT-COUNT @ ITC-MAX-ENTRIES >= IF 2DROP DROP EXIT THEN
    _ITC-ENT-COUNT @ _ITC-ENT-NSLOT  ( offset c-addr u slot )
    >R
    DUP 31 MIN DUP R@ C!           ( offset c-addr u min-u )
    -ROT                            ( offset min-u c-addr u )
    DROP                            ( offset min-u c-addr )
    R> 1+                           ( offset min-u c-addr slot+1 )
    ROT                             ( offset c-addr slot+1 min-u )
    CMOVE                           ( offset )
    _ITC-ENT-COUNT @ CELLS _ITC-ENT-OFFS + !
    1 _ITC-ENT-COUNT +! ;

\ _ITC-ENT-FIND ( c-addr u -- offset -1 | 0 )
: _ITC-ENT-FIND  ( c-addr u -- offset -1 | 0 )
    _ITC-ENT-COUNT @ 0 ?DO
        2DUP I _ITC-ENT-NSLOT _ITC-WL-MATCH IF
            2DROP I CELLS _ITC-ENT-OFFS + @ -1
            UNLOOP EXIT
        THEN
    LOOP
    2DROP 0 ;

\ ITC-ENTRY@ ( index -- name-addr name-len offset )
: ITC-ENTRY@  ( index -- name-addr name-len offset )
    DUP _ITC-ENT-NSLOT             ( idx slot )
    DUP 1+                          ( idx slot name-addr )
    SWAP C@ 31 AND                  ( idx name-addr name-len )
    ROT CELLS _ITC-ENT-OFFS + @ ;  ( name-addr name-len offset )

\ =====================================================================
\  6. Compiler State
\ =====================================================================

VARIABLE _ITC-CP          \ compile pointer (absolute addr into buf)
VARIABLE _ITC-BUF-BASE    \ start of output buffer
VARIABLE _ITC-BUF-END     \ end of output buffer
VARIABLE _ITC-STATE       \ 0 = interpret, -1 = compile
VARIABLE _ITC-ERR         \ 0 = ok, else fault code
VARIABLE _ITC-SRC         \ current source pointer
VARIABLE _ITC-SRC-LEN     \ remaining source length
VARIABLE _ITC-DATA-PTR    \ data-region pointer for VARIABLE alloc
VARIABLE _ITC-DATA-END    \ data-region end

\ Control-flow stack for forward-reference patching
64 CONSTANT _ITC-CS-MAX
CREATE _ITC-CSTACK  _ITC-CS-MAX CELLS ALLOT
VARIABLE _ITC-CSP         \ index into _ITC-CSTACK (0 = empty)

\ Current definition start offset (for RECURSE)
VARIABLE _ITC-DEF-OFF

\ _ITC-CS-PUSH ( val -- )
: _ITC-CS-PUSH  ( val -- )
    _ITC-CSP @ _ITC-CS-MAX >= IF ITC-FAULT-COMPILE _ITC-ERR ! DROP EXIT THEN
    _ITC-CSP @ CELLS _ITC-CSTACK + !
    1 _ITC-CSP +! ;

\ _ITC-CS-POP ( -- val )
: _ITC-CS-POP  ( -- val )
    _ITC-CSP @ 1 < IF ITC-FAULT-COMPILE _ITC-ERR ! 0 EXIT THEN
    -1 _ITC-CSP +!
    _ITC-CSP @ CELLS _ITC-CSTACK + @ ;

\ =====================================================================
\  7. Code Emission Helpers
\ =====================================================================

\ _ITC-EMIT ( cell -- )   Append one cell to the output buffer.
: _ITC-EMIT  ( cell -- )
    _ITC-CP @ _ITC-BUF-END @ >= IF
        DROP ITC-FAULT-COMPILE _ITC-ERR ! EXIT
    THEN
    _ITC-CP @ !
    1 CELLS _ITC-CP +! ;

\ _ITC-HERE ( -- addr )   Current compile pointer.
: _ITC-HERE  ( -- addr )
    _ITC-CP @ ;

\ _ITC-PLACEHOLDER ( -- addr )  Emit 0, return its address for backpatch.
: _ITC-PLACEHOLDER  ( -- addr )
    _ITC-HERE  0 _ITC-EMIT ;

\ =====================================================================
\  8. Keyword Matching Helpers
\ =====================================================================
\
\ Short inline comparisons for the ~15 compile-time keywords.
\ Uses COMPARE (BIOS built-in).

: _ITC-KW=  ( c-addr u c-addr2 u2 -- flag )
    COMPARE 0= ;

\ =====================================================================
\  9. Compiler — Control-Flow Words
\ =====================================================================

\ These are called when the compiler recognises a keyword in compile
\ mode.  They emit pseudo-ops and manage the control-flow stack.

: _ITC-DO-IF  ( -- )
    ITC-OP-0BRANCH _ITC-EMIT
    _ITC-PLACEHOLDER _ITC-CS-PUSH ;

: _ITC-DO-ELSE  ( -- )
    ITC-OP-BRANCH _ITC-EMIT
    _ITC-PLACEHOLDER               ( else-placeholder )
    _ITC-CS-POP                     ( if-placeholder )
    _ITC-HERE SWAP !                \ backpatch IF → here
    _ITC-CS-PUSH ;                  \ push ELSE for THEN

: _ITC-DO-THEN  ( -- )
    _ITC-CS-POP _ITC-HERE SWAP ! ;

: _ITC-DO-BEGIN  ( -- )
    _ITC-HERE _ITC-CS-PUSH ;

: _ITC-DO-UNTIL  ( -- )
    ITC-OP-0BRANCH _ITC-EMIT
    _ITC-CS-POP _ITC-EMIT ;

: _ITC-DO-WHILE  ( -- )
    ITC-OP-0BRANCH _ITC-EMIT
    _ITC-PLACEHOLDER                ( while-placeholder )
    \ swap BEGIN addr under WHILE placeholder on CS
    _ITC-CS-POP                     ( while-ph begin-addr )
    SWAP _ITC-CS-PUSH               ( begin-addr )  \ push begin back under
    _ITC-CS-PUSH ;                  \ push while-ph on top
    \ CS now: ... while-ph begin-addr  (begin on top)
    \ Wait — need begin on bottom, while on top for REPEAT.
    \ Actually: CS-POP gives begin-addr. Then we push while-ph, then begin.
    \ So CS is: ... while-ph begin-addr.  REPEAT pops begin, then while.

: _ITC-DO-REPEAT  ( -- )
    ITC-OP-BRANCH _ITC-EMIT
    _ITC-CS-POP _ITC-EMIT          \ branch back to BEGIN
    _ITC-CS-POP _ITC-HERE SWAP ! ; \ backpatch WHILE → here

: _ITC-DO-DO  ( -- )
    ITC-OP-DO _ITC-EMIT
    _ITC-HERE _ITC-CS-PUSH ;       \ save loop-start for LOOP

: _ITC-DO-LOOP  ( -- )
    ITC-OP-LOOP _ITC-EMIT
    _ITC-CS-POP _ITC-EMIT ;        \ branch target = DO's body start

: _ITC-DO-PLOOP  ( -- )
    ITC-OP-PLOOP _ITC-EMIT
    _ITC-CS-POP _ITC-EMIT ;

: _ITC-DO-RECURSE  ( -- )
    ITC-OP-CALL _ITC-EMIT
    _ITC-DEF-OFF @ _ITC-EMIT ;

\ =====================================================================
\  10. Compiler — Main Loop
\ =====================================================================

\ _ITC-NEXT-TOKEN ( -- c-addr u )
\   Pull next whitespace-delimited token from source buffer.
\   Returns ( addr 0 ) when exhausted.
: _ITC-NEXT-TOKEN  ( -- c-addr u )
    _ITC-SRC @ _ITC-SRC-LEN @
    STR-PARSE-TOKEN                 ( tok tlen rest rlen )
    _ITC-SRC-LEN ! _ITC-SRC !      \ update remaining
    ;                               ( tok tlen )

\ _ITC-COMPILE-TOKEN ( c-addr u -- )
\   Process one token in compile mode.
: _ITC-COMPILE-TOKEN  ( c-addr u -- )
    \ Check keywords first (most frequent path = normal word)
    2DUP S" ;" _ITC-KW= IF 2DROP
        ITC-OP-EXIT _ITC-EMIT  0 _ITC-STATE !  EXIT THEN
    2DUP S" IF" _ITC-KW= IF 2DROP _ITC-DO-IF EXIT THEN
    2DUP S" ELSE" _ITC-KW= IF 2DROP _ITC-DO-ELSE EXIT THEN
    2DUP S" THEN" _ITC-KW= IF 2DROP _ITC-DO-THEN EXIT THEN
    2DUP S" BEGIN" _ITC-KW= IF 2DROP _ITC-DO-BEGIN EXIT THEN
    2DUP S" UNTIL" _ITC-KW= IF 2DROP _ITC-DO-UNTIL EXIT THEN
    2DUP S" WHILE" _ITC-KW= IF 2DROP _ITC-DO-WHILE EXIT THEN
    2DUP S" REPEAT" _ITC-KW= IF 2DROP _ITC-DO-REPEAT EXIT THEN
    2DUP S" DO" _ITC-KW= IF 2DROP _ITC-DO-DO EXIT THEN
    2DUP S" LOOP" _ITC-KW= IF 2DROP _ITC-DO-LOOP EXIT THEN
    2DUP S" +LOOP" _ITC-KW= IF 2DROP _ITC-DO-PLOOP EXIT THEN
    2DUP S" RECURSE" _ITC-KW= IF 2DROP _ITC-DO-RECURSE EXIT THEN

    \ Check entry table (previously defined ITC words)
    2DUP _ITC-ENT-FIND IF          ( c-addr u offset )
        -ROT 2DROP
        ITC-OP-CALL _ITC-EMIT  _ITC-EMIT  EXIT
    THEN

    \ Check symbol table (CONSTANT / VARIABLE)
    2DUP _ITC-SYM-FIND IF          ( c-addr u value )
        -ROT 2DROP
        ITC-OP-LIT _ITC-EMIT  _ITC-EMIT  EXIT
    THEN

    \ Check whitelist
    2DUP ITC-WL-FIND IF             ( c-addr u index )
        -ROT 2DROP
        _ITC-WL-OFFSET + _ITC-EMIT  EXIT
    THEN

    \ Try as number
    2DUP STR>NUM IF                 ( c-addr u number )
        -ROT 2DROP
        ITC-OP-LIT _ITC-EMIT  _ITC-EMIT  EXIT
    THEN
    DROP

    \ Unknown token → error
    2DROP ITC-FAULT-COMPILE _ITC-ERR ! ;

\ _ITC-DO-COLON ( -- )
\   Handle : — parse name, register entry, enter compile mode.
: _ITC-DO-COLON  ( -- )
    _ITC-NEXT-TOKEN                 ( name len )
    DUP 0= IF 2DROP ITC-FAULT-COMPILE _ITC-ERR ! EXIT THEN
    _ITC-HERE                       ( name len here )
    -ROT                            ( here name len )
    _ITC-ENT-ADD
    _ITC-HERE _ITC-DEF-OFF !
    -1 _ITC-STATE ! ;

\ _ITC-DO-CONSTANT ( -- )
\   Handle CONSTANT — pop value from host stack, parse name, store.
: _ITC-DO-CONSTANT  ( -- )
    _ITC-NEXT-TOKEN                 ( value name len )
    DUP 0= IF 2DROP DROP ITC-FAULT-COMPILE _ITC-ERR ! EXIT THEN
    _ITC-SYM-ADD ;

\ _ITC-DO-VARIABLE ( -- )
\   Handle VARIABLE — allocate 1 cell from data region, store addr.
: _ITC-DO-VARIABLE  ( -- )
    _ITC-NEXT-TOKEN                 ( name len )
    DUP 0= IF 2DROP ITC-FAULT-COMPILE _ITC-ERR ! EXIT THEN
    _ITC-DATA-PTR @ _ITC-DATA-END @ >= IF
        2DROP ITC-FAULT-COMPILE _ITC-ERR ! EXIT THEN
    _ITC-DATA-PTR @                 ( name len addr )
    -ROT                            ( addr name len )
    _ITC-SYM-ADD
    1 CELLS _ITC-DATA-PTR +! ;

\ _ITC-INTERPRET-TOKEN ( c-addr u -- )
\   Process one token in interpret mode.
: _ITC-INTERPRET-TOKEN  ( c-addr u -- )
    2DUP S" :" _ITC-KW= IF 2DROP _ITC-DO-COLON EXIT THEN
    2DUP S" CONSTANT" _ITC-KW= IF 2DROP _ITC-DO-CONSTANT EXIT THEN
    2DUP S" VARIABLE" _ITC-KW= IF 2DROP _ITC-DO-VARIABLE EXIT THEN

    \ Try as number — push to host data stack (for CONSTANT)
    2DUP STR>NUM IF
        -ROT 2DROP EXIT             \ number stays on stack
    THEN
    DROP

    \ Unknown in interpret mode → error
    2DROP ITC-FAULT-COMPILE _ITC-ERR ! ;

\ ITC-COMPILE ( src len buf limit -- entry-count | -1 )
\   Compile source text into ITC body in buf.
\   limit = size of buf in bytes.
\   Returns entry count on success, -1 on error.
\
\   Optional: set _ITC-DATA-PTR / _ITC-DATA-END before calling
\   to enable VARIABLE allocation.
: ITC-COMPILE  ( src len buf limit -- entry-count | -1 )
    OVER + _ITC-BUF-END !
    DUP _ITC-BUF-BASE !  _ITC-CP !
    _ITC-SRC-LEN ! _ITC-SRC !
    \ Reset compiler state
    0 _ITC-STATE !  0 _ITC-ERR !  0 _ITC-CSP !
    0 _ITC-ENT-COUNT !  0 _ITC-SYM-COUNT !  0 _ITC-DEF-OFF !
    \ Main loop
    BEGIN
        _ITC-ERR @ 0= WHILE
        _ITC-NEXT-TOKEN             ( tok tlen )
        DUP 0= IF 2DROP            \ exhausted
            _ITC-STATE @ IF         \ still compiling → missing ;
                ITC-FAULT-COMPILE _ITC-ERR !
            THEN
            _ITC-ERR @ IF -1 ELSE _ITC-ENT-COUNT @ THEN EXIT
        THEN
        _ITC-STATE @ IF
            _ITC-COMPILE-TOKEN
        ELSE
            _ITC-INTERPRET-TOKEN
        THEN
    REPEAT
    -1 ;

\ =====================================================================
\  11. Inner Interpreter
\ =====================================================================

VARIABLE _ITC-IP          \ instruction pointer (absolute addr)
VARIABLE _ITC-RSP         \ return-stack pointer (grows upward)
VARIABLE _ITC-RSP-BASE    \ low bound
VARIABLE _ITC-RSP-END     \ high bound (exclusive)
VARIABLE _ITC-RUNNING     \ -1 = running, 0 = stopped
VARIABLE _ITC-FAULT       \ 0 = ok, else fault code

\ Callback: called before each whitelist dispatch.
\ Signature of target word: ( index -- continue-flag )
\ Set to 0 to disable.
VARIABLE _ITC-PRE-DISPATCH-XT

\ _ITC-RPUSH ( val -- )
: _ITC-RPUSH  ( val -- )
    _ITC-RSP @ _ITC-RSP-END @ >= IF
        DROP ITC-FAULT-STACK _ITC-FAULT ! 0 _ITC-RUNNING ! EXIT
    THEN
    _ITC-RSP @ !
    1 CELLS _ITC-RSP +! ;

\ _ITC-RPOP ( -- val )
: _ITC-RPOP  ( -- val )
    _ITC-RSP @ _ITC-RSP-BASE @ = IF
        ITC-FAULT-STACK _ITC-FAULT ! 0 _ITC-RUNNING ! 0 EXIT
    THEN
    -1 CELLS _ITC-RSP +!
    _ITC-RSP @ @ ;

\ _ITC-RPEEK ( -- val )   Top of ITC R-stack without popping.
: _ITC-RPEEK  ( -- val )
    _ITC-RSP @ 1 CELLS - @ ;

\ _ITC-FETCH-ADVANCE ( -- cell )   Fetch cell at IP, advance IP by 1 cell.
: _ITC-FETCH-ADVANCE  ( -- cell )
    _ITC-IP @ @
    1 CELLS _ITC-IP +! ;

\ _ITC-DO-PSEUDO ( opcode -- )
\   Handle pseudo-ops 0-7 inline.
: _ITC-DO-PSEUDO  ( op -- )
    CASE
        ITC-OP-LIT OF
            _ITC-FETCH-ADVANCE          \ push literal
        ENDOF
        ITC-OP-BRANCH OF
            _ITC-FETCH-ADVANCE _ITC-IP !
        ENDOF
        ITC-OP-0BRANCH OF
            _ITC-FETCH-ADVANCE          ( target )
            SWAP 0= IF _ITC-IP ! ELSE DROP THEN
        ENDOF
        ITC-OP-EXIT OF
            _ITC-RSP @ _ITC-RSP-BASE @ = IF
                \ top-level EXIT → stop
                0 _ITC-RUNNING !
            ELSE
                _ITC-RPOP _ITC-IP !
            THEN
        ENDOF
        ITC-OP-CALL OF
            _ITC-FETCH-ADVANCE          ( target )
            _ITC-IP @ _ITC-RPUSH        \ push return addr
            _ITC-IP !
        ENDOF
        ITC-OP-DO OF
            \ ( limit index -- )  push index then limit to R-stack
            SWAP
            _ITC-RPUSH                  \ push limit
            _ITC-RPUSH                  \ push index
        ENDOF
        ITC-OP-LOOP OF
            _ITC-FETCH-ADVANCE          ( target )
            _ITC-RPOP 1+               ( target index+1 )
            _ITC-RPEEK                  ( target index+1 limit )
            2DUP = IF
                2DROP DROP
                _ITC-RPOP DROP          \ discard limit
            ELSE
                DROP                    ( target index+1 )
                _ITC-RPUSH              \ push updated index
                _ITC-IP !              \ branch back
            THEN
        ENDOF
        ITC-OP-PLOOP OF
            _ITC-FETCH-ADVANCE          ( step target )
            SWAP                        ( target step )
            _ITC-RPOP +                ( target index+step )
            _ITC-RPEEK                  ( target index' limit )
            2DUP = IF
                2DROP DROP
                _ITC-RPOP DROP
            ELSE
                DROP
                _ITC-RPUSH
                _ITC-IP !
            THEN
        ENDOF
        \ Unknown pseudo-op
        ITC-FAULT-BAD-OP _ITC-FAULT !
        0 _ITC-RUNNING !
    ENDCASE ;

\ ITC-EXECUTE ( ip rsp-base rsp-size -- fault-code )
\   Run ITC body starting at ip.
\   rsp-base = start of return-stack region.
\   rsp-size = size in bytes.
\   Returns fault code (0 = success).
: ITC-EXECUTE  ( ip rsp-base rsp-size -- fault-code )
    OVER + _ITC-RSP-END !
    DUP _ITC-RSP-BASE !  _ITC-RSP !
    _ITC-IP !
    0 _ITC-FAULT !
    -1 _ITC-RUNNING !

    BEGIN _ITC-RUNNING @ _ITC-FAULT @ 0= AND WHILE
        _ITC-FETCH-ADVANCE              ( cell )
        DUP 8 < IF
            _ITC-DO-PSEUDO
        ELSE
            \ Whitelist dispatch
            _ITC-WL-OFFSET -            ( wl-index )
            DUP _ITC-WL-COUNT @ >= IF
                DROP ITC-FAULT-BAD-OP _ITC-FAULT !
                0 _ITC-RUNNING !
            ELSE
                \ Pre-dispatch callback
                _ITC-PRE-DISPATCH-XT @ ?DUP IF
                    OVER SWAP EXECUTE       ( wl-index flag )
                    0= IF
                        DROP
                        ITC-FAULT-ABORT _ITC-FAULT !
                        0 _ITC-RUNNING !
                    ELSE
                        ITC-WL-XT@ EXECUTE
                    THEN
                ELSE
                    ITC-WL-XT@ EXECUTE
                THEN
            THEN
        THEN
    REPEAT

    _ITC-FAULT @ ;

\ =====================================================================
\  12. Image Serialization
\ =====================================================================
\
\ Image format (cell-aligned):
\   Cell 0:  magic  0x49544346  ("ITCF")
\   Cell 1:  version (1)
\   Cell 2:  entry count
\   Cell 3:  body size in bytes
\   Cell 4:  data size in bytes  (caller's data region usage)
\   Cell 5..:  entry table  [32 B name-slot][1 cell offset] × count
\   Then:      ITC body (cells, stored as relative offsets)
\
\ All offsets in the saved body are relative to body-base so the
\ image is position-independent.

0x49544346 CONSTANT _ITC-IMG-MAGIC
1          CONSTANT _ITC-IMG-VERSION
40         CONSTANT _ITC-IMG-ENT-SZ   \ 32B name + 8B offset

\ ITC-SAVE-IMAGE ( buf body-addr body-len -- total-len )
\   Serialize entry table + ITC body into buf.
\   body-addr = _ITC-BUF-BASE @.  body-len = _ITC-CP @ - _ITC-BUF-BASE @.
\   Returns total bytes written to buf.
VARIABLE _ITC-IMG-BADDR   \ body-addr scratch for ITC-SAVE-IMAGE
VARIABLE _ITC-IMG-BLEN    \ body-len  scratch for ITC-SAVE-IMAGE

: ITC-SAVE-IMAGE  ( buf body-addr body-len -- total-len )
    _ITC-IMG-BLEN !  _ITC-IMG-BADDR !
    \ Header: 5 cells
    DUP                             ( buf buf )
    _ITC-IMG-MAGIC OVER !  CELL+
    _ITC-IMG-VERSION   OVER !  CELL+
    _ITC-ENT-COUNT @   OVER !  CELL+
    _ITC-IMG-BLEN @    OVER !  CELL+
    0                  OVER !  CELL+  ( buf ptr — past 5-cell header )
    \ Entry table
    _ITC-ENT-COUNT @ 0 ?DO
        I _ITC-ENT-NSLOT OVER _ITC-SYM-NSZ CMOVE
        _ITC-SYM-NSZ +
        I CELLS _ITC-ENT-OFFS + @      ( buf ptr ent-off )
        _ITC-IMG-BADDR @ -              ( buf ptr rel-off )
        OVER !  CELL+
    LOOP
    \ Body — copy raw bytes
    _ITC-IMG-BADDR @  OVER  _ITC-IMG-BLEN @  CMOVE
    _ITC-IMG-BLEN @ +                  ( buf ptr+blen )
    SWAP - ;                           ( total-len )

\ ITC-LOAD-IMAGE ( image-addr image-len -- body-addr body-len entry-count | 0 )
\   Parse header, validate magic/version, return pointers.
\   On failure returns a single 0.
: ITC-LOAD-IMAGE  ( image-addr image-len -- body-addr body-len entry-count | 0 )
    OVER @ _ITC-IMG-MAGIC <> IF 2DROP 0 EXIT THEN
    OVER CELL+ @ _ITC-IMG-VERSION <> IF 2DROP 0 EXIT THEN
    OVER 2 CELLS + @                ( img len entry-count )
    >R
    OVER 3 CELLS + @                ( img len body-len )
    >R
    \ Skip header (5 cells) + entry table
    DROP                            ( img )
    5 CELLS +
    R@ _ITC-IMG-ENT-SZ * +          ( body-addr  — past header + entries )
    R> R>                           ( body-addr body-len entry-count )
    ;

\ =====================================================================
\  13. Concurrency Guard
\ =====================================================================
\
\ All public ITC- words are serialized via _itc-guard.  The module
\ uses shared scratch state (_ITC-CP, _ITC-IP, symbol/entry tables,
\ etc.) so concurrent access would corrupt compilation or execution.

REQUIRE ../concurrency/guard.f
GUARD _itc-guard

' ITC-WL-ADD     CONSTANT _itc-wl-add-xt
' ITC-WL-FIND    CONSTANT _itc-wl-find-xt
' ITC-WL-XT@     CONSTANT _itc-wl-xt-xt
' ITC-WL-IMM?    CONSTANT _itc-wl-imm-xt
' ITC-WL-RESET   CONSTANT _itc-wl-reset-xt
' ITC-COMPILE    CONSTANT _itc-compile-xt
' ITC-EXECUTE    CONSTANT _itc-execute-xt
' ITC-ENTRY@     CONSTANT _itc-entry-xt
' ITC-SAVE-IMAGE CONSTANT _itc-save-xt
' ITC-LOAD-IMAGE CONSTANT _itc-load-xt

: ITC-WL-ADD     _itc-wl-add-xt   _itc-guard WITH-GUARD ;
: ITC-WL-FIND    _itc-wl-find-xt  _itc-guard WITH-GUARD ;
: ITC-WL-XT@     _itc-wl-xt-xt    _itc-guard WITH-GUARD ;
: ITC-WL-IMM?    _itc-wl-imm-xt   _itc-guard WITH-GUARD ;
: ITC-WL-RESET   _itc-wl-reset-xt _itc-guard WITH-GUARD ;
: ITC-COMPILE    _itc-compile-xt  _itc-guard WITH-GUARD ;
: ITC-EXECUTE    _itc-execute-xt  _itc-guard WITH-GUARD ;
: ITC-ENTRY@     _itc-entry-xt    _itc-guard WITH-GUARD ;
: ITC-SAVE-IMAGE _itc-save-xt     _itc-guard WITH-GUARD ;
: ITC-LOAD-IMAGE _itc-load-xt     _itc-guard WITH-GUARD ;

\ =====================================================================
\  Done.
\ =====================================================================
