\ profile.f — LIRAQ Presentation Profile Parser (Spec §07)
\
\ Loads and queries YAML presentation profiles using akashic-yaml.
\ Implements the 6-level cascade resolution for single-capability profiles:
\   1. Capability defaults   (defaults.<category>.<property>)
\   2. Element-type defaults  (element-types.<type>.<property>)
\   3. Role overrides         (roles.<role>.<property>)
\   4. State overrides        (states.<state>.<property>)
\   5. Importance overrides   (importance.<level>.<property>)
\   6. Inline overrides       (handled by caller — present-* attributes)
\
\ Profile documents are YAML text (addr len).  All lookups are
\ cursor-based (zero-copy) via the akashic-yaml library.
\
\ Public API:
\   PROF-NAME      PROF-VERSION   PROF-DESC?     PROF-VALID?
\   PROF-CAPS-COUNT  PROF-HAS-CAP?
\   PROF-DEFAULT   PROF-ETYPE     PROF-ROLE      PROF-STATE   PROF-IMPORTANCE
\   PROF-DENSITY   PROF-HIGH-CONTRAST
\   PROF-ELEM-CAT  PROF-SET-TYPE  PROF-SET-ROLE  PROF-SET-STATE  PROF-SET-IMP
\   PROF-CLEAR-CTX PROF-GET
\
\ Prefix: PROF-   (public API)
\         _PRF-  (internal helpers)
\
\ Load with:   REQUIRE profile.f

REQUIRE ../utils/yaml.f
REQUIRE ../utils/string.f

PROVIDED akashic-profile

\ =====================================================================
\  Error Handling
\ =====================================================================

VARIABLE PROF-ERR
0 PROF-ERR !

1 CONSTANT PROF-E-NOT-FOUND       \ property not found through cascade
2 CONSTANT PROF-E-BAD-PROFILE     \ missing profile: header or capabilities

: PROF-FAIL      ( code -- )  PROF-ERR ! ;
: PROF-OK?       ( -- flag )  PROF-ERR @ 0= ;
: PROF-CLEAR-ERR ( -- )       0 PROF-ERR ! ;

\ =====================================================================
\  Profile Metadata
\ =====================================================================

\ PROF-NAME ( p-a p-l -- str-a str-l )
\   Extract profile name string.  Aborts if profile.name absent.
: PROF-NAME  ( p-a p-l -- str-a str-l )
    S" profile" YAML-KEY S" name" YAML-KEY YAML-GET-STRING ;

\ PROF-VERSION ( p-a p-l -- str-a str-l )
\   Extract profile version string.
: PROF-VERSION  ( p-a p-l -- str-a str-l )
    S" profile" YAML-KEY S" version" YAML-KEY YAML-GET-STRING ;

\ PROF-DESC? ( p-a p-l -- str-a str-l flag )
\   Extract optional profile description.
\   Returns ( str-a str-l -1 ) if present, ( 0 0 0 ) if absent.
: PROF-DESC?  ( p-a p-l -- str-a str-l flag )
    S" profile" YAML-KEY S" description" YAML-KEY?
    IF YAML-GET-STRING -1 ELSE 0 THEN ;

\ PROF-CAPS-COUNT ( p-a p-l -- n )
\   Number of capabilities declared by the profile.
: PROF-CAPS-COUNT  ( p-a p-l -- n )
    S" profile" YAML-KEY S" capabilities" YAML-KEY
    YAML-ENTER YAML-FLOW-COUNT ;

\ PROF-HAS-CAP? ( p-a p-l cap-a cap-l -- flag )
\   Does the profile's capabilities array contain the given string?
VARIABLE _PRFH-CA
VARIABLE _PRFH-CL

: PROF-HAS-CAP?  ( p-a p-l cap-a cap-l -- flag )
    _PRFH-CL ! _PRFH-CA !
    S" profile" YAML-KEY? 0= IF 2DROP 0 EXIT THEN
    S" capabilities" YAML-KEY? 0= IF 0 EXIT THEN
    YAML-ENTER
    BEGIN
        YAML-SKIP-WS
        DUP 0> WHILE
        OVER C@ 93 = IF 2DROP 0 EXIT THEN        \ ]
        2DUP YAML-GET-STRING _PRFH-CA @ _PRFH-CL @ STR-STR=
        IF 2DROP -1 EXIT THEN
        YAML-FLOW-NEXT 0= IF 0 EXIT THEN
    REPEAT
    2DROP 0 ;

\ PROF-VALID? ( p-a p-l -- flag )
\   Does this YAML document have a valid profile header with
\   at least name and capabilities?
: PROF-VALID?  ( p-a p-l -- flag )
    S" profile" YAML-KEY? 0= IF 2DROP 0 EXIT THEN
    2DUP S" name" YAML-KEY? NIP NIP 0= IF 2DROP 0 EXIT THEN
    S" capabilities" YAML-KEY? NIP NIP ;

\ =====================================================================
\  Element Category Classifier
\ =====================================================================
\
\ The LIRAQ spec defines 16 UIDL element types grouped into four
\ default categories for the cascade:
\   content:     label, indicator, media, canvas, symbol, meta
\   container:   region, group, collection, table
\   interactive: action, input, selector, toggle, range
\   separator:   separator

\ PROF-ELEM-CAT ( type-a type-l -- cat-a cat-l )
\   Map a UIDL element type name to its default cascade category.
: PROF-ELEM-CAT  ( type-a type-l -- cat-a cat-l )
    \ Interactive types (most common for cascade queries)
    2DUP S" action"   STR-STR= IF 2DROP S" interactive" EXIT THEN
    2DUP S" input"    STR-STR= IF 2DROP S" interactive" EXIT THEN
    2DUP S" selector" STR-STR= IF 2DROP S" interactive" EXIT THEN
    2DUP S" toggle"   STR-STR= IF 2DROP S" interactive" EXIT THEN
    2DUP S" range"    STR-STR= IF 2DROP S" interactive" EXIT THEN
    \ Container types
    2DUP S" region"     STR-STR= IF 2DROP S" container" EXIT THEN
    2DUP S" group"      STR-STR= IF 2DROP S" container" EXIT THEN
    2DUP S" collection" STR-STR= IF 2DROP S" container" EXIT THEN
    2DUP S" table"      STR-STR= IF 2DROP S" container" EXIT THEN
    \ Separator
    2DUP S" separator" STR-STR= IF 2DROP S" separator" EXIT THEN
    \ Everything else is content (label, indicator, media, canvas,
    \ symbol, meta, or any unknown type)
    2DROP S" content" ;

\ =====================================================================
\  Direct Layer Access
\ =====================================================================
\
\ Each layer accessor takes:
\   ( profile-a profile-l  key-a key-l  prop-a prop-l -- val-a val-l flag )
\ Where key is the subsection name (category, element-type, role, etc.)
\ and prop is the property name within that subsection.
\ Returns ( val-cursor-a val-cursor-l -1 ) on success,
\         ( 0 0 0 ) on not-found.

VARIABLE _PRF-PA   \ saved property addr
VARIABLE _PRF-PL   \ saved property len

\ PROF-DEFAULT ( p-a p-l cat-a cat-l prop-a prop-l -- val-a val-l flag )
\   Look up: defaults.<category>.<property>
: PROF-DEFAULT  ( p-a p-l cat-a cat-l prop-a prop-l -- val-a val-l flag )
    _PRF-PL ! _PRF-PA !   2>R
    S" defaults" YAML-KEY? 0= IF 2R> 2DROP 0 EXIT THEN
    2R> YAML-KEY? 0= IF 0 EXIT THEN
    _PRF-PA @ _PRF-PL @ YAML-KEY? ;

\ PROF-ETYPE ( p-a p-l type-a type-l prop-a prop-l -- val-a val-l flag )
\   Look up: element-types.<type>.<property>
: PROF-ETYPE  ( p-a p-l type-a type-l prop-a prop-l -- val-a val-l flag )
    _PRF-PL ! _PRF-PA !   2>R
    S" element-types" YAML-KEY? 0= IF 2R> 2DROP 0 EXIT THEN
    2R> YAML-KEY? 0= IF 0 EXIT THEN
    _PRF-PA @ _PRF-PL @ YAML-KEY? ;

\ PROF-ROLE ( p-a p-l role-a role-l prop-a prop-l -- val-a val-l flag )
\   Look up: roles.<role>.<property>
: PROF-ROLE  ( p-a p-l role-a role-l prop-a prop-l -- val-a val-l flag )
    _PRF-PL ! _PRF-PA !   2>R
    S" roles" YAML-KEY? 0= IF 2R> 2DROP 0 EXIT THEN
    2R> YAML-KEY? 0= IF 0 EXIT THEN
    _PRF-PA @ _PRF-PL @ YAML-KEY? ;

\ PROF-STATE ( p-a p-l state-a state-l prop-a prop-l -- val-a val-l flag )
\   Look up: states.<state>.<property>
: PROF-STATE  ( p-a p-l state-a state-l prop-a prop-l -- val-a val-l flag )
    _PRF-PL ! _PRF-PA !   2>R
    S" states" YAML-KEY? 0= IF 2R> 2DROP 0 EXIT THEN
    2R> YAML-KEY? 0= IF 0 EXIT THEN
    _PRF-PA @ _PRF-PL @ YAML-KEY? ;

\ PROF-IMPORTANCE ( p-a p-l imp-a imp-l prop-a prop-l -- val-a val-l flag )
\   Look up: importance.<level>.<property>
: PROF-IMPORTANCE  ( p-a p-l imp-a imp-l prop-a prop-l -- val-a val-l flag )
    _PRF-PL ! _PRF-PA !   2>R
    S" importance" YAML-KEY? 0= IF 2R> 2DROP 0 EXIT THEN
    2R> YAML-KEY? 0= IF 0 EXIT THEN
    _PRF-PA @ _PRF-PL @ YAML-KEY? ;

\ PROF-DENSITY ( p-a p-l name-a name-l key-a key-l -- val-a val-l flag )
\   Look up: density.<name>.<key>
\   E.g. PROF-DENSITY S" compact" S" defaults.content.font-size"
: PROF-DENSITY  ( p-a p-l name-a name-l key-a key-l -- val-a val-l flag )
    _PRF-PL ! _PRF-PA !   2>R
    S" density" YAML-KEY? 0= IF 2R> 2DROP 0 EXIT THEN
    2R> YAML-KEY? 0= IF 0 EXIT THEN
    _PRF-PA @ _PRF-PL @ YAML-KEY? ;

\ PROF-HIGH-CONTRAST ( p-a p-l key-a key-l -- val-a val-l flag )
\   Look up: high-contrast.<key>
\   E.g. PROF-HIGH-CONTRAST S" foreground"
: PROF-HIGH-CONTRAST  ( p-a p-l key-a key-l -- val-a val-l flag )
    2>R
    S" high-contrast" YAML-KEY? 0= IF 2R> 2DROP 0 EXIT THEN
    2R> YAML-KEY? ;

\ =====================================================================
\  Cascade Context
\ =====================================================================
\
\ Instead of passing all cascade parameters on the stack for every
\ property lookup, set the context once and call PROF-GET repeatedly.
\
\ Usage:
\   S" label" PROF-SET-TYPE
\   S" navigation" PROF-SET-ROLE
\   S" attended" PROF-SET-STATE
\   prof-a prof-l S" color" PROF-GET  ( -- val-a val-l flag )
\   prof-a prof-l S" font-size" PROF-GET  ( -- val-a val-l flag )
\   PROF-CLEAR-CTX

VARIABLE _PRF-TYPE-A   VARIABLE _PRF-TYPE-L
VARIABLE _PRF-ROLE-A   VARIABLE _PRF-ROLE-L
VARIABLE _PRF-STATE-A  VARIABLE _PRF-STATE-L
VARIABLE _PRF-IMP-A    VARIABLE _PRF-IMP-L
VARIABLE _PRF-CAT-A    VARIABLE _PRF-CAT-L

: PROF-CLEAR-CTX  ( -- )
    0 _PRF-TYPE-A !   0 _PRF-TYPE-L !
    0 _PRF-ROLE-A !   0 _PRF-ROLE-L !
    0 _PRF-STATE-A !  0 _PRF-STATE-L !
    0 _PRF-IMP-A !    0 _PRF-IMP-L !
    0 _PRF-CAT-A !    0 _PRF-CAT-L ! ;

PROF-CLEAR-CTX   \ initialize on load

\ PROF-SET-TYPE ( type-a type-l -- )
\   Set element type for cascade.  Also auto-sets the default category.
: PROF-SET-TYPE  ( type-a type-l -- )
    _PRF-TYPE-L ! _PRF-TYPE-A !
    _PRF-TYPE-A @ _PRF-TYPE-L @
    PROF-ELEM-CAT _PRF-CAT-L ! _PRF-CAT-A ! ;

\ PROF-SET-ROLE ( role-a role-l -- )
: PROF-SET-ROLE  ( role-a role-l -- )
    _PRF-ROLE-L ! _PRF-ROLE-A ! ;

\ PROF-SET-STATE ( state-a state-l -- )
: PROF-SET-STATE  ( state-a state-l -- )
    _PRF-STATE-L ! _PRF-STATE-A ! ;

\ PROF-SET-IMP ( imp-a imp-l -- )
\   Set importance level for cascade.
: PROF-SET-IMP  ( imp-a imp-l -- )
    _PRF-IMP-L ! _PRF-IMP-A ! ;

\ =====================================================================
\  Cascade Resolver
\ =====================================================================

VARIABLE _PRFG-PA    VARIABLE _PRFG-PL    \ profile addr/len
VARIABLE _PRFG-PRA   VARIABLE _PRFG-PRL   \ property name (for re-use)
VARIABLE _PRFG-VA    VARIABLE _PRFG-VL    \ best result so far
VARIABLE _PRFG-F                          \ found flag

\ PROF-GET ( p-a p-l prop-a prop-l -- val-a val-l flag )
\   Resolve a property through the full cascade using the current
\   context (PROF-SET-TYPE / PROF-SET-ROLE / PROF-SET-STATE / PROF-SET-IMP).
\   Returns the most-specific (highest-priority) value found.
\   Cascade order: defaults → element-type → role → state → importance
\   Later matches override earlier ones.
: PROF-GET  ( p-a p-l prop-a prop-l -- val-a val-l flag )
    PROF-CLEAR-ERR
    _PRFG-PRL ! _PRFG-PRA !     \ save property name
    _PRFG-PL ! _PRFG-PA !       \ save profile
    0 _PRFG-F !
    \ Layer 1: defaults.<category>.<property>
    _PRF-CAT-L @ IF
        _PRFG-PA @ _PRFG-PL @  _PRF-CAT-A @ _PRF-CAT-L @
        _PRFG-PRA @ _PRFG-PRL @  PROF-DEFAULT
        IF _PRFG-VL ! _PRFG-VA !  -1 _PRFG-F ! ELSE 2DROP THEN
    THEN
    \ Layer 2: element-types.<type>.<property>
    _PRF-TYPE-L @ IF
        _PRFG-PA @ _PRFG-PL @  _PRF-TYPE-A @ _PRF-TYPE-L @
        _PRFG-PRA @ _PRFG-PRL @  PROF-ETYPE
        IF _PRFG-VL ! _PRFG-VA !  -1 _PRFG-F ! ELSE 2DROP THEN
    THEN
    \ Layer 3: roles.<role>.<property>
    _PRF-ROLE-L @ IF
        _PRFG-PA @ _PRFG-PL @  _PRF-ROLE-A @ _PRF-ROLE-L @
        _PRFG-PRA @ _PRFG-PRL @  PROF-ROLE
        IF _PRFG-VL ! _PRFG-VA !  -1 _PRFG-F ! ELSE 2DROP THEN
    THEN
    \ Layer 4: states.<state>.<property>
    _PRF-STATE-L @ IF
        _PRFG-PA @ _PRFG-PL @  _PRF-STATE-A @ _PRF-STATE-L @
        _PRFG-PRA @ _PRFG-PRL @  PROF-STATE
        IF _PRFG-VL ! _PRFG-VA !  -1 _PRFG-F ! ELSE 2DROP THEN
    THEN
    \ Layer 5: importance.<level>.<property>
    _PRF-IMP-L @ IF
        _PRFG-PA @ _PRFG-PL @  _PRF-IMP-A @ _PRF-IMP-L @
        _PRFG-PRA @ _PRFG-PRL @  PROF-IMPORTANCE
        IF _PRFG-VL ! _PRFG-VA !  -1 _PRFG-F ! ELSE 2DROP THEN
    THEN
    \ Return result
    _PRFG-F @ IF
        _PRFG-VA @ _PRFG-VL @ -1
    ELSE
        PROF-E-NOT-FOUND PROF-FAIL  0 0 0
    THEN ;

\ =====================================================================
\  Auditory Property Constants (spec §5)
\ =====================================================================

: PROF-VOICE          S" voice" ;
: PROF-RATE           S" rate" ;
: PROF-PITCH          S" pitch" ;
: PROF-VOLUME         S" volume" ;
: PROF-PAUSE-BEFORE   S" pause-before" ;
: PROF-PAUSE-AFTER    S" pause-after" ;
: PROF-EARCON         S" earcon" ;
: PROF-EARCON-BEFORE  S" earcon-before" ;
: PROF-EARCON-AFTER   S" earcon-after" ;
: PROF-PRIORITY       S" priority" ;
: PROF-SONIFICATION   S" sonification" ;
: PROF-CUE-SPEECH     S" cue-speech" ;

\ =====================================================================
\  Tactile Property Constants (spec §6)
\ =====================================================================

: PROF-CELL-ROUTING       S" cell-routing" ;
: PROF-CONTRACTED-BRAILLE S" contracted-braille" ;
: PROF-SEPARATOR          S" separator" ;
: PROF-PADDING-CELLS      S" padding-cells" ;
: PROF-PREFIX             S" prefix" ;
: PROF-HAPTIC             S" haptic" ;
: PROF-PIN-FLASH          S" pin-flash" ;

\ =====================================================================
\  Multi-Capability Scoped Lookup (spec §7)
\ =====================================================================
\
\ For multi-cap profiles, properties may be nested under capability:
\   defaults:
\     visual:
\       content:
\         color: "#FF9900"
\     content:            ← unscoped fallback
\       font-size: 18
\
\ PROF-CAP-SECTION tries defaults.<cap>.<prop> first, falls back to
\ defaults.<prop>.

VARIABLE _PRF-CAP-A   VARIABLE _PRF-CAP-L    \ active capability

: PROF-SET-CAP  ( cap-a cap-l -- )  _PRF-CAP-L ! _PRF-CAP-A ! ;

: PROF-CLEAR-CAP  ( -- )  0 _PRF-CAP-A !  0 _PRF-CAP-L ! ;

VARIABLE _PRFC-PA   VARIABLE _PRFC-PL   \ saved property
VARIABLE _PRFC-CA   VARIABLE _PRFC-CL   \ saved cap name
VARIABLE _PRFC-DA   VARIABLE _PRFC-DL   \ saved defaults cursor

: PROF-CAP-SECTION  ( p-a p-l cap-a cap-l prop-a prop-l -- val-a val-l flag )
    _PRFC-PL ! _PRFC-PA !           \ save property
    _PRFC-CL ! _PRFC-CA !           \ save cap name
    \ Stack: ( p-a p-l )
    S" defaults" YAML-KEY?
    0= IF 0 EXIT THEN                \ no defaults -> ( 0 0 0 )
    _PRFC-DL ! _PRFC-DA !           \ save defaults cursor
    \ Try cap-scoped: defaults.<cap>.<prop>
    _PRFC-DA @ _PRFC-DL @ _PRFC-CA @ _PRFC-CL @ YAML-KEY?
    IF
        _PRFC-PA @ _PRFC-PL @ YAML-KEY?  \ defaults.<cap>.<prop>
        IF -1 EXIT THEN            \ found! return ( val-a val-l -1 )
        2DROP                      \ prop not in cap section
    ELSE
        2DROP                      \ cap section not found
    THEN
    \ Fallback: defaults.<prop> (unscoped)
    _PRFC-DA @ _PRFC-DL @ _PRFC-PA @ _PRFC-PL @ YAML-KEY? ;

\ =====================================================================
\  Profile Stacking (spec §8.3)
\ =====================================================================
\
\ PROF-STACK merges two profiles: B's properties override A's.
\ Implementation: stores both profile pointers, PROF-STACK-GET
\ checks B first, falls back to A.

VARIABLE _PRF-SA   VARIABLE _PRF-SL    \ stacked profile A
VARIABLE _PRF-SB   VARIABLE _PRF-SBL   \ stacked profile B

: PROF-STACK  ( a-a a-l b-a b-l -- )
    _PRF-SBL ! _PRF-SB !
    _PRF-SL !  _PRF-SA ! ;

: PROF-STACK-GET  ( prop-a prop-l -- val-a val-l flag )
    \ Try B first (overrides)
    2DUP _PRF-SB @ _PRF-SBL @ 2SWAP PROF-GET
    IF 2SWAP 2DROP -1 EXIT THEN
    2DROP
    \ Fall back to A
    _PRF-SA @ _PRF-SL @ 2SWAP PROF-GET ;

\ =====================================================================
\  Inline Override Support (spec §11)
\ =====================================================================
\
\ PROF-INLINE checks for present-<prop> in YAML element attributes
\ and overrides the matching profile property.

CREATE _PRF-IBUF 256 ALLOT    \ "present-<prop>" key buffer
VARIABLE _PRF-ILEN

: _PRF-BUILD-INLINE  ( prop-a prop-l -- buf-a buf-l )
    \ Build "present-<prop>" string in _PRF-IBUF
    S" present-" _PRF-IBUF SWAP MOVE
    8 _PRF-ILEN !   \ "present-" is 8 chars
    DUP _PRF-ILEN @ + 256 > IF 2DROP _PRF-IBUF 0 EXIT THEN
    _PRF-IBUF _PRF-ILEN @ + SWAP MOVE
    _PRF-ILEN +!
    _PRF-IBUF _PRF-ILEN @ ;

VARIABLE _PRFI-EA   VARIABLE _PRFI-EL   \ element YAML addr/len

: PROF-SET-ELEM  ( elem-a elem-l -- )  _PRFI-EL ! _PRFI-EA ! ;

: PROF-INLINE  ( prop-a prop-l val-a val-l -- out-a out-l )
    \ Check if element has present-<prop> attribute
    2SWAP 2DUP _PRF-BUILD-INLINE  ( val-a val-l  prop-a prop-l  ibuf-a ibuf-l )
    DUP 0= IF 2DROP 2DROP EXIT THEN   \ buffer overflow — keep original
    _PRFI-EA @ _PRFI-EL @ 2SWAP YAML-KEY?
    IF YAML-GET-STRING 2SWAP 2DROP 2SWAP 2DROP EXIT THEN  \ override found
    2DROP 2DROP ;   \ no override, original val already on stack

\ =====================================================================
\  Accommodation Support (spec §8.2)
\ =====================================================================
\
\ Flags for active accommodations.  Set via PROF-ACCOMMODATE, then
\ PROF-ACCOM-GET applies transformations to resolved values.

VARIABLE _PRF-ACCOM-LT    \ large-text flag
VARIABLE _PRF-ACCOM-HC    \ high-contrast flag
VARIABLE _PRF-ACCOM-RM    \ reduced-motion flag
VARIABLE _PRF-AA  VARIABLE _PRF-AL   \ accommodation YAML addr/len

: PROF-ACCOMMODATE  ( accom-a accom-l -- )
    _PRF-AL ! _PRF-AA !
    0 _PRF-ACCOM-LT !  0 _PRF-ACCOM-HC !  0 _PRF-ACCOM-RM !
    _PRF-AA @ _PRF-AL @ S" large-text" YAML-KEY?
    IF YAML-GET-STRING S" true" STR-STR= IF -1 _PRF-ACCOM-LT ! THEN
    ELSE 2DROP THEN
    _PRF-AA @ _PRF-AL @ S" high-contrast" YAML-KEY?
    IF YAML-GET-STRING S" true" STR-STR= IF -1 _PRF-ACCOM-HC ! THEN
    ELSE 2DROP THEN
    _PRF-AA @ _PRF-AL @ S" reduced-motion" YAML-KEY?
    IF YAML-GET-STRING S" true" STR-STR= IF -1 _PRF-ACCOM-RM ! THEN
    ELSE 2DROP THEN ;

: PROF-ACCOM-CLEAR  ( -- )
    0 _PRF-ACCOM-LT !  0 _PRF-ACCOM-HC !  0 _PRF-ACCOM-RM ! ;

: PROF-ACCOM-LT?  ( -- flag )  _PRF-ACCOM-LT @ ;
: PROF-ACCOM-HC?  ( -- flag )  _PRF-ACCOM-HC @ ;
: PROF-ACCOM-RM?  ( -- flag )  _PRF-ACCOM-RM @ ;

\ PROF-ACCOM-INT ( n prop-a prop-l -- n' )
\   Apply accommodation scaling to an integer value.
\   large-text + font-size → n * 3 / 2  (150%)
\   reduced-motion + animation-duration → 0
: PROF-ACCOM-INT  ( n prop-a prop-l -- n' )
    _PRF-ACCOM-LT @ IF
        2DUP S" font-size" STR-STR= IF 2DROP 3 * 2 / EXIT THEN
    THEN
    _PRF-ACCOM-RM @ IF
        2DUP S" animation-duration" STR-STR= IF 2DROP DROP 0 EXIT THEN
    THEN
    2DROP ;

\ =====================================================================
\  Profile Resolution (spec §8)
\ =====================================================================
\
\ Capability bits for subset matching.

1 CONSTANT PROF-CAP-VISUAL
2 CONSTANT PROF-CAP-AUDITORY
4 CONSTANT PROF-CAP-TACTILE

\ Resolution list: up to 8 profiles, 3 cells each (addr, len, bitcount)
CREATE _PRF-RLIST 8 3 * CELLS ALLOT
VARIABLE _PRF-RCNT

: _PRF-CAP-BIT  ( cap-a cap-l -- bit )
    2DUP S" visual"   STR-STR= IF 2DROP 1 EXIT THEN
    2DUP S" auditory"  STR-STR= IF 2DROP 2 EXIT THEN
    2DUP S" tactile"   STR-STR= IF 2DROP 4 EXIT THEN
    2DROP 0 ;

\ Compute bitmask from a profile's capabilities array
VARIABLE _PRF-RMASK

: _PRF-CAPS-MASK  ( p-a p-l -- mask )
    0 _PRF-RMASK !
    S" profile" YAML-KEY? 0= IF 2DROP 0 EXIT THEN
    S" capabilities" YAML-KEY? 0= IF 2DROP 0 EXIT THEN
    YAML-ENTER
    BEGIN
        YAML-SKIP-WS
        DUP 0> WHILE
        OVER C@ 93 = IF 2DROP _PRF-RMASK @ EXIT THEN   \ ]
        2DUP YAML-GET-STRING _PRF-CAP-BIT
        _PRF-RMASK @ OR _PRF-RMASK !
        YAML-FLOW-NEXT 0= IF 2DROP _PRF-RMASK @ EXIT THEN
    REPEAT
    2DROP _PRF-RMASK @ ;

\ Count set bits in a small integer (0-7)
: _PRF-BITCNT  ( n -- count )
    DUP 1 AND SWAP
    1 RSHIFT DUP 1 AND ROT + SWAP
    1 RSHIFT 1 AND + ;

\ PROF-RESOLVE  ( caps-mask  prof-addrs prof-lens prof-count -- best-a best-l flag )
\   Filter profiles whose caps are subset of caps-mask.
\   Return the most-specific (fewest extra caps) profile.
VARIABLE _PRF-RA   VARIABLE _PRF-RL   \ arrays
VARIABLE _PRF-RN                       \ count
VARIABLE _PRF-RMSK                     \ required mask
VARIABLE _PRF-BEST-A  VARIABLE _PRF-BEST-L
VARIABLE _PRF-BEST-BC

: PROF-RESOLVE  ( caps-mask  addrs lens count -- best-a best-l flag )
    _PRF-RN !  _PRF-RL !  _PRF-RA !  _PRF-RMSK !
    0 _PRF-BEST-A !  0 _PRF-BEST-L !  99 _PRF-BEST-BC !
    _PRF-RN @ 0 DO
        \ Get profile i's addr and len
        _PRF-RA @ I CELLS + @       \ addr
        _PRF-RL @ I CELLS + @       \ len
        2DUP _PRF-CAPS-MASK         \ ( addr len mask )
        DUP _PRF-RMSK @ AND _PRF-RMSK @ = IF
            \ caps are subset — check specificity
            _PRF-BITCNT              \ ( addr len bitcount )
            DUP _PRF-BEST-BC @ < IF
                _PRF-BEST-BC !
                _PRF-BEST-L !  _PRF-BEST-A !
            ELSE
                DROP 2DROP
            THEN
        ELSE
            DROP 2DROP
        THEN
    LOOP
    _PRF-BEST-A @ _PRF-BEST-L @ 2DUP OR IF -1 ELSE 0 THEN ;

\ =====================================================================
\  Profile → CSL Translation (spec bridge)
\ =====================================================================
\
\ Serialise resolved profile properties into CSL key:value text.

CREATE _PRF-CBUF 2048 ALLOT
VARIABLE _PRF-CLEN

: _PRF-CEMIT  ( c -- )
    _PRF-CBUF _PRF-CLEN @ + C!  1 _PRF-CLEN +! ;

: _PRF-CSTR  ( addr len -- )
    0 DO DUP I + C@ _PRF-CEMIT LOOP DROP ;

\ _PRF-CKV ( key-a key-l val-a val-l -- )
\   Append "key: val\n" to CSL buffer
: _PRF-CKV  ( key-a key-l val-a val-l -- )
    2SWAP _PRF-CSTR
    58 _PRF-CEMIT  32 _PRF-CEMIT   \ ": "
    _PRF-CSTR
    10 _PRF-CEMIT ;                 \ newline

\ Table of visual properties to try
CREATE _PRF-VKEYS
  \ Inline packed: 5 keys
  \ We store addr/len pairs at compile time

VARIABLE _PRF-TK-A  VARIABLE _PRF-TK-L   \ temp key

: _PRF-TRY-CSL  ( p-a p-l key-a key-l -- )
    _PRF-TK-L ! _PRF-TK-A !
    2DUP _PRF-TK-A @ _PRF-TK-L @ PROF-GET
    IF  \ found
        YAML-GET-STRING
        _PRF-TK-A @ _PRF-TK-L @ 2SWAP _PRF-CKV
        2DROP
    ELSE
        2DROP 2DROP
    THEN ;

: PROF-TO-CSL  ( p-a p-l buf max -- len )
    2DROP   \ ignore caller buf/max, use internal buffer
    0 _PRF-CLEN !
    \ Visual properties
    2DUP S" color"       _PRF-TRY-CSL
    2DUP S" font-size"   _PRF-TRY-CSL
    2DUP S" font-family" _PRF-TRY-CSL
    2DUP S" background"  _PRF-TRY-CSL
    2DUP S" font-weight" _PRF-TRY-CSL
    2DUP S" opacity"     _PRF-TRY-CSL
    \ Auditory properties (mapped to CSL names)
    2DUP S" voice"       _PRF-TRY-CSL
    2DUP S" rate"        _PRF-TRY-CSL
    2DUP S" pitch"       _PRF-TRY-CSL
    2DUP S" earcon"      _PRF-TRY-CSL
    2DUP S" cue-speech"  _PRF-TRY-CSL
    2DROP
    \ Copy to caller's buffer — but we return internal buf + len
    _PRF-CBUF _PRF-CLEN @ ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _lprof-guard

' PROF-FAIL       CONSTANT _prof-fail-xt
' PROF-OK?        CONSTANT _prof-ok-q-xt
' PROF-CLEAR-ERR  CONSTANT _prof-clear-err-xt
' PROF-NAME       CONSTANT _prof-name-xt
' PROF-VERSION    CONSTANT _prof-version-xt
' PROF-DESC?      CONSTANT _prof-desc-q-xt
' PROF-CAPS-COUNT CONSTANT _prof-caps-count-xt
' PROF-HAS-CAP?   CONSTANT _prof-has-cap-q-xt
' PROF-VALID?     CONSTANT _prof-valid-q-xt
' PROF-ELEM-CAT   CONSTANT _prof-elem-cat-xt
' PROF-DEFAULT    CONSTANT _prof-default-xt
' PROF-ETYPE      CONSTANT _prof-etype-xt
' PROF-ROLE       CONSTANT _prof-role-xt
' PROF-STATE      CONSTANT _prof-state-xt
' PROF-IMPORTANCE CONSTANT _prof-importance-xt
' PROF-DENSITY    CONSTANT _prof-density-xt
' PROF-HIGH-CONTRAST CONSTANT _prof-high-contrast-xt
' PROF-CLEAR-CTX  CONSTANT _prof-clear-ctx-xt
' PROF-SET-TYPE   CONSTANT _prof-set-type-xt
' PROF-SET-ROLE   CONSTANT _prof-set-role-xt
' PROF-SET-STATE  CONSTANT _prof-set-state-xt
' PROF-SET-IMP    CONSTANT _prof-set-imp-xt
' PROF-GET        CONSTANT _prof-get-xt
' PROF-VOICE      CONSTANT _prof-voice-xt
' PROF-RATE       CONSTANT _prof-rate-xt
' PROF-PITCH      CONSTANT _prof-pitch-xt
' PROF-VOLUME     CONSTANT _prof-volume-xt
' PROF-PAUSE-BEFORE CONSTANT _prof-pause-before-xt
' PROF-PAUSE-AFTER CONSTANT _prof-pause-after-xt
' PROF-EARCON     CONSTANT _prof-earcon-xt
' PROF-EARCON-BEFORE CONSTANT _prof-earcon-before-xt
' PROF-EARCON-AFTER CONSTANT _prof-earcon-after-xt
' PROF-PRIORITY   CONSTANT _prof-priority-xt
' PROF-SONIFICATION CONSTANT _prof-sonification-xt
' PROF-CUE-SPEECH CONSTANT _prof-cue-speech-xt
' PROF-CELL-ROUTING CONSTANT _prof-cell-routing-xt
' PROF-CONTRACTED-BRAILLE CONSTANT _prof-contracted-braille-xt
' PROF-SEPARATOR  CONSTANT _prof-separator-xt
' PROF-PADDING-CELLS CONSTANT _prof-padding-cells-xt
' PROF-PREFIX     CONSTANT _prof-prefix-xt
' PROF-HAPTIC     CONSTANT _prof-haptic-xt
' PROF-PIN-FLASH  CONSTANT _prof-pin-flash-xt
' PROF-SET-CAP    CONSTANT _prof-set-cap-xt
' PROF-CLEAR-CAP  CONSTANT _prof-clear-cap-xt
' PROF-CAP-SECTION CONSTANT _prof-cap-section-xt
' PROF-STACK      CONSTANT _prof-stack-xt
' PROF-STACK-GET  CONSTANT _prof-stack-get-xt
' PROF-SET-ELEM   CONSTANT _prof-set-elem-xt
' PROF-INLINE     CONSTANT _prof-inline-xt
' PROF-ACCOMMODATE CONSTANT _prof-accommodate-xt
' PROF-ACCOM-CLEAR CONSTANT _prof-accom-clear-xt
' PROF-ACCOM-LT?  CONSTANT _prof-accom-lt-q-xt
' PROF-ACCOM-HC?  CONSTANT _prof-accom-hc-q-xt
' PROF-ACCOM-RM?  CONSTANT _prof-accom-rm-q-xt
' PROF-ACCOM-INT  CONSTANT _prof-accom-int-xt
' PROF-RESOLVE    CONSTANT _prof-resolve-xt
' PROF-TO-CSL     CONSTANT _prof-to-csl-xt

: PROF-FAIL       _prof-fail-xt _lprof-guard WITH-GUARD ;
: PROF-OK?        _prof-ok-q-xt _lprof-guard WITH-GUARD ;
: PROF-CLEAR-ERR  _prof-clear-err-xt _lprof-guard WITH-GUARD ;
: PROF-NAME       _prof-name-xt _lprof-guard WITH-GUARD ;
: PROF-VERSION    _prof-version-xt _lprof-guard WITH-GUARD ;
: PROF-DESC?      _prof-desc-q-xt _lprof-guard WITH-GUARD ;
: PROF-CAPS-COUNT _prof-caps-count-xt _lprof-guard WITH-GUARD ;
: PROF-HAS-CAP?   _prof-has-cap-q-xt _lprof-guard WITH-GUARD ;
: PROF-VALID?     _prof-valid-q-xt _lprof-guard WITH-GUARD ;
: PROF-ELEM-CAT   _prof-elem-cat-xt _lprof-guard WITH-GUARD ;
: PROF-DEFAULT    _prof-default-xt _lprof-guard WITH-GUARD ;
: PROF-ETYPE      _prof-etype-xt _lprof-guard WITH-GUARD ;
: PROF-ROLE       _prof-role-xt _lprof-guard WITH-GUARD ;
: PROF-STATE      _prof-state-xt _lprof-guard WITH-GUARD ;
: PROF-IMPORTANCE _prof-importance-xt _lprof-guard WITH-GUARD ;
: PROF-DENSITY    _prof-density-xt _lprof-guard WITH-GUARD ;
: PROF-HIGH-CONTRAST _prof-high-contrast-xt _lprof-guard WITH-GUARD ;
: PROF-CLEAR-CTX  _prof-clear-ctx-xt _lprof-guard WITH-GUARD ;
: PROF-SET-TYPE   _prof-set-type-xt _lprof-guard WITH-GUARD ;
: PROF-SET-ROLE   _prof-set-role-xt _lprof-guard WITH-GUARD ;
: PROF-SET-STATE  _prof-set-state-xt _lprof-guard WITH-GUARD ;
: PROF-SET-IMP    _prof-set-imp-xt _lprof-guard WITH-GUARD ;
: PROF-GET        _prof-get-xt _lprof-guard WITH-GUARD ;
: PROF-VOICE      _prof-voice-xt _lprof-guard WITH-GUARD ;
: PROF-RATE       _prof-rate-xt _lprof-guard WITH-GUARD ;
: PROF-PITCH      _prof-pitch-xt _lprof-guard WITH-GUARD ;
: PROF-VOLUME     _prof-volume-xt _lprof-guard WITH-GUARD ;
: PROF-PAUSE-BEFORE _prof-pause-before-xt _lprof-guard WITH-GUARD ;
: PROF-PAUSE-AFTER _prof-pause-after-xt _lprof-guard WITH-GUARD ;
: PROF-EARCON     _prof-earcon-xt _lprof-guard WITH-GUARD ;
: PROF-EARCON-BEFORE _prof-earcon-before-xt _lprof-guard WITH-GUARD ;
: PROF-EARCON-AFTER _prof-earcon-after-xt _lprof-guard WITH-GUARD ;
: PROF-PRIORITY   _prof-priority-xt _lprof-guard WITH-GUARD ;
: PROF-SONIFICATION _prof-sonification-xt _lprof-guard WITH-GUARD ;
: PROF-CUE-SPEECH _prof-cue-speech-xt _lprof-guard WITH-GUARD ;
: PROF-CELL-ROUTING _prof-cell-routing-xt _lprof-guard WITH-GUARD ;
: PROF-CONTRACTED-BRAILLE _prof-contracted-braille-xt _lprof-guard WITH-GUARD ;
: PROF-SEPARATOR  _prof-separator-xt _lprof-guard WITH-GUARD ;
: PROF-PADDING-CELLS _prof-padding-cells-xt _lprof-guard WITH-GUARD ;
: PROF-PREFIX     _prof-prefix-xt _lprof-guard WITH-GUARD ;
: PROF-HAPTIC     _prof-haptic-xt _lprof-guard WITH-GUARD ;
: PROF-PIN-FLASH  _prof-pin-flash-xt _lprof-guard WITH-GUARD ;
: PROF-SET-CAP    _prof-set-cap-xt _lprof-guard WITH-GUARD ;
: PROF-CLEAR-CAP  _prof-clear-cap-xt _lprof-guard WITH-GUARD ;
: PROF-CAP-SECTION _prof-cap-section-xt _lprof-guard WITH-GUARD ;
: PROF-STACK      _prof-stack-xt _lprof-guard WITH-GUARD ;
: PROF-STACK-GET  _prof-stack-get-xt _lprof-guard WITH-GUARD ;
: PROF-SET-ELEM   _prof-set-elem-xt _lprof-guard WITH-GUARD ;
: PROF-INLINE     _prof-inline-xt _lprof-guard WITH-GUARD ;
: PROF-ACCOMMODATE _prof-accommodate-xt _lprof-guard WITH-GUARD ;
: PROF-ACCOM-CLEAR _prof-accom-clear-xt _lprof-guard WITH-GUARD ;
: PROF-ACCOM-LT?  _prof-accom-lt-q-xt _lprof-guard WITH-GUARD ;
: PROF-ACCOM-HC?  _prof-accom-hc-q-xt _lprof-guard WITH-GUARD ;
: PROF-ACCOM-RM?  _prof-accom-rm-q-xt _lprof-guard WITH-GUARD ;
: PROF-ACCOM-INT  _prof-accom-int-xt _lprof-guard WITH-GUARD ;
: PROF-RESOLVE    _prof-resolve-xt _lprof-guard WITH-GUARD ;
: PROF-TO-CSL     _prof-to-csl-xt _lprof-guard WITH-GUARD ;
[THEN] [THEN]
