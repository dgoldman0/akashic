\ =================================================================
\  app-desc.f — APP-DESC Application Descriptor
\ =================================================================
\  Megapad-64 / KDOS Forth
\  Pure data layout.  No I/O, no terminal, no UIDL dependency.
\
\  12 cells = 96 bytes.  The app allocates (CREATE ... APP-DESC ALLOT)
\  and fills in whichever fields it needs.  Unused callback fields
\  must be 0 (the shell skips them).
\ =================================================================

PROVIDED akashic-tui-app-desc

 0 CONSTANT _AD-INIT        \ ( -- )         app init callback
 8 CONSTANT _AD-EVENT       \ ( ev -- flag ) key/mouse handler
16 CONSTANT _AD-TICK        \ ( -- )         periodic tick
24 CONSTANT _AD-PAINT       \ ( -- )         custom widget paint
32 CONSTANT _AD-SHUTDOWN    \ ( -- )         cleanup
40 CONSTANT _AD-UIDL-A      \ UIDL XML addr (0 = no UIDL)
48 CONSTANT _AD-UIDL-U      \ UIDL XML len
56 CONSTANT _AD-WIDTH       \ preferred width  (0 = auto)
64 CONSTANT _AD-HEIGHT      \ preferred height (0 = auto)
72 CONSTANT _AD-TITLE-A     \ terminal title addr (0 = none)
80 CONSTANT _AD-TITLE-U     \ terminal title len
88 CONSTANT _AD-FLAGS       \ reserved (0)

96 CONSTANT APP-DESC         \ total size in bytes

\ --- Field accessors ---

: APP.INIT-XT      ( desc -- addr )  _AD-INIT     + ;
: APP.EVENT-XT     ( desc -- addr )  _AD-EVENT    + ;
: APP.TICK-XT      ( desc -- addr )  _AD-TICK     + ;
: APP.PAINT-XT     ( desc -- addr )  _AD-PAINT    + ;
: APP.SHUTDOWN-XT  ( desc -- addr )  _AD-SHUTDOWN + ;
: APP.UIDL-A       ( desc -- addr )  _AD-UIDL-A   + ;
: APP.UIDL-U       ( desc -- addr )  _AD-UIDL-U   + ;
: APP.WIDTH        ( desc -- addr )  _AD-WIDTH    + ;
: APP.HEIGHT       ( desc -- addr )  _AD-HEIGHT   + ;
: APP.TITLE-A      ( desc -- addr )  _AD-TITLE-A  + ;
: APP.TITLE-U      ( desc -- addr )  _AD-TITLE-U  + ;
: APP.FLAGS        ( desc -- addr )  _AD-FLAGS    + ;

\ --- Convenience: zero-fill a descriptor ---
: APP-DESC-INIT  ( desc -- )
    APP-DESC 0 FILL ;
