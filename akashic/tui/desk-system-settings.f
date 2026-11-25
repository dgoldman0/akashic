\ =====================================================================
\  desk-system-settings.f — Desk's system settings, on the settings disk
\ =====================================================================
\  Megapad-64 / KDOS Forth      Prefix: DSET-
\
\  Desk's system settings live in system.toml on the settings disk, which
\  only the host changes.  Desk with a rich terminal reads them as it
\  starts: they say whether safe mode is on (check-mode.f), set the times
\  of the occasional full refresh (rich-terminal/frame-refresh.f), and say
\  whether the machine may reach this computer and its local network,
\  which Desk then warns of.
\ =====================================================================

PROVIDED akashic-tui-desk-system-settings

REQUIRE platform/settings-disk.f
REQUIRE ../utils/toml.f
REQUIRE check-mode.f
REQUIRE rich-terminal/frame-refresh.f

\ DSET-BOOL? ( a u path-a path-u -- flag )
\   Whether the setting at PATH in the system settings text at A U is the
\   boolean true.  A setting that is missing, or is not a boolean, is
\   false.  The TOML layer's error state and abort switch are left as they
\   were, for whoever parses next.
: DSET-BOOL?  ( a u path-a path-u -- flag )
    TOML-ERR @ >R  TOML-ABORT-ON-ERROR @ >R  0 TOML-ABORT-ON-ERROR !
    TOML-PATH? IF
        2DUP TOML-BOOL? IF TOML-GET-BOOL TOML-OK? AND ELSE 2DROP 0 THEN
    ELSE
        2DROP 0
    THEN
    R> TOML-ABORT-ON-ERROR !  R> TOML-ERR ! ;

\ DSET-SAFE-MODE? ( a u -- flag )
\   Whether the system settings text at A U asks for safe mode:
\   [desk.rich-terminal] safe-mode = true.
: DSET-SAFE-MODE?  ( a u -- flag )
    S" desk.rich-terminal.safe-mode" DSET-BOOL? ;

\ DSET-LOCAL-ACCESS? ( a u -- flag )
\   Whether the system settings text at A U lets the machine reach this
\   computer and its local network: [desk.network] local-access = true.
: DSET-LOCAL-ACCESS?  ( a u -- flag )
    S" desk.network.local-access" DSET-BOOL? ;

\ DSET-LOCAL-ACCESS ( -- addr )
\   Whether the last DSET-APPLY found local access on.
VARIABLE DSET-LOCAL-ACCESS
0 DSET-LOCAL-ACCESS !

\ DSET-LOCAL-ACCESS-WARNING ( -- a u )
\   What Desk says at every start while local access is on.
: DSET-LOCAL-ACCESS-WARNING  ( -- a u )
    S" Local access is on: programs here can reach services on this computer and its local network." ;

\ DSET-MS ( a u path-a path-u -- ms )
\   The setting at PATH in the system settings text at A U, when it is a
\   whole number of milliseconds above zero, or 0.  The TOML layer's error
\   state and abort switch are left as they were.
: DSET-MS  ( a u path-a path-u -- ms )
    TOML-ERR @ >R  TOML-ABORT-ON-ERROR @ >R  0 TOML-ABORT-ON-ERROR !
    TOML-PATH? IF
        2DUP TOML-INTEGER? IF
            TOML-GET-INT TOML-OK? 0= IF DROP 0 THEN
        ELSE 2DROP 0 THEN
    ELSE
        2DROP 0
    THEN
    DUP 0> 0= IF DROP 0 THEN
    R> TOML-ABORT-ON-ERROR !  R> TOML-ERR ! ;

\ DSET-REFRESH ( a u -- )
\   Set the full refresh's times from the system settings text at A U:
\   [desk.rich-terminal] full-refresh-quiet-ms, how long input must be
\   quiet, and full-refresh-interval-ms, the longest time between checks.
\   A time that is missing, or is not a whole number of milliseconds above
\   zero, keeps its default.
: DSET-REFRESH  ( a u -- )
    2DUP S" desk.rich-terminal.full-refresh-quiet-ms" DSET-MS
        ?DUP IF RFSH-QUIET-MS ! THEN
    S" desk.rich-terminal.full-refresh-interval-ms" DSET-MS
        ?DUP IF RFSH-INTERVAL-MS ! THEN ;

\ DSET-APPLY ( -- )
\   Read the system settings and act on them: set the full refresh's
\   times, note in DSET-LOCAL-ACCESS whether local access is on, and turn
\   safe mode on, with the system settings as its reason, when they ask
\   for it.  Settings that are absent or unreadable ask for nothing: they
\   are outside data, not an anomaly.
: DSET-APPLY  ( -- )
    0 DSET-LOCAL-ACCESS !
    S" system.toml" SETDISK-READ IF 2DROP EXIT THEN
    OVER >R 2DUP DSET-REFRESH 2DUP DSET-LOCAL-ACCESS? DSET-LOCAL-ACCESS !
    DSET-SAFE-MODE? R> FREE
    IF CHK-WHY-CONFIG CHK-SAFE-ON THEN ;
