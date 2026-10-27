"""The rich terminal's owner says when safe mode is on, and why.

Safe mode (tui/check-mode.f) is a mode of the rich terminal's screen, so the
APT-1 owner of the app shell says it, from its service.  These checks run
the owner's production notice words with the app shell's warning notice
replaced by a recorder; nothing else of the shell runs.
"""

import re
from pathlib import Path

import pytest

from rich_terminal_desktop_acceptance import SAFE_MODE_NOTICES
from test_rich_glyph_growth import GrowthHarness
from test_rich_terminal_control_map import (
    MEGAPAD_ROOT, MegaForthRuntime, ROOT, _definitions,
)

EVERY = "every frame is built in full and checked."
NAME = b"the test structure"


class NoticeHarness(GrowthHarness):
    def __init__(self, backend):
        self.runtime = MegaForthRuntime(execution_backend=backend)
        source = "\n".join(path.read_text() for path in (
            ROOT / "akashic/tui/app-shell.f",
            ROOT / "akashic/tui/keys.f",
            MEGAPAD_ROOT / "rich-terminal.f",
            ROOT / "akashic/tui/rich-terminal/frame-refresh.f",
            ROOT / "akashic/tui/app-shell-apt1.f",
        ))
        self.definitions = _definitions(source)
        # APTAS embeds the generic shell descriptor; keep its production
        # offset arithmetic.
        for match in re.finditer(
            r"(?m)^ASHELL-TERMINAL-DESC-SIZE[^\n]* CONSTANT (\S+)", source,
        ):
            self.definitions[match[1]] = match[0]
        self.definitions.update({
            "_APTAS-SAFE-TEXT": "CREATE _APTAS-SAFE-TEXT 256 ALLOT",
            # The full refresh's report, which names a missed change.
            "RFSH-TITLE": "CREATE RFSH-TITLE 64 ALLOT",
            "RFSH-ID": "CREATE RFSH-ID 64 ALLOT",
            "TEST-TOAST": "CREATE TEST-TOAST 256 ALLOT",
            "TEST-TOAST-U": "VARIABLE TEST-TOAST-U",
            "TEST-TOAST-MS": "VARIABLE TEST-TOAST-MS",
            "TEST-TOASTS": "VARIABLE TEST-TOASTS",
            "ASHELL-TOAST-WARNING": (
                ": ASHELL-TOAST-WARNING ( a u ms -- ) TEST-TOAST-MS ! "
                "DUP TEST-TOAST-U ! TEST-TOAST SWAP MOVE 1 TEST-TOASTS +! ;"
            ),
        })
        chunks, seen = [], set()

        def include(name):
            if name in seen:
                return
            seen.add(name)
            declaration = self.definitions[name]
            for token in re.sub(r"\\[^\n]*|\([^)]*\)", "", declaration).split():
                if token != name and token in self.definitions:
                    include(token)
            chunks.append(declaration)

        # The missed change's notice quotes parentheses, which the scan for
        # dependencies takes for a stack comment, so the report it reads is
        # named here.
        for name in ("APTAS-SIZE", "RFSH-REPORT!", "RFSH-WHAT-A", "RFSH-WHAT-U",
                     "RFSH-TITLE", "RFSH-TITLE-U", "RFSH-ID", "RFSH-ID-U",
                     "_APTAS-SAFE-TICK", "CHK-ANOMALY"):
            include(name)
        self.runtime.evaluate("\n".join(chunks).encode(), step_budget=3_000_000)
        self.serial = 0
        self.name = self.allocate(NAME)

    def owner(self):
        """A fresh owner, zeroed as APTAS-INIT leaves the fields it adds."""
        return self.allocate(bytes(self.constant("APTAS-SIZE")))

    def tick(self, owner):
        assert self.results("_APTAS-SAFE-TICK", owner) == ()

    def toasts(self):
        return self.variable("TEST-TOASTS")

    def toast(self):
        address = self.runtime.find("TEST-TOAST").body_address
        return self.runtime.memory.read_bytes(address, self.variable("TEST-TOAST-U")).decode()

    def reset(self):
        for name in ("CHK-SAFE-MODE", "CHK-DAMAGE-A", "CHK-DAMAGE-U", "CHK-DAMAGE-COUNT",
                     "TEST-TOASTS", "RFSH-WHAT-U", "RFSH-TITLE-U", "RFSH-ID-U"):
            self.variable(name, 0)

    def report(self, what: bytes, title: bytes, ident: bytes, element: int, revision: int):
        """Keep a full refresh's report, as the check that found it does."""
        assert self.results(
            "RFSH-REPORT!", self.allocate(what), len(what), self.allocate(title), len(title),
            self.allocate(ident), len(ident), element, revision,
        ) == ()


@pytest.fixture(params=["python", "native"])
def notice(request):
    return NoticeHarness(request.param)


def test_the_owner_says_once_that_safe_mode_is_on_and_why(notice):
    h = notice
    owner = h.owner()
    h.tick(owner)
    assert h.toasts() == 0
    h.variable("CHK-SAFE-MODE", h.constant("CHK-WHY-BOOT"))
    h.tick(owner)
    assert h.toasts() == 1
    assert h.toast() == f"Safe mode is on, as asked at boot: {EVERY}" == SAFE_MODE_NOTICES["boot"]
    assert h.variable("TEST-TOAST-MS") == h.constant("_APTAS-SAFE-NOTICE-MS")
    h.tick(owner)
    assert h.toasts() == 1
    # The first structure a check names is said once, however often it is
    # named again.
    assert h.results("CHK-DAMAGED", h.name, len(NAME)) == ()
    h.tick(owner)
    assert h.toasts() == 2
    assert h.toast() == "A check found the test structure damaged, and the screen did not use it."
    assert h.results("CHK-DAMAGED", h.name, len(NAME)) == ()
    h.tick(owner)
    assert h.toasts() == 2


def test_an_anomaly_s_notice_names_what_was_damaged_and_says_nothing_more(notice):
    h = notice
    h.reset()
    owner = h.owner()
    assert h.results("CHK-ANOMALY", h.name, len(NAME)) == ()
    h.tick(owner)
    assert h.toasts() == 1
    assert h.toast() == ("Safe mode is on: a check found the test structure damaged. "
                         "Every frame is now built in full and checked.")
    h.tick(owner)
    assert h.toasts() == 1


def test_a_missed_change_s_notice_names_where_it_was(notice):
    h = notice
    h.reset()
    owner = h.owner()
    h.report(b"collections", b"File Explorer", b"file-list", 3, 41)
    h.variable("CHK-SAFE-MODE", h.constant("CHK-WHY-MISSED"))
    h.tick(owner)
    assert h.toasts() == 1
    assert h.toast() == (
        "Safe mode is on: a full refresh found a change nothing reported, in "
        "File Explorer (collections, file-list). Every frame is now built in full "
        "and checked."
    )
    h.tick(owner)
    assert h.toasts() == 1
    # A document with no application title, and a family that names no
    # element, say what they can.
    h.reset()
    owner = h.owner()
    h.report(b"dialogs", b"", b"", -1, 0)
    h.variable("CHK-SAFE-MODE", h.constant("CHK-WHY-MISSED"))
    h.tick(owner)
    assert h.toast() == (
        "Safe mode is on: a full refresh found a change nothing reported, in "
        "dialogs. Every frame is now built in full and checked."
    )


def test_the_system_settings_give_their_own_reason(notice):
    h = notice
    h.reset()
    owner = h.owner()
    h.variable("CHK-SAFE-MODE", h.constant("CHK-WHY-CONFIG"))
    h.tick(owner)
    assert h.toast() == f"Safe mode is on, as the system settings ask: {EVERY}" == (
        SAFE_MODE_NOTICES["config"]
    )


def test_the_service_says_it_after_the_publisher_has_run():
    source = (Path(__file__).resolve().parents[1] / "akashic/tui/app-shell-apt1.f").read_text()
    service = re.search(r"(?ms)^: _APTAS-SERVICE(?=\s).*?;\s*$", source)[0]
    assert service.index("APTSCB-SERVICE") < service.index(
        "PT-ST-LOST = IF SCB-S-SESSION-LOST TRUE EXIT THEN\n"
        "    _APTAS-C @ _APTAS-SAFE-TICK\n"
        "    _APTAS-STATUS @ TRUE ;")
    assert "REQUIRE check-mode.f" in source
