\ =================================================================
\  content.f  —  a page's content, read for its text
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: PDF-CONTENT-, PDF-RUN- (public),
\                               _PDC- (private)
\  Depends on: pdf/lexer.f, pdf/filter.f, pdf/file.f, pdf/page.f,
\              pdf/font.f
\
\  Public API:
\   PDF-CONTENT-SIZE  ( -- bytes )                 a page content's record
\   PDF-CONTENT-READ  ( page fonts content -- status )   read an open page
\   PDF-CONTENT-FREE  ( content -- )
\   PDF-CONTENT-RUNS  ( content -- n )             the runs of text read
\   PDF-CONTENT-RUN   ( i content -- run )
\   PDF-RUN-TEXT      ( run content -- a u )       its characters, UTF-8
\   PDF-RUN-START     ( run -- x y )               where it starts
\   PDF-RUN-END       ( run -- x y )               where it ends
\   PDF-RUN-SIZE      ( run -- size )
\   PDF-RUN-STYLE     ( run -- flags )
\   PDF-RUN-MCID      ( run -- mcid | -1 )
\
\  PDF-CONTENT-READ interprets the page's content streams (PDF 32000-1
\  sections 8 and 9.4): the graphics state's matrix, its saves and
\  restores, the text state, text objects, text positioning and showing,
\  and marked content; a form XObject's content is read inside the
\  page's, under its matrix and with its resources; inline images are
\  passed over, and so are the operators that only draw.
\
\  A run is text shown with one font at one size whose glyphs follow one
\  another: a show that starts within a tenth of the size of where the
\  open run ends continues it, so kerning stays inside a run, while a
\  gap, as between words a producer places one by one, starts another.
\  Points and sizes are in the page's default space in 16.16 fixed
\  point: the start is the first glyph's origin on the baseline, the end
\  where the last glyph's advance leaves the text position, and the size
\  the text size as the matrices scale it.  A run's style is its font's,
\  with PDF-RUN-INVISIBLE for text drawn in rendering mode 3, as scanned
\  pages carry recognized text, and PDF-RUN-ARTIFACT inside /Artifact
\  marked content.  Its MCID is the innermost marked content's, or -1.
\
\  Fonts come from FONTS, a set of fonts (pdf/font.f) the caller keeps,
\  so the pages of a document read each font once.  A form that is being
\  drawn is not drawn again inside itself.  Content streams, saves and marked
\  content nest on explicit stacks that grow from the file's memory
\  source, not on the return stack.  A damaged content stream is read as
\  far as it goes, and its status returned.  One call runs at a time.
\ =================================================================

PROVIDED akashic-pdf-content

REQUIRE lexer.f
REQUIRE filter.f
REQUIRE file.f
REQUIRE page.f
REQUIRE font.f

256 CONSTANT PDF-RUN-INVISIBLE
512 CONSTANT PDF-RUN-ARTIFACT

\ The record: the file, its memory source, the runs and their text.
: _PDC.FILE   ( c -- a )        ;
: _PDC.MSRC   ( c -- a )    8 + ;
: _PDC.RUNS   ( c -- buf )  16 + ;
: _PDC.TEXT   ( c -- buf )  40 + ;
64 CONSTANT PDF-CONTENT-SIZE

\ A run: start x y, end x y, size, style, its text's offset and length,
\ its MCID.
72 CONSTANT _PDC-RUN

: PDF-CONTENT-RUNS  ( content -- n )  _PDC.RUNS PDF-BUF.U @ _PDC-RUN / ;
: PDF-CONTENT-RUN   ( i content -- run )  _PDC.RUNS PDF-BUF.A @ SWAP _PDC-RUN * + ;
: PDF-RUN-TEXT   ( run content -- a u )  _PDC.TEXT PDF-BUF.A @ OVER 48 + @ + SWAP 56 + @ ;
: PDF-RUN-START  ( run -- x y )  DUP @ SWAP 8 + @ ;
: PDF-RUN-END    ( run -- x y )  DUP 16 + @ SWAP 24 + @ ;
: PDF-RUN-SIZE   ( run -- size )  32 + @ ;
: PDF-RUN-STYLE  ( run -- flags )  40 + @ ;
: PDF-RUN-MCID   ( run -- mcid )  64 + @ ;

VARIABLE _PDC-C   \ the content's record
VARIABLE _PDC-F   \ its file

: _PDC-MSRC     ( -- msrc )  _PDC-C @ _PDC.MSRC @ ;
: _PDC-GET      ( num -- obj status )  _PDC-F @ PDF-GET ;
: _PDC-FREE     ( obj -- )  _PDC-F @ PDF-OBJ-FREE ;
: _PDC-RESOLVE  ( va vu type -- obj va' vu' type' status )  _PDC-F @ PDF-RESOLVE ;
: _PDC-ADV      ( a u n -- a+n u-n )  TUCK - >R + R> ;

\ =====================================================================
\  Matrices, in 16.16
\ =====================================================================

65536 CONSTANT _PDC-ONE
: _PDC-F*  ( a b -- ab )  * 65536 / ;

VARIABLE _PDC-MA   VARIABLE _PDC-MB
CREATE _PDC-T 48 ALLOT

: _PDC-A@  ( i -- v )  CELLS _PDC-MA @ + @ ;
: _PDC-B@  ( i -- v )  CELLS _PDC-MB @ + @ ;

\ C = A B, matrices of six values; C may be A or B.
: _PDC-MUL  ( a b c -- )
    >R _PDC-MB ! _PDC-MA !
    0 _PDC-A@ 0 _PDC-B@ _PDC-F*  1 _PDC-A@ 2 _PDC-B@ _PDC-F* +  _PDC-T !
    0 _PDC-A@ 1 _PDC-B@ _PDC-F*  1 _PDC-A@ 3 _PDC-B@ _PDC-F* +  _PDC-T 8 + !
    2 _PDC-A@ 0 _PDC-B@ _PDC-F*  3 _PDC-A@ 2 _PDC-B@ _PDC-F* +  _PDC-T 16 + !
    2 _PDC-A@ 1 _PDC-B@ _PDC-F*  3 _PDC-A@ 3 _PDC-B@ _PDC-F* +  _PDC-T 24 + !
    4 _PDC-A@ 0 _PDC-B@ _PDC-F*  5 _PDC-A@ 2 _PDC-B@ _PDC-F* + 4 _PDC-B@ +  _PDC-T 32 + !
    4 _PDC-A@ 1 _PDC-B@ _PDC-F*  5 _PDC-A@ 3 _PDC-B@ _PDC-F* + 5 _PDC-B@ +  _PDC-T 40 + !
    _PDC-T R> 48 MOVE ;

\ A point through a matrix.
: _PDC-POINT  ( x y m -- x' y' )
    _PDC-MA !
    OVER 0 _PDC-A@ _PDC-F*  OVER 2 _PDC-A@ _PDC-F* +  4 _PDC-A@ +
    -ROT SWAP 1 _PDC-A@ _PDC-F*  SWAP 3 _PDC-A@ _PDC-F* +  5 _PDC-A@ + ;

: _PDC-IDENTITY  ( m -- )  DUP 48 0 FILL  _PDC-ONE OVER !  _PDC-ONE SWAP 24 + ! ;

: _PDC-SQRT  ( n -- root )
    DUP 2 < IF EXIT THEN
    DUP BEGIN 2DUP / OVER + 2/ 2DUP > WHILE NIP REPEAT
    DROP NIP ;

\ =====================================================================
\  State
\ =====================================================================

\ The graphics state: its matrix, then the text state: character and
\ word spacing, horizontal scale, leading, font, size, rendering mode,
\ rise.
CREATE _PDC-GS 112 ALLOT
112 CONSTANT _PDC-GS-SIZE
: _PDC-CTM   ( -- m )  _PDC-GS ;
: _PDC.TC    ( -- a )  _PDC-GS 48 + ;
: _PDC.TW    ( -- a )  _PDC-GS 56 + ;
: _PDC.TH    ( -- a )  _PDC-GS 64 + ;
: _PDC.TL    ( -- a )  _PDC-GS 72 + ;
: _PDC.FONT  ( -- a )  _PDC-GS 80 + ;
: _PDC.TFS   ( -- a )  _PDC-GS 88 + ;
: _PDC.TR    ( -- a )  _PDC-GS 96 + ;
: _PDC.TS    ( -- a )  _PDC-GS 104 + ;

CREATE _PDC-TM 48 ALLOT      \ the text matrix
CREATE _PDC-TLM 48 ALLOT     \ the text line matrix
CREATE _PDC-M 48 ALLOT       \ a matrix read

\ Buffers kept while reading: the saved graphics states, the content
\ streams being read, the marked content open (MCID, artifact?), a
\ string's bytes.
CREATE _PDC-BUFS-S 4 24 * 7 + ALLOT
: _PDC-GSTACK  ( -- buf )  _PDC-BUFS-S 7 + -8 AND ;
: _PDC-FRAMES  ( -- buf )  _PDC-GSTACK 24 + ;
: _PDC-MARKS   ( -- buf )  _PDC-GSTACK 48 + ;
: _PDC-SB      ( -- buf )  _PDC-GSTACK 72 + ;

VARIABLE _PDC-SET     \ the fonts the caller keeps
VARIABLE _PDC-SZOK    \ the text size kept is good
VARIABLE _PDC-SZC     \ the text size kept

\ The matrices or the text size changed.
: _PDC-RESIZE  ( -- )  0 _PDC-SZOK ! ;

\ A frame: a content stream being read.  Its bytes, decoded; where
\ reading is; its resources and the object holding them when that is
\ its own; the form's object and number, 0 for the page's; the saves
\ open when it began; its /Font dictionary once looked up, with the
\ object holding it.
: _PDC.FBUF    ( fr -- buf )      ;
: _PDC.FA      ( fr -- a )   24 + ;
: _PDC.FU      ( fr -- a )   32 + ;
: _PDC.FRA     ( fr -- a )   40 + ;
: _PDC.FRU     ( fr -- a )   48 + ;
: _PDC.FRT     ( fr -- a )   56 + ;
: _PDC.FRO     ( fr -- a )   64 + ;
: _PDC.FFO     ( fr -- a )   72 + ;
: _PDC.FNUM    ( fr -- a )   80 + ;
: _PDC.FDEPTH  ( fr -- a )   88 + ;
: _PDC.FONTO   ( fr -- a )   96 + ;
: _PDC.FONTA   ( fr -- a )  104 + ;
: _PDC.FONTU   ( fr -- a )  112 + ;
120 CONSTANT _PDC-FRAME

CREATE _PDC-ZERO _PDC-FRAME ALLOT  _PDC-ZERO _PDC-FRAME 0 FILL

: _PDC-NFRAMES  ( -- n )  _PDC-FRAMES PDF-BUF.U @ _PDC-FRAME / ;
: _PDC-FRAME@   ( i -- fr )  _PDC-FRAME * _PDC-FRAMES PDF-BUF.A @ + ;
: _PDC-TOP      ( -- fr )  _PDC-NFRAMES 1- _PDC-FRAME@ ;
: _PDC-FRAME+   ( -- ok? )  _PDC-ZERO _PDC-FRAME _PDC-FRAMES _PDC-MSRC PDF-BUF-APPEND ;
: _PDC-POS@     ( -- a u )  _PDC-TOP DUP _PDC.FA @ SWAP _PDC.FU @ ;
: _PDC-POS!     ( a u -- )  _PDC-TOP TUCK _PDC.FU ! _PDC.FA ! ;

: _PDC-GDEPTH  ( -- n )  _PDC-GSTACK PDF-BUF.U @ _PDC-GS-SIZE / ;
: _PDC-SAVE    ( -- ok? )  _PDC-GS _PDC-GS-SIZE _PDC-GSTACK _PDC-MSRC PDF-BUF-APPEND ;
: _PDC-POP-GS  ( -- )
    _PDC-RESIZE
    _PDC-GS-SIZE NEGATE _PDC-GSTACK PDF-BUF.U +!
    _PDC-GSTACK DUP PDF-BUF.A @ SWAP PDF-BUF.U @ + _PDC-GS _PDC-GS-SIZE MOVE ;

\ Q: restore the last save the frame made; a form's own save stays.
: _PDC-RESTORE  ( -- )
    _PDC-TOP DUP _PDC.FDEPTH @ SWAP _PDC.FNUM @ 0<> 1 AND +
    _PDC-GDEPTH < IF _PDC-POP-GS THEN ;

\ The frame ends: its saves are restored and its objects given back.
: _PDC-POP-FRAME  ( -- )
    _PDC-TOP >R
    BEGIN _PDC-GDEPTH R@ _PDC.FDEPTH @ > WHILE _PDC-POP-GS REPEAT
    R@ _PDC.FBUF _PDC-MSRC PDF-BUF-FREE
    R@ _PDC.FRO @ _PDC-FREE  R@ _PDC.FFO @ _PDC-FREE  R> _PDC.FONTO @ _PDC-FREE
    _PDC-FRAME NEGATE _PDC-FRAMES PDF-BUF.U +! ;

\ The last eight operands, as spans and types.
CREATE _PDC-OPS 192 ALLOT
VARIABLE _PDC-NOPS

: _PDC-OP+  ( va vu type -- )
    _PDC-NOPS @ 7 AND 24 * _PDC-OPS + >R  R@ 16 + !  R@ 8 + !  R> !
    1 _PDC-NOPS +! ;

\ Operand K counted back from the operator, 0 the last; or 0 0 PDF-T-END.
: _PDC-OP  ( k -- va vu type )
    DUP _PDC-NOPS @ < 0= OVER 7 > OR IF DROP 0 0 PDF-T-END EXIT THEN
    _PDC-NOPS @ 1- SWAP - 7 AND 24 * _PDC-OPS + DUP @ OVER 8 + @ ROT 16 + @ ;

\ Operand K as a number in 16.16, or 0.
: _PDC-NUM  ( k -- f )
    _PDC-OP DUP PDF-T-INT = SWAP PDF-T-REAL = OR IF PDF-FIXED ELSE 2DROP 0 THEN ;

\ The six operands a matrix operator takes, into _PDC-M.
: _PDC-OPS>M  ( -- )  6 0 DO 5 I - _PDC-NUM I CELLS _PDC-M + ! LOOP ;

\ An array of six numbers into _PDC-M, the identity's where it has fewer.
: _PDC-ARRAY>M  ( va vu -- )
    _PDC-M _PDC-IDENTITY
    PDF-TOKEN DROP 2DROP
    6 0 DO
        PDF-OPERAND DUP PDF-T-INT = SWAP PDF-T-REAL = OR IF
            PDF-FIXED I CELLS _PDC-M + !
        ELSE 2DROP LEAVE THEN
    LOOP 2DROP ;

\ =====================================================================
\  Marked content
\ =====================================================================

VARIABLE _PDC-MCID   VARIABLE _PDC-ART
CREATE _PDC-PAIR 16 ALLOT

\ The innermost MCID, and whether any marked content open is an artifact.
: _PDC-MARKED  ( -- )
    -1 _PDC-MCID !  0 _PDC-ART !
    _PDC-MARKS PDF-BUF.A @  _PDC-MARKS PDF-BUF.U @ 16 / 0 ?DO
        DUP I 16 * + DUP @ DUP 0< 0= IF _PDC-MCID ! ELSE DROP THEN
        8 + @ IF -1 _PDC-ART ! THEN
    LOOP DROP ;

: _PDC-MARK+  ( mcid artifact? -- status )
    _PDC-PAIR 8 + !  _PDC-PAIR !
    _PDC-PAIR 16 _PDC-MARKS _PDC-MSRC PDF-BUF-APPEND
    _PDC-MARKED IF PDF-S-OK ELSE PDF-S-MEMORY THEN ;

: _PDC-ARTIFACT?  ( va vu type -- flag )
    PDF-T-NAME = IF S" Artifact" PDF-NAME= ELSE 2DROP 0 THEN ;

\ The MCID a property list gives, or -1.
: _PDC-PROPS  ( va vu type -- mcid )
    PDF-T-DICT = IF
        S" MCID" 2SWAP PDF-DICT@ PDF-T-INT = IF PDF-INT ELSE 2DROP -1 THEN
    ELSE 2DROP -1 THEN ;

: _PDC-EMC  ( -- )
    _PDC-MARKS PDF-BUF.U @ IF -16 _PDC-MARKS PDF-BUF.U +! THEN _PDC-MARKED ;

\ =====================================================================
\  Fonts
\ =====================================================================

\ The frame's /Font dictionary, looked up once; 0 0 when it has none.
: _PDC-FONTDICT  ( -- da du )
    _PDC-TOP _PDC.FONTU @ 0< IF
        0 _PDC-TOP _PDC.FONTU !
        _PDC-TOP _PDC.FRT @ PDF-T-DICT = IF
            S" Font" _PDC-TOP DUP _PDC.FRA @ SWAP _PDC.FRU @ PDF-DICT@ _PDC-RESOLVE
            ?DUP IF DROP 2DROP DROP _PDC-FREE ELSE
                PDF-T-DICT = IF
                    _PDC-TOP _PDC.FONTU !  _PDC-TOP _PDC.FONTA !  _PDC-TOP _PDC.FONTO !
                ELSE 2DROP _PDC-FREE THEN
            THEN
        THEN
    THEN
    _PDC-TOP DUP _PDC.FONTA @ SWAP _PDC.FONTU @ ;

\ The font the frame's resources name; 0 for one that cannot be read.
: _PDC-FONT-NAMED  ( na nu -- font status )
    _PDC-FONTDICT DUP 0= IF 2DROP 2DROP 0 PDF-S-OK EXIT THEN
    PDF-DICT@ _PDC-F @ _PDC-SET @ PDF-FONTS-GET ;

: _PDC-TF  ( -- status )
    _PDC-RESIZE  0 _PDC-NUM _PDC.TFS !
    1 _PDC-OP PDF-T-NAME <> IF 2DROP 0 _PDC.FONT ! PDF-S-OK EXIT THEN
    1- SWAP 1+ SWAP _PDC-FONT-NAMED SWAP _PDC.FONT ! ;

\ =====================================================================
\  Runs
\ =====================================================================

VARIABLE _PDC-OPEN?               \ a run is open
CREATE _PDC-NEW _PDC-RUN ALLOT    \ the open run
VARIABLE _PDC-RFONT               \ its font
VARIABLE _PDC-X   VARIABLE _PDC-Y   VARIABLE _PDC-SZ   VARIABLE _PDC-ST

: _PDC-TEXT-U  ( -- u )  _PDC-C @ _PDC.TEXT PDF-BUF.U @ ;

\ Close the open run, keeping it when it has text.
: _PDC-CLOSE  ( -- ok? )
    _PDC-OPEN? @ 0= IF -1 EXIT THEN  0 _PDC-OPEN? !
    _PDC-TEXT-U _PDC-NEW 48 + @ - DUP _PDC-NEW 56 + !
    0= IF -1 EXIT THEN
    _PDC-NEW _PDC-RUN _PDC-C @ _PDC.RUNS _PDC-MSRC PDF-BUF-APPEND ;

\ Where the text position is on the page.
: _PDC-HERE  ( -- x y )  0 _PDC.TS @ _PDC-TM _PDC-POINT _PDC-CTM _PDC-POINT ;

\ The text size, as the text and graphics matrices scale it.
CREATE _PDC-TRM 48 ALLOT
: _PDC-SIZE  ( -- size )
    _PDC-SZOK @ IF _PDC-SZC @ EXIT THEN
    _PDC-TM _PDC-CTM _PDC-TRM _PDC-MUL
    _PDC-TRM 16 + @ DUP * _PDC-TRM 24 + @ DUP * + _PDC-SQRT
    _PDC.TFS @ ABS _PDC-F*  DUP _PDC-SZC !  -1 _PDC-SZOK ! ;

: _PDC-STYLE  ( -- flags )
    _PDC.FONT @ PDF-FONT-STYLE
    _PDC.TR @ 3 = IF PDF-RUN-INVISIBLE OR THEN
    _PDC-ART @ IF PDF-RUN-ARTIFACT OR THEN ;

\ Whether two values differ by more than LIMIT.
: _PDC-FAR?  ( a b limit -- flag )  >R - ABS R> > ;

\ Before a show: continue the open run when the show starts where it
\ ended with its font, size, style and MCID; else open another.
: _PDC-BEGIN  ( -- ok? )
    _PDC-HERE _PDC-Y ! _PDC-X !  _PDC-SIZE _PDC-SZ !  _PDC-STYLE _PDC-ST !
    _PDC-OPEN? @ IF
        _PDC-RFONT @ _PDC.FONT @ =
        _PDC-NEW 32 + @ _PDC-SZ @ OVER 32 / _PDC-FAR? 0= AND
        _PDC-NEW 40 + @ _PDC-ST @ = AND
        _PDC-NEW 64 + @ _PDC-MCID @ = AND
        _PDC-X @ _PDC-NEW 16 + @ _PDC-SZ @ 10 / _PDC-FAR? 0= AND
        _PDC-Y @ _PDC-NEW 24 + @ _PDC-SZ @ 10 / _PDC-FAR? 0= AND
        IF -1 EXIT THEN
        _PDC-CLOSE 0= IF 0 EXIT THEN
    THEN
    -1 _PDC-OPEN? !  _PDC.FONT @ _PDC-RFONT !
    _PDC-X @ _PDC-NEW !  _PDC-Y @ _PDC-NEW 8 + !
    _PDC-SZ @ _PDC-NEW 32 + !  _PDC-ST @ _PDC-NEW 40 + !
    _PDC-TEXT-U _PDC-NEW 48 + !  _PDC-MCID @ _PDC-NEW 64 + !
    -1 ;

\ Move the text position TX along the text line, in text space.
: _PDC-ADVANCE  ( tx -- )
    DUP _PDC-TM @ _PDC-F* _PDC-TM 32 + +!
    _PDC-TM 8 + @ _PDC-F* _PDC-TM 40 + +! ;

\ A string's bytes, into _PDC-SB.
: _PDC-BYTES  ( va vu type -- a u ok? )
    >R 2DUP R@ _PDC-SB PDF-BUF.A @ _PDC-SB PDF-BUF.CAP @ PDF-STRING
    DUP _PDC-SB PDF-BUF.CAP @ > IF
        DUP _PDC-SB _PDC-MSRC PDF-BUF-GROW 0= IF DROP 2DROP R> DROP 0 0 0 EXIT THEN
        DROP R@ _PDC-SB PDF-BUF.A @ _PDC-SB PDF-BUF.CAP @ PDF-STRING
    ELSE NIP NIP THEN
    R> DROP _PDC-SB PDF-BUF.A @ SWAP -1 ;

VARIABLE _PDC-TX   VARIABLE _PDC-WS

\ Show a string: each code's characters onto the run, and the text
\ position moved by the codes' advance (PDF 32000-1 section 9.4.4).
: _PDC-SHOW  ( va vu type -- status )
    _PDC.FONT @ 0= IF DROP 2DROP PDF-S-OK EXIT THEN
    _PDC-BYTES 0= IF 2DROP PDF-S-MEMORY EXIT THEN
    DUP 0= IF 2DROP PDF-S-OK EXIT THEN
    _PDC-BEGIN 0= IF 2DROP PDF-S-MEMORY EXIT THEN
    0 _PDC-TX !
    BEGIN DUP WHILE
        _PDC.FONT @ PDF-FONT-NEXT
        1 = OVER 32 = AND _PDC-WS !
        _PDC.FONT @ PDF-FONT-GLYPH
        >R _PDC-C @ _PDC.TEXT _PDC-MSRC PDF-BUF-APPEND 0= IF
            R> DROP 2DROP PDF-S-MEMORY EXIT
        THEN
        R> _PDC.TFS @ * 1000 /  _PDC.TC @ +
        _PDC-WS @ IF _PDC.TW @ + THEN
        _PDC.TH @ _PDC-F* _PDC-TX +!
    REPEAT 2DROP
    _PDC-TX @ _PDC-ADVANCE
    _PDC-HERE _PDC-NEW 24 + ! _PDC-NEW 16 + !  PDF-S-OK ;

\ TJ: strings shown, and numbers moving the text position back by
\ thousandths of the size.
: _PDC-TJ  ( -- status )
    0 _PDC-OP PDF-T-ARRAY <> IF 2DROP PDF-S-OK EXIT THEN
    PDF-TOKEN DROP 2DROP
    BEGIN
        PDF-OPERAND DUP PDF-T-STRING = OVER PDF-T-HEX = OR IF
            _PDC-SHOW ?DUP IF >R 2DROP R> EXIT THEN
        ELSE DUP PDF-T-INT = OVER PDF-T-REAL = OR IF
            DROP PDF-FIXED NEGATE _PDC.TFS @ _PDC-F* 1000 / _PDC.TH @ _PDC-F* _PDC-ADVANCE
        ELSE DROP 2DROP 2DROP PDF-S-OK EXIT THEN THEN
    AGAIN ;

\ Td: the line moved by TX TY, the text position to its start.
: _PDC-TD  ( tx ty -- )
    _PDC-TLM _PDC-POINT _PDC-TLM 40 + ! _PDC-TLM 32 + !
    _PDC-TLM _PDC-TM 48 MOVE ;

: _PDC-T*  ( -- )  0 _PDC.TL @ NEGATE _PDC-TD ;

\ =====================================================================
\  Forms and inline images
\ =====================================================================

VARIABLE _PDC-XN   VARIABLE _PDC-XO
VARIABLE _PDC-PRA   VARIABLE _PDC-PRU   VARIABLE _PDC-PRT

\ Whether form NUM is being drawn.
: _PDC-DRAWING?  ( num -- flag )
    _PDC-NFRAMES 0 ?DO
        DUP I _PDC-FRAME@ _PDC.FNUM @ = IF DROP -1 UNLOOP EXIT THEN
    LOOP DROP 0 ;

\ The XObject the last operand names: its number, or 0.
: _PDC-XOBJECT  ( -- num )
    0 _PDC-OP PDF-T-NAME <> IF 2DROP 0 EXIT THEN
    1- SWAP 1+ SWAP
    _PDC-TOP _PDC.FRT @ PDF-T-DICT <> IF 2DROP 0 EXIT THEN
    S" XObject" _PDC-TOP DUP _PDC.FRA @ SWAP _PDC.FRU @ PDF-DICT@ _PDC-RESOLVE
    ?DUP IF DROP 2DROP DROP _PDC-FREE 2DROP 0 EXIT THEN
    PDF-T-DICT <> IF 2DROP _PDC-FREE 2DROP 0 EXIT THEN
    ROT _PDC-XO !  PDF-DICT@ PDF-T-REF = IF PDF-REF@ DROP ELSE 2DROP 0 THEN
    _PDC-XO @ _PDC-FREE ;

\ Begin reading the form OBJ inside the frame that drew it: under its
\ matrix, with its resources or else its drawer's, its state saved.
: _PDC-FORM  ( obj -- status )
    _PDC-TOP DUP _PDC.FRA @ _PDC-PRA !  DUP _PDC.FRU @ _PDC-PRU !  _PDC.FRT @ _PDC-PRT !
    _PDC-FRAME+ 0= IF _PDC-FREE PDF-S-MEMORY EXIT THEN
    _PDC-TOP >R
    R@ _PDC.FFO !  _PDC-XN @ R@ _PDC.FNUM !  -1 R@ _PDC.FONTU !  _PDC-GDEPTH R> _PDC.FDEPTH !
    _PDC-SAVE 0= IF _PDC-POP-FRAME PDF-S-MEMORY EXIT THEN
    _PDC-TOP _PDC.FFO @ _PDC-TOP _PDC.FBUF _PDC-F @ PDF-STREAM
    PDF-S-MEMORY = IF _PDC-POP-FRAME PDF-S-MEMORY EXIT THEN
    S" Resources" _PDC-TOP _PDC.FFO @ PDF-OBJ-VALUE DROP PDF-DICT@ _PDC-RESOLVE DROP
    DUP PDF-T-DICT = IF
        _PDC-TOP >R  R@ _PDC.FRT !  R@ _PDC.FRU !  R@ _PDC.FRA !  R> _PDC.FRO !
    ELSE
        DROP 2DROP _PDC-FREE
        _PDC-PRA @ _PDC-TOP _PDC.FRA !  _PDC-PRU @ _PDC-TOP _PDC.FRU !
        _PDC-PRT @ _PDC-TOP _PDC.FRT !
    THEN
    S" Matrix" _PDC-TOP _PDC.FFO @ PDF-OBJ-VALUE DROP PDF-DICT@ PDF-T-ARRAY = IF
        _PDC-ARRAY>M  _PDC-M _PDC-CTM _PDC-CTM _PDC-MUL  _PDC-RESIZE
    ELSE 2DROP THEN
    _PDC-TOP DUP _PDC.FBUF PDF-BUF.A @ OVER _PDC.FA !
    DUP _PDC.FBUF PDF-BUF.U @ SWAP _PDC.FU !
    PDF-S-OK ;

\ Do: a form is read; anything else is passed over.
: _PDC-DO  ( -- status )
    _PDC-XOBJECT DUP 0= IF EXIT THEN
    DUP _PDC-DRAWING? IF DROP PDF-S-OK EXIT THEN
    DUP _PDC-XN !  _PDC-GET ?DUP IF
        NIP DUP PDF-S-MEMORY = IF EXIT THEN DROP PDF-S-OK EXIT
    THEN
    DUP PDF-OBJ-STREAM? 0= IF _PDC-FREE PDF-S-OK EXIT THEN
    DUP PDF-OBJ-VALUE DROP S" Subtype" 2SWAP PDF-DICT@ PDF-T-NAME = IF
        S" Form" PDF-NAME=
    ELSE 2DROP 0 THEN
    0= IF _PDC-FREE PDF-S-OK EXIT THEN
    _PDC-FORM ;

: _PDC-WHITE?  ( c -- flag )
    DUP 32 = OVER 10 = OR OVER 13 = OR OVER 9 = OR OVER 12 = OR SWAP 0= OR ;

\ From an inline image's data to past its "EI" between white space.
: _PDC-EI  ( a u -- a' u' )
    BEGIN DUP 2 > WHILE
        OVER C@ _PDC-WHITE? IF
            OVER 1+ C@ 69 = 2 PICK 2 + C@ 73 = AND IF
                DUP 3 = IF 3 _PDC-ADV EXIT THEN
                OVER 3 + C@ _PDC-WHITE? IF 3 _PDC-ADV EXIT THEN
            THEN
        THEN
        1 _PDC-ADV
    REPEAT + 0 ;

\ BI: an inline image's dictionary to "ID", one white space, its data.
: _PDC-BI  ( -- )
    _PDC-POS@
    BEGIN
        PDF-TOKEN DUP PDF-T-END = IF DROP 2DROP _PDC-POS! EXIT THEN
        PDF-T-KEYWORD = IF
            S" ID" COMPARE 0= IF DUP IF 1 _PDC-ADV THEN _PDC-EI _PDC-POS! EXIT THEN
        ELSE 2DROP THEN
    AGAIN ;

\ =====================================================================
\  Operators
\ =====================================================================

\ An operator's bytes, three at most, as a number.
: _PDC-PACK  ( ta tu -- k )
    DUP 3 > IF 2DROP 0 EXIT THEN
    0 SWAP 0 ?DO OVER I + C@ I 8 * LSHIFT OR LOOP NIP ;

: _PDC-OK  ( flag -- status )  IF PDF-S-OK ELSE PDF-S-MEMORY THEN ;

: _PDC-OPERATOR  ( ta tu -- status )
    _PDC-PACK CASE
        0x71 OF _PDC-SAVE _PDC-OK ENDOF                                    \ q
        0x51 OF _PDC-RESTORE PDF-S-OK ENDOF                                \ Q
        0x6D63 OF                                                          \ cm
            _PDC-OPS>M _PDC-M _PDC-CTM _PDC-CTM _PDC-MUL _PDC-RESIZE PDF-S-OK
        ENDOF
        0x5442 OF                                                          \ BT
            _PDC-TM _PDC-IDENTITY _PDC-TLM _PDC-IDENTITY _PDC-RESIZE PDF-S-OK
        ENDOF
        0x6354 OF 0 _PDC-NUM _PDC.TC ! PDF-S-OK ENDOF                      \ Tc
        0x7754 OF 0 _PDC-NUM _PDC.TW ! PDF-S-OK ENDOF                      \ Tw
        0x7A54 OF 0 _PDC-NUM 100 / _PDC.TH ! PDF-S-OK ENDOF                \ Tz
        0x4C54 OF 0 _PDC-NUM _PDC.TL ! PDF-S-OK ENDOF                      \ TL
        0x6654 OF _PDC-TF ENDOF                                            \ Tf
        0x7254 OF 0 _PDC-NUM 16 RSHIFT _PDC.TR ! PDF-S-OK ENDOF            \ Tr
        0x7354 OF 0 _PDC-NUM _PDC.TS ! PDF-S-OK ENDOF                      \ Ts
        0x6454 OF 1 _PDC-NUM 0 _PDC-NUM _PDC-TD PDF-S-OK ENDOF             \ Td
        0x4454 OF                                                          \ TD
            0 _PDC-NUM NEGATE _PDC.TL !  1 _PDC-NUM 0 _PDC-NUM _PDC-TD PDF-S-OK
        ENDOF
        0x6D54 OF                                                          \ Tm
            _PDC-OPS>M  _PDC-M _PDC-TM 48 MOVE  _PDC-M _PDC-TLM 48 MOVE  _PDC-RESIZE PDF-S-OK
        ENDOF
        0x2A54 OF _PDC-T* PDF-S-OK ENDOF                                   \ T*
        0x6A54 OF 0 _PDC-OP _PDC-SHOW ENDOF                                \ Tj
        0x4A54 OF _PDC-TJ ENDOF                                            \ TJ
        0x27 OF _PDC-T* 0 _PDC-OP _PDC-SHOW ENDOF                          \ '
        0x22 OF                                                            \ "
            2 _PDC-NUM _PDC.TW !  1 _PDC-NUM _PDC.TC !  _PDC-T*  0 _PDC-OP _PDC-SHOW
        ENDOF
        0x6F44 OF _PDC-DO ENDOF                                            \ Do
        0x434D42 OF -1 0 _PDC-OP _PDC-ARTIFACT? _PDC-MARK+ ENDOF           \ BMC
        0x434442 OF 0 _PDC-OP _PDC-PROPS 1 _PDC-OP _PDC-ARTIFACT? _PDC-MARK+ ENDOF \ BDC
        0x434D45 OF _PDC-EMC PDF-S-OK ENDOF                                \ EMC
        0x4942 OF _PDC-BI PDF-S-OK ENDOF                                   \ BI
        PDF-S-OK SWAP
    ENDCASE ;

\ Read the frames until the page's ends.
: _PDC-INTERPRET  ( -- status )
    BEGIN
        _PDC-POS@ PDF-OPERAND >R 2SWAP _PDC-POS! R>
        DUP PDF-T-END = IF
            DROP 2DROP
            _PDC-NFRAMES 1 = IF PDF-S-OK EXIT THEN
            _PDC-POP-FRAME  0 _PDC-NOPS !
        ELSE DUP PDF-T-KEYWORD = IF
            DROP _PDC-OPERATOR  0 _PDC-NOPS !
            ?DUP IF EXIT THEN
        ELSE DUP PDF-T-BAD = IF
            DROP 2DROP 0 _PDC-NOPS !
        ELSE _PDC-OP+ THEN THEN THEN
    AGAIN ;

\ =====================================================================
\  Reading a page
\ =====================================================================

\ Give back everything kept while reading.
: _PDC-CLEANUP  ( -- )
    BEGIN _PDC-NFRAMES WHILE _PDC-POP-FRAME REPEAT
    _PDC-GSTACK _PDC-MSRC PDF-BUF-FREE
    _PDC-FRAMES _PDC-MSRC PDF-BUF-FREE  _PDC-MARKS _PDC-MSRC PDF-BUF-FREE
    _PDC-SB _PDC-MSRC PDF-BUF-FREE ;

\ PDF-CONTENT-FREE ( content -- )   Give back the runs and their text.
: PDF-CONTENT-FREE  ( content -- )
    DUP _PDC.MSRC @ ?DUP IF
        >R DUP _PDC.RUNS R@ PDF-BUF-FREE  DUP _PDC.TEXT R> PDF-BUF-FREE
    THEN
    PDF-CONTENT-SIZE 0 FILL ;

VARIABLE _PDC-STATUS

\ PDF-CONTENT-READ ( page fonts content -- status )   An open page's runs.
: PDF-CONTENT-READ  ( page fonts content -- status )
    DUP _PDC-C !  PDF-CONTENT-SIZE 0 FILL  _PDC-SET !
    DUP PDF-PAGE-FILE DUP _PDC-F !  DUP _PDC-C @ _PDC.FILE !
    PDF-FILE-MSRC _PDC-C @ _PDC.MSRC !
    _PDC-GSTACK 4 PDF-BUF-SIZE * 0 FILL  _PDC-RESIZE
    _PDC-GS _PDC-GS-SIZE 0 FILL  _PDC-CTM _PDC-IDENTITY  _PDC-ONE _PDC.TH !
    _PDC-TM _PDC-IDENTITY  _PDC-TLM _PDC-IDENTITY
    0 _PDC-OPEN? !  -1 _PDC-MCID !  0 _PDC-ART !  0 _PDC-NOPS !
    _PDC-FRAME+ 0= IF DROP PDF-S-MEMORY EXIT THEN
    DUP _PDC-TOP _PDC.FBUF PDF-PAGE-CONTENTS
    DUP PDF-S-MEMORY = IF NIP _PDC-CLEANUP EXIT THEN
    _PDC-STATUS !
    PDF-PAGE-RESOURCES _PDC-TOP >R  R@ _PDC.FRT !  R@ _PDC.FRU !  R@ _PDC.FRA !
    -1 R@ _PDC.FONTU !
    R@ _PDC.FBUF PDF-BUF.A @ R@ _PDC.FA !  R@ _PDC.FBUF PDF-BUF.U @ R> _PDC.FU !
    _PDC-INTERPRET
    _PDC-CLOSE 0= IF DROP PDF-S-MEMORY THEN
    DUP 0= IF DROP _PDC-STATUS @ THEN
    _PDC-CLEANUP ;
