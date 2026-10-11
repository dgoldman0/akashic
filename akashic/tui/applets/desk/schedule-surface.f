\ =====================================================================
\  schedule-surface.f - Desk's screens for scheduled runs
\ =====================================================================
\  Two overlays Desk opens above its tiles.  Each is an ordinary UIDL
\  document with a canonical list, so it lowers to rich output like any
\  applet's list:
\
\    the approval     shows a schedule Daybook asks Desk's user to
\                     approve through Desk's schedule broker
\                     (schedule-broker.f): why the Agent could not run
\                     it, when it could not, then its title, when it
\                     runs, the model, provider and limits it names, and
\                     its prompt in full;
\    the permissions  lists the permissions the user granted, each named
\                     by its schedule's title, and revokes them.
\
\  Each overlay keeps its state in its own instance.  Desk launches it,
\  binds it to the broker, sends it every key while it is open, and after
\  each key and each tick calls SCHS-SERVICE, which carries out what the
\  user chose outside the overlay's own callbacks and says whether to
\  close it.
\
\  The approval shows the broker's oldest approval awaiting an answer,
\  and only while it still waits: once the broker withdraws it, the
\  overlay shows nothing of it and closes unanswered.  A allows, and R or
\  Escape refuses.  Allow is locked until the view has shown the
\  request's last line, and is not offered when the Agent could not run
\  the schedule on its model: the catalog does not offer the model, or
\  the prompt is too large for it.  An Agent that only is not connected
\  does not stop it: the run is checked again as it starts.  Allow checks
\  again before it grants, and a grant the permission store refuses
\  keeps the approval open and says why.
\
\  In the permissions, R revokes the selected one, which cancels any run
\  in flight under it, and Escape closes.
\
\  Public API:
\    SCHS-APPROVE-DESC SCHS-PERMS-DESC   ( -- desc )
\    SCHS-OVERLAY?       ( desc -- flag )
\    SCHS-BOX            ( desc -- row col h w )
\    SCHS-APPROVE-BIND   ( id broker style-xt instance -- )
\    SCHS-PERMS-BIND     ( broker label-xt label-context style-xt instance -- )
\    SCHS-SERVICE        ( now instance -- close? )
\ =====================================================================

PROVIDED akashic-desk-schedule-surface

REQUIRE ../../app-desc.f
REQUIRE ../../uidl-tui.f
REQUIRE ../../region.f
REQUIRE ../../keys.f
REQUIRE ../../widgets/list.f
REQUIRE ../../../utils/datetime.f
REQUIRE ../../../utils/string.f
REQUIRE schedule-broker.f

\ =====================================================================
\  Text
\ =====================================================================
\  A text is built in a buffer that grows to what it needs.  Its parts
\  are added twice: once counted, then, given room, written.

  0 CONSTANT _SCHT-BUF
  8 CONSTANT _SCHT-CAP
 16 CONSTANT _SCHT-LEN
 24 CONSTANT _SCHT-WRITE     \ whether parts are written, or only counted
 32 CONSTANT _SCHT-STAMP     \ an RFC 3339 instant, formatted
_SCHT-STAMP DT-RFC3339-UTC-S-LENGTH + 7 + -8 AND CONSTANT _SCHT-SIZE

: _SCHT.BUF    ( t -- a ) _SCHT-BUF + ;
: _SCHT.CAP    ( t -- a ) _SCHT-CAP + ;
: _SCHT.LEN    ( t -- a ) _SCHT-LEN + ;
: _SCHT.WRITE  ( t -- a ) _SCHT-WRITE + ;
: _SCHT.STAMP  ( t -- a ) _SCHT-STAMP + ;

: _SCHT$  ( t -- address length ) DUP _SCHT.BUF @ SWAP _SCHT.LEN @ ;

: _SCHT-FREE  ( t -- )
    DUP _SCHT.BUF @ ?DUP IF FREE THEN _SCHT-SIZE 0 FILL ;

\ Adds text: its bytes, or, while counting, only its length.
: _SCHT+  ( address length t -- )
    >R R@ _SCHT.WRITE @ IF
        R@ _SCHT.BUF @ R@ _SCHT.LEN @ + SWAP DUP >R MOVE R>
    ELSE
        NIP
    THEN
    R> _SCHT.LEN +! ;

: _SCHT-NUM+  ( n t -- ) >R NUM>STR R> _SCHT+ ;

\ Room for U bytes; whether there was memory for it.
: _SCHT-ROOM  ( u t -- flag )
    2DUP _SCHT.CAP @ > 0= IF 2DROP -1 EXIT THEN
    OVER ALLOCATE IF 2DROP DROP 0 EXIT THEN          ( u t new )
    OVER _SCHT.BUF @ ?DUP IF FREE THEN
    OVER _SCHT.BUF !
    _SCHT.CAP ! -1 ;

\ Runs XT ( x t -- ), which adds a text's parts, once counting them and
\ again, given room, writing them: the text, or 0 0 without memory.
: _SCHT-COMPOSE  ( x xt t -- address length )
    >R 0 R@ _SCHT.WRITE ! 0 R@ _SCHT.LEN !
    2DUP R@ SWAP EXECUTE                             ( x xt )
    R@ _SCHT.LEN @ R@ _SCHT-ROOM 0= IF 2DROP R> DROP 0 0 EXIT THEN
    -1 R@ _SCHT.WRITE ! 0 R@ _SCHT.LEN !
    R@ SWAP EXECUTE
    R> _SCHT$ ;

\ A time limit: whole minutes, whole seconds, or milliseconds.
: _SCHT-TIME+  ( ms t -- )
    >R
    DUP 0> OVER 60000 MOD 0= AND IF
        60000 / R@ _SCHT-NUM+ S"  min" R> _SCHT+ EXIT
    THEN
    DUP 0> OVER 1000 MOD 0= AND IF
        1000 / R@ _SCHT-NUM+ S"  s" R> _SCHT+ EXIT
    THEN
    R@ _SCHT-NUM+ S"  ms" R> _SCHT+ ;

\ "TIME to run, N bytes to disclose, M bytes of reply".
: _SCHT-LIMITS+  ( time disclosure output t -- )
    >R ROT R@ _SCHT-TIME+ S"  to run, " R@ _SCHT+
    SWAP R@ _SCHT-NUM+ S"  bytes to disclose, " R@ _SCHT+
    R@ _SCHT-NUM+ S"  bytes of reply" R> _SCHT+ ;

\ An instant in milliseconds, "YYYY-MM-DD HH:MM UTC", or that it is not
\ known.  The RFC 3339 form is reshaped: its T becomes a space, and its
\ seconds and Z the zone's name.
: _SCHT-WHEN+  ( ms t -- )
    >R DUP 0> IF
        1000 / R@ _SCHT.STAMP DT-RFC3339-UTC-S-LENGTH DT-RFC3339-UTC-S NIP 0= IF
            BL R@ _SCHT.STAMP 10 + C!
            S"  UTC" R@ _SCHT.STAMP 16 + SWAP MOVE
            R@ _SCHT.STAMP DT-RFC3339-UTC-S-LENGTH R> _SCHT+ EXIT
        THEN
    ELSE
        DROP
    THEN
    S" at a time not known" R> _SCHT+ ;

\ ", ID WHAT" after a model, when ID is not empty.
: _SCHT-OPTION+  ( id-a id-u what-a what-u t -- )
    >R 2 PICK 0= IF 2DROP 2DROP R> DROP EXIT THEN
    2SWAP S" , " R@ _SCHT+ R@ _SCHT+ R> _SCHT+ ;

\ =====================================================================
\  State
\ =====================================================================

1 CONSTANT _SCHS-K-APPROVE
2 CONSTANT _SCHS-K-PERMS

\ What the user chose.
1 CONSTANT _SCHS-C-ALLOW
2 CONSTANT _SCHS-C-REFUSE
3 CONSTANT _SCHS-C-REVOKE

  0 CONSTANT _SCHS-KIND
  8 CONSTANT _SCHS-BROKER
 16 CONSTANT _SCHS-STYLE
 24 CONSTANT _SCHS-LIST
 32 CONSTANT _SCHS-LIST-RGN
 40 CONSTANT _SCHS-E-LIST
 48 CONSTANT _SCHS-E-STATUS
 56 CONSTANT _SCHS-E-HINT
 64 CONSTANT _SCHS-ROWS
 72 CONSTANT _SCHS-ASK-ID
 80 CONSTANT _SCHS-REQUEST
 88 CONSTANT _SCHS-REASON
 96 CONSTANT _SCHS-READ
104 CONSTANT _SCHS-CHOICE
112 CONSTANT _SCHS-ROW
120 CONSTANT _SCHS-DONE
128 CONSTANT _SCHS-REFRESH
136 CONSTANT _SCHS-SHOWN
144 CONSTANT _SCHS-LABEL-XT
152 CONSTANT _SCHS-LABEL-CTX
160 CONSTANT _SCHS-RID       \ 32 bytes: a permission's RID, as it is revoked
192 CONSTANT _SCHS-TEXT      \ a row's text
_SCHS-TEXT _SCHT-SIZE + CONSTANT _SCHS-STATUS     \ the status line
_SCHS-STATUS _SCHT-SIZE + CONSTANT _SCHS-SIZE

\ The broker, and Desk's style for each element.
: _SCHS.KIND       ( s -- a ) _SCHS-KIND + ;
: _SCHS.BROKER     ( s -- a ) _SCHS-BROKER + ;
: _SCHS.STYLE      ( s -- a ) _SCHS-STYLE + ;
: _SCHS.LIST       ( s -- a ) _SCHS-LIST + ;
: _SCHS.LIST-RGN   ( s -- a ) _SCHS-LIST-RGN + ;
: _SCHS.E-LIST     ( s -- a ) _SCHS-E-LIST + ;
: _SCHS.E-STATUS   ( s -- a ) _SCHS-E-STATUS + ;
: _SCHS.E-HINT     ( s -- a ) _SCHS-E-HINT + ;
: _SCHS.ROWS       ( s -- a ) _SCHS-ROWS + ;
\ The approval shown: its id, its request as the broker last gave it (0
\ once it no longer waits), why the Agent could not run it, and whether
\ its last line has been shown.
: _SCHS.ASK-ID     ( s -- a ) _SCHS-ASK-ID + ;
: _SCHS.REQUEST    ( s -- a ) _SCHS-REQUEST + ;
: _SCHS.REASON     ( s -- a ) _SCHS-REASON + ;
: _SCHS.READ       ( s -- a ) _SCHS-READ + ;
\ The user's choice, the row it is for, and whether Escape closed the
\ permissions.
: _SCHS.CHOICE     ( s -- a ) _SCHS-CHOICE + ;
: _SCHS.ROW        ( s -- a ) _SCHS-ROW + ;
: _SCHS.DONE       ( s -- a ) _SCHS-DONE + ;
\ Whether the rows changed, and whether the status line is on screen.
: _SCHS.REFRESH    ( s -- a ) _SCHS-REFRESH + ;
: _SCHS.SHOWN      ( s -- a ) _SCHS-SHOWN + ;
\ What names a permission's schedule: ( rid context -- address length ).
: _SCHS.LABEL-XT   ( s -- a ) _SCHS-LABEL-XT + ;
: _SCHS.LABEL-CTX  ( s -- a ) _SCHS-LABEL-CTX + ;
: _SCHS.RID        ( s -- rid ) _SCHS-RID + ;
: _SCHS.TEXT       ( s -- t ) _SCHS-TEXT + ;
: _SCHS.STATUS     ( s -- t ) _SCHS-STATUS + ;

: _SCHS-APPROVE?  ( s -- flag ) _SCHS.KIND @ _SCHS-K-APPROVE = ;

\ Sets the status line to one text, or two.
: _SCHS-SAY2  ( a1 u1 a2 u2 s -- )
    >R 2 PICK OVER + R@ _SCHS.STATUS _SCHT-ROOM IF
        -1 R@ _SCHS.STATUS _SCHT.WRITE ! 0 R@ _SCHS.STATUS _SCHT.LEN !
        2SWAP R@ _SCHS.STATUS _SCHT+ R@ _SCHS.STATUS _SCHT+
    ELSE
        2DROP 2DROP 0 R@ _SCHS.STATUS _SCHT.LEN !
    THEN
    0 R> _SCHS.SHOWN ! ;

: _SCHS-SAY  ( address length s -- ) >R 0 0 R> _SCHS-SAY2 ;

\ Why the permission store refused.
: _SCHS-WHY$  ( sperm-status -- address length )
    CASE
        SPERM-S-IO OF S" the permissions could not be written" ENDOF
        SPERM-S-NOMEM OF S" memory ran out" ENDOF
        SPERM-S-BLOCKED OF S" the permissions are blocked" ENDOF
        SPERM-S-NOT-FOUND OF S" it is no longer there" ENDOF
        >R S" the permissions refused" R>
    ENDCASE ;

\ =====================================================================
\  The approval
\ =====================================================================
\  Its rows: a note, when the Agent could not run the schedule, then the
\  schedule's title, when it runs, the model, the provider, the limits
\  and the prompt.

\ Whether the Agent could not run the schedule.
: _SCHS-NOTE?  ( s -- flag ) _SCHS.REASON @ 0<> ;

\ Whether Allow is offered: the Agent could run the schedule, or only is
\ not connected now.
: _SCHS-ALLOWABLE?  ( s -- flag )
    _SCHS.REASON @ DUP 0= SWAP SACT-R-AGENT-UNAVAILABLE = OR ;

\ Row INDEX as the approval's own: -1 for the note, then 0 to 5.
: _SCHS-APPROVE-ROW  ( index s -- row ) _SCHS-NOTE? IF 1- THEN ;

: _SCHS-HEADER$  ( row -- address length )
    CASE
        -1 OF S" Note" ENDOF
         0 OF S" Schedule" ENDOF
         1 OF S" When" ENDOF
         2 OF S" Model" ENDOF
         3 OF S" Provider" ENDOF
         4 OF S" Limits" ENDOF
        >R S" Prompt" R>
    ENDCASE ;

\ What the note says.
: _SCHS-NOTE$  ( reason -- address length )
    CASE
        SACT-R-MODEL-UNAVAILABLE OF
            S" The Agent does not offer this model, so this cannot be allowed."
        ENDOF
        SACT-R-TOO-LARGE OF
            S" The prompt is too large for this model, so this cannot be allowed."
        ENDOF
        SACT-R-AGENT-UNAVAILABLE OF
            S" The Agent is not connected now. A run due while it is not ends blocked."
        ENDOF
        >R S" The Agent cannot run this request, so it cannot be allowed." R>
    ENDCASE ;

\ The model the request names, with its effort, tier and verbosity.
: _SCHS-MODEL+  ( request t -- )
    >R SDSP-OPERANDS$ DROP
    DUP SACT-MODEL$ R@ _SCHT+
    DUP SACT-EFFORT$ S"  effort" R@ _SCHT-OPTION+
    DUP SACT-TIER$ S"  tier" R@ _SCHT-OPTION+
    SACT-O.VERBOSITY @ CASE
        ARVERB-LOW OF S" low" ENDOF
        ARVERB-MEDIUM OF S" medium" ENDOF
        ARVERB-HIGH OF S" high" ENDOF
        >R 0 0 R>
    ENDCASE
    S"  verbosity" R> _SCHT-OPTION+ ;

: _SCHS-LIMITS+  ( request t -- )
    >R SDSP-OPERANDS$ DROP
    DUP SACT-O.TIME @ OVER SACT-O.DISCLOSURE @ ROT SACT-O.OUTPUT @
    R> _SCHT-LIMITS+ ;

\ The text of the approval's ROW.  A request the approval forgot has no
\ rows, so no row's text is asked for.
: _SCHS-BODY$  ( row s -- address length )
    >R
    CASE
        -1 OF R@ _SCHS.REASON @ _SCHS-NOTE$ ENDOF
         0 OF R@ _SCHS.REQUEST @ SDSP-TITLE$ ENDOF
         1 OF R@ _SCHS.REQUEST @ SDSP-TRIGGER$ ENDOF
         2 OF R@ _SCHS.REQUEST @ ['] _SCHS-MODEL+ R@ _SCHS.TEXT _SCHT-COMPOSE ENDOF
         3 OF R@ _SCHS.REQUEST @ SDSP-OPERANDS$ DROP SACT-PROVIDER$ ENDOF
         4 OF R@ _SCHS.REQUEST @ ['] _SCHS-LIMITS+ R@ _SCHS.TEXT _SCHT-COMPOSE ENDOF
         5 OF R@ _SCHS.REQUEST @ SDSP-OPERANDS$ DROP SACT-PROMPT$ ENDOF
        >R 0 0 R>
    ENDCASE
    R> DROP ;

: _SCHS-APPROVE-KEY  ( index widget -- key ) DROP 1+ ;

: _SCHS-APPROVE-FIELD  ( index column widget -- address length )
    LST-CONTEXT@ >R
    SWAP R@ _SCHS-APPROVE-ROW SWAP
    IF R> _SCHS-BODY$ ELSE R> DROP _SCHS-HEADER$ THEN ;

\ Whether the approval still waits: the broker's oldest approval
\ awaiting an answer is still the one shown.  Its request, which the
\ broker may have moved, is taken again, or forgotten.
: _SCHS-ASKING?  ( s -- flag )
    DUP _SCHS.BROKER @ SBRK-ASKING                   ( s id request )
    OVER 3 PICK _SCHS.ASK-ID @ = OVER 0<> AND IF
        NIP SWAP _SCHS.REQUEST ! -1 EXIT
    THEN
    2DROP 0 SWAP _SCHS.REQUEST ! 0 ;

\ The status the approval shows.
: _SCHS-APPROVE-STATUS  ( s -- )
    DUP _SCHS-ALLOWABLE? 0= IF S" This cannot be allowed" ROT _SCHS-SAY EXIT THEN
    DUP _SCHS.READ @ 0= IF S" Read it to the end to allow it" ROT _SCHS-SAY EXIT THEN
    S" A allows it to run when it is due" ROT _SCHS-SAY ;

: _SCHS-APPROVE-SERVICE  ( now s -- close? )
    DUP _SCHS-ASKING? 0= IF 2DROP -1 EXIT THEN
    DUP _SCHS.CHOICE @ ?DUP 0= IF 2DROP 0 EXIT THEN
    0 2 PICK _SCHS.CHOICE !
    _SCHS-C-ALLOW <> IF
        DUP _SCHS.ASK-ID @ 0 3 PICK 3 PICK _SCHS.BROKER @ SBRK-ANSWER DROP
        2DROP -1 EXIT
    THEN
    DUP _SCHS.READ @ 0= IF NIP _SCHS-APPROVE-STATUS 0 EXIT THEN
    \ The Agent may have changed since the approval opened.
    DUP _SCHS.REQUEST @ OVER _SCHS.BROKER @ SBRK-VET OVER _SCHS.REASON !
    DUP _SCHS-ALLOWABLE? 0= IF
        -1 OVER _SCHS.REFRESH ! 0 OVER _SCHS.READ !
        NIP _SCHS-APPROVE-STATUS 0 EXIT
    THEN
    DUP _SCHS.ASK-ID @ -1 3 PICK 3 PICK _SCHS.BROKER @ SBRK-ANSWER
    ?DUP IF
        _SCHS-WHY$ S" Not allowed: " 2SWAP 4 PICK _SCHS-SAY2 2DROP 0 EXIT
    THEN
    2DROP -1 ;

\ =====================================================================
\  The permissions
\ =====================================================================

: _SCHS-STORE  ( s -- store ) _SCHS.BROKER @ SBRK-STORE ;

: _SCHS-READY?  ( s -- flag )
    DUP _SCHS.BROKER @ SBRK-VALID? 0= IF DROP 0 EXIT THEN
    _SCHS-STORE SPERM-STATE@ SPERM-READY = ;

: _SCHS-PERMS-N  ( s -- n )
    DUP _SCHS-READY? IF _SCHS-STORE SPERM-COUNT@ ELSE DROP 0 THEN ;

\ The permission row INDEX shows, or 0.
: _SCHS-PERM  ( index s -- permission|0 )
    OVER 0< OVER _SCHS-PERMS-N 3 PICK > 0= OR IF 2DROP 0 EXIT THEN
    _SCHS-STORE SPERM-NTH ;

\ "Granted WHEN; LIMITS".
: _SCHS-PERMISSION+  ( permission t -- )
    >R S" Granted " R@ _SCHT+
    DUP SPERM-P.GRANTED @ R@ _SCHT-WHEN+
    S" ; " R@ _SCHT+
    DUP SPERM-P.TIME @ OVER SPERM-P.DISCLOSURE @ ROT SPERM-P.OUTPUT @
    R> _SCHT-LIMITS+ ;

\ A permission's schedule's title, as Daybook names it.
: _SCHS-TITLE$  ( permission s -- address length )
    >R SPERM-P.SCHEDULE R@ _SCHS.LABEL-CTX @ R> _SCHS.LABEL-XT @
    ?DUP IF EXECUTE ELSE 2DROP 0 0 THEN
    DUP 0= IF 2DROP S" A schedule Daybook no longer has" THEN ;

\ A permission's key: its serial, which never moves.
: _SCHS-PERMS-KEY  ( index widget -- key )
    LST-CONTEXT@ _SCHS-PERM ?DUP IF SPERM-P.SERIAL @ ELSE 1 THEN ;

: _SCHS-PERMS-FIELD  ( index column widget -- address length )
    LST-CONTEXT@ >R SWAP R@ _SCHS-PERM ?DUP 0= IF DROP R> DROP 0 0 EXIT THEN
    SWAP IF ['] _SCHS-PERMISSION+ R> _SCHS.TEXT _SCHT-COMPOSE EXIT THEN
    R> _SCHS-TITLE$ ;

\ The status the permissions open with.
: _SCHS-PERMS-STATUS  ( s -- )
    DUP _SCHS-READY? 0= IF S" The permissions cannot be read" ROT _SCHS-SAY EXIT THEN
    DUP _SCHS-PERMS-N 0= IF S" No scheduled run has been allowed" ROT _SCHS-SAY EXIT THEN
    S" " ROT _SCHS-SAY ;

\ Revokes the permission the user chose, by a copy of its RID: revoking
\ removes the record.
: _SCHS-PERMS-SERVICE  ( now s -- close? )
    NIP
    DUP _SCHS.DONE @ IF DROP -1 EXIT THEN
    DUP _SCHS.CHOICE @ _SCHS-C-REVOKE <> IF DROP 0 EXIT THEN
    0 OVER _SCHS.CHOICE !
    DUP _SCHS.ROW @ OVER _SCHS-PERM ?DUP 0= IF DROP 0 EXIT THEN
    SPERM-P.RID OVER _SCHS.RID RID-COPY
    DUP _SCHS.RID OVER _SCHS.BROKER @ SBRK-REVOKE ?DUP IF
        _SCHS-WHY$ S" Not revoked: " 2SWAP 4 PICK _SCHS-SAY2
    ELSE
        S" Revoked; any run under it is cancelled" 2 PICK _SCHS-SAY
    THEN
    -1 SWAP _SCHS.REFRESH ! 0 ;

\ =====================================================================
\  Overlay lifecycle
\ =====================================================================

: _SCHS-UIDL  ( -- a u )
    S" <uidl arrange=stack><label id=title/><region id=rows/><label id=status/><label id=hint/></uidl>" ;

: _SCHS-TITLE-TEXT$  ( s -- a u )
    _SCHS-APPROVE? IF S" Approve a scheduled Agent run" ELSE S" Scheduled run permissions" THEN ;

: _SCHS-HINT$  ( s -- a u )
    DUP _SCHS-APPROVE? 0= IF DROP S" Up/Down choose  R revoke  Esc close" EXIT THEN
    _SCHS-ALLOWABLE? IF
        S" Up/Down/PgUp/PgDn read  A allow  R or Esc refuse"
    ELSE
        S" Up/Down/PgUp/PgDn read  R or Esc refuse"
    THEN ;

CREATE _SCHS-COLUMNS 2 LST-COLUMN-SIZE * ALLOT

: _SCHS-COLUMNS-INIT  ( -- )
    _SCHS-COLUMNS 2 LST-COLUMN-SIZE * 0 FILL
    LST-TEXT-COLUMN _SCHS-COLUMNS LST-COLUMN-KIND + !
    _SCHS-COLUMNS LST-COLUMN-SIZE +
        LST-TEXT-COLUMN OVER LST-COLUMN-KIND + !
        LST-COLUMN-WRAP SWAP LST-COLUMN-FLAGS + ! ;

: _SCHS-ROW-N  ( s -- n )
    DUP _SCHS-APPROVE? IF
        DUP _SCHS.REQUEST @ 0= IF DROP 0 EXIT THEN
        _SCHS-NOTE? IF 7 ELSE 6 THEN EXIT
    THEN
    _SCHS-PERMS-N ;

\ Gives the list N rows, its view at the top: a log's rows would show its
\ end, and an approval would seem read before its top was shown.
: _SCHS-ROWS!  ( n s -- )
    2DUP _SCHS.ROWS ! _SCHS.LIST @ TUCK LST-ROWS! 0 SWAP LST-SCROLL-SET ;

: _SCHS-STYLE-ALL  ( s -- )
    _SCHS.STYLE @ ?DUP 0= IF EXIT THEN
    UIDL-ROOT OVER EXECUTE
    UIDL-ROOT ?DUP IF
        UIDL-FIRST-CHILD
        BEGIN ?DUP WHILE 2DUP SWAP EXECUTE UIDL-NEXT-SIB REPEAT
    THEN
    DROP ;

\ Activation runs with the overlay's UIDL context current, before each of
\ its events, ticks and paints.  It keeps the request, the style, the
\ rows, the hint and the status line current.
: _SCHS-ACTIVATE  ( instance -- )
    CINST-STATE >R
    R@ _SCHS-APPROVE? IF R@ _SCHS-ASKING? DROP THEN
    R@ _SCHS-STYLE-ALL
    R@ _SCHS.LIST @ ?DUP IF
        R@ _SCHS-ROW-N DUP R@ _SCHS.ROWS @ <> R@ _SCHS.REFRESH @ OR IF
            NIP R@ _SCHS-ROWS!
            0 R@ _SCHS.REFRESH !
            R@ _SCHS.E-LIST @ ?DUP IF UIDL-DIRTY! THEN
            R@ _SCHS.E-HINT @ ?DUP IF S" text" R@ _SCHS-HINT$ UTUI-SET-ATTR THEN
        ELSE
            2DROP
        THEN
    THEN
    R@ _SCHS.SHOWN @ 0= IF
        -1 R@ _SCHS.SHOWN !
        R@ _SCHS.E-STATUS @ ?DUP IF
            S" text" R@ _SCHS.STATUS _SCHT$ UTUI-SET-ATTR
        THEN
    THEN
    R> DROP ;

\ An approval whose view shows its last line has been read, for good.
: _SCHS-SEEN  ( s -- )
    DUP _SCHS-APPROVE? 0= IF DROP EXIT THEN
    DUP _SCHS.READ @ IF DROP EXIT THEN
    DUP _SCHS.LIST @ ?DUP 0= IF DROP EXIT THEN
    DUP LST-COUNT 0= IF 2DROP EXIT THEN
    LST-SCROLL-INFO + > IF DROP EXIT THEN
    -1 OVER _SCHS.READ !
    _SCHS-APPROVE-STATUS ;

\ After the overlay is drawn, at the size it is shown at.
: _SCHS-PAINT  ( instance -- ) CINST-STATE _SCHS-SEEN ;

: _SCHS-INIT  ( instance kind -- )
    SWAP CINST-STATE >R
    R@ _SCHS-SIZE 0 FILL
    R@ _SCHS.KIND !
    -1 R@ _SCHS.SHOWN !
    S" status" UTUI-BY-ID R@ _SCHS.E-STATUS !
    S" hint" UTUI-BY-ID R@ _SCHS.E-HINT !
    S" title" UTUI-BY-ID ?DUP IF S" text" R@ _SCHS-TITLE-TEXT$ UTUI-SET-ATTR THEN
    S" rows" UTUI-BY-ID DUP R@ _SCHS.E-LIST ! 0= IF R> DROP EXIT THEN
    R@ _SCHS.E-LIST @ UTUI-ELEM-RGN RGN-NEW DUP R@ _SCHS.LIST-RGN !
    R@ _SCHS-APPROVE? IF
        ['] _SCHS-APPROVE-KEY ['] _SCHS-APPROVE-FIELD LST-NEW
        LST-CARDS LST-LOG OR LST-UNTRUSTED OR
    ELSE
        ['] _SCHS-PERMS-KEY ['] _SCHS-PERMS-FIELD LST-NEW
        LST-CARDS LST-UNTRUSTED OR
    THEN
    OVER LST-MODE!
    DUP R@ _SCHS.LIST !
    _SCHS-COLUMNS 2 ROT LST-COLUMNS!
    R@ R@ _SCHS.LIST @ LST-CONTEXT!
    R@ _SCHS.LIST @ R@ _SCHS.E-LIST @ UTUI-WIDGET-SET
    R@ _SCHS.E-LIST @ UTUI-FOCUS!
    R> DROP ;

: _SCHS-APPROVE-INIT  ( instance -- ) _SCHS-K-APPROVE _SCHS-INIT ;
: _SCHS-PERMS-INIT  ( instance -- ) _SCHS-K-PERMS _SCHS-INIT ;

: _SCHS-SHUTDOWN  ( instance -- )
    CINST-STATE >R
    R@ _SCHS.E-LIST @ ?DUP IF 0 SWAP UTUI-WIDGET-SET THEN
    R@ _SCHS.LIST @ ?DUP IF LST-FREE THEN
    R@ _SCHS.LIST-RGN @ ?DUP IF RGN-FREE THEN
    R@ _SCHS.TEXT _SCHT-FREE
    R@ _SCHS.STATUS _SCHT-FREE
    R> _SCHS-SIZE 0 FILL ;

: _SCHS-EV-TYPE  ( ev -- type ) @ ;
: _SCHS-EV-CODE  ( ev -- code ) 8 + @ ;
: _SCHS-EV-PLAIN?  ( ev -- flag )
    16 + @ KEY-MOD-CTRL KEY-MOD-ALT OR AND 0= ;

\ Escape refuses the approval and closes the permissions.  In the
\ approval, A allows and R refuses; in the permissions, R revokes the
\ selected one.  Every other key goes to the list.
: _SCHS-EVENT  ( ev instance -- handled? )
    CINST-STATE >R
    DUP _SCHS-EV-TYPE KEY-T-SPECIAL = IF
        DUP _SCHS-EV-CODE KEY-ESC = IF
            DROP
            R@ _SCHS-APPROVE? IF
                _SCHS-C-REFUSE R@ _SCHS.CHOICE !
            ELSE
                -1 R@ _SCHS.DONE !
            THEN
            R> DROP -1 EXIT
        THEN
    THEN
    DUP _SCHS-EV-TYPE KEY-T-CHAR = OVER _SCHS-EV-PLAIN? AND IF
        DUP _SCHS-EV-CODE 32 OR
        R@ _SCHS-APPROVE? IF
            DUP [CHAR] a = IF 2DROP _SCHS-C-ALLOW R> _SCHS.CHOICE ! -1 EXIT THEN
            [CHAR] r = IF DROP _SCHS-C-REFUSE R> _SCHS.CHOICE ! -1 EXIT THEN
        ELSE
            [CHAR] r = IF
                DROP _SCHS-C-REVOKE R@ _SCHS.CHOICE !
                R@ _SCHS.LIST @ ?DUP IF LST-SELECTED ELSE -1 THEN
                R> _SCHS.ROW ! -1 EXIT
            THEN
        THEN
    THEN
    DROP R> DROP 0 ;

\ =====================================================================
\  Descriptors and Desk's interface
\ =====================================================================

CREATE SCHS-APPROVE-DESC APP-DESC ALLOT
CREATE SCHS-PERMS-DESC APP-DESC ALLOT
CREATE _SCHS-APPROVE-COMP COMP-DESC ALLOT
CREATE _SCHS-PERMS-COMP COMP-DESC ALLOT

: _SCHS-DESC!  ( init-xt title-a title-u id-a id-u comp desc -- )
    >R
    DUP COMP-DESC-INIT
    TUCK COMP.ID-U ! TUCK COMP.ID-A !
    S" 1.0.0" 2 PICK COMP.VERSION-U ! OVER COMP.VERSION-A !
    _SCHS-SIZE OVER COMP.STATE-SIZE !
    R@ APP-DESC-INIT
    R@ APP.COMP-DESC !
    R@ APP.TITLE-U ! R@ APP.TITLE-A !
    R@ APP.INIT-XT !
    ['] _SCHS-SHUTDOWN R@ APP.SHUTDOWN-XT !
    ['] _SCHS-ACTIVATE R@ APP.ACTIVATE-XT !
    ['] _SCHS-EVENT R@ APP.EVENT-XT !
    ['] _SCHS-PAINT R@ APP.PAINT-XT !
    _SCHS-UIDL R@ APP.UIDL-U ! R> APP.UIDL-A ! ;

: _SCHS-SETUP  ( -- )
    _SCHS-COLUMNS-INIT
    ['] _SCHS-APPROVE-INIT S" Approve a run"
        S" org.akashic.desk.schedule-approval" _SCHS-APPROVE-COMP
        SCHS-APPROVE-DESC _SCHS-DESC!
    ['] _SCHS-PERMS-INIT S" Run permissions"
        S" org.akashic.desk.schedule-permissions" _SCHS-PERMS-COMP
        SCHS-PERMS-DESC _SCHS-DESC! ;

_SCHS-SETUP

: SCHS-OVERLAY?  ( desc -- flag )
    DUP SCHS-APPROVE-DESC = SWAP SCHS-PERMS-DESC = OR ;

\ The centred box an overlay of DESC takes: as tall as the screen allows
\ less the taskbar and a row each side, and as wide as a reading column.
: SCHS-BOX  ( desc -- row col h w )
    DROP SCR-H 3 - 6 MAX
    SCR-W 4 - 76 MIN DUP 24 < IF DROP SCR-W 2 - THEN
    OVER SCR-H SWAP - 1- 2 / 0 MAX
    OVER SCR-W SWAP - 2 / 0 MAX
    2SWAP ;

\ Binds a launched approval to the broker's approval ID.  STYLE-XT
\ ( elem -- ) styles each element, or is 0.  Why the Agent could not run
\ it is asked once here, and again as it is allowed.
: SCHS-APPROVE-BIND  ( id broker style-xt instance -- )
    CINST-STATE >R
    R@ _SCHS.STYLE ! R@ _SCHS.BROKER ! R@ _SCHS.ASK-ID !
    0 R@ _SCHS.READ !
    R@ _SCHS-ASKING? IF
        R@ _SCHS.REQUEST @ R@ _SCHS.BROKER @ SBRK-VET R@ _SCHS.REASON !
    THEN
    -1 R@ _SCHS.REFRESH !
    R> _SCHS-APPROVE-STATUS ;

\ Binds a launched permissions list to the broker.  LABEL-XT ( rid
\ context -- address length ) names a permission's schedule, or gives
\ 0 0 for one it does not know.
: SCHS-PERMS-BIND  ( broker label-xt label-context style-xt instance -- )
    CINST-STATE >R
    R@ _SCHS.STYLE ! R@ _SCHS.LABEL-CTX ! R@ _SCHS.LABEL-XT ! R@ _SCHS.BROKER !
    -1 R@ _SCHS.REFRESH !
    R> _SCHS-PERMS-STATUS ;

\ Carries out what the user chose and says whether Desk should close the
\ overlay.  NOW is the wall clock in milliseconds, or -1 while it is not
\ set, for a permission granted.  Desk calls it after the host dispatches
\ each key and on each tick, never from inside the overlay's callbacks.
: SCHS-SERVICE  ( now instance -- close? )
    CINST-STATE DUP _SCHS-APPROVE? IF _SCHS-APPROVE-SERVICE EXIT THEN
    _SCHS-PERMS-SERVICE ;
