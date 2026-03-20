\ uidl-chrome.f — Chrome Element Registrations (Phase 0)
\
\ Registers chrome + must-have + nice-to-have UI elements into the
\ Element Registry.  Loaded after uidl.f, before any backend.
\
\ Chrome elements:
\   menubar, menu, item, tabs, tab, split, scroll, tree,
\   status, dialog, toast
\
\ Must-have additions:
\   textarea, dropdown, radiogroup, radio, toolbar
\
\ Nice-to-have additions:
\   log, code, accordion, password, contextmenu
\
\ All render-xt / event-xt / layout-xt start as NOOP.
\ Backends set them via EL-SET-RENDER / EL-SET-EVENT / EL-SET-LAYOUT
\ using the UIDL-T-* type-id constants.  External code (applets,
\ plugins) uses the same API — no library modification needed.
\
\ Prefix: UIDL-T-  (type constants)
\
\ Load with:   REQUIRE uidl-chrome.f

REQUIRE uidl.f

PROVIDED akashic-uidl-chrome

\ --- Chrome elements (11) ---
\ ( render-xt event-xt layout-xt flags "name" -- )
' NOOP ' NOOP ' NOOP  EL-CONTAINER OR-CHROME             DEFINE-ELEMENT menubar
    CONSTANT UIDL-T-MENUBAR
' NOOP ' NOOP ' NOOP  EL-CONTAINER OR-CHROME OR-FOCUS    DEFINE-ELEMENT menu
    CONSTANT UIDL-T-MENU
' NOOP ' NOOP ' NOOP  EL-LEAF OR-CHROME OR-FOCUS OR-SELF DEFINE-ELEMENT item
    CONSTANT UIDL-T-ITEM
' NOOP ' NOOP ' NOOP  EL-CONTAINER OR-CHROME             DEFINE-ELEMENT tabs
    CONSTANT UIDL-T-TABS
' NOOP ' NOOP ' NOOP  EL-CONTAINER OR-CHROME OR-FOCUS    DEFINE-ELEMENT tab
    CONSTANT UIDL-T-TAB
' NOOP ' NOOP ' NOOP  EL-FIXED-2 OR-CHROME               DEFINE-ELEMENT split
    CONSTANT UIDL-T-SPLIT
' NOOP ' NOOP ' NOOP  EL-FIXED-1 OR-CHROME               DEFINE-ELEMENT scroll
    CONSTANT UIDL-T-SCROLL
' NOOP ' NOOP ' NOOP  EL-CONTAINER OR-CHROME OR-FOCUS    DEFINE-ELEMENT tree
    CONSTANT UIDL-T-TREE
' NOOP ' NOOP ' NOOP  EL-CONTAINER OR-CHROME             DEFINE-ELEMENT status
    CONSTANT UIDL-T-STATUS
' NOOP ' NOOP ' NOOP  EL-CONTAINER OR-CHROME             DEFINE-ELEMENT dialog
    CONSTANT UIDL-T-DIALOG
' NOOP ' NOOP ' NOOP  EL-LEAF OR-CHROME                  DEFINE-ELEMENT toast
    CONSTANT UIDL-T-TOAST

\ --- Must-have additions (5) ---
' NOOP ' NOOP ' NOOP  EL-LEAF OR-DATA OR-FOCUS OR-TWOWAY DEFINE-ELEMENT textarea
    CONSTANT UIDL-T-TEXTAREA
' NOOP ' NOOP ' NOOP  EL-CONTAINER OR-DATA OR-FOCUS      DEFINE-ELEMENT dropdown
    CONSTANT UIDL-T-DROPDOWN
' NOOP ' NOOP ' NOOP  EL-CONTAINER OR-DATA               DEFINE-ELEMENT radiogroup
    CONSTANT UIDL-T-RADIOGROUP
' NOOP ' NOOP ' NOOP  EL-LEAF OR-DATA OR-FOCUS OR-TWOWAY DEFINE-ELEMENT radio
    CONSTANT UIDL-T-RADIO
' NOOP ' NOOP ' NOOP  EL-CONTAINER OR-CHROME             DEFINE-ELEMENT toolbar
    CONSTANT UIDL-T-TOOLBAR

\ --- Nice-to-have additions (5) ---
' NOOP ' NOOP ' NOOP  EL-CONTAINER OR-DATA               DEFINE-ELEMENT log
    CONSTANT UIDL-T-LOG
' NOOP ' NOOP ' NOOP  EL-LEAF OR-DATA                    DEFINE-ELEMENT code
    CONSTANT UIDL-T-CODE
' NOOP ' NOOP ' NOOP  EL-CONTAINER OR-DATA               DEFINE-ELEMENT accordion
    CONSTANT UIDL-T-ACCORDION
' NOOP ' NOOP ' NOOP  EL-LEAF OR-DATA OR-FOCUS OR-TWOWAY DEFINE-ELEMENT password
    CONSTANT UIDL-T-PASSWORD
' NOOP ' NOOP ' NOOP  EL-CONTAINER OR-CHROME             DEFINE-ELEMENT contextmenu
    CONSTANT UIDL-T-CONTEXTMENU

\ --- End of chrome registrations ---
\ Total: 21 (core) + 21 (chrome) = 42 elements registered
