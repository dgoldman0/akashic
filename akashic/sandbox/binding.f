\ =====================================================================
\  binding.f - Exact empty activation binding for pure sandbox plans
\ =====================================================================
\  A binding is activation policy, not guest data.  Stage 1 admits only
\  plans with zero imports, so this fixed caller-owned object proves that
\  the exact plan/profile pair is import-free before an instance exists.
\
\  Nonempty trusted adapter tables can extend this boundary later.  They do
\  not belong in candidate bytes, verified plans, profiles, or VM state, and
\  the pure runtime never stores or dispatches a native execution token.
\ =====================================================================

REQUIRE plan.f
REQUIRE profile.f

PROVIDED akashic-sbx-binding

\ =====================================================================
\  Status and fixed sealed object
\ =====================================================================

0 CONSTANT SBOX-BINDING-S-OK
1 CONSTANT SBOX-BINDING-S-INVALID
2 CONSTANT SBOX-BINDING-S-MISMATCH
3 CONSTANT SBOX-BINDING-S-NOT-PURE
4 CONSTANT SBOX-BINDING-S-ALIAS
5 CONSTANT SBOX-BINDING-S-RANGE
6 CONSTANT SBOX-BINDING-S-PROTECTED
7 CONSTANT SBOX-BINDING-S-PLATFORM

: SBOX-BINDING-STATUS-VALID?  ( status -- flag )
    DUP SBOX-BINDING-S-OK >=
    SWAP SBOX-BINDING-S-PLATFORM <= AND ;

0x53425842494E4421 CONSTANT _SBIND-MAGIC  \ "SBXBIND!"

 0 CONSTANT _SBI-MAGIC
 8 CONSTANT _SBI-SELF
16 CONSTANT _SBI-PLAN
24 CONSTANT _SBI-PROFILE
32 CONSTANT _SBI-PROFILE-TAG
40 CONSTANT _SBI-IMPORT-N
48 CONSTANT _SBI-RESERVED0
56 CONSTANT _SBI-RESERVED1
64 CONSTANT SBOX-BINDING-SIZE

: _SBIND-B.MAGIC       ( binding -- address ) _SBI-MAGIC + ;
: _SBIND-B.SELF        ( binding -- address ) _SBI-SELF + ;
: _SBIND-B.PLAN        ( binding -- address ) _SBI-PLAN + ;
: _SBIND-B.PROFILE     ( binding -- address ) _SBI-PROFILE + ;
: _SBIND-B.PROFILE-TAG ( binding -- address ) _SBI-PROFILE-TAG + ;
: _SBIND-B.IMPORT-N    ( binding -- address ) _SBI-IMPORT-N + ;
: _SBIND-B.RESERVED0   ( binding -- address ) _SBI-RESERVED0 + ;
: _SBIND-B.RESERVED1   ( binding -- address ) _SBI-RESERVED1 + ;

: _SBIND-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF
        DROP SBOX-BINDING-S-OK EXIT
    THEN
    DUP CALLER-SPAN-S-RANGE = IF
        DROP SBOX-BINDING-S-RANGE EXIT
    THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP SBOX-BINDING-S-PROTECTED EXIT
    THEN
    DROP SBOX-BINDING-S-PLATFORM ;

: _SBIND-SPAN-STATUS  ( binding -- status )
    SBOX-BINDING-SIZE CALLER-SPAN-STATUS
    _SBIND-CALLER>STATUS ;

: _SBIND-ZERO?  ( binding -- flag )
    SBOX-BINDING-SIZE 0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

\ The complete binding span has already passed _SBIND-SPAN-STATUS.
: _SBIND-HEADER?  ( binding -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP _SBIND-B.MAGIC @ _SBIND-MAGIC <> IF DROP 0 EXIT THEN
    DUP _SBIND-B.SELF @ OVER <> IF DROP 0 EXIT THEN
    DUP _SBIND-B.PLAN @ 0= IF DROP 0 EXIT THEN
    DUP _SBIND-B.PROFILE @ 0= IF DROP 0 EXIT THEN
    DUP _SBIND-B.PROFILE-TAG @ 0= IF DROP 0 EXIT THEN
    DUP _SBIND-B.IMPORT-N @ IF DROP 0 EXIT THEN
    DUP _SBIND-B.RESERVED0 @ IF DROP 0 EXIT THEN
    _SBIND-B.RESERVED1 @ 0= ;

: _SBIND-PLAN-PROFILE-MATCH?  ( plan profile -- flag )
    >R
    DUP SBOX-PLAN-VALID? 0= IF DROP R> DROP 0 EXIT THEN
    R@ SBOX-PROFILE-VALID? 0= IF DROP R> DROP 0 EXIT THEN
    DUP SBOX-PLAN-PROFILE@ R@ =
    OVER SBOX-PLAN-PROFILE-TAG@
    R@ SBOX-PROFILE-TAG@
    DUP IF
        >R 2DROP DROP R> DROP 0
    ELSE
        DROP = AND
    THEN
    NIP R> DROP ;

: _SBIND-IMPORT-OPCODE-DISABLED?  ( profile -- flag )
    >R
    SBOX-MACHINE-OP-IMPORT-CALL R@
    SBOX-PROFILE-OPCODE-ENABLED?
    DUP IF
        >R DROP R> DROP R> DROP 0 EXIT
    THEN
    DROP 0=
    R> DROP ;

: _SBIND-PURE-PAIR?  ( plan profile -- flag )
    2DUP _SBIND-PLAN-PROFILE-MATCH? 0= IF 2DROP 0 EXIT THEN
    OVER SBOX-PLAN-IMPORT-N@ 0= >R
    NIP _SBIND-IMPORT-OPCODE-DISABLED?
    R> AND ;

: _SBIND-INPUTS-DISJOINT?  ( plan profile binding -- flag )
    >R
    OVER SBOX-PLAN-TOTAL@ DUP 0= IF
        DROP 2DROP R> DROP 0 EXIT
    THEN
    2 PICK OVER
        R@ SBOX-BINDING-SIZE MSPAN-OVERLAP? 0=
    2 PICK SBOX-PROFILE-SIZE
        R@ SBOX-BINDING-SIZE MSPAN-OVERLAP? 0= AND
    3 PICK 2 PICK
        4 PICK SBOX-PROFILE-SIZE MSPAN-OVERLAP? 0= AND
    >R 2DROP DROP R> R> DROP ;

\ =====================================================================
\  Seal, validation, and release
\ =====================================================================

: SBOX-BINDING-PURE-INIT  ( plan binding -- status )
    DUP _SBIND-SPAN-STATUS ?DUP IF
        >R 2DROP R> EXIT
    THEN
    OVER SBOX-PLAN-VALID? 0= IF
        2DROP SBOX-BINDING-S-INVALID EXIT
    THEN
    OVER SBOX-PLAN-PROFILE@ DUP SBOX-PROFILE-VALID? 0= IF
        DROP 2DROP SBOX-BINDING-S-INVALID EXIT
    THEN
    >R
    OVER R@ 2 PICK _SBIND-INPUTS-DISJOINT? 0= IF
        R> DROP 2DROP SBOX-BINDING-S-ALIAS EXIT
    THEN

    \ Once all borrowed inputs and aliases are admitted, invalidate the
    \ complete destination before staging.  MAGIC is the final write.
    DUP SBOX-BINDING-SIZE 0 FILL
    DUP DUP _SBIND-B.SELF !
    OVER OVER _SBIND-B.PLAN !
    R@ OVER _SBIND-B.PROFILE !
    OVER SBOX-PLAN-PROFILE-TAG@ OVER _SBIND-B.PROFILE-TAG !

    OVER R@ _SBIND-PURE-PAIR? 0= IF
        DUP SBOX-BINDING-SIZE 0 FILL
        R> DROP 2DROP SBOX-BINDING-S-NOT-PURE EXIT
    THEN

    _SBIND-MAGIC OVER _SBIND-B.MAGIC !
    R> DROP 2DROP SBOX-BINDING-S-OK ;

: SBOX-BINDING-VALID-FOR?  ( plan binding -- flag )
    DUP _SBIND-SPAN-STATUS IF 2DROP 0 EXIT THEN
    DUP _SBIND-HEADER? 0= IF 2DROP 0 EXIT THEN
    2DUP _SBIND-B.PLAN @ SWAP <> IF 2DROP 0 EXIT THEN
    DUP _SBIND-B.PROFILE @ >R
    OVER R@ _SBIND-PURE-PAIR? 0= IF
        R> DROP 2DROP 0 EXIT
    THEN
    OVER SBOX-PLAN-PROFILE-TAG@
    OVER _SBIND-B.PROFILE-TAG @ =
    NIP NIP R> DROP ;

: SBOX-BINDING-VALID?  ( binding -- flag )
    DUP _SBIND-SPAN-STATUS IF DROP 0 EXIT THEN
    DUP _SBIND-HEADER? 0= IF DROP 0 EXIT THEN
    DUP _SBIND-B.PLAN @ SWAP SBOX-BINDING-VALID-FOR? ;

: SBOX-BINDING-PLAN@  ( binding -- plan|0 )
    DUP SBOX-BINDING-VALID? IF _SBIND-B.PLAN @ ELSE DROP 0 THEN ;

: SBOX-BINDING-PROFILE@  ( binding -- profile|0 )
    DUP SBOX-BINDING-VALID? IF _SBIND-B.PROFILE @ ELSE DROP 0 THEN ;

: SBOX-BINDING-PROFILE-TAG@  ( binding -- tag|0 )
    DUP SBOX-BINDING-VALID? IF
        _SBIND-B.PROFILE-TAG @
    ELSE
        DROP 0
    THEN ;

: SBOX-BINDING-RELEASE  ( binding -- status )
    DUP _SBIND-SPAN-STATUS ?DUP IF NIP EXIT THEN
    DUP _SBIND-ZERO? IF DROP SBOX-BINDING-S-OK EXIT THEN
    DUP SBOX-BINDING-VALID? >R
    DUP SBOX-BINDING-SIZE 0 FILL
    DROP R> IF SBOX-BINDING-S-OK ELSE SBOX-BINDING-S-INVALID THEN ;
