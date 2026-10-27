\ =====================================================================
\  desk-system-settings.f — Desk's system settings, on the settings disk
\ =====================================================================
\  Megapad-64 / KDOS Forth      Prefix: DSET-
\
\  Desk's system settings live in system.toml on the settings disk, which
\  only the host changes.  Desk with a rich terminal reads them as it
\  starts: they say whether safe mode is on (check-mode.f), and set the
\  times of the occasional full refresh (rich-terminal/frame-refresh.f).
\ =====================================================================

PROVIDED akashic-tui-desk-system-settings

REQUIRE platform/settings-disk.f
REQUIRE ../utils/toml.f
REQUIRE check-mode.f
REQUIRE rich-terminal/frame-refresh.f

\ DSET-SAFE-MODE? ( a u -- flag )
\   Whether the system settings text at A U asks for safe mode:
\   [desk.rich-terminal] safe-mode = true.  A setting that is missing, or
\   is not a boolean, asks for nothing.  The TOML layer's error state and
\   abort switch are left as they were, for whoever parses next.
: DSET-SAFE-MODE?  ( a u -- flag )
    TOML-ERR @ >R  TOML-ABORT-ON-ERROR @ >R  0 TOML-ABORT-ON-ERROR !
    S" desk.rich-terminal.safe-mode" TOML-PATH? IF
        2DUP TOML-BOOL? IF TOML-GET-BOOL TOML-OK? AND ELSE 2DROP 0 THEN
    ELSE
        2DROP 0
    THEN
    R> TOML-ABORT-ON-ERROR !  R> TOML-ERR ! ;

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
\   times, and turn safe mode on, with the system settings as its reason,
\   when they ask for it.  Settings that are absent or unreadable ask for
\   nothing: they are outside data, not an anomaly.
: DSET-APPLY  ( -- )
    S" system.toml" SETDISK-READ IF 2DROP EXIT THEN
    OVER >R 2DUP DSET-REFRESH DSET-SAFE-MODE? R> FREE
    IF CHK-WHY-CONFIG CHK-SAFE-ON THEN ;
