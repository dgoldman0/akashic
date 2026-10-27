\ =====================================================================
\  frame-refresh.f -- the occasional full refresh of a rich screen
\ =====================================================================
\
\  A change whose owner fails to count it leaves the rich screen showing
\  old content: the frame build reuses what an earlier draw captured, so
\  nothing sends the change.  The full refresh bounds how long that lasts.
\  Once input has been quiet for a while, and at least once an interval
\  while a rich screen is shown, the rich terminal's owner runs a check at
\  a moment when no paint is pending.  The check captures every visible
\  document live and compares the capture with the snapshot the screen was
\  built from.  Every change counted since that snapshot asked for a
\  paint, so with none pending the two agree; a difference is a change
\  nothing reported.
\
\  Nothing is sent when they agree.  When they differ, the first
\  difference is kept as a report that names the application, the family
\  and the element, with its revision, and safe mode turns on
\  (check-mode.f).  The next frame is then built in full from live state
\  and goes out whole, so the change reaches the screen, and every frame
\  after it is built in full.
\
\  The two times are settings, kept with Desk's system settings: how long
\  input must be quiet, and the longest time between checks.  The check
\  belongs to whatever captures the screen's documents, which registers it
\  here with its context:
\     check ( context -- compared? differs? )
\  COMPARED? is false when the check could not compare, for instance
\  because the screen has drawn since its snapshot was taken; that check is
\  counted as skipped and the next falls due an interval later.
\
\  RFSH-QUIET-MS     ( -- addr )  quiet time after input, in ms (1000)
\  RFSH-INTERVAL-MS  ( -- addr )  longest time between checks, in ms (5000)
\  RFSH-CHECK!       ( xt context -- )  register the check; 0 0 removes it
\  RFSH-INPUT        ( -- )       input has arrived
\  RFSH-DEADLINE     ( -- ms|-1 ) when the next check falls due, or -1
\  RFSH-SERVICE      ( quiet? -- )  run the check when it is due, if QUIET?
\  RFSH-REPORT!      ( what-a what-u title-a title-u id-a id-u element
\                      revision -- )  keep the first difference's report
\  RFSH-CHECKS, RFSH-MISSED, RFSH-SKIPPED  ( -- addr )  the checks that
\                      compared, those that found a difference, and those
\                      that could not compare
\  The report: RFSH-WHAT-A/U, the family; RFSH-TITLE/-U, the application;
\  RFSH-ID/-U, the element's id; RFSH-ELEMENT, its index or -1;
\  RFSH-REVISION, its revision.
\
\  Prefix: RFSH- (public), _RFSH- (private)

PROVIDED akashic-tui-rterm-rfsh

REQUIRE ../check-mode.f

VARIABLE RFSH-QUIET-MS
1000 RFSH-QUIET-MS !
VARIABLE RFSH-INTERVAL-MS
5000 RFSH-INTERVAL-MS !

VARIABLE RFSH-CHECKS
VARIABLE RFSH-MISSED
VARIABLE RFSH-SKIPPED
0 RFSH-CHECKS ! 0 RFSH-MISSED ! 0 RFSH-SKIPPED !

VARIABLE _RFSH-CHECK-XT
VARIABLE _RFSH-CHECK-CTX
0 _RFSH-CHECK-XT ! 0 _RFSH-CHECK-CTX !

\ When the last check ran, or the check was registered; when input last
\ arrived; and whether a check is owed for the quiet after that input.
VARIABLE _RFSH-LAST
VARIABLE _RFSH-LAST-INPUT
VARIABLE _RFSH-QUIET-OWED
0 _RFSH-LAST ! 0 _RFSH-LAST-INPUT ! 0 _RFSH-QUIET-OWED !

\ ---------------------------------------------------------------------
\ The report
\ ---------------------------------------------------------------------

\ A report names; it holds no content, so a long name is cut here.  The
\ family's name is a string the checking module compiled; the
\ application's title and the element's id are copied, since an
\ application can close and free them.
64 CONSTANT _RFSH-NAME-CAP

VARIABLE RFSH-WHAT-A
VARIABLE RFSH-WHAT-U
CREATE RFSH-TITLE _RFSH-NAME-CAP ALLOT
VARIABLE RFSH-TITLE-U
CREATE RFSH-ID _RFSH-NAME-CAP ALLOT
VARIABLE RFSH-ID-U
VARIABLE RFSH-ELEMENT
VARIABLE RFSH-REVISION
0 RFSH-WHAT-A ! 0 RFSH-WHAT-U ! 0 RFSH-TITLE-U ! 0 RFSH-ID-U !
-1 RFSH-ELEMENT ! 0 RFSH-REVISION !

: _RFSH-NAME!  ( a u dest u-var -- )
    >R SWAP _RFSH-NAME-CAP MIN DUP R> ! MOVE ;

\ RFSH-REPORT! ( what-a what-u title-a title-u id-a id-u element revision -- )
\   A check found a difference: keep its report, unless one is kept
\   already.  The first difference of a session is the one that turned
\   safe mode on.
: RFSH-REPORT!
    ( what-a what-u title-a title-u id-a id-u element revision -- )
    RFSH-WHAT-U @ IF 2DROP 2DROP 2DROP 2DROP EXIT THEN
    RFSH-REVISION ! RFSH-ELEMENT !
    RFSH-ID RFSH-ID-U _RFSH-NAME!
    RFSH-TITLE RFSH-TITLE-U _RFSH-NAME!
    RFSH-WHAT-U ! RFSH-WHAT-A ! ;

\ ---------------------------------------------------------------------
\ When a check falls due
\ ---------------------------------------------------------------------

\ RFSH-CHECK! ( xt context -- )
\   Register the check and its context, or remove it with 0 0.  The first
\   interval runs from now.
: RFSH-CHECK!  ( xt context -- )
    _RFSH-CHECK-CTX ! _RFSH-CHECK-XT !
    MS@ _RFSH-LAST ! 0 _RFSH-QUIET-OWED ! ;

\ RFSH-INPUT ( -- )  Input has arrived: a check is owed once it is quiet.
: RFSH-INPUT  ( -- )
    MS@ _RFSH-LAST-INPUT ! -1 _RFSH-QUIET-OWED ! ;

\ Checks run while a check is registered and safe mode is off: in safe
\ mode every frame is built in full already.
: _RFSH-ARMED?  ( -- flag )
    _RFSH-CHECK-XT @ 0<> CHK-SAFE? 0= AND ;

\ The earlier of two moments, either of which may be -1 for none.
: _RFSH-EARLIER  ( ms1 ms2 -- ms )
    DUP -1 = IF DROP EXIT THEN
    OVER -1 = IF NIP EXIT THEN
    2DUP - 0< IF DROP ELSE NIP THEN ;

: RFSH-DEADLINE  ( -- ms|-1 )
    _RFSH-ARMED? 0= IF -1 EXIT THEN
    _RFSH-LAST @ RFSH-INTERVAL-MS @ +
    _RFSH-QUIET-OWED @ IF
        _RFSH-LAST-INPUT @ RFSH-QUIET-MS @ + _RFSH-EARLIER
    THEN ;

: _RFSH-DUE?  ( -- flag )
    RFSH-DEADLINE DUP -1 = IF DROP 0 EXIT THEN
    MS@ SWAP - 0< 0= ;

\ ---------------------------------------------------------------------
\ Running a check
\ ---------------------------------------------------------------------

: _RFSH-RUN  ( -- )
    MS@ _RFSH-LAST ! 0 _RFSH-QUIET-OWED !
    _RFSH-CHECK-CTX @ _RFSH-CHECK-XT @ EXECUTE
    SWAP 0= IF DROP 1 RFSH-SKIPPED +! EXIT THEN
    1 RFSH-CHECKS +!
    IF 1 RFSH-MISSED +! CHK-WHY-MISSED CHK-SAFE-ON THEN ;

\ RFSH-SERVICE ( quiet? -- )
\   Run the check when one is due, provided QUIET?: no paint is pending,
\   so every change counted since the last draw has been drawn.  A check
\   that is due waits for the next quiet service.
: RFSH-SERVICE  ( quiet? -- )
    0= IF EXIT THEN
    _RFSH-DUE? 0= IF EXIT THEN
    _RFSH-RUN ;
