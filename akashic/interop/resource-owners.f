\ =====================================================================
\  resource-owners.f - Where a locator's owner is reached
\ =====================================================================
\  A qualified locator names the owner of its resource by id
\  (QLOC-OWNER$).  The directory maps an owner id to what attaches a
\  locator through that owner: its acquisition root and attach word.
\  The component instance that runs an owner publishes it while it runs
\  and withdraws it as it stops; an owner id has one publication at a
\  time.  A publication names its instance by id and generation, so a
\  later instance never replaces or withdraws an earlier one's.  Only an
\  instance the component registry holds publishes, and a publication
\  whose instance the registry no longer holds is dropped when it is
\  next looked up, so an owner that stopped without withdrawing is never
\  reached.
\
\  An optional policy decides who may publish what:
\    ( owner-a owner-u instance context -- allowed? )
\
\  An attach word has RACQ-ATTACH's effect:
\    ( locator root context rreg binding result -- status )
\
\  The directory borrows each root, and grows as owners publish.  It is
\  caller-owned and caller-serialized.
\
\  Public API:
\    ROWN-SIZE       ( -- u )
\    ROWN-INIT       ( registry directory -- )
\    ROWN-FREE       ( directory -- )
\    ROWN-POLICY!    ( xt context directory -- )
\    ROWN-COUNT@     ( directory -- n )
\    ROWN-PUBLISH    ( owner-a owner-u root attach-xt instance directory
\                      -- status )
\    ROWN-WITHDRAW   ( owner-a owner-u instance directory -- status )
\    ROWN-FIND       ( owner-a owner-u directory -- entry|0 )
\    ROWN-E.ROOT ROWN-E.ATTACH-XT  ( entry -- a )
\    ROWN-ATTACH     ( locator context rreg binding result directory
\                      -- status )
\ =====================================================================

PROVIDED akashic-interop-rowners

REQUIRE qualified-locator.f
REQUIRE resource-acquisition.f
REQUIRE ../runtime/instance.f
REQUIRE ../runtime/registry.f
REQUIRE ../utils/record-table.f

0 CONSTANT ROWN-S-OK
1 CONSTANT ROWN-S-INVALID
2 CONSTANT ROWN-S-TAKEN        \ another instance publishes that owner
3 CONSTANT ROWN-S-NOT-FOUND
4 CONSTANT ROWN-S-NOMEM
5 CONSTANT ROWN-S-REFUSED      \ the policy does not allow it

\ A publication: the owner id, then the root, the attach word, and the
\ publishing instance's id and generation.
 0 CONSTANT _ROWN-E-OWNER-U
 8 CONSTANT _ROWN-E-OWNER
_ROWN-E-OWNER QLOC-OWNER-MAX + CONSTANT _ROWN-E-ROOT
_ROWN-E-ROOT 8 + CONSTANT _ROWN-E-ATTACH
_ROWN-E-ATTACH 8 + CONSTANT _ROWN-E-ID
_ROWN-E-ID 8 + CONSTANT _ROWN-E-GENERATION
_ROWN-E-GENERATION 8 + CONSTANT _ROWN-E-SIZE

: ROWN-E.ROOT       ( entry -- a ) _ROWN-E-ROOT + ;
: ROWN-E.ATTACH-XT  ( entry -- a ) _ROWN-E-ATTACH + ;
: _ROWN-E.OWNER$    ( entry -- a u ) DUP _ROWN-E-OWNER + SWAP @ ;

\ The directory: its table, its policy and the policy's context, and the
\ registry whose instances publish.
RTAB-SIZE CONSTANT _ROWN-POLICY
_ROWN-POLICY 8 + CONSTANT _ROWN-POLICY-CONTEXT
_ROWN-POLICY-CONTEXT 8 + CONSTANT _ROWN-REGISTRY
_ROWN-REGISTRY 8 + CONSTANT ROWN-SIZE

: ROWN-INIT  ( registry directory -- )
    DUP ROWN-SIZE 0 FILL _ROWN-REGISTRY + ! ;

\ Frees the table; the directory is empty, keeping no policy or registry.
: ROWN-FREE  ( directory -- ) DUP _ROWN-E-SIZE RTAB-FREE ROWN-SIZE 0 FILL ;

: ROWN-POLICY!  ( xt context directory -- )
    TUCK _ROWN-POLICY-CONTEXT + ! _ROWN-POLICY + ! ;

: ROWN-COUNT@  ( directory -- n ) RTAB-COUNT@ ;

: _ROWN-NTH  ( index directory -- entry ) _ROWN-E-SIZE RTAB-NTH ;

\ Whether ENTRY was published by INSTANCE, as it now is.
: _ROWN-BY?  ( instance entry -- flag )
    OVER CINST.ID @ OVER _ROWN-E-ID + @ =
    ROT CINST.GENERATION @ ROT _ROWN-E-GENERATION + @ = AND ;

\ Whether the registry holds INSTANCE.
: _ROWN-HELD?  ( instance directory -- flag )
    _ROWN-REGISTRY + @ ?DUP 0= IF DROP 0 EXIT THEN
    >R DUP CINST.ID @ OVER CINST.GENERATION @ R> CREG-INST-FIND = ;

\ Whether the registry still holds the instance that published ENTRY.
: _ROWN-LIVE?  ( entry directory -- flag )
    _ROWN-REGISTRY + @ ?DUP 0= IF DROP 0 EXIT THEN
    >R DUP _ROWN-E-ID + @ SWAP _ROWN-E-GENERATION + @ R> CREG-INST-FIND 0<> ;

\ The index of owner id A U's publication, or -1.
: _ROWN-INDEX  ( a u directory -- index|-1 )
    DUP ROWN-COUNT@ 0 ?DO
        I OVER _ROWN-NTH _ROWN-E.OWNER$ 4 PICK 4 PICK COMPARE 0= IF
            DROP 2DROP I UNLOOP EXIT
        THEN
    LOOP
    DROP 2DROP -1 ;

\ Owner id OWNER's publication, or 0.  One whose instance is gone is
\ dropped first.
: ROWN-FIND  ( owner-a owner-u directory -- entry|0 )
    DUP >R _ROWN-INDEX DUP 0< IF DROP R> DROP 0 EXIT THEN
    DUP R@ _ROWN-NTH DUP R@ _ROWN-LIVE? IF NIP R> DROP EXIT THEN
    DROP R> _ROWN-E-SIZE RTAB-DELETE 0 ;

\ Whether owner id A U is one a locator can carry: 1 through
\ QLOC-OWNER-MAX bytes.
: _ROWN-OWNER?  ( a u -- flag )
    DUP 1 QLOC-OWNER-MAX 1+ WITHIN 0= IF 2DROP 0 EXIT THEN
    DROP 0<> ;

VARIABLE _RWP-A  VARIABLE _RWP-U  VARIABLE _RWP-ROOT  VARIABLE _RWP-XT
VARIABLE _RWP-INST

\ Publishes owner id OWNER as reached through ROOT and ATTACH-XT, by
\ INSTANCE.  The same instance publishing again replaces its own
\ publication; another instance's stands, and the answer is TAKEN.
: ROWN-PUBLISH  ( owner-a owner-u root attach-xt instance directory -- status )
    >R _RWP-INST ! _RWP-XT ! _RWP-ROOT ! _RWP-U ! _RWP-A !
    _RWP-A @ _RWP-U @ _ROWN-OWNER? 0=
    _RWP-ROOT @ 0= OR _RWP-XT @ 0= OR _RWP-INST @ 0= OR IF
        R> DROP ROWN-S-INVALID EXIT
    THEN
    _RWP-INST @ R@ _ROWN-HELD? 0= IF R> DROP ROWN-S-INVALID EXIT THEN
    R@ _ROWN-POLICY + @ ?DUP IF
        _RWP-A @ _RWP-U @ _RWP-INST @ R@ _ROWN-POLICY-CONTEXT + @
        4 ROLL EXECUTE 0= IF R> DROP ROWN-S-REFUSED EXIT THEN
    THEN
    _RWP-A @ _RWP-U @ R@ ROWN-FIND ?DUP IF
        _RWP-INST @ OVER _ROWN-BY? 0= IF DROP R> DROP ROWN-S-TAKEN EXIT THEN
    ELSE
        R@ _ROWN-E-SIZE RTAB-RESERVE IF R> DROP ROWN-S-NOMEM EXIT THEN
        R@ ROWN-COUNT@ R@ _ROWN-E-SIZE RTAB-INSERT
        _RWP-U @ OVER ! _RWP-A @ OVER _ROWN-E-OWNER + _RWP-U @ MOVE
    THEN                                        ( entry )
    _RWP-ROOT @ OVER ROWN-E.ROOT !
    _RWP-XT @ OVER ROWN-E.ATTACH-XT !
    _RWP-INST @ CINST.ID @ OVER _ROWN-E-ID + !
    _RWP-INST @ CINST.GENERATION @ SWAP _ROWN-E-GENERATION + !
    R> DROP ROWN-S-OK ;

\ Withdraws INSTANCE's publication of owner id OWNER.
: ROWN-WITHDRAW  ( owner-a owner-u instance directory -- status )
    >R >R R@ 0= IF 2DROP R> R> 2DROP ROWN-S-INVALID EXIT THEN
    R> -ROT R@ _ROWN-INDEX                      ( instance index|-1 )
    DUP 0< IF 2DROP R> DROP ROWN-S-NOT-FOUND EXIT THEN
    SWAP OVER R@ _ROWN-NTH _ROWN-BY? 0= IF DROP R> DROP ROWN-S-TAKEN EXIT THEN
    R> _ROWN-E-SIZE RTAB-DELETE ROWN-S-OK ;

\ Attaches LOCATOR through the owner its locator names, as RACQ-ATTACH
\ would: UNAVAILABLE when no instance publishes that owner.
VARIABLE _RWA-ROOT  VARIABLE _RWA-XT

: ROWN-ATTACH  ( locator context rreg binding result directory -- status )
    5 PICK QLOC-VALID? 0= IF 2DROP 2DROP 2DROP RACQ-S-INVALID EXIT THEN
    5 PICK QLOC-OWNER$ ROT ROWN-FIND ?DUP 0= IF
        2DROP 2DROP DROP RACQ-S-UNAVAILABLE EXIT
    THEN                     ( locator context rreg binding result entry )
    DUP ROWN-E.ROOT @ _RWA-ROOT ! ROWN-E.ATTACH-XT @ _RWA-XT !
    >R >R >R >R _RWA-ROOT @ R> R> R> R>
    _RWA-XT @ EXECUTE ;
