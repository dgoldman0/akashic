\ =====================================================================
\  intent.f - Semantic intent handlers and deterministic resolution
\ =====================================================================

PROVIDED akashic-interop-intent

REQUIRE ../runtime/registry.f

\ Installed intent declaration referenced by COMP.INTENTS-A/N.
 0 CONSTANT _CID-ID-A
 8 CONSTANT _CID-ID-U
16 CONSTANT _CID-CAP
24 CONSTANT _CID-PRIORITY
32 CONSTANT _CID-FLAGS
40 CONSTANT _CID-RESERVED
48 CONSTANT CINT-DESC-SIZE

: CINTD.ID-A      ( desc -- a ) _CID-ID-A + ;
: CINTD.ID-U      ( desc -- a ) _CID-ID-U + ;
: CINTD.CAP       ( desc -- a ) _CID-CAP + ;
: CINTD.PRIORITY  ( desc -- a ) _CID-PRIORITY + ;
: CINTD.FLAGS     ( desc -- a ) _CID-FLAGS + ;

: CINT-DESC-INIT  ( desc -- ) CINT-DESC-SIZE 0 FILL ;

32 CONSTANT CINT-MAX
64 CONSTANT CINT-ENTRY-SIZE

 0 CONSTANT _CIE-ID-A
 8 CONSTANT _CIE-ID-U
16 CONSTANT _CIE-COMP-DESC
24 CONSTANT _CIE-CAP
32 CONSTANT _CIE-PRIORITY
40 CONSTANT _CIE-FLAGS
48 CONSTANT _CIE-ORDER
56 CONSTANT _CIE-RESERVED

: CIE.ID-A       ( entry -- a ) _CIE-ID-A + ;
: CIE.ID-U       ( entry -- a ) _CIE-ID-U + ;
: CIE.COMP-DESC  ( entry -- a ) _CIE-COMP-DESC + ;
: CIE.CAP        ( entry -- a ) _CIE-CAP + ;
: CIE.PRIORITY   ( entry -- a ) _CIE-PRIORITY + ;
: CIE.FLAGS      ( entry -- a ) _CIE-FLAGS + ;

 0 CONSTANT _CIR-COUNT
 8 CONSTANT _CIR-NEXT-ORDER
16 CONSTANT _CIR-ENTRIES
_CIR-ENTRIES CINT-MAX CINT-ENTRY-SIZE * + CONSTANT CINT-SIZE

: CINT.COUNT    ( router -- a ) _CIR-COUNT + ;
: CINT.NEXT     ( router -- a ) _CIR-NEXT-ORDER + ;
: CINT.ENTRIES  ( router -- a ) _CIR-ENTRIES + ;

: CINT-NEW  ( -- router ior )
    CINT-SIZE ALLOCATE
    DUP IF EXIT THEN
    DROP DUP CINT-SIZE 0 FILL 1 OVER CINT.NEXT ! 0 ;

: CINT-FREE  ( router -- ) ?DUP IF FREE THEN ;

: CINT-NTH  ( index router -- entry | 0 )
    >R DUP 0< OVER R@ CINT.COUNT @ >= OR IF DROP R> DROP 0 EXIT THEN
    CINT-ENTRY-SIZE * R> CINT.ENTRIES + ;

VARIABLE _CIR-ID-A
VARIABLE _CIR-ID-U
VARIABLE _CIR-DESC
VARIABLE _CIR-CAP
VARIABLE _CIR-PRI
VARIABLE _CIR-R

: CINT-REGISTER  ( id-a id-u comp-desc cap priority router -- ior )
    _CIR-R ! _CIR-PRI ! _CIR-CAP ! _CIR-DESC ! _CIR-ID-U ! _CIR-ID-A !
    _CIR-R @ CINT.COUNT @ CINT-MAX >= IF CREG-E-FULL EXIT THEN
    _CIR-R @ CINT.COUNT @ CINT-ENTRY-SIZE *
    _CIR-R @ CINT.ENTRIES + DUP >R
    _CIR-ID-A @ R@ CIE.ID-A !
    _CIR-ID-U @ R@ CIE.ID-U !
    _CIR-DESC @ R@ CIE.COMP-DESC !
    _CIR-CAP @ R@ CIE.CAP !
    _CIR-PRI @ R@ CIE.PRIORITY !
    _CIR-R @ CINT.NEXT @ R@ _CIE-ORDER + !
    1 _CIR-R @ CINT.NEXT +!
    1 _CIR-R @ CINT.COUNT +!
    DROP R> DROP 0 ;

VARIABLE _CIDR-I
VARIABLE _CIDR-C
VARIABLE _CIDR-R

: CINT-REGISTER-DESC  ( intent-desc comp-desc router -- ior )
    _CIDR-R ! _CIDR-C ! _CIDR-I !
    _CIDR-I @ CINTD.ID-A @ _CIDR-I @ CINTD.ID-U @
    _CIDR-C @ _CIDR-I @ CINTD.CAP @ _CIDR-I @ CINTD.PRIORITY @
    _CIDR-R @ CINT-REGISTER ;

VARIABLE _CIC-DESC
VARIABLE _CIC-R

: CINT-REGISTER-COMP  ( comp-desc router -- ior )
    _CIC-R ! _CIC-DESC !
    _CIC-DESC @ COMP.INTENTS-N @ 0 ?DO
        _CIC-DESC @ COMP.INTENTS-A @ I CINT-DESC-SIZE * +
        _CIC-DESC @ _CIC-R @ CINT-REGISTER-DESC
        ?DUP IF UNLOOP EXIT THEN
    LOOP
    0 ;

VARIABLE _CIF-A
VARIABLE _CIF-U
VARIABLE _CIF-R
VARIABLE _CIF-BEST
VARIABLE _CIF-PRI

: CINT-RESOLVE  ( id-a id-u router -- entry | 0 )
    _CIF-R ! _CIF-U ! _CIF-A !
    0 _CIF-BEST ! -2147483648 _CIF-PRI !
    _CIF-R @ CINT.COUNT @ 0 ?DO
        I _CIF-R @ CINT-NTH >R
        R@ CIE.ID-A @ R@ CIE.ID-U @ _CIF-A @ _CIF-U @ STR-STR= IF
            R@ CIE.PRIORITY @ _CIF-PRI @ > IF
                R@ _CIF-BEST ! R@ CIE.PRIORITY @ _CIF-PRI !
            THEN
        THEN
        R> DROP
    LOOP
    _CIF-BEST @ ;
