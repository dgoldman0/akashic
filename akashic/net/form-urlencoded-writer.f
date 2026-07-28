\ =====================================================================
\  form-urlencoded-writer.f - Caller-owned bounded form body writer
\ =====================================================================
\  The writer composes complete application/x-www-form-urlencoded bodies
\  from independently encoded name/value components.  Its descriptor and
\  byte arena are supplied by the caller.  The module owns no mutable state.
\
\  FIELD qualifies and measures both borrowed components before touching
\  the arena.  It then stages the complete "&name=value" contribution in
\  the unpublished arena tail and advances length/count only after both
\  component encoders succeed with the measured total.  A failed staged
\  write clears that entire tail contribution and leaves the published form
\  unchanged.
\
\  Public API:
\    FUEW-SIZE
\    FUEW-STATUS-VALID?  ( status -- flag )
\    FUEW-VALID?         ( writer -- flag )
\    FUEW-INIT           ( body-a body-capacity writer -- status )
\    FUEW-FIELD
\      ( name-a name-u value-a value-u writer -- status )
\    FUEW-SEAL           ( writer -- status )
\    FUEW-BODY@          ( writer -- body-a body-u status )
\    FUEW-STATE@         ( writer -- state status )
\    FUEW-LENGTH@        ( writer -- length status )
\    FUEW-FIELD-COUNT@   ( writer -- count status )
\    FUEW-WIPE           ( writer -- status )
\ =====================================================================

PROVIDED akashic-fue-writer

REQUIRE form-urlencoded.f
REQUIRE ../utils/memory-span.f
REQUIRE ../utils/caller-span.f

\ =====================================================================
\  Public state and status vocabulary
\ =====================================================================

1 CONSTANT FUEW-STATE-BUILDING
2 CONSTANT FUEW-STATE-SEALED

0 CONSTANT FUEW-S-OK
1 CONSTANT FUEW-S-INVALID
2 CONSTANT FUEW-S-STATE
3 CONSTANT FUEW-S-CAPACITY
4 CONSTANT FUEW-S-ALIAS
5 CONSTANT FUEW-S-RANGE
6 CONSTANT FUEW-S-PROTECTED
7 CONSTANT FUEW-S-PLATFORM
8 CONSTANT FUEW-S-INTERNAL

: FUEW-STATUS-VALID?  ( status -- flag )
    DUP FUEW-S-OK >=
    SWAP FUEW-S-INTERNAL <= AND ;

\ =====================================================================
\  Caller-owned descriptor
\ =====================================================================

0x4655455752495445 CONSTANT _FUEW-MAGIC-VALUE  \ "FUEWRITE"

 0 CONSTANT _FUEW-MAGIC
 8 CONSTANT _FUEW-STATE
16 CONSTANT _FUEW-BODY
24 CONSTANT _FUEW-CAPACITY
32 CONSTANT _FUEW-LENGTH
40 CONSTANT _FUEW-FIELD-COUNT
48 CONSTANT FUEW-SIZE

: _FUEW.MAGIC       ( writer -- address ) _FUEW-MAGIC + ;
: FUEW.STATE        ( writer -- address ) _FUEW-STATE + ;
: FUEW.BODY         ( writer -- address ) _FUEW-BODY + ;
: FUEW.CAPACITY     ( writer -- address ) _FUEW-CAPACITY + ;
: FUEW.LENGTH       ( writer -- address ) _FUEW-LENGTH + ;
: FUEW.FIELD-COUNT  ( writer -- address ) _FUEW-FIELD-COUNT + ;

\ =====================================================================
\  Admission and structural validation
\ =====================================================================

: _FUEW-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF DROP FUEW-S-OK EXIT THEN
    DUP CALLER-SPAN-S-RANGE = IF DROP FUEW-S-RANGE EXIT THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP FUEW-S-PROTECTED EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP FUEW-S-PLATFORM EXIT
    THEN
    DROP FUEW-S-PLATFORM ;

: _FUEW-SPAN-STATUS  ( address length -- status )
    DUP 0< IF 2DROP FUEW-S-INVALID EXIT THEN
    DUP 0= IF 2DROP FUEW-S-OK EXIT THEN
    OVER 0= IF 2DROP FUEW-S-INVALID EXIT THEN
    CALLER-SPAN-STATUS _FUEW-CALLER>STATUS ;

: _FUEW-WRITER-STATUS  ( writer -- status )
    DUP 0= IF DROP FUEW-S-INVALID EXIT THEN
    DUP 7 AND IF DROP FUEW-S-INVALID EXIT THEN
    FUEW-SIZE _FUEW-SPAN-STATUS ;

: FUEW-VALID?  ( writer -- flag )
    DUP _FUEW-WRITER-STATUS ?DUP IF
        2DROP 0 EXIT
    THEN
    DUP _FUEW.MAGIC @ _FUEW-MAGIC-VALUE <> IF
        DROP 0 EXIT
    THEN
    DUP FUEW.STATE @
    DUP FUEW-STATE-BUILDING =
    SWAP FUEW-STATE-SEALED = OR 0= IF
        DROP 0 EXIT
    THEN
    DUP FUEW.CAPACITY @ DUP 0< IF
        2DROP 0 EXIT
    THEN
    DROP
    DUP FUEW.LENGTH @ DUP 0< IF
        2DROP 0 EXIT
    THEN
    DROP
    DUP FUEW.LENGTH @ OVER FUEW.CAPACITY @ U> IF
        DROP 0 EXIT
    THEN
    DUP FUEW.FIELD-COUNT @ DUP 0< IF
        2DROP 0 EXIT
    THEN
    OVER FUEW.LENGTH @ U> IF
        DROP 0 EXIT
    THEN
    DUP FUEW.FIELD-COUNT @ 0=
    OVER FUEW.LENGTH @ 0<> AND IF
        DROP 0 EXIT
    THEN
    DUP FUEW.BODY @ OVER FUEW.CAPACITY @
        _FUEW-SPAN-STATUS FUEW-S-OK <> IF
        DROP 0 EXIT
    THEN
    DUP FUEW.BODY @ OVER FUEW.CAPACITY @
    2 PICK FUEW-SIZE MSPAN-OVERLAP? IF
        DROP 0 EXIT
    THEN
    DROP -1 ;

\ =====================================================================
\  Initialization and result access
\ =====================================================================

: _FUEW-DROP3  ( x1 x2 x3 -- )
    2DROP DROP ;

: _FUEW-DROP5  ( x1 x2 x3 x4 x5 -- )
    2DROP 2DROP DROP ;

: _FUEW-RETURN3  ( x1 x2 x3 status -- status )
    >R _FUEW-DROP3 R> ;

: FUEW-INIT  ( body-a body-capacity writer -- status )
    DUP _FUEW-WRITER-STATUS ?DUP IF
        _FUEW-RETURN3 EXIT
    THEN
    2 PICK 2 PICK _FUEW-SPAN-STATUS ?DUP IF
        _FUEW-RETURN3 EXIT
    THEN
    2 PICK 2 PICK 2 PICK FUEW-SIZE MSPAN-OVERLAP? IF
        FUEW-S-ALIAS _FUEW-RETURN3 EXIT
    THEN

    \ A live descriptor may be rebound, but its old complete arena is
    \ cleared first.  A corrupt descriptor carrying our magic is rejected
    \ because its retained arena geometry cannot be trusted for cleanup.
    DUP _FUEW.MAGIC @ _FUEW-MAGIC-VALUE = IF
        DUP FUEW-VALID? 0= IF
            FUEW-S-INVALID _FUEW-RETURN3 EXIT
        THEN
        DUP FUEW.BODY @ OVER FUEW.CAPACITY @ 0 FILL
    THEN

    >R
    2DUP 0 FILL
    R@ FUEW-SIZE 0 FILL
    OVER R@ FUEW.BODY !
    DUP R@ FUEW.CAPACITY !
    FUEW-STATE-BUILDING R@ FUEW.STATE !
    _FUEW-MAGIC-VALUE R@ _FUEW.MAGIC !
    2DROP
    R> DROP
    FUEW-S-OK ;

: FUEW-STATE@  ( writer -- state status )
    DUP FUEW-VALID? 0= IF
        DROP 0 FUEW-S-INVALID EXIT
    THEN
    FUEW.STATE @ FUEW-S-OK ;

: FUEW-FIELD-COUNT@  ( writer -- count status )
    DUP FUEW-VALID? 0= IF
        DROP 0 FUEW-S-INVALID EXIT
    THEN
    FUEW.FIELD-COUNT @ FUEW-S-OK ;

: FUEW-LENGTH@  ( writer -- length status )
    DUP FUEW-VALID? 0= IF
        DROP 0 FUEW-S-INVALID EXIT
    THEN
    FUEW.LENGTH @ FUEW-S-OK ;

: FUEW-BODY@  ( writer -- body-a body-u status )
    DUP FUEW-VALID? 0= IF
        DROP 0 0 FUEW-S-INVALID EXIT
    THEN
    DUP FUEW.STATE @ FUEW-STATE-SEALED <> IF
        DROP 0 0 FUEW-S-STATE EXIT
    THEN
    DUP FUEW.BODY @ SWAP FUEW.LENGTH @ FUEW-S-OK ;

\ =====================================================================
\  Transactional field append
\ =====================================================================

-1 1 RSHIFT CONSTANT _FUEW-LENGTH-MAX

: _FUEW-FORM>STATUS  ( form-status -- status )
    DUP FORM-URLENCODED-S-OK = IF
        DROP FUEW-S-OK EXIT
    THEN
    DUP FORM-URLENCODED-S-INVALID = IF
        DROP FUEW-S-INVALID EXIT
    THEN
    DUP FORM-URLENCODED-S-CAPACITY = IF
        DROP FUEW-S-CAPACITY EXIT
    THEN
    DUP FORM-URLENCODED-S-ALIAS = IF
        DROP FUEW-S-ALIAS EXIT
    THEN
    DUP FORM-URLENCODED-S-RANGE = IF
        DROP FUEW-S-RANGE EXIT
    THEN
    DUP FORM-URLENCODED-S-PROTECTED = IF
        DROP FUEW-S-PROTECTED EXIT
    THEN
    DUP FORM-URLENCODED-S-PLATFORM = IF
        DROP FUEW-S-PLATFORM EXIT
    THEN
    DROP FUEW-S-INTERNAL ;

: _FUEW-MEASURE  ( source source-u -- encoded-u status )
    FORM-URLENCODED-MEASURE
    DUP FORM-URLENCODED-S-OK = IF EXIT THEN
    _FUEW-FORM>STATUS ;

: _FUEW-SOURCE-ALIASES?  ( source source-u writer -- flag )
    >R
    2DUP R@ FUEW.BODY @ R@ FUEW.CAPACITY @
        MSPAN-OVERLAP? IF
        2DROP R> DROP -1 EXIT
    THEN
    R> FUEW-SIZE MSPAN-OVERLAP? ;

: _FUEW-ADD-CHECKED  ( left right -- sum valid? )
    >R
    DUP _FUEW-LENGTH-MAX R@ - U> IF
        DROP R> DROP 0 0 EXIT
    THEN
    R> + -1 ;

: _FUEW-FIELD-TOTAL
  ( value-encoded-u name-encoded-u field-count -- total status )
    IF 2 ELSE 1 THEN
    _FUEW-ADD-CHECKED 0= IF
        2DROP 0 FUEW-S-CAPACITY EXIT
    THEN
    _FUEW-ADD-CHECKED 0= IF
        DROP 0 FUEW-S-CAPACITY EXIT
    THEN
    FUEW-S-OK ;

: _FUEW-5DUP
  ( x1 x2 x3 x4 x5 -- x1 x2 x3 x4 x5 x1 x2 x3 x4 x5 )
    4 PICK 4 PICK 4 PICK 4 PICK 4 PICK ;

: _FUEW-FIELD-GEOMETRY
  ( name-a name-u value-a value-u writer -- total status )
    DUP FUEW-VALID? 0= IF
        _FUEW-DROP5 0 FUEW-S-INVALID EXIT
    THEN
    DUP FUEW.STATE @ FUEW-STATE-BUILDING <> IF
        _FUEW-DROP5 0 FUEW-S-STATE EXIT
    THEN
    4 PICK 4 PICK 2 PICK _FUEW-SOURCE-ALIASES? IF
        _FUEW-DROP5 0 FUEW-S-ALIAS EXIT
    THEN
    2 PICK 2 PICK 2 PICK _FUEW-SOURCE-ALIASES? IF
        _FUEW-DROP5 0 FUEW-S-ALIAS EXIT
    THEN

    4 PICK 4 PICK _FUEW-MEASURE
    ?DUP IF
        >R DROP _FUEW-DROP5 0 R> EXIT
    THEN
    >R

    2 PICK 2 PICK _FUEW-MEASURE
    ?DUP IF
        >R DROP _FUEW-DROP5
        0 R> R> DROP EXIT
    THEN
    >R

    \ The return stack holds name length below value length.
    R> R>
    2 PICK FUEW.FIELD-COUNT @
    _FUEW-FIELD-TOTAL
    ?DUP IF
        >R DROP _FUEW-DROP5 0 R> EXIT
    THEN

    \ Compare against remaining arena capacity without overflowing the
    \ already validated length/capacity pair.
    >R
    DUP FUEW.CAPACITY @
    OVER FUEW.LENGTH @ -
    R@ SWAP U> IF
        _FUEW-DROP5
        R> DROP
        0 FUEW-S-CAPACITY EXIT
    THEN
    _FUEW-DROP5
    R> FUEW-S-OK ;

: _FUEW-FIELD-START  ( writer -- address )
    DUP FUEW.BODY @ SWAP FUEW.LENGTH @ + ;

: _FUEW-SEPARATOR-U  ( writer -- zero-or-one )
    FUEW.FIELD-COUNT @ 0<> IF 1 ELSE 0 THEN ;

: _FUEW-ZERO-FIELD  ( total writer -- )
    DUP _FUEW-FIELD-START
    ROT 0 FILL
    DROP ;

: _FUEW-FIELD-COMMIT
  ( name-a name-u value-a value-u writer total -- status )
    \ Clear the entire unpublished contribution before staging.  This also
    \ guarantees that rollback does not leave encoded secret fragments.
    DUP 2 PICK _FUEW-ZERO-FIELD

    1 PICK FUEW.FIELD-COUNT @ IF
        [CHAR] &
        2 PICK _FUEW-FIELD-START C!
    THEN

    \ Encode the name after the optional separator.  Its advertised
    \ destination capacity is the complete remaining contribution, never
    \ bytes beyond the preflighted field.
    5 PICK 5 PICK
    3 PICK _FUEW-FIELD-START
    4 PICK _FUEW-SEPARATOR-U +
    3 PICK
    5 PICK _FUEW-SEPARATOR-U -
    FORM-URLENCODED-ENCODE
    ?DUP IF
        _FUEW-FORM>STATUS >R
        DROP
        1 PICK _FUEW-ZERO-FIELD
        _FUEW-DROP5
        R> EXIT
    THEN
    >R

    \ Write '=' immediately after the encoded name.
    1 PICK _FUEW-FIELD-START
    2 PICK _FUEW-SEPARATOR-U +
    R@ +
    [CHAR] = SWAP C!

    \ Encode the value into the exact remaining portion of this field.
    3 PICK 3 PICK
    3 PICK _FUEW-FIELD-START
    4 PICK _FUEW-SEPARATOR-U +
    R@ + 1+
    3 PICK
    5 PICK _FUEW-SEPARATOR-U -
    R@ - 1-
    FORM-URLENCODED-ENCODE
    ?DUP IF
        _FUEW-FORM>STATUS >R
        DROP
        1 PICK _FUEW-ZERO-FIELD
        _FUEW-DROP5
        R> R> DROP EXIT
    THEN

    \ Source bytes are borrowed and required to remain stable.  Still
    \ verify that the two successful writes equal the measured transaction
    \ before publishing length/count.
    R> +
    2 PICK _FUEW-SEPARATOR-U + 1+
    2DUP <> IF
        DROP >R
        DUP R@ SWAP _FUEW-ZERO-FIELD
        _FUEW-DROP5
        R> DROP
        FUEW-S-INTERNAL EXIT
    THEN
    DROP

    DUP 2 PICK FUEW.LENGTH +!
    1 2 PICK FUEW.FIELD-COUNT +!
    DROP
    _FUEW-DROP5
    FUEW-S-OK ;

: FUEW-FIELD
  ( name-a name-u value-a value-u writer -- status )
    _FUEW-5DUP _FUEW-FIELD-GEOMETRY
    ?DUP IF
        >R DROP _FUEW-DROP5 R> EXIT
    THEN
    _FUEW-FIELD-COMMIT ;

\ =====================================================================
\  Seal and cleanup
\ =====================================================================

: FUEW-SEAL  ( writer -- status )
    DUP FUEW-VALID? 0= IF
        DROP FUEW-S-INVALID EXIT
    THEN
    DUP FUEW.STATE @ FUEW-STATE-BUILDING <> IF
        DROP FUEW-S-STATE EXIT
    THEN
    FUEW-STATE-SEALED SWAP FUEW.STATE !
    FUEW-S-OK ;

: FUEW-WIPE  ( writer -- status )
    DUP FUEW-VALID? 0= IF
        DROP FUEW-S-INVALID EXIT
    THEN
    DUP FUEW.BODY @ OVER FUEW.CAPACITY @ 0 FILL
    DUP FUEW-SIZE 0 FILL
    DROP FUEW-S-OK ;

\ =====================================================================
\  Compile-time geometry assertions
\ =====================================================================

: _FUEW-GEOMETRY-ABORT  ( -- )
    ." Form URL-encoded writer geometry mismatch" CR ABORT ;

1 CELLS 8 <> [IF]
    _FUEW-GEOMETRY-ABORT
[THEN]

FUEW-SIZE 48 <> [IF]
    _FUEW-GEOMETRY-ABORT
[THEN]
