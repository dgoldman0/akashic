\ =====================================================================
\  desk-system-settings.f — Desk's system settings, on the settings disk
\ =====================================================================
\  Megapad-64 / KDOS Forth      Prefix: DSET-
\
\  Desk's system settings live in system.toml on the settings disk, which
\  only the host changes.  Desk with a rich terminal reads them as it
\  starts; today they say whether safe mode is on (check-mode.f).
\ =====================================================================

PROVIDED akashic-tui-desk-system-settings

REQUIRE platform/settings-disk.f
REQUIRE ../utils/toml.f
REQUIRE check-mode.f

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

\ DSET-APPLY ( -- )
\   Read the system settings and act on them: turn safe mode on, with the
\   system settings as its reason, when they ask for it.  Settings that
\   are absent or unreadable ask for nothing: they are outside data, not
\   an anomaly.
: DSET-APPLY  ( -- )
    S" system.toml" SETDISK-READ IF 2DROP EXIT THEN
    OVER >R DSET-SAFE-MODE? R> FREE
    IF CHK-WHY-CONFIG CHK-SAFE-ON THEN ;
