\ =====================================================================
\  Library applet functional controller contract
\ =====================================================================
\  Exercise the real ASHELL/UIDL lifecycle while keeping the scenario
\  intentionally narrow: create, corpus query, exact preview, and archive.
\  The _LAPP-* words are a white-box test seam, not public applet ABI.
\ =====================================================================

VARIABLE _laf-fails
VARIABLE _laf-checks
VARIABLE _laf-depth
VARIABLE _laf-outer-depth
VARIABLE _laf-init-entry-depth
VARIABLE _laf-ran
CREATE _laf-desc APP-DESC ALLOT
CREATE _laf-rid LIB-DIGEST-SIZE ALLOT

: _laf-assert  ( flag -- )
    1 _laf-checks +!
    0= IF
        1 _laf-fails +!
        ." LIBRARY APPLET FUNCTIONAL ASSERT " _laf-checks @ . CR
    THEN ;

: _laf-stack  ( -- )
    DEPTH DUP _laf-depth @ <> IF
        ." LIBRARY APPLET FUNCTIONAL STACK "
            _laf-depth @ . ." -> " DUP . CR .S CR
    THEN
    _laf-depth @ = _laf-assert ;

: _laf-preview-body?  ( -- flag )
    _LAPP-PREVIEW-BYTES _LAPP-PREVIEW-U @
        S" functional exact preview" STR-STR= ;

: _laf-create  ( -- )
    _LAPP-STORE-INITIALIZED @ _laf-assert
    _LAPP-READY @ 0= _laf-assert
    _LAPP-LAST-STATUS @ LIBSTORE-S-ABSENT = _laf-assert
    _LAPP-PREVIEW-BUFFER @ 0<> _laf-assert
    _LAPP-PREVIEW-BUFFER @ >R
    0 _LAPP-PREVIEW-BUFFER !
    LIBSTORE-S-OK _LAPP-LAST-STATUS !
    _LAPP-ENSURE-PROVISIONED LIBSTORE-S-ALLOCATION = _laf-assert
    R> _LAPP-PREVIEW-BUFFER !
    \ Presentation-only actions may replace the visible ABSENT status.  The
    \ create path must reclassify storage instead of trusting that cache.
    _LAPP-BACK LIBSTORE-S-OK = _laf-assert
    _LAPP-LAST-STATUS @ LIBSTORE-S-OK = _laf-assert

    S" Functional needle" DUP _LAPP-PENDING-TITLE-U !
        _LAPP-PENDING-TITLE SWAP CMOVE
    S" functional exact preview" DUP _LAPP-PENDING-BODY-U !
        _LAPP-PENDING-BODY SWAP CMOVE
    _LAPP-CONFIGURE-CREATE LIBSTORE-S-OK = _laf-assert
    _LAPP-PENDING-CREATE @ _LAPP-CREATE-PREPARED = _laf-assert
    _LAPP-DISPATCH-PENDING-CREATE LIBSTORE-S-OK = _laf-assert

    _LAPP-READY? _laf-assert
    _LAPP-PENDING-CREATE @ 0= _laf-assert
    _LAPP-RESULT-ENTRY LIB-ENTRY-VALID? _laf-assert
    _LAPP-RESULT-ENTRY LIBE.ID DUP RID-PRESENT? _laf-assert
        _laf-rid RID-COPY
    _LAPP-RESULT-ENTRY LIBE.DOMAIN-REVISION @ 1 = _laf-assert
    _LAPP-RESULT-ENTRY LIBE.LIFECYCLE @
        LIB-LIFECYCLE-ACTIVE = _laf-assert
    _LAPP-REFRESH-AFTER-MUTATION
    _laf-stack ;

: _laf-query-and-preview  ( -- )
    S" needle" DUP _LAPP-TERM-U ! _LAPP-TERM SWAP CMOVE
    _LAPP-RESET-PAGE LIBSTORE-S-OK = _laf-assert
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    0 _LAPP-CORPUS-ROW DUP LIBQS.REF RREF.ID
        _laf-rid RID= _laf-assert
    LIBQS-TITLE$ S" Functional needle" STR-STR= _laf-assert
    _LAPP-PREVIEW-READY @ _laf-assert
    _LAPP-TARGET-ID _laf-rid RID= _laf-assert
    _LAPP-TARGET-REVISION @ 1 = _laf-assert
    _LAPP-ENTRY LIBE.ID _laf-rid RID= _laf-assert
    _LAPP-ENTRY LIBE.DOMAIN-REVISION @ 1 = _laf-assert
    _LAPP-CONTENT LIBCT-DATA$
        S" functional exact preview" STR-STR= _laf-assert
    _laf-preview-body? _laf-assert
    _laf-stack ;

: _laf-archive  ( -- )
    0 _LAPP-DO-ARCHIVE
    _LAPP-LAST-STATUS @ LIBSTORE-S-OK = _laf-assert
    _LAPP-RESULT-ENTRY LIBE.ID _laf-rid RID= _laf-assert
    _LAPP-RESULT-ENTRY LIBE.DOMAIN-REVISION @ 2 = _laf-assert
    _LAPP-RESULT-ENTRY LIBE.LIFECYCLE @
        LIB-LIFECYCLE-ARCHIVED = _laf-assert
    _LAPP-ROW-COUNT @ 0= _laf-assert
    _LAPP-PREVIEW-READY @ 0= _laf-assert

    0 _LAPP-DO-SHOW-ARCHIVED
    _LAPP-VIEW @ _LAPP-V-ARCHIVED = _laf-assert
    _LAPP-LAST-STATUS @ LIBSTORE-S-OK = _laf-assert
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    0 _LAPP-CORPUS-ROW LIBQS.REF RREF.ID
        _laf-rid RID= _laf-assert
    _LAPP-PREVIEW-READY @ _laf-assert
    _LAPP-TARGET-REVISION @ 2 = _laf-assert
    _LAPP-ENTRY LIBE.ID _laf-rid RID= _laf-assert
    _LAPP-ENTRY LIBE.LIFECYCLE @
        LIB-LIFECYCLE-ARCHIVED = _laf-assert
    _laf-preview-body? _laf-assert
    _laf-stack ;

: _laf-history-and-unarchive  ( -- )
    _LAPP-OPEN-HISTORY LIBSTORE-S-OK = _laf-assert
    _LAPP-VIEW @ _LAPP-V-HISTORY = _laf-assert
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    \ Lifecycle changes advance the entry domain revision without rewriting
    \ immutable content history; its retained frame remains revision 1.
    0 _LAPP-HISTORY-ROW LIBRS.DOMAIN-REVISION @ 1 = _laf-assert
    0 _LAPP-HISTORY-ROW LIBRS.CONTENT-REVISION @ 1 = _laf-assert
    _LAPP-PREVIEW-READY @ _laf-assert
    _laf-preview-body? _laf-assert

    _LAPP-BACK LIBSTORE-S-OK = _laf-assert
    _LAPP-VIEW @ _LAPP-V-ARCHIVED = _laf-assert
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    0 _LAPP-DO-UNARCHIVE
    _LAPP-LAST-STATUS @ LIBSTORE-S-OK = _laf-assert
    _LAPP-RESULT-ENTRY LIBE.DOMAIN-REVISION @ 3 = _laf-assert
    _LAPP-RESULT-ENTRY LIBE.LIFECYCLE @
        LIB-LIFECYCLE-ACTIVE = _laf-assert
    _LAPP-ROW-COUNT @ 0= _laf-assert
    _LAPP-PREVIEW-READY @ 0= _laf-assert

    0 _LAPP-DO-SHOW-ACTIVE
    _LAPP-VIEW @ _LAPP-V-ACTIVE = _laf-assert
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    _LAPP-TARGET-REVISION @ 3 = _laf-assert
    _LAPP-ENTRY LIBE.LIFECYCLE @
        LIB-LIFECYCLE-ACTIVE = _laf-assert
    _laf-preview-body? _laf-assert
    _laf-stack ;

: _laf-shell-init  ( instance -- )
    DEPTH _laf-init-entry-depth !
    LIBRARY-APPLET-INIT-CB
    DEPTH _laf-init-entry-depth @ 1- = _laf-assert
    DEPTH _laf-depth !
    -1 _laf-ran !
    _laf-create
    _laf-query-and-preview
    _laf-archive
    _laf-history-and-unarchive
    _laf-stack
    ASHELL-QUIT ;

: _laf-run  ( -- )
    0 _laf-fails ! 0 _laf-checks ! 0 _laf-ran !
    DEPTH _laf-outer-depth !
    _laf-desc LIBRARY-APPLET-ENTRY
    ['] _laf-shell-init _laf-desc APP.INIT-XT !
    _laf-desc ASHELL-RUN
    _laf-ran @ _laf-assert
    DEPTH DUP _laf-outer-depth @ <> IF
        ." LIBRARY APPLET FUNCTIONAL OUTER STACK "
            _laf-outer-depth @ . ." -> " DUP . CR .S CR
    THEN
    _laf-outer-depth @ = _laf-assert
    _laf-fails @ ?DUP IF
        ." LIBRARY APPLET FUNCTIONAL FAIL " .
            ." / " _laf-checks @ . CR
    ELSE
        ." LIBRARY APPLET FUNCTIONAL PASS " _laf-checks @ . CR
    THEN ;

_laf-run
