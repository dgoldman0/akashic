\ =================================================================
\  file-types.f — File Type Registry
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: FT- / _FT-
\  Depends on: utils/string.f
\
\  Maps filename extensions to type descriptors carrying metadata
\  useful for editors, file browsers, and launchers.
\
\  No TUI/presentation dependencies — consumers provide their own
\  icon or colour mappings keyed by the type-id or lang-id.
\
\  Descriptor layout (8 cells = 64 bytes per entry):
\    +0   ext-a       Extension string addr (e.g. ".f")
\    +8   ext-u       Extension string length
\    +16  name-a      Display name addr (e.g. "Forth source")
\    +24  name-u      Display name length
\    +32  lang-id     Language id  (FT-LANG-*)
\    +40  tab-w       Default tab width (spaces)
\    +48  line-end    Line ending:  0 = LF, 1 = CRLF
\    +56  handler     App-desc pointer (0 = none; set at run time)
\
\  Public API:
\    FT-LOOKUP      ( fn-a fn-u -- desc | 0 )
\    FT-EXT         ( desc -- addr u )
\    FT-NAME        ( desc -- addr u )
\    FT-LANG-ID     ( desc -- id )
\    FT-TAB-W       ( desc -- n )
\    FT-LINE-END    ( desc -- 0|1 )
\    FT-HANDLER     ( desc -- app-desc | 0 )
\    FT-SET-HANDLER ( app-desc desc -- )
\    FT-LANG-*      Language-id constants
\    FT-COUNT       ( -- n )          Number of registered types
\    FT-NTH         ( n -- desc )     Descriptor by index
\ =================================================================

PROVIDED akashic-file-types

REQUIRE string.f

\ =====================================================================
\  S1 -- Language IDs (presentation-independent)
\ =====================================================================

0 CONSTANT FT-LANG-PLAIN
1 CONSTANT FT-LANG-FORTH
2 CONSTANT FT-LANG-MARKDOWN
3 CONSTANT FT-LANG-TOML
4 CONSTANT FT-LANG-YAML
5 CONSTANT FT-LANG-JSON
6 CONSTANT FT-LANG-C
7 CONSTANT FT-LANG-BINARY

\ =====================================================================
\  S2 -- Descriptor Layout
\ =====================================================================

 0 CONSTANT _FT-O-EXT-A
 8 CONSTANT _FT-O-EXT-U
16 CONSTANT _FT-O-NAME-A
24 CONSTANT _FT-O-NAME-U
32 CONSTANT _FT-O-LANG
40 CONSTANT _FT-O-TAB-W
48 CONSTANT _FT-O-LEND
56 CONSTANT _FT-O-HANDLER
64 CONSTANT _FT-DESC-SZ

\ =====================================================================
\  S3 -- Accessors
\ =====================================================================

: FT-EXT       ( desc -- addr u ) DUP _FT-O-EXT-A + @  SWAP _FT-O-EXT-U + @ ;
: FT-NAME      ( desc -- addr u ) DUP _FT-O-NAME-A + @ SWAP _FT-O-NAME-U + @ ;
: FT-LANG-ID   ( desc -- id )     _FT-O-LANG + @ ;
: FT-TAB-W     ( desc -- n )      _FT-O-TAB-W + @ ;
: FT-LINE-END  ( desc -- 0|1 )    _FT-O-LEND + @ ;
: FT-HANDLER   ( desc -- ad|0 )   _FT-O-HANDLER + @ ;
: FT-SET-HANDLER ( app-desc desc -- ) _FT-O-HANDLER + ! ;

\ =====================================================================
\  S4 -- Static Type Table
\ =====================================================================
\
\  Each entry is _FT-DESC-SZ bytes.  Extension strings and names
\  are compile-time string literals (in dictionary).

\ Helper: compile a descriptor inline
: _FT-ENTRY,  ( ext-a ext-u name-a name-u lang tab-w lend -- )
    >R >R >R >R >R
    ,  ,                       \ ext-a ext-u
    R> , R> ,                  \ name-a name-u
    R> ,                       \ lang-id
    R> ,                       \ tab-w
    R> ,                       \ line-end
    0 ,                        \ handler (none initially)
    ;

CREATE _FT-TABLE

S" .f"        S" Forth source"      FT-LANG-FORTH     4 0 _FT-ENTRY,
S" .fs"       S" Forth source"      FT-LANG-FORTH     4 0 _FT-ENTRY,
S" .fth"      S" Forth source"      FT-LANG-FORTH     4 0 _FT-ENTRY,
S" .4th"      S" Forth source"      FT-LANG-FORTH     4 0 _FT-ENTRY,
S" .md"       S" Markdown"          FT-LANG-MARKDOWN  4 0 _FT-ENTRY,
S" .markdown" S" Markdown"          FT-LANG-MARKDOWN  4 0 _FT-ENTRY,
S" .txt"      S" Plain text"        FT-LANG-PLAIN     8 0 _FT-ENTRY,
S" .log"      S" Log file"          FT-LANG-PLAIN     8 0 _FT-ENTRY,
S" .toml"     S" TOML config"       FT-LANG-TOML      2 0 _FT-ENTRY,
S" .yaml"     S" YAML config"       FT-LANG-YAML      2 0 _FT-ENTRY,
S" .yml"      S" YAML config"       FT-LANG-YAML      2 0 _FT-ENTRY,
S" .json"     S" JSON data"         FT-LANG-JSON      2 0 _FT-ENTRY,
S" .c"        S" C source"          FT-LANG-C         4 0 _FT-ENTRY,
S" .h"        S" C header"          FT-LANG-C         4 0 _FT-ENTRY,
S" .cfg"      S" Config file"       FT-LANG-PLAIN     4 0 _FT-ENTRY,
S" .ini"      S" INI config"        FT-LANG-PLAIN     4 0 _FT-ENTRY,
S" .csv"      S" CSV data"          FT-LANG-PLAIN     4 0 _FT-ENTRY,

HERE CONSTANT _FT-TABLE-END

_FT-TABLE-END _FT-TABLE -  _FT-DESC-SZ /  CONSTANT _FT-N

: FT-COUNT  ( -- n )  _FT-N ;
: FT-NTH    ( n -- desc )  _FT-DESC-SZ *  _FT-TABLE + ;

\ =====================================================================
\  S5 -- Lookup
\ =====================================================================

VARIABLE _FTL-FA   VARIABLE _FTL-FU   \ filename
VARIABLE _FTL-DA   VARIABLE _FTL-DU   \ dot-suffix of filename

\ _FT-EXTRACT-EXT ( fn-a fn-u -- ext-a ext-u )
\   Extract the extension from a filename (last '.' to end).
\   Returns 0 0 if no dot found.
: _FT-EXTRACT-EXT  ( fn-a fn-u -- ext-a ext-u )
    _FTL-FU !  _FTL-FA !
    _FTL-FA @  _FTL-FU @  [CHAR] .  STR-RINDEX   ( idx | -1 )
    DUP -1 = IF DROP 0 0 EXIT THEN
    _FTL-FA @ OVER +                               ( idx ext-a )
    SWAP _FTL-FU @ SWAP -                          ( ext-a ext-u )
    ;

\ FT-LOOKUP ( fn-a fn-u -- desc | 0 )
\   Find the type descriptor for a filename.  Case-insensitive
\   extension match.  Returns 0 if no match.
: FT-LOOKUP  ( fn-a fn-u -- desc | 0 )
    _FT-EXTRACT-EXT                    ( ext-a ext-u )
    DUP 0= IF 2DROP 0 EXIT THEN
    _FTL-DU !  _FTL-DA !
    _FT-N 0 ?DO
        I FT-NTH FT-EXT               ( tbl-ext-a tbl-ext-u )
        _FTL-DA @  _FTL-DU @
        2SWAP STR-STRI=
        IF I FT-NTH UNLOOP EXIT THEN
    LOOP
    0 ;

\ =====================================================================
\  S6 -- Convenience
\ =====================================================================

\ FT-LOOKUP-LANG ( fn-a fn-u -- lang-id )
\   Shorthand: returns language id, or FT-LANG-PLAIN if unknown.
: FT-LOOKUP-LANG  ( fn-a fn-u -- lang-id )
    FT-LOOKUP DUP IF FT-LANG-ID ELSE DROP FT-LANG-PLAIN THEN ;

\ FT-LOOKUP-TAB ( fn-a fn-u -- tab-w )
\   Shorthand: returns tab width, defaulting to 4 if unknown.
: FT-LOOKUP-TAB  ( fn-a fn-u -- tab-w )
    FT-LOOKUP DUP IF FT-TAB-W ELSE DROP 4 THEN ;

\ =====================================================================
\  S7 -- Guard (Concurrency Safety)
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _ft-guard

' FT-LOOKUP       CONSTANT _ft-lookup-xt
' FT-LOOKUP-LANG  CONSTANT _ft-llang-xt
' FT-LOOKUP-TAB   CONSTANT _ft-ltab-xt
' FT-SET-HANDLER  CONSTANT _ft-sethdl-xt

: FT-LOOKUP       _ft-lookup-xt  _ft-guard WITH-GUARD ;
: FT-LOOKUP-LANG  _ft-llang-xt   _ft-guard WITH-GUARD ;
: FT-LOOKUP-TAB   _ft-ltab-xt    _ft-guard WITH-GUARD ;
: FT-SET-HANDLER  _ft-sethdl-xt  _ft-guard WITH-GUARD ;
[THEN] [THEN]
