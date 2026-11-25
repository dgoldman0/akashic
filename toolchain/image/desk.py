"""Desk's composition: the applets an image opens and offers, and the boot
script that starts them.

Until Practices declare their entry lenses (release Part 5a), the image tool
composes Desk's boot from a list of applets: Desk's and each applet's
module, the blank development Practice it provisions, the records an applet
starts with, the sandbox's policy, and the run of Desk itself.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class RecordsSeed:
    """Records a Desk applet starts with, written at boot before Desk starts,
    in the home where Desk keeps that applet's records (_DESK_RECORDS_SEED).
    FORTH defines WORD, ( home -- ), which writes them in HOME through the
    applet's own stores."""

    forth: str
    word: str


# The Desktop profile composes Desk with these applets.  The same table gives
# Desk with a single applet, for checking one applet's work on the optional
# rich terminal before the full Desktop journey runs as regression.
@dataclass(frozen=True)
class DeskApplet:
    """One applet the Desktop profile composes, and how Desk starts it."""

    name: str  # the boot descriptor is _boot-<name>-desc
    module: str
    resources: tuple[str, ...]
    entry: str  # the applet's descriptor word
    ready: tuple[str, ...] = ()  # visible once it has started
    stable: tuple[str, ...] = ()  # visible while it runs
    tile: bool = True  # starts in a tile; otherwise a discoverable built-in
    note: str = ""  # comment above a built-in's registration
    setup: str = ""  # Forth run once its descriptor is filled, before Desk takes it
    seeds: tuple[RecordsSeed, ...] = ()  # records it starts with, in its home


DESK_APPLETS = (
    DeskApplet(
        "pad",
        "tui/applets/pad/pad.f",
        ("tui/applets/pad/pad.uidl", "tui/applets/pad/pad.toml"),
        "PAD-ENTRY",
        ready=("Selection", "Untitled"),
        stable=("Selection", "UTF-8"),
    ),
    DeskApplet(
        "fexp",
        "tui/applets/fexplorer/fexplorer.f",
        ("tui/applets/fexplorer/fexplorer.uidl", "tui/applets/fexplorer/fexplorer.toml"),
        "FEXP-ENTRY",
        ready=("Details", "Tools"),
        stable=("Details", "Tools"),
    ),
    DeskApplet(
        "daybook",
        "tui/applets/daybook/daybook.f",
        ("tui/applets/daybook/daybook.uidl",),
        "DAYBOOK-ENTRY",
        ready=("Entry",),
        stable=("Entry",),
    ),
    DeskApplet(
        "grid",
        "tui/applets/grid/grid.f",
        ("tui/applets/grid/grid.uidl",),
        "GRID-ENTRY",
        ready=("Data", "Grid"),
        stable=("Data", "Grid"),
    ),
    DeskApplet(
        "agent",
        "tui/applets/agent/agent.f",
        ("tui/applets/agent/agent.uidl",),
        "AGENT-ENTRY",
        ready=("Agent",),
        stable=("Agent",),
    ),
    DeskApplet(
        "streams",
        "tui/applets/streams/streams.f",
        ("tui/applets/streams/streams.uidl",),
        "STREAMS-ENTRY",
        tile=False,
        note=(
            "\\ Streams is a discoverable built-in but does not consume a startup tile or\n"
            "\\ start external I/O. Desk and the active Practice still gate explicit work."
        ),
    ),
)
# Applets Desk runs that the Desktop profile does not compose.  Desk with
# one of them checks its work on the optional rich terminal.  Sound Lab,
# Observatory and Worlds stay out of the first release.
ADJACENT_DESK_APPLETS = (
    DeskApplet(
        "soundlab",
        "tui/applets/soundlab/soundlab.f",
        ("tui/applets/soundlab/soundlab.uidl",),
        "SOUNDLAB-ENTRY",
        tile=False,
        note="\\ Sound Lab is a discoverable built-in but does not consume a startup tile.",
    ),
    DeskApplet(
        "observatory",
        "tui/applets/observatory/observatory.f",
        ("tui/applets/observatory/observatory.uidl",),
        "OBSERVATORY-ENTRY",
        ready=("OBSERVATORY / SERIES PROFILE",),
        stable=("OBSERVATORY / SERIES PROFILE",),
    ),
    DeskApplet(
        "worlds",
        "tui/applets/worlds/worlds.f",
        ("tui/applets/worlds/worlds.uidl",),
        "WORLDS-ENTRY",
        ready=("WORLDS / RESERVOIR FACILITY",),
        stable=("WORLDS / RESERVOIR FACILITY",),
    ),
    # Folio Watch, the game library's first game, ships its room as a text
    # map in its origin; no configuration composes it yet.
    DeskApplet(
        "folio",
        "tui/applets/folio/folio.f",
        ("tui/applets/folio/folio.uidl", "tui/applets/folio/reading-room.map"),
        "FOLIO-ENTRY",
        ready=("Night", "Help"),
        stable=("Night",),
    ),
)
_DESK_AGENT_PROVIDER = "tui/applets/agent/providers/devtools/scripted.f"

_DESK_PRACTICE_PROVISION = r"""\ Development-image installation step: provision only genuinely blank media.
\ Existing but invalid slots are deliberately left for Desk recovery.
CREATE _boot-practice-head PHEAD-SIZE ALLOT
CREATE _boot-practice-out PHEAD-SIZE ALLOT
CREATE _boot-practice-store PHEADVFS-SIZE ALLOT
: _boot-practice-id!  ( value id -- ) DUP RID-CLEAR ! ;
: _boot-practice-slot?  ( path-a path-u -- flag )
    VFS-FF-READ PLACES-DEFAULT PLSET-HOME PLACE-OPEN
    IF DROP 0 ELSE VFS-CLOSE -1 THEN ;
: _boot-practice-present?  ( -- flag )
    S" /practice-head-a.bin" _boot-practice-slot?
    S" /practice-head-b.bin" _boot-practice-slot? OR ;
: _boot-practice-provision  ( -- )
    _boot-practice-present? IF EXIT THEN
    PLACES-DEFAULT PLSET-HOME _boot-practice-store PHEADVFS-INIT
        PHEADVFS-S-OK <> ABORT" Practice store init failed"
    _boot-practice-out _boot-practice-store PHEADVFS-LOAD
        PHEADVFS-S-RECOVERY <> ABORT" blank Practice did not enter recovery"
    _boot-practice-head PHEAD-INIT
    1 _boot-practice-head PHEAD.ID _boot-practice-id!
    2 _boot-practice-head PHEAD.CURRENT-ROOT _boot-practice-id!
    _boot-practice-head _boot-practice-store PHEADVFS-REINITIALIZE
        PHEADVFS-S-OK <> ABORT" Practice provision failed" ;
_boot-practice-provision
"""
# A build whose home can be missing, as one with the user volume, provisions
# only a home that is there: a missing one is not blank media, and Desk
# starts in recovery and says why (docs/utils/fs/places.md).
_DESK_PRACTICE_PROVISION_HEAD = (
    ": _boot-practice-provision  ( -- )\n"
    "    _boot-practice-present? IF EXIT THEN\n"
)
_DESK_PRACTICE_PROVISION_HOME_GUARD = (
    ": _boot-practice-provision  ( -- )\n"
    "    PLACES-DEFAULT PLSET-HOME PLACE-STATUS IF EXIT THEN\n"
    "    _boot-practice-present? IF EXIT THEN\n"
)


def _with_practice_home_guard(autoexec: str) -> str:
    """AUTOEXEC with Desk's Practice provisioning left out while the home
    is unavailable.  An autoexec without that provisioning is unchanged."""

    return autoexec.replace(
        _DESK_PRACTICE_PROVISION_HEAD, _DESK_PRACTICE_PROVISION_HOME_GUARD
    )


# Records an applet starts with (RecordsSeed), seeded at boot where Desk will
# keep them.  Desk activates the Practice over the default set when it starts,
# and its stores keep each component's records in the home the activation
# gives that component's stores (PACT-STORE-PLACES): a folder named by the
# component's id under the records place in the shipping form, and the one
# place of the linked form, which is the documents place too.  Desk binds the
# Agent's conversation store, which loads the conversation at once, before
# any applet or boot code runs again, so a seed writes before Desk starts.
# The boot then activates the Practice it has just provisioned over the same
# default set, asks the activation for the set of the stores of the component
# an applet's descriptor names, runs the seed in that set's home, and frees
# the set and the activation.  A seed names no place and no folder: the
# activation decides both, as it does for Desk.
_DESK_RECORDS_SEED = r"""\ Records an applet starts with, seeded where Desk keeps them.
CREATE _boot-records-pact-raw PACT-SIZE 7 + ALLOT
: _boot-records-pact  ( -- pact ) _boot-records-pact-raw 7 + -8 AND ;
VARIABLE _boot-records-set
\ Runs XT ( home -- ) in the home of the stores that keep the records of
\ the component APP-DESC names, the home the activation gives Desk for them.
: _boot-records-in  ( xt app-desc -- )
    _boot-records-pact PACT-INIT
    PLACES-DEFAULT _boot-records-pact PACT-ACTIVATE
        PACT-S-OK <> ABORT" records: Practice activation failed"
    APP.COMP-DESC @ DUP COMP.ID-A @ SWAP COMP.ID-U @
        _boot-records-pact PACT-STORE-PLACES
    DUP 0= ABORT" records: no places for the applet's records"
    DUP _boot-records-set !
    PLSET-HOME DUP 0= ABORT" records: no home for the applet's records"
    SWAP EXECUTE
    _boot-records-set @ PLSET-FREE  0 _boot-records-set !
    _boot-records-pact PACT-DEACTIVATE ;
"""


def _records_seed_lines(applet: DeskApplet) -> str:
    """Forth that seeds APPLET's records (DeskApplet.seeds), each seed's word
    run in the home of its records, once the applet's descriptor is filled."""

    descriptor = f"_boot-{applet.name}-desc"
    return "".join(
        f"{seed.forth}' {seed.word} {descriptor} _boot-records-in\n"
        for seed in applet.seeds
    )


_DESK_SANDBOX_POLICY = r"""\ The product Desktop offers the shared sandbox under this policy.  A run
\ gets ten seconds and twenty milliseconds of each fifty-millisecond tick.
CREATE _boot-sandbox-policy-raw SBOX-LIMITS-SIZE 7 + ALLOT
: _boot-sandbox-policy  ( -- limits ) _boot-sandbox-policy-raw 7 + -8 AND ;
: _boot-sandbox-limit  ( value field -- )
    _boot-sandbox-policy SBOX-LIMIT-CAP
    SBOX-LIMITS-S-OK <> ABORT" sandbox policy refused a limit" ;
: _boot-sandbox  ( -- )
    _boot-sandbox-policy SBOX-LIMITS-BEGIN
        SBOX-LIMITS-S-OK <> ABORT" sandbox policy could not begin"
    1000000 SBOX-LIMIT-INSTRUCTION-BUDGET _boot-sandbox-limit
      16384 SBOX-LIMIT-VALUE-OP-BUDGET _boot-sandbox-limit
    1048576 SBOX-LIMIT-COPY-BUDGET _boot-sandbox-limit
      10000 SBOX-LIMIT-WALL-MS _boot-sandbox-limit
         16 SBOX-LIMIT-DEPTH _boot-sandbox-limit
      65536 SBOX-LIMIT-BLOB-BYTES _boot-sandbox-limit
       1024 SBOX-LIMIT-LIST-COUNT _boot-sandbox-limit
       1024 SBOX-LIMIT-MAP-COUNT _boot-sandbox-limit
       4096 SBOX-LIMIT-INPUT-NODES _boot-sandbox-limit
      65536 SBOX-LIMIT-INPUT-BYTES _boot-sandbox-limit
      16384 SBOX-LIMIT-OUTPUT-ARENA-NODES _boot-sandbox-limit
     262144 SBOX-LIMIT-OUTPUT-ARENA-BYTES _boot-sandbox-limit
       4096 SBOX-LIMIT-OUTPUT-RESULT-NODES _boot-sandbox-limit
      65536 SBOX-LIMIT-OUTPUT-RESULT-BYTES _boot-sandbox-limit
       1024 SBOX-LIMIT-DATA-STACK _boot-sandbox-limit
        256 SBOX-LIMIT-CALL-FRAMES _boot-sandbox-limit
        256 SBOX-LIMIT-LOOP-FRAMES _boot-sandbox-limit
    1048576 SBOX-LIMIT-MEMORY-BYTES _boot-sandbox-limit
    _boot-sandbox-policy SBOX-LIMITS-SEAL
        SBOX-LIMITS-S-OK <> ABORT" sandbox policy could not seal"
    _boot-sandbox-policy 4 1024 20 SBOX-JOB-OTHER-CORES DESK-SANDBOX-CONFIGURE
        SBOX-JOB-S-OK <> ABORT" Desk refused the sandbox policy" ;
_boot-sandbox
"""

_DESK_ANSI_RUN = """." [akashic] starting desktop" CR
: _boot-run-desktop  ( -- ) DESK-RUN ;
' _boot-run-desktop CATCH ?DUP IF
    ." [akashic] desktop exception " . CR
THEN
." [akashic] desktop exited" CR
"""

_DESK_APT1_RUN = """." [akashic boot] entering Desk" CR TX-FLUSH
: _boot-rich-quarantine  ( -- ) BEGIN IDLE AGAIN ;
: _boot-run-desktop  ( -- ) APT1-DESK-RUN ;
: _boot-report-desktop-apt1-error  ( ior -- )
    PT-STREAM-OWNED? IF DROP _boot-rich-quarantine THEN
    ." [akashic] desktop exception " . CR ;
: _boot-desktop-session-entry  ( -- )
    ['] _boot-run-desktop CATCH ?DUP IF
        _boot-report-desktop-apt1-error
    THEN
    PT-STREAM-OWNED? IF _boot-rich-quarantine THEN
    ." [akashic] desktop exited" CR ;
_boot-desktop-session-entry
"""


def desktop_roots(applets, *, rich: bool = False) -> tuple[str, ...]:
    desk = "tui/desk-apt1.f" if rich else "tui/applets/desk/desk.f"
    agent = any(applet.name == "agent" for applet in applets)
    return (
        desk,
        *(applet.module for applet in applets),
        *((_DESK_AGENT_PROVIDER,) if agent else ()),
    )


# Desk's system settings, which the settings disk holds.  Desk with a rich
# terminal reads them as it starts (tui/desk-system-settings.f).
DESK_SYSTEM_SETTINGS = "tui/applets/desk/system.toml"
# The settings disk's sectors: the RTL settings slot's default window.
SETTINGS_DISK_SECTORS = 2048


def desktop_resources(applets) -> tuple[str, ...]:
    return (
        "tui/applets/desk/desk.toml",
        *(resource for applet in applets for resource in applet.resources),
    )


# How the Desktop hands Desk the Agent's scripted provider, which focused
# profiles replace with their own.
_DESK_AGENT_SOURCE_BOOT = (
    ": _boot-agent-source  ( -- )\n"
    '    SCRIPTED-SOURCE-NEW 0<> ABORT" scripted source allocation failed"\n'
    "    DESK-AGENT-SOURCE! ;"
)


def desktop_autoexec(applets, *, rich: bool = False) -> str:
    """Desk's autoexec: load Desk and APPLETS, provision a blank Practice,
    seed the records an applet starts with in its home, start each tile
    applet, register each built-in, then run Desk, either in the ANSI
    terminal or as the optional rich terminal's session."""

    agent = any(applet.name == "agent" for applet in applets)
    parts = [
        "\\ autoexec.f - Akashic desktop profile\nENTER-USERLAND\n",
        (
            '." [akashic boot] configuring Desk" CR TX-FLUSH\n'
            if rich
            else '." [akashic] loading desktop" CR\n'
        ),
    ]
    parts.extend(f"REQUIRE {root}\n" for root in desktop_roots(applets, rich=rich))
    if agent:
        parts.append(_DESK_AGENT_SOURCE_BOOT + "\n_boot-agent-source\n")
    parts.append("\n" + _DESK_PRACTICE_PROVISION)
    if rich:
        parts.append('." [akashic boot] Practice ready" CR TX-FLUSH\n')
    if any(applet.seeds for applet in applets):
        parts.append("\n" + _DESK_RECORDS_SEED)
    blocks = []
    for applet in applets:
        descriptor = f"_boot-{applet.name}-desc"
        if applet.tile:
            blocks.append(
                f"CREATE {descriptor} APP-DESC ALLOT\n"
                f"{descriptor} {applet.entry}\n"
                f"{applet.setup}"
                f"{_records_seed_lines(applet)}"
                f"{descriptor} DESK-QUEUE-LAUNCH\n"
            )
        else:
            blocks.append(
                f"{applet.note}\n"
                f"CREATE {descriptor} APP-DESC ALLOT\n"
                f"{descriptor} {applet.entry}\n"
                f"{applet.setup}"
                f"{_records_seed_lines(applet)}"
                f"{descriptor}\n"
                "ACAT-F-ENABLED ACAT-F-PINNED OR ACAT-F-BUILTIN OR\n"
                "DESK-QUEUE-BUILTIN\n"
            )
    parts.append("\n" + "\n".join(blocks))
    if rich:
        parts.append('." [akashic boot] app descriptors ready" CR TX-FLUSH\n')
    parts.append("\n" + _DESK_SANDBOX_POLICY)
    parts.append("\n" + (_DESK_APT1_RUN if rich else _DESK_ANSI_RUN))
    return "".join(parts)


def desktop_ready_markers(applets) -> tuple[str, ...]:
    return tuple(marker for applet in applets for marker in applet.ready)


def desktop_stable_markers(applets) -> tuple[str, ...]:
    return tuple(marker for applet in applets for marker in applet.stable)


def desktop_composes(name: str) -> bool:
    """Whether the Desktop profile composes the Desk applet NAME."""

    return any(applet.name == name for applet in DESK_APPLETS)


def desk_applet(name: str) -> DeskApplet:
    """The Desk applet NAME, from the Desktop's or the adjacent ones."""

    for applet in (*DESK_APPLETS, *ADJACENT_DESK_APPLETS):
        if applet.name == name:
            return applet
    raise ValueError(f"no Desk applet {name!r}")
