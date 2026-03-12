\ html5.f — HTML5 document model layer
\
\ Sits atop dom.f and provides:
\   1. Document scaffolding: DOM-HTML-INIT creates <html>/<head>/<body>
\      and stores them in the doc descriptor's D.HTML / D.HEAD / D.BODY
\      slots added in dom.f v2 (13-cell descriptor).
\   2. Structural getters: DOM-HTML, DOM-HEAD, DOM-BODY.
\   3. Element sugar: DOM-DIV, DOM-SPAN, DOM-P, etc. — one-liner
\      wrappers around DOM-CREATE-ELEMENT with baked-in tag strings.
\
\ Does NOT import event.f — orthogonal concern.
\
\ Prefix: DOM-   (HTML5 public API, extends dom.f namespace)
\         _D5-   (internal helpers)
\
\ Load with:   REQUIRE html5.f

PROVIDED akashic-html5
REQUIRE dom.f

\ =====================================================================
\  Section 1 — Document Scaffolding
\ =====================================================================
\
\ DOM-HTML-INIT creates the standard HTML5 skeleton:
\   <html>
\     <head></head>
\     <body></body>
\   </html>
\ and stores the three nodes in the doc descriptor.
\ Call once after DOM-DOC-NEW + DOM-USE.
\ Calling twice on the same doc ABORTs.

: DOM-HTML-INIT  ( -- )
    DOM-DOC D.HTML @ 0<> ABORT" html5: already initialised"
    S" html" DOM-CREATE-ELEMENT  DOM-DOC D.HTML !
    S" head" DOM-CREATE-ELEMENT  DUP DOM-DOC D.HTML @ DOM-APPEND
    DOM-DOC D.HEAD !
    S" body" DOM-CREATE-ELEMENT  DUP DOM-DOC D.HTML @ DOM-APPEND
    DOM-DOC D.BODY ! ;

\ =====================================================================
\  Section 2 — Structural Getters
\ =====================================================================

: DOM-HTML  ( -- node )  DOM-DOC D.HTML @ ;
: DOM-HEAD  ( -- node )  DOM-DOC D.HEAD @ ;
: DOM-BODY  ( -- node )  DOM-DOC D.BODY @ ;

\ =====================================================================
\  Section 3 — Element Sugar
\ =====================================================================
\
\ One-line wrappers around DOM-CREATE-ELEMENT for the most common
\ HTML5 tags.  Each returns a freshly-allocated element node.
\ Caller is responsible for appending to the tree.

\ -- Structural / sectioning --
: DOM-DIV      ( -- node )  S" div"      DOM-CREATE-ELEMENT ;
: DOM-SECTION  ( -- node )  S" section"  DOM-CREATE-ELEMENT ;
: DOM-ARTICLE  ( -- node )  S" article"  DOM-CREATE-ELEMENT ;
: DOM-NAV      ( -- node )  S" nav"      DOM-CREATE-ELEMENT ;
: DOM-HEADER   ( -- node )  S" header"   DOM-CREATE-ELEMENT ;
: DOM-FOOTER   ( -- node )  S" footer"   DOM-CREATE-ELEMENT ;
: DOM-MAIN     ( -- node )  S" main"     DOM-CREATE-ELEMENT ;
: DOM-ASIDE    ( -- node )  S" aside"    DOM-CREATE-ELEMENT ;

\ -- Headings --
: DOM-H1       ( -- node )  S" h1"       DOM-CREATE-ELEMENT ;
: DOM-H2       ( -- node )  S" h2"       DOM-CREATE-ELEMENT ;
: DOM-H3       ( -- node )  S" h3"       DOM-CREATE-ELEMENT ;
: DOM-H4       ( -- node )  S" h4"       DOM-CREATE-ELEMENT ;
: DOM-H5       ( -- node )  S" h5"       DOM-CREATE-ELEMENT ;
: DOM-H6       ( -- node )  S" h6"       DOM-CREATE-ELEMENT ;

\ -- Inline / phrasing --
: DOM-SPAN     ( -- node )  S" span"     DOM-CREATE-ELEMENT ;
: DOM-A        ( -- node )  S" a"        DOM-CREATE-ELEMENT ;
: DOM-STRONG   ( -- node )  S" strong"   DOM-CREATE-ELEMENT ;
: DOM-EM       ( -- node )  S" em"       DOM-CREATE-ELEMENT ;
: DOM-P        ( -- node )  S" p"        DOM-CREATE-ELEMENT ;
: DOM-PRE      ( -- node )  S" pre"      DOM-CREATE-ELEMENT ;
: DOM-CODE     ( -- node )  S" code"     DOM-CREATE-ELEMENT ;

\ -- Lists --
: DOM-UL       ( -- node )  S" ul"       DOM-CREATE-ELEMENT ;
: DOM-OL       ( -- node )  S" ol"       DOM-CREATE-ELEMENT ;
: DOM-LI       ( -- node )  S" li"       DOM-CREATE-ELEMENT ;

\ -- Tables --
: DOM-TABLE    ( -- node )  S" table"    DOM-CREATE-ELEMENT ;
: DOM-THEAD    ( -- node )  S" thead"    DOM-CREATE-ELEMENT ;
: DOM-TBODY    ( -- node )  S" tbody"    DOM-CREATE-ELEMENT ;
: DOM-TR       ( -- node )  S" tr"       DOM-CREATE-ELEMENT ;
: DOM-TH       ( -- node )  S" th"       DOM-CREATE-ELEMENT ;
: DOM-TD       ( -- node )  S" td"       DOM-CREATE-ELEMENT ;

\ -- Forms / interactive --
: DOM-FORM     ( -- node )  S" form"     DOM-CREATE-ELEMENT ;
: DOM-BUTTON   ( -- node )  S" button"   DOM-CREATE-ELEMENT ;
: DOM-INPUT    ( -- node )  S" input"    DOM-CREATE-ELEMENT ;
: DOM-LABEL    ( -- node )  S" label"    DOM-CREATE-ELEMENT ;
: DOM-SELECT   ( -- node )  S" select"   DOM-CREATE-ELEMENT ;
: DOM-OPTION   ( -- node )  S" option"   DOM-CREATE-ELEMENT ;
: DOM-TEXTAREA ( -- node )  S" textarea" DOM-CREATE-ELEMENT ;

\ -- Media / embedded --
: DOM-IMG      ( -- node )  S" img"      DOM-CREATE-ELEMENT ;
: DOM-CANVAS   ( -- node )  S" canvas"   DOM-CREATE-ELEMENT ;

\ -- Misc --
: DOM-BR       ( -- node )  S" br"       DOM-CREATE-ELEMENT ;
: DOM-HR       ( -- node )  S" hr"       DOM-CREATE-ELEMENT ;

\ =====================================================================
\  Section 4 — Guard Wrappers (optional)
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _d5-guard

' DOM-HTML-INIT CONSTANT _d5-html-init-xt
' DOM-HTML      CONSTANT _d5-html-xt
' DOM-HEAD      CONSTANT _d5-head-xt
' DOM-BODY      CONSTANT _d5-body-xt

: DOM-HTML-INIT _d5-html-init-xt _d5-guard WITH-GUARD ;
: DOM-HTML      _d5-html-xt     _d5-guard WITH-GUARD ;
: DOM-HEAD      _d5-head-xt     _d5-guard WITH-GUARD ;
: DOM-BODY      _d5-body-xt     _d5-guard WITH-GUARD ;

\ Element sugar words are pure allocators — guarded through
\ DOM-CREATE-ELEMENT's own guard in dom.f.  No extra guard needed.
[THEN] [THEN]
