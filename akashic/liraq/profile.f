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
\   PP-NAME      PP-VERSION   PP-DESC?     PP-VALID?
\   PP-CAPS-COUNT  PP-HAS-CAP?
\   PP-DEFAULT   PP-ETYPE     PP-ROLE      PP-STATE   PP-IMPORTANCE
\   PP-DENSITY   PP-HIGH-CONTRAST
\   PP-ELEM-CAT  PP-SET-TYPE  PP-SET-ROLE  PP-SET-STATE  PP-SET-IMP
\   PP-CLEAR-CTX PP-GET
\
\ Prefix: PP-   (public API)
\         _PP-  (internal helpers)
\
\ Load with:   REQUIRE profile.f

REQUIRE ../utils/yaml.f
REQUIRE ../utils/string.f

PROVIDED akashic-pp

\ =====================================================================
\  Error Handling
\ =====================================================================

VARIABLE PP-ERR
0 PP-ERR !

1 CONSTANT PP-E-NOT-FOUND       \ property not found through cascade
2 CONSTANT PP-E-BAD-PROFILE     \ missing profile: header or capabilities

: PP-FAIL      ( code -- )  PP-ERR ! ;
: PP-OK?       ( -- flag )  PP-ERR @ 0= ;
: PP-CLEAR-ERR ( -- )       0 PP-ERR ! ;

\ =====================================================================
\  Profile Metadata
\ =====================================================================

\ PP-NAME ( p-a p-l -- str-a str-l )
\   Extract profile name string.  Aborts if profile.name absent.
: PP-NAME  ( p-a p-l -- str-a str-l )
    S" profile" YAML-KEY S" name" YAML-KEY YAML-GET-STRING ;

\ PP-VERSION ( p-a p-l -- str-a str-l )
\   Extract profile version string.
: PP-VERSION  ( p-a p-l -- str-a str-l )
    S" profile" YAML-KEY S" version" YAML-KEY YAML-GET-STRING ;

\ PP-DESC? ( p-a p-l -- str-a str-l flag )
\   Extract optional profile description.
\   Returns ( str-a str-l -1 ) if present, ( 0 0 0 ) if absent.
: PP-DESC?  ( p-a p-l -- str-a str-l flag )
    S" profile" YAML-KEY S" description" YAML-KEY?
    IF YAML-GET-STRING -1 ELSE 0 THEN ;

\ PP-CAPS-COUNT ( p-a p-l -- n )
\   Number of capabilities declared by the profile.
: PP-CAPS-COUNT  ( p-a p-l -- n )
    S" profile" YAML-KEY S" capabilities" YAML-KEY
    YAML-ENTER YAML-FLOW-COUNT ;

\ PP-HAS-CAP? ( p-a p-l cap-a cap-l -- flag )
\   Does the profile's capabilities array contain the given string?
VARIABLE _PHC-CA
VARIABLE _PHC-CL

: PP-HAS-CAP?  ( p-a p-l cap-a cap-l -- flag )
    _PHC-CL ! _PHC-CA !
    S" profile" YAML-KEY? 0= IF 2DROP 0 EXIT THEN
    S" capabilities" YAML-KEY? 0= IF 0 EXIT THEN
    YAML-ENTER
    BEGIN
        YAML-SKIP-WS
        DUP 0> WHILE
        OVER C@ 93 = IF 2DROP 0 EXIT THEN        \ ]
        2DUP YAML-GET-STRING _PHC-CA @ _PHC-CL @ STR-STR=
        IF 2DROP -1 EXIT THEN
        YAML-FLOW-NEXT 0= IF 0 EXIT THEN
    REPEAT
    2DROP 0 ;

\ PP-VALID? ( p-a p-l -- flag )
\   Does this YAML document have a valid profile header with
\   at least name and capabilities?
: PP-VALID?  ( p-a p-l -- flag )
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

\ PP-ELEM-CAT ( type-a type-l -- cat-a cat-l )
\   Map a UIDL element type name to its default cascade category.
: PP-ELEM-CAT  ( type-a type-l -- cat-a cat-l )
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

VARIABLE _PP-PA   \ saved property addr
VARIABLE _PP-PL   \ saved property len

\ PP-DEFAULT ( p-a p-l cat-a cat-l prop-a prop-l -- val-a val-l flag )
\   Look up: defaults.<category>.<property>
: PP-DEFAULT  ( p-a p-l cat-a cat-l prop-a prop-l -- val-a val-l flag )
    _PP-PL ! _PP-PA !   2>R
    S" defaults" YAML-KEY? 0= IF 2R> 2DROP 0 EXIT THEN
    2R> YAML-KEY? 0= IF 0 EXIT THEN
    _PP-PA @ _PP-PL @ YAML-KEY? ;

\ PP-ETYPE ( p-a p-l type-a type-l prop-a prop-l -- val-a val-l flag )
\   Look up: element-types.<type>.<property>
: PP-ETYPE  ( p-a p-l type-a type-l prop-a prop-l -- val-a val-l flag )
    _PP-PL ! _PP-PA !   2>R
    S" element-types" YAML-KEY? 0= IF 2R> 2DROP 0 EXIT THEN
    2R> YAML-KEY? 0= IF 0 EXIT THEN
    _PP-PA @ _PP-PL @ YAML-KEY? ;

\ PP-ROLE ( p-a p-l role-a role-l prop-a prop-l -- val-a val-l flag )
\   Look up: roles.<role>.<property>
: PP-ROLE  ( p-a p-l role-a role-l prop-a prop-l -- val-a val-l flag )
    _PP-PL ! _PP-PA !   2>R
    S" roles" YAML-KEY? 0= IF 2R> 2DROP 0 EXIT THEN
    2R> YAML-KEY? 0= IF 0 EXIT THEN
    _PP-PA @ _PP-PL @ YAML-KEY? ;

\ PP-STATE ( p-a p-l state-a state-l prop-a prop-l -- val-a val-l flag )
\   Look up: states.<state>.<property>
: PP-STATE  ( p-a p-l state-a state-l prop-a prop-l -- val-a val-l flag )
    _PP-PL ! _PP-PA !   2>R
    S" states" YAML-KEY? 0= IF 2R> 2DROP 0 EXIT THEN
    2R> YAML-KEY? 0= IF 0 EXIT THEN
    _PP-PA @ _PP-PL @ YAML-KEY? ;

\ PP-IMPORTANCE ( p-a p-l imp-a imp-l prop-a prop-l -- val-a val-l flag )
\   Look up: importance.<level>.<property>
: PP-IMPORTANCE  ( p-a p-l imp-a imp-l prop-a prop-l -- val-a val-l flag )
    _PP-PL ! _PP-PA !   2>R
    S" importance" YAML-KEY? 0= IF 2R> 2DROP 0 EXIT THEN
    2R> YAML-KEY? 0= IF 0 EXIT THEN
    _PP-PA @ _PP-PL @ YAML-KEY? ;

\ PP-DENSITY ( p-a p-l name-a name-l key-a key-l -- val-a val-l flag )
\   Look up: density.<name>.<key>
\   E.g. PP-DENSITY S" compact" S" defaults.content.font-size"
: PP-DENSITY  ( p-a p-l name-a name-l key-a key-l -- val-a val-l flag )
    _PP-PL ! _PP-PA !   2>R
    S" density" YAML-KEY? 0= IF 2R> 2DROP 0 EXIT THEN
    2R> YAML-KEY? 0= IF 0 EXIT THEN
    _PP-PA @ _PP-PL @ YAML-KEY? ;

\ PP-HIGH-CONTRAST ( p-a p-l key-a key-l -- val-a val-l flag )
\   Look up: high-contrast.<key>
\   E.g. PP-HIGH-CONTRAST S" foreground"
: PP-HIGH-CONTRAST  ( p-a p-l key-a key-l -- val-a val-l flag )
    2>R
    S" high-contrast" YAML-KEY? 0= IF 2R> 2DROP 0 EXIT THEN
    2R> YAML-KEY? ;

\ =====================================================================
\  Cascade Context
\ =====================================================================
\
\ Instead of passing all cascade parameters on the stack for every
\ property lookup, set the context once and call PP-GET repeatedly.
\
\ Usage:
\   S" label" PP-SET-TYPE
\   S" navigation" PP-SET-ROLE
\   S" attended" PP-SET-STATE
\   prof-a prof-l S" color" PP-GET  ( -- val-a val-l flag )
\   prof-a prof-l S" font-size" PP-GET  ( -- val-a val-l flag )
\   PP-CLEAR-CTX

VARIABLE _PP-TYPE-A   VARIABLE _PP-TYPE-L
VARIABLE _PP-ROLE-A   VARIABLE _PP-ROLE-L
VARIABLE _PP-STATE-A  VARIABLE _PP-STATE-L
VARIABLE _PP-IMP-A    VARIABLE _PP-IMP-L
VARIABLE _PP-CAT-A    VARIABLE _PP-CAT-L

: PP-CLEAR-CTX  ( -- )
    0 _PP-TYPE-A !   0 _PP-TYPE-L !
    0 _PP-ROLE-A !   0 _PP-ROLE-L !
    0 _PP-STATE-A !  0 _PP-STATE-L !
    0 _PP-IMP-A !    0 _PP-IMP-L !
    0 _PP-CAT-A !    0 _PP-CAT-L ! ;

PP-CLEAR-CTX   \ initialize on load

\ PP-SET-TYPE ( type-a type-l -- )
\   Set element type for cascade.  Also auto-sets the default category.
: PP-SET-TYPE  ( type-a type-l -- )
    _PP-TYPE-L ! _PP-TYPE-A !
    _PP-TYPE-A @ _PP-TYPE-L @
    PP-ELEM-CAT _PP-CAT-L ! _PP-CAT-A ! ;

\ PP-SET-ROLE ( role-a role-l -- )
: PP-SET-ROLE  ( role-a role-l -- )
    _PP-ROLE-L ! _PP-ROLE-A ! ;

\ PP-SET-STATE ( state-a state-l -- )
: PP-SET-STATE  ( state-a state-l -- )
    _PP-STATE-L ! _PP-STATE-A ! ;

\ PP-SET-IMP ( imp-a imp-l -- )
\   Set importance level for cascade.
: PP-SET-IMP  ( imp-a imp-l -- )
    _PP-IMP-L ! _PP-IMP-A ! ;

\ =====================================================================
\  Cascade Resolver
\ =====================================================================

VARIABLE _PPG-PA    VARIABLE _PPG-PL    \ profile addr/len
VARIABLE _PPG-PRA   VARIABLE _PPG-PRL   \ property name (for re-use)
VARIABLE _PPG-VA    VARIABLE _PPG-VL    \ best result so far
VARIABLE _PPG-F                          \ found flag

\ PP-GET ( p-a p-l prop-a prop-l -- val-a val-l flag )
\   Resolve a property through the full cascade using the current
\   context (PP-SET-TYPE / PP-SET-ROLE / PP-SET-STATE / PP-SET-IMP).
\   Returns the most-specific (highest-priority) value found.
\   Cascade order: defaults → element-type → role → state → importance
\   Later matches override earlier ones.
: PP-GET  ( p-a p-l prop-a prop-l -- val-a val-l flag )
    PP-CLEAR-ERR
    _PPG-PRL ! _PPG-PRA !     \ save property name
    _PPG-PL ! _PPG-PA !       \ save profile
    0 _PPG-F !
    \ Layer 1: defaults.<category>.<property>
    _PP-CAT-L @ IF
        _PPG-PA @ _PPG-PL @  _PP-CAT-A @ _PP-CAT-L @
        _PPG-PRA @ _PPG-PRL @  PP-DEFAULT
        IF _PPG-VL ! _PPG-VA !  -1 _PPG-F ! ELSE 2DROP THEN
    THEN
    \ Layer 2: element-types.<type>.<property>
    _PP-TYPE-L @ IF
        _PPG-PA @ _PPG-PL @  _PP-TYPE-A @ _PP-TYPE-L @
        _PPG-PRA @ _PPG-PRL @  PP-ETYPE
        IF _PPG-VL ! _PPG-VA !  -1 _PPG-F ! ELSE 2DROP THEN
    THEN
    \ Layer 3: roles.<role>.<property>
    _PP-ROLE-L @ IF
        _PPG-PA @ _PPG-PL @  _PP-ROLE-A @ _PP-ROLE-L @
        _PPG-PRA @ _PPG-PRL @  PP-ROLE
        IF _PPG-VL ! _PPG-VA !  -1 _PPG-F ! ELSE 2DROP THEN
    THEN
    \ Layer 4: states.<state>.<property>
    _PP-STATE-L @ IF
        _PPG-PA @ _PPG-PL @  _PP-STATE-A @ _PP-STATE-L @
        _PPG-PRA @ _PPG-PRL @  PP-STATE
        IF _PPG-VL ! _PPG-VA !  -1 _PPG-F ! ELSE 2DROP THEN
    THEN
    \ Layer 5: importance.<level>.<property>
    _PP-IMP-L @ IF
        _PPG-PA @ _PPG-PL @  _PP-IMP-A @ _PP-IMP-L @
        _PPG-PRA @ _PPG-PRL @  PP-IMPORTANCE
        IF _PPG-VL ! _PPG-VA !  -1 _PPG-F ! ELSE 2DROP THEN
    THEN
    \ Return result
    _PPG-F @ IF
        _PPG-VA @ _PPG-VL @ -1
    ELSE
        PP-E-NOT-FOUND PP-FAIL  0 0 0
    THEN ;
