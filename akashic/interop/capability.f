\ =====================================================================
\  capability.f - Commands, resources, events, intents, and effects
\ =====================================================================

PROVIDED akashic-interop-capability

REQUIRE schema.f
REQUIRE ../runtime/instance.f

1 CONSTANT CAP-K-COMMAND
2 CONSTANT CAP-K-RESOURCE
3 CONSTANT CAP-K-EVENT
4 CONSTANT CAP-K-INTENT

1   CONSTANT CAP-E-OBSERVE
2   CONSTANT CAP-E-NAVIGATE
4   CONSTANT CAP-E-MUTATE
8   CONSTANT CAP-E-PERSIST
16  CONSTANT CAP-E-DESTRUCTIVE
32  CONSTANT CAP-E-EXTERNAL

1 CONSTANT CAP-F-IDEMPOTENT
2 CONSTANT CAP-F-REVERSIBLE
4 CONSTANT CAP-F-NEEDS-TARGET
8 CONSTANT CAP-F-CONTEXT-DEFAULT

\ Capability descriptor, 16 cells / 128 bytes.
  0 CONSTANT _CAP-KIND
  8 CONSTANT _CAP-ID-A
 16 CONSTANT _CAP-ID-U
 24 CONSTANT _CAP-TITLE-A
 32 CONSTANT _CAP-TITLE-U
 40 CONSTANT _CAP-DESC-A
 48 CONSTANT _CAP-DESC-U
 56 CONSTANT _CAP-IN-SCHEMA
 64 CONSTANT _CAP-OUT-SCHEMA
 72 CONSTANT _CAP-EFFECTS
 80 CONSTANT _CAP-FLAGS
 88 CONSTANT _CAP-HANDLER-XT      \ ( request instance -- status )
 96 CONSTANT _CAP-PREVIEW-XT      \ ( request instance -- status )
104 CONSTANT _CAP-UNDO-XT
112 CONSTANT _CAP-MAX-MS
120 CONSTANT _CAP-RESERVED
128 CONSTANT CAP-DESC

: CAP.KIND        ( cap -- a ) _CAP-KIND + ;
: CAP.ID-A        ( cap -- a ) _CAP-ID-A + ;
: CAP.ID-U        ( cap -- a ) _CAP-ID-U + ;
: CAP.TITLE-A     ( cap -- a ) _CAP-TITLE-A + ;
: CAP.TITLE-U     ( cap -- a ) _CAP-TITLE-U + ;
: CAP.DESC-A      ( cap -- a ) _CAP-DESC-A + ;
: CAP.DESC-U      ( cap -- a ) _CAP-DESC-U + ;
: CAP.IN-SCHEMA   ( cap -- a ) _CAP-IN-SCHEMA + ;
: CAP.OUT-SCHEMA  ( cap -- a ) _CAP-OUT-SCHEMA + ;
: CAP.EFFECTS     ( cap -- a ) _CAP-EFFECTS + ;
: CAP.FLAGS       ( cap -- a ) _CAP-FLAGS + ;
: CAP.HANDLER-XT  ( cap -- a ) _CAP-HANDLER-XT + ;
: CAP.PREVIEW-XT  ( cap -- a ) _CAP-PREVIEW-XT + ;
: CAP.UNDO-XT     ( cap -- a ) _CAP-UNDO-XT + ;
: CAP.MAX-MS      ( cap -- a ) _CAP-MAX-MS + ;

: CAP-DESC-INIT  ( cap -- ) CAP-DESC 0 FILL ;

: CAP-ID  ( cap -- addr len )
    DUP CAP.ID-A @ SWAP CAP.ID-U @ ;

: COMP-CAP-NTH  ( index comp-desc -- cap | 0 )
    >R DUP 0< OVER R@ COMP.CAPS-N @ >= OR IF DROP R> DROP 0 EXIT THEN
    CAP-DESC * R> COMP.CAPS-A @ + ;

VARIABLE _CCF-A
VARIABLE _CCF-U
VARIABLE _CCF-D

: COMP-CAP-FIND  ( id-a id-u comp-desc -- cap | 0 )
    _CCF-D ! _CCF-U ! _CCF-A !
    _CCF-D @ COMP.CAPS-N @ 0 ?DO
        I _CCF-D @ COMP-CAP-NTH DUP CAP-ID
        _CCF-A @ _CCF-U @ STR-STR= IF UNLOOP EXIT THEN
        DROP
    LOOP
    0 ;
