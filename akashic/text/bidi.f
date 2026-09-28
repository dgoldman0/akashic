\ =================================================================
\  bidi.f — the Unicode Bidirectional Algorithm (UAX #9, 15.1.0)
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: BIDI- / _BD-
\  Depends on: unicode-props.f
\
\  Resolves embedding levels for one paragraph and reorders a line,
\  as the shared text contract (docs/rich-terminal/APT-1-TEXT.md
\  Section 7) requires: rules P2 and P3, X1 to X10 with isolates and
\  the maximum depth of 125, W1 to W7, N0 with paired brackets, N1,
\  N2, I1, I2, L1, and L2.  It passes every case in Unicode's
\  BidiTest.txt and BidiCharacterTest.txt.
\
\  Public API:
\    BIDI-AUTO BIDI-LTR BIDI-RTL      paragraph directions
\    BIDI-REMOVED                     level of a character X9 removes
\    BIDI-WORK-BYTES ( n -- bytes )   workspace for n characters
\    BIDI-RESOLVE ( classes scalars n direction work -- paragraph )
\        CLASSES is a byte array of Bidi_Class values (UP-BC-*).
\        SCALARS is a 32-bit array of the characters, used only for
\        paired brackets, or 0 when there are none.  WORK is caller
\        storage of BIDI-WORK-BYTES n bytes, cell aligned.
\    BIDI-LEVELS ( work -- addr )     the resolved level bytes
\    BIDI-REORDER ( levels n order -- m )
\        Rule L2 over a byte array of levels: ORDER receives, as 32-bit
\        values, the indexes of every entry that is not BIDI-REMOVED,
\        left to right; M is how many.
\    BIDI-TRAILING? ( class -- flag )
\        Rule L1 resets a run of such characters at a line's end:
\        whitespace, isolate controls, and the characters X9 removes.
\        BIDI-RESOLVE applies L1 with the paragraph's end as the only
\        line end; a caller breaking the paragraph into lines applies
\        it at each line's end with this word.
\
\  The algorithm keeps its scratch state in module variables, so the
\  resolving and reordering words are guarded in GUARDED builds.  They
\  call only the pure UP- lookups.  BIDI-TRAILING? is pure.
\ =================================================================

PROVIDED akashic-bidi

REQUIRE unicode-props.f

0 CONSTANT BIDI-AUTO
1 CONSTANT BIDI-LTR
2 CONSTANT BIDI-RTL
255 CONSTANT BIDI-REMOVED
125 CONSTANT _BD-MAX-DEPTH

\ Fixed stacks sized by the algorithm itself: the directional status
\ stack holds at most max_depth + 2 entries (X1), and BD16 keeps at most
\ 63 open brackets.
_BD-MAX-DEPTH 2 + CONSTANT _BD-DS-ENTRIES
63 CONSTANT _BD-BS-ENTRIES

\ =====================================================================
\  §1 — Workspace
\ =====================================================================
\
\  For n characters: types, levels, and explicit levels (one byte each),
\  then match, sequence, and bracket-pair arrays (four bytes each), then
\  the two stacks (one cell per entry).

: _BD-ALIGN  ( n -- n' )  7 + -8 AND ;

: BIDI-WORK-BYTES  ( n -- bytes )
    DUP 3 * _BD-ALIGN SWAP 12 * _BD-ALIGN +
    _BD-DS-ENTRIES _BD-BS-ENTRIES + CELLS + ;

VARIABLE _BD-N
VARIABLE _BD-C-A     \ classes (input)
VARIABLE _BD-X-A     \ scalars (input) or 0
VARIABLE _BD-T-A     \ working types
VARIABLE _BD-L-A     \ levels (output)
VARIABLE _BD-E-A     \ explicit levels, kept for sos and eos
VARIABLE _BD-M-A     \ matching isolate partner, index + 1
VARIABLE _BD-S-A     \ current isolating run sequence
VARIABLE _BD-P-A     \ bracket pairs of the current sequence
VARIABLE _BD-DS-A    \ directional status stack
VARIABLE _BD-BS-A    \ bracket stack
VARIABLE _BD-PARA

: _BD-LAYOUT  ( work -- )
    DUP _BD-T-A !
    _BD-N @ + DUP _BD-L-A !
    _BD-N @ + DUP _BD-E-A !
    DROP _BD-T-A @ _BD-N @ 3 * _BD-ALIGN + DUP _BD-M-A !
    _BD-N @ 4 * + DUP _BD-S-A !
    _BD-N @ 4 * + DUP _BD-P-A !
    _BD-N @ 4 * + _BD-ALIGN DUP _BD-DS-A !
    _BD-DS-ENTRIES CELLS + _BD-BS-A ! ;

: _BD-CLASS    ( i -- c )   _BD-C-A @ + C@ ;
: _BD-TYPE@    ( i -- t )   _BD-T-A @ + C@ ;
: _BD-TYPE!    ( t i -- )   _BD-T-A @ + C! ;
: _BD-LEVEL@   ( i -- l )   _BD-L-A @ + C@ ;
: _BD-LEVEL!   ( l i -- )   _BD-L-A @ + C! ;
: _BD-EXPL@    ( i -- l )   _BD-E-A @ + C@ ;
: _BD-MATCH@   ( i -- j|-1 ) 4 * _BD-M-A @ + L@ 1- ;
: _BD-MATCH!   ( j i -- )   SWAP 1+ SWAP 4 * _BD-M-A @ + L! ;
: _BD-SEQ@     ( k -- i )   4 * _BD-S-A @ + L@ ;
: _BD-SEQ!     ( i k -- )   4 * _BD-S-A @ + L! ;
: _BD-K@       ( k -- t )   _BD-SEQ@ _BD-TYPE@ ;
: _BD-K!       ( t k -- )   _BD-SEQ@ _BD-TYPE! ;

\ Explicit embedding and override controls and BN are removed by X9.
: _BD-REMOVED-CLASS?  ( c -- flag )
    DUP UP-BC-BN = SWAP UP-BC-LRE UP-BC-LRI WITHIN OR ;
: _BD-REMOVED?  ( i -- flag )  _BD-CLASS _BD-REMOVED-CLASS? ;
: _BD-ISOLATE-INITIATOR?  ( c -- flag )  UP-BC-LRI UP-BC-PDI WITHIN ;

: BIDI-LEVELS  ( work -- addr )  DROP _BD-L-A @ ;

\ =====================================================================
\  §2 — Paragraph level (P2, P3) and matching isolates (BD9)
\ =====================================================================

VARIABLE _BD-FS-DEPTH

\ _BD-FIRST-STRONG ( start end -- 0 | 1 | -1 )
\   0 for L, 1 for R or AL, -1 when no strong character precedes a
\   paragraph separator; isolate content is skipped.
: _BD-FIRST-STRONG  ( start end -- level|-1 )
    0 _BD-FS-DEPTH !
    SWAP ?DO
        I _BD-CLASS
        DUP _BD-ISOLATE-INITIATOR? IF
            DROP 1 _BD-FS-DEPTH +!
        ELSE DUP UP-BC-PDI = IF
            DROP _BD-FS-DEPTH @ IF -1 _BD-FS-DEPTH +! THEN
        ELSE DUP UP-BC-B = IF
            DROP UNLOOP -1 EXIT
        ELSE
            _BD-FS-DEPTH @ 0= IF
                DUP UP-BC-L = IF DROP UNLOOP 0 EXIT THEN
                DUP UP-BC-R = OVER UP-BC-AL = OR IF DROP UNLOOP 1 EXIT THEN
            THEN
            DROP
        THEN THEN THEN
    LOOP
    -1 ;

VARIABLE _BD-SP

: _BD-MATCH-ISOLATES  ( -- )
    _BD-M-A @ _BD-N @ 4 * 0 FILL
    0 _BD-SP !
    _BD-N @ 0 ?DO
        I _BD-CLASS
        DUP _BD-ISOLATE-INITIATOR? IF
            DROP I _BD-SP @ _BD-SEQ! 1 _BD-SP +!
        ELSE DUP UP-BC-PDI = IF
            DROP _BD-SP @ IF
                -1 _BD-SP +! _BD-SP @ _BD-SEQ@
                DUP I SWAP _BD-MATCH!
                I _BD-MATCH!
            THEN
        ELSE
            UP-BC-B = IF 0 _BD-SP ! THEN
        THEN THEN
    LOOP ;

\ =====================================================================
\  §3 — Explicit levels and directions (X1 to X8)
\ =====================================================================
\
\  A stack entry is level | override << 8 | isolate << 16, where the
\  override is 0 for none, 1 for L, and 2 for R.

VARIABLE _BD-DSP
VARIABLE _BD-OVF-ISO
VARIABLE _BD-OVF-EMB
VARIABLE _BD-VALID-ISO

: _BD-DS-TOP       ( -- entry )  _BD-DSP @ 1- CELLS _BD-DS-A @ + @ ;
: _BD-DS-PUSH      ( entry -- )  _BD-DSP @ CELLS _BD-DS-A @ + ! 1 _BD-DSP +! ;
: _BD-DS-POP       ( -- )        -1 _BD-DSP +! ;
: _BD-TOP-LEVEL    ( -- l )      _BD-DS-TOP 255 AND ;
: _BD-TOP-ISOLATE? ( -- flag )   _BD-DS-TOP 16 RSHIFT 1 AND 0<> ;

: _BD-APPLY-OVERRIDE  ( i -- )
    _BD-DS-TOP 8 RSHIFT 255 AND ?DUP IF 1- SWAP _BD-TYPE! ELSE DROP THEN ;

: _BD-NEXT-LEVEL  ( rtl? -- level )
    _BD-TOP-LEVEL SWAP IF 1+ 1 OR ELSE 2 + -2 AND THEN ;

: _BD-ROOM?  ( level -- flag )
    _BD-MAX-DEPTH <= _BD-OVF-ISO @ 0= AND _BD-OVF-EMB @ 0= AND ;

: _BD-X-EMBEDDING  ( class i -- )
    _BD-TOP-LEVEL SWAP _BD-LEVEL!
    DUP UP-BC-RLE >= _BD-NEXT-LEVEL          ( class level )
    DUP _BD-ROOM? IF
        SWAP DUP UP-BC-RLO = IF DROP 2 ELSE UP-BC-LRO = IF 1 ELSE 0 THEN THEN
        8 LSHIFT OR _BD-DS-PUSH
    ELSE
        2DROP _BD-OVF-ISO @ 0= IF 1 _BD-OVF-EMB +! THEN
    THEN ;

: _BD-X-ISOLATE  ( class i -- )
    >R
    _BD-TOP-LEVEL R@ _BD-LEVEL!
    R@ _BD-APPLY-OVERRIDE
    DUP UP-BC-FSI = IF
        DROP R@ 1+ R@ _BD-MATCH@ DUP 0< IF DROP _BD-N @ THEN
        _BD-FIRST-STRONG 1 =
    ELSE
        UP-BC-RLI =
    THEN
    R> DROP
    _BD-NEXT-LEVEL
    DUP _BD-ROOM? IF
        1 _BD-VALID-ISO +! 65536 OR _BD-DS-PUSH
    ELSE
        DROP 1 _BD-OVF-ISO +!
    THEN ;

: _BD-X-PDI  ( i -- )
    _BD-OVF-ISO @ IF
        -1 _BD-OVF-ISO +!
    ELSE _BD-VALID-ISO @ IF
        0 _BD-OVF-EMB !
        BEGIN _BD-TOP-ISOLATE? 0= WHILE _BD-DS-POP REPEAT
        _BD-DS-POP -1 _BD-VALID-ISO +!
    THEN THEN
    _BD-TOP-LEVEL OVER _BD-LEVEL!
    _BD-APPLY-OVERRIDE ;

: _BD-X-PDF  ( i -- )
    _BD-TOP-LEVEL SWAP _BD-LEVEL!
    _BD-OVF-ISO @ IF EXIT THEN
    _BD-OVF-EMB @ IF -1 _BD-OVF-EMB +! EXIT THEN
    _BD-TOP-ISOLATE? 0= _BD-DSP @ 2 >= AND IF _BD-DS-POP THEN ;

: _BD-EXPLICIT  ( -- )
    0 _BD-DSP ! _BD-PARA @ _BD-DS-PUSH
    0 _BD-OVF-ISO ! 0 _BD-OVF-EMB ! 0 _BD-VALID-ISO !
    _BD-N @ 0 ?DO
        I _BD-CLASS DUP I _BD-TYPE!
        DUP UP-BC-LRE UP-BC-PDF WITHIN IF
            I _BD-X-EMBEDDING
        ELSE DUP _BD-ISOLATE-INITIATOR? IF
            I _BD-X-ISOLATE
        ELSE DUP UP-BC-PDI = IF
            DROP I _BD-X-PDI
        ELSE DUP UP-BC-PDF = IF
            DROP I _BD-X-PDF
        ELSE DUP UP-BC-B = IF
            DROP _BD-PARA @ I _BD-LEVEL!
        ELSE UP-BC-BN = IF
            _BD-TOP-LEVEL I _BD-LEVEL!
        ELSE
            _BD-TOP-LEVEL I _BD-LEVEL!
            I _BD-APPLY-OVERRIDE
        THEN THEN THEN THEN THEN THEN
    LOOP
    _BD-L-A @ _BD-E-A @ _BD-N @ CMOVE ;

\ =====================================================================
\  §4 — Weak types (W1 to W7) over one isolating run sequence
\ =====================================================================

VARIABLE _BD-SEQ-N
VARIABLE _BD-SOS
VARIABLE _BD-EOS
VARIABLE _BD-SLEVEL
VARIABLE _BD-STRONG

: _BD-DIR  ( level -- type )  1 AND IF UP-BC-R ELSE UP-BC-L THEN ;

\ _BD-NEIGHBOUR ( i step -- level )
\   Explicit level of the nearest character not removed by X9 in the
\   direction of STEP, or the paragraph level when there is none.
: _BD-NEIGHBOUR  ( i step -- level )
    >R
    BEGIN R@ + DUP 0< 0= OVER _BD-N @ < AND WHILE
        DUP _BD-REMOVED? 0= IF _BD-EXPL@ R> DROP EXIT THEN
    REPEAT
    DROP R> DROP _BD-PARA @ ;

: _BD-SOS-EOS  ( -- )
    0 _BD-SEQ@ _BD-EXPL@ DUP _BD-SLEVEL !
    0 _BD-SEQ@ -1 _BD-NEIGHBOUR MAX _BD-DIR _BD-SOS !
    _BD-SEQ-N @ 1- _BD-SEQ@                  ( last )
    DUP _BD-CLASS _BD-ISOLATE-INITIATOR? OVER _BD-MATCH@ 0< AND IF
        _BD-PARA @
    ELSE
        DUP 1 _BD-NEIGHBOUR
    THEN
    SWAP _BD-EXPL@ MAX _BD-DIR _BD-EOS ! ;

: _BD-W1  ( -- )
    _BD-SEQ-N @ 0 ?DO
        I _BD-K@ UP-BC-NSM = IF
            I 0= IF
                _BD-SOS @
            ELSE
                I 1- _BD-K@ DUP UP-BC-LRI UP-BC-PDI 1+ WITHIN IF
                    DROP UP-BC-ON
                THEN
            THEN
            I _BD-K!
        THEN
    LOOP ;

: _BD-W2-W3  ( -- )
    _BD-SOS @ _BD-STRONG !
    _BD-SEQ-N @ 0 ?DO
        I _BD-K@
        DUP UP-BC-L = OVER UP-BC-R = OR OVER UP-BC-AL = OR IF
            _BD-STRONG !
        ELSE
            UP-BC-EN = _BD-STRONG @ UP-BC-AL = AND IF UP-BC-AN I _BD-K! THEN
        THEN
    LOOP
    _BD-SEQ-N @ 0 ?DO
        I _BD-K@ UP-BC-AL = IF UP-BC-R I _BD-K! THEN
    LOOP ;

: _BD-W4  ( -- )
    _BD-SEQ-N @ 3 < IF EXIT THEN
    _BD-SEQ-N @ 1- 1 ?DO
        I _BD-K@
        DUP UP-BC-ES = IF
            DROP
            I 1- _BD-K@ UP-BC-EN = I 1+ _BD-K@ UP-BC-EN = AND IF
                UP-BC-EN I _BD-K!
            THEN
        ELSE UP-BC-CS = IF
            I 1- _BD-K@ DUP I 1+ _BD-K@ = OVER UP-BC-EN = 2 PICK UP-BC-AN = OR AND IF
                I _BD-K!
            ELSE DROP THEN
        THEN THEN
    LOOP ;

VARIABLE _BD-RUN-END

: _BD-ET-RUN-END  ( k -- end )
    BEGIN DUP _BD-SEQ-N @ < WHILE
        DUP _BD-K@ UP-BC-ET <> IF EXIT THEN
        1+
    REPEAT ;

: _BD-W5  ( -- )
    0 BEGIN DUP _BD-SEQ-N @ < WHILE
        DUP _BD-K@ UP-BC-ET = IF
            DUP _BD-ET-RUN-END _BD-RUN-END !
            DUP 0> IF DUP 1- _BD-K@ UP-BC-EN = ELSE 0 THEN
            _BD-RUN-END @ _BD-SEQ-N @ < IF
                _BD-RUN-END @ _BD-K@ UP-BC-EN = OR
            THEN
            IF
                _BD-RUN-END @ OVER ?DO UP-BC-EN I _BD-K! LOOP
            THEN
            DROP _BD-RUN-END @
        ELSE
            1+
        THEN
    REPEAT DROP ;

: _BD-W6-W7  ( -- )
    _BD-SEQ-N @ 0 ?DO
        I _BD-K@ DUP UP-BC-ES = OVER UP-BC-ET = OR SWAP UP-BC-CS = OR IF
            UP-BC-ON I _BD-K!
        THEN
    LOOP
    _BD-SOS @ _BD-STRONG !
    _BD-SEQ-N @ 0 ?DO
        I _BD-K@
        DUP UP-BC-L = OVER UP-BC-R = OR IF
            _BD-STRONG !
        ELSE
            UP-BC-EN = _BD-STRONG @ UP-BC-L = AND IF UP-BC-L I _BD-K! THEN
        THEN
    LOOP ;

\ =====================================================================
\  §5 — Paired brackets (BD16, N0)
\ =====================================================================

VARIABLE _BD-BSP       \ bracket stack depth
VARIABLE _BD-PAIRS     \ pairs found in the current sequence
VARIABLE _BD-E         \ embedding direction of the sequence

: _BD-PAIR@  ( p -- open close )
    8 * _BD-P-A @ + DUP L@ SWAP 4 + L@ ;

\ Insert a pair keeping the list sorted by opening position.
: _BD-ADD-PAIR  ( open close -- )
    _BD-PAIRS @                               ( open close p )
    BEGIN DUP 0> WHILE
        DUP 1- _BD-PAIR@ DROP 3 PICK > 0= IF
            8 * _BD-P-A @ + TUCK 4 + L! L!
            1 _BD-PAIRS +! EXIT
        THEN
        DUP 1- 8 * _BD-P-A @ + OVER 8 * _BD-P-A @ + 8 CMOVE
        1-
    REPEAT
    8 * _BD-P-A @ + TUCK 4 + L! L!
    1 _BD-PAIRS +! ;

: _BD-BS-ENTRY  ( d -- addr )  CELLS _BD-BS-A @ + ;

\ Canonical equivalents: U+2329 and U+232A pair as U+3008 and U+3009.
: _BD-CANONICAL-BRACKET  ( cp -- cp' )
    DUP 0x2329 = IF DROP 0x3008 EXIT THEN
    DUP 0x232A = IF DROP 0x3009 THEN ;

\ _BD-CLOSE ( cp k -- )  Match a closing bracket against the stack.
: _BD-CLOSE  ( cp k -- )
    _BD-BSP @
    BEGIN DUP 0> WHILE
        1-
        DUP _BD-BS-ENTRY @ 32 RSHIFT 3 PICK = IF
            DUP _BD-BS-ENTRY @ 0xFFFFFFFF AND     ( cp k d open )
            2 PICK _BD-ADD-PAIR
            _BD-BSP ! 2DROP EXIT
        THEN
    REPEAT
    DROP 2DROP ;

: _BD-FIND-PAIRS  ( -- )
    0 _BD-PAIRS ! 0 _BD-BSP !
    _BD-SEQ-N @ 0 ?DO
        I _BD-K@ UP-BC-ON = IF
            I _BD-SEQ@ 4 * _BD-X-A @ + L@ _BD-CANONICAL-BRACKET
            DUP UP-BRACKET                   ( cp pair type )
            DUP 1 = IF
                DROP NIP
                _BD-BSP @ _BD-BS-ENTRIES = IF DROP UNLOOP EXIT THEN
                32 LSHIFT I OR _BD-BSP @ _BD-BS-ENTRY !
                1 _BD-BSP +!
            ELSE 2 = IF
                DROP I _BD-CLOSE
            ELSE
                2DROP
            THEN THEN
        THEN
    LOOP ;

: _BD-STRONG-OF  ( type -- dir | -1 )
    DUP UP-BC-L = IF EXIT THEN
    DUP UP-BC-R = OVER UP-BC-AL = OR OVER UP-BC-EN = OR SWAP UP-BC-AN = OR IF
        UP-BC-R
    ELSE -1 THEN ;

VARIABLE _BD-FOUND-E
VARIABLE _BD-FOUND-O

: _BD-SET-BRACKET  ( dir k -- )
    2DUP _BD-K!
    1+ BEGIN DUP _BD-SEQ-N @ < WHILE
        DUP _BD-SEQ@ _BD-CLASS UP-BC-NSM <> IF 2DROP EXIT THEN
        2DUP _BD-K!
        1+
    REPEAT 2DROP ;

: _BD-N0-PAIR  ( open close -- )
    0 _BD-FOUND-E ! 0 _BD-FOUND-O !
    2DUP SWAP 1+ ?DO                         \ strong types inside the pair
        I _BD-K@ _BD-STRONG-OF
        DUP _BD-E @ = IF DROP -1 _BD-FOUND-E ! LEAVE THEN
        0< 0= IF -1 _BD-FOUND-O ! THEN
    LOOP                                     ( open close )
    _BD-FOUND-E @ IF
        _BD-E @
    ELSE _BD-FOUND-O @ IF                    \ context before the pair
        _BD-SOS @ 2 PICK
        BEGIN DUP 0> WHILE
            1- DUP _BD-K@ _BD-STRONG-OF DUP 0< 0= IF NIP NIP 0 ELSE DROP THEN
        REPEAT DROP                          ( open close context )
        DUP _BD-E @ <> IF ELSE DROP _BD-E @ THEN
    ELSE
        2DROP EXIT
    THEN THEN                                ( open close dir )
    TUCK OVER _BD-SET-BRACKET                ( open dir close ) ( sets close )
    DROP SWAP _BD-SET-BRACKET ;

: _BD-N0  ( -- )
    _BD-X-A @ 0= IF EXIT THEN
    _BD-FIND-PAIRS
    _BD-PAIRS @ 0 ?DO
        I _BD-PAIR@ _BD-N0-PAIR
    LOOP ;

\ =====================================================================
\  §6 — Neutrals (N1, N2) and implicit levels (I1, I2)
\ =====================================================================

: _BD-NEUTRAL?  ( type -- flag )
    DUP UP-BC-B UP-BC-ON 1+ WITHIN            \ B S WS ON
    SWAP UP-BC-LRI UP-BC-PDI 1+ WITHIN OR ;    \ LRI RLI FSI PDI

: _BD-SIDE  ( type -- dir | -1 )
    DUP UP-BC-L = IF EXIT THEN
    DUP UP-BC-R = OVER UP-BC-EN = OR SWAP UP-BC-AN = OR IF UP-BC-R ELSE -1 THEN ;

: _BD-NEUTRAL-END  ( k -- end )
    BEGIN DUP _BD-SEQ-N @ < WHILE
        DUP _BD-K@ _BD-NEUTRAL? 0= IF EXIT THEN
        1+
    REPEAT ;

: _BD-N1-N2  ( -- )
    0 BEGIN DUP _BD-SEQ-N @ < WHILE
        DUP _BD-K@ _BD-NEUTRAL? IF
            DUP _BD-NEUTRAL-END _BD-RUN-END !
            DUP 0= IF _BD-SOS @ ELSE DUP 1- _BD-K@ _BD-SIDE THEN   ( k before )
            _BD-RUN-END @ _BD-SEQ-N @ = IF
                _BD-EOS @
            ELSE
                _BD-RUN-END @ _BD-K@ _BD-SIDE
            THEN                                                 ( k before after )
            OVER = OVER 0< 0= AND 0= IF DROP _BD-E @ THEN      ( k dir )
            _BD-RUN-END @ ROT ?DO DUP I _BD-K! LOOP
            DROP _BD-RUN-END @
        ELSE
            1+
        THEN
    REPEAT DROP ;

: _BD-IMPLICIT  ( -- )
    _BD-SEQ-N @ 0 ?DO
        I _BD-K@ _BD-SLEVEL @
        DUP 1 AND IF
            SWAP DUP UP-BC-L = OVER UP-BC-EN = OR SWAP UP-BC-AN = OR IF 1+ THEN
        ELSE
            SWAP DUP UP-BC-R = IF
                DROP 1+
            ELSE DUP UP-BC-AN = SWAP UP-BC-EN = OR IF
                2 +
            THEN THEN
        THEN
        I _BD-SEQ@ _BD-LEVEL!
    LOOP ;

: _BD-RESOLVE-SEQUENCE  ( -- )
    _BD-SOS-EOS
    _BD-SLEVEL @ _BD-DIR _BD-E !
    _BD-W1 _BD-W2-W3 _BD-W4 _BD-W5 _BD-W6-W7
    _BD-N0
    _BD-N1-N2
    _BD-IMPLICIT ;

\ =====================================================================
\  §7 — Isolating run sequences (X9, X10) and line rules (L1)
\ =====================================================================

\ A level run starts at I when the nearest earlier character not removed
\ by X9 has a different explicit level, or there is none.
: _BD-RUN-START?  ( i -- flag )
    DUP _BD-EXPL@ SWAP
    BEGIN 1- DUP 0< 0= WHILE
        DUP _BD-REMOVED? 0= IF _BD-EXPL@ <> EXIT THEN
    REPEAT
    2DROP -1 ;

\ Append the level run that starts at START to the current sequence.
: _BD-APPEND-RUN  ( start -- )
    DUP _BD-EXPL@ SWAP                        ( level i )
    BEGIN DUP _BD-N @ < WHILE
        DUP _BD-REMOVED? 0= IF
            2DUP _BD-EXPL@ <> IF 2DROP EXIT THEN
            DUP _BD-SEQ-N @ _BD-SEQ! 1 _BD-SEQ-N +!
        THEN
        1+
    REPEAT 2DROP ;

\ While the sequence ends in an isolate initiator with a matching PDI
\ that starts a run, continue with that run.
: _BD-CHAIN-RUNS  ( -- )
    BEGIN
        _BD-SEQ-N @ 1- _BD-SEQ@               ( last )
        DUP _BD-CLASS _BD-ISOLATE-INITIATOR? OVER _BD-MATCH@ 0< 0= AND IF
            _BD-MATCH@ DUP _BD-RUN-START? IF
                _BD-APPEND-RUN 0
            ELSE
                DROP -1
            THEN
        ELSE
            DROP -1
        THEN
    UNTIL ;

: _BD-SEQUENCES  ( -- )
    _BD-N @ 0 ?DO
        I _BD-REMOVED? 0= IF
            I _BD-RUN-START? IF
                I _BD-CLASS UP-BC-PDI = I _BD-MATCH@ 0< 0= AND 0= IF
                    0 _BD-SEQ-N !
                    I _BD-APPEND-RUN
                    _BD-CHAIN-RUNS
                    _BD-RESOLVE-SEQUENCE
                THEN
            THEN
        THEN
    LOOP ;

VARIABLE _BD-TRAILING

: BIDI-TRAILING?  ( class -- flag )
    DUP UP-BC-WS = OVER UP-BC-LRI UP-BC-PDI 1+ WITHIN OR
    SWAP _BD-REMOVED-CLASS? OR ;

: _BD-L1  ( -- )
    -1 _BD-TRAILING !
    _BD-N @ BEGIN DUP 0> WHILE
        1-
        DUP _BD-CLASS
        DUP UP-BC-S = OVER UP-BC-B = OR IF
            DROP _BD-PARA @ OVER _BD-LEVEL! -1 _BD-TRAILING !
        ELSE
            BIDI-TRAILING? IF
                _BD-TRAILING @ IF _BD-PARA @ OVER _BD-LEVEL! THEN
            ELSE
                0 _BD-TRAILING !
            THEN
        THEN
    REPEAT DROP ;

: _BD-MARK-REMOVED  ( -- )
    _BD-N @ 0 ?DO
        I _BD-REMOVED? IF BIDI-REMOVED I _BD-LEVEL! THEN
    LOOP ;

\ =====================================================================
\  §8 — Public words
\ =====================================================================

: BIDI-RESOLVE  ( classes scalars n direction work -- paragraph )
    >R >R
    _BD-N ! _BD-X-A ! _BD-C-A !
    R> R> _BD-LAYOUT                          ( direction )
    DUP BIDI-AUTO = IF
        DROP 0 _BD-N @ _BD-FIRST-STRONG 0 MAX
    ELSE
        BIDI-RTL = IF 1 ELSE 0 THEN
    THEN _BD-PARA !
    _BD-N @ 0= IF _BD-PARA @ EXIT THEN
    _BD-MATCH-ISOLATES
    _BD-EXPLICIT
    _BD-SEQUENCES
    _BD-L1
    _BD-MARK-REMOVED
    _BD-PARA @ ;

VARIABLE _BD-RO-L
VARIABLE _BD-RO-O
VARIABLE _BD-RO-M
VARIABLE _BD-RO-HI
VARIABLE _BD-RO-LO

: _BD-RO-LEVEL  ( k -- level )  4 * _BD-RO-O @ + L@ _BD-RO-L @ + C@ ;

\ Reverse ORDER entries [a, b).
: _BD-RO-REVERSE  ( a b -- )
    1- BEGIN 2DUP < WHILE
        OVER 4 * _BD-RO-O @ + DUP L@          ( a b pa va )
        2 PICK 4 * _BD-RO-O @ + DUP L@        ( a b pa va pb vb )
        ROT SWAP >R SWAP L! R> SWAP L!
        SWAP 1+ SWAP 1-
    REPEAT 2DROP ;

: BIDI-REORDER  ( levels n order -- m )
    _BD-RO-O ! SWAP _BD-RO-L !
    0 _BD-RO-M !
    0 ?DO
        I _BD-RO-L @ + C@ BIDI-REMOVED <> IF
            I _BD-RO-M @ 4 * _BD-RO-O @ + L!
            1 _BD-RO-M +!
        THEN
    LOOP
    _BD-RO-M @ 0= IF 0 EXIT THEN
    \ Reverse from the highest level down to the lowest odd level.  With
    \ no odd level every run would be reversed an even number of times.
    0 _BD-RO-HI ! 128 _BD-RO-LO !
    _BD-RO-M @ 0 ?DO
        I _BD-RO-LEVEL
        DUP _BD-RO-HI @ MAX _BD-RO-HI !
        DUP 1 AND IF _BD-RO-LO @ MIN _BD-RO-LO ! ELSE DROP THEN
    LOOP
    _BD-RO-LO @ _BD-RO-HI @                   ( lowest-odd level )
    BEGIN 2DUP <= WHILE
        0 BEGIN DUP _BD-RO-M @ < WHILE
            DUP _BD-RO-LEVEL 2 PICK >= IF
                DUP BEGIN DUP _BD-RO-M @ < IF DUP _BD-RO-LEVEL 3 PICK >= ELSE 0 THEN WHILE 1+ REPEAT
                2DUP _BD-RO-REVERSE NIP
            ELSE
                1+
            THEN
        REPEAT DROP
        1-
    REPEAT 2DROP
    _BD-RO-M @ ;

\ =====================================================================
\  §9 — Guard (Concurrency Safety)
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _bidi-guard

' BIDI-RESOLVE  CONSTANT _bidi-resolve-xt
' BIDI-REORDER  CONSTANT _bidi-reorder-xt

: BIDI-RESOLVE  _bidi-resolve-xt _bidi-guard WITH-GUARD ;
: BIDI-REORDER  _bidi-reorder-xt _bidi-guard WITH-GUARD ;
[THEN] [THEN]
