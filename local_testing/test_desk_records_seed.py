#!/usr/bin/env python3
"""Records a Desk check's applet starts with, seeded where Desk keeps them.

A check's boot writes its applet's records before Desk starts
(akashic_tui.RecordsSeed).  It activates the Practice over the default place
set, as Desk does when it starts, and runs each seed in the home that this
activation gives the stores of the applet's component (PACT-STORE-PLACES).
These checks run the boot's own Forth for it, akashic_tui._DESK_RECORDS_SEED,
with the boot's Practice provisioning before it, on a fresh native machine
(native_forth.py) over a RAM volume laid out as the builder lays out each
form: the shipping form's documents, records and origin places
(_user_volume_boot_lines), and the linked form's one place
(PLACES_BOOT_LINES).  They show that a seed writes in the folder that Desk's
own activation gives the component's stores afterwards, that the boot's
activation leaves no state behind, and that Daybook's sample day becomes
Daybook's document where the home holds none and leaves one that is there.
"""
from __future__ import annotations

import sys
from pathlib import Path

LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui  # noqa: E402
from native_forth import NativeForth  # noqa: E402

ROOTS = (
    "runtime/practice-activation.f",
    "tui/app-desc.f",
    "tui/applets/daybook/shared-document.f",
)
# The id of the component the checks' applet descriptor names.
COMPONENT = "org.example.seeded"
# A document Daybook keeps already, which the sample day must leave alone.
KEPT = "# Daybook"

HELPERS = (
    ': T-VFS  ( -- vfs )',
    '    524288 A-XMEM ARENA-NEW IF -1 THROW THEN',
    '    VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN ;',
    'VARIABLE VOL  VARIABLE PVOL  VARIABLE SET',
    'VARIABLE D-ORIGIN  VARIABLE D-DOCS  VARIABLE D-RECS',
    # An applet's descriptor, its component named COMPONENT and keeping its
    # records in its home, as Daybook's and the Agent's do.  CREATE does not
    # align, so each record sits on a cell boundary in a larger buffer.
    'CREATE T-COMP-RAW COMP-DESC 7 + ALLOT',
    ': T-COMP  ( -- desc ) T-COMP-RAW 7 + -8 AND ;',
    'CREATE T-APP-RAW APP-DESC 7 + ALLOT',
    ': T-APP  ( -- desc ) T-APP-RAW 7 + -8 AND ;',
    ': T-DESCRIPTOR  ( -- )',
    '    T-COMP COMP-DESC-INIT  PLACES-NEED-HOME T-COMP COMP.PLACE-NEEDS !',
    f'    S" {COMPONENT}" T-COMP COMP.ID-U ! T-COMP COMP.ID-A !',
    '    T-APP APP-DESC-INIT  T-COMP T-APP APP.COMP-DESC ! ;',
    # A seed that leaves a file in the home it is given, and notes whether
    # that home was writable; the home's set is freed once the seed returns.
    'VARIABLE SEEDED-WRITABLE',
    ': T-SEED  ( home -- )',
    '    DUP PLACE-WRITABLE? SEEDED-WRITABLE !',
    '    S" /seeded.txt" ROT PLACE-CREATE NIP THROW ;',
    # A file's bytes between << and >>, or [absent].
    'VARIABLE T-FD  VARIABLE T-N',
    'CREATE T-BUF 1024 ALLOT',
    ': T-SHOW  ( path-a path-u -- )',
    '    VOL @ VFS-OPEN DUP T-FD ! 0= IF ." [absent]" EXIT THEN',
    '    T-FD @ VFS-SIZE T-N !',
    '    T-BUF T-N @ T-FD @ VFS-READ-EXACT IF ." [io]" THEN',
    '    T-FD @ VFS-CLOSE  ." <<" T-BUF T-N @ TYPE ." >>" ;',
    # Writes a file of A U at PATH, which must not exist.
    ': T-PUT  ( a u path-a path-u -- )',
    '    2DUP VOL @ VFS-CREATE 0= IF -1 THROW THEN',
    '    VFS-FF-WRITE VOL @ VFS-OPEN? THROW T-FD !',
    '    T-FD @ VFS-WRITE-EXACT THROW  T-FD @ VFS-CLOSE ;',
    # Desk's activation, made after the boot's as Desk makes it.
    'CREATE T-PACT-RAW PACT-SIZE 7 + ALLOT',
    ': T-PACT  ( -- pact ) T-PACT-RAW 7 + -8 AND ;',
)

SUITE = NativeForth(ROOTS, prelude=HELPERS)


def _shipping_places() -> list[str]:
    """The shipping form's places over one RAM volume: the builder's
    folders and names (akashic_tui._user_volume_boot_lines), with the
    origin over the volume's root.  A word compiles them, since S" outside
    a definition reuses one buffer."""

    origin_name, origin_folder, _ = akashic_tui.USER_VOLUME_ORIGIN
    documents_name, documents_folder, _ = akashic_tui.USER_VOLUME_DOCUMENTS
    records_name, records_folder, _ = akashic_tui.USER_VOLUME_RECORDS
    return [
        ': T-PLACES  ( -- )',
        '    T-VFS VOL !',
        *(f'    S" {folder.strip("/")}" VOL @ VFS-MKDIR THROW'
          for folder in akashic_tui.USER_VOLUME_FOLDERS),
        '    S" user" PLACES-VOLUME THROW PVOL !  VOL @ PVOL @ PVOL-ATTACH THROW',
        f'    S" {origin_name}" S" {origin_folder}" PLACE-READ-ONLY PVOL @',
        '        PLACES-DECLARE THROW D-ORIGIN !',
        f'    S" {documents_name}" S" {documents_folder}" PLACE-WRITABLE PVOL @',
        '        PLACES-DECLARE THROW D-DOCS !',
        f'    S" {records_name}" S" {records_folder}" PLACE-WRITABLE PVOL @',
        '        PLACES-DECLARE THROW D-RECS !',
        '    PLSET-NEW THROW SET !',
        '    PLACE-WRITABLE D-DOCS @ SET @ PLSET-GRANT THROW SET @ PLSET-DOCUMENTS!',
        '    PLACE-WRITABLE D-RECS @ SET @ PLSET-GRANT THROW SET @ PLSET-HOME!',
        '    PLACE-READ-ONLY D-ORIGIN @ SET @ PLSET-GRANT THROW SET @ PLSET-ORIGIN!',
        '    SET @ PLACES-DEFAULT! ;',
        'T-PLACES',
    ]


def _linked_places() -> list[str]:
    """The linked form's one place, as its boot declares it
    (akashic_tui.PLACES_BOOT_LINES), over a RAM volume reported as the boot
    volume."""

    return [
        ': T-BOOT-VOLUME  ( -- )',
        '    T-VFS VOL !',
        '    S" boot" PLACES-VOLUME THROW PVOL !  VOL @ PVOL @ PVOL-ATTACH THROW ;',
        'T-BOOT-VOLUME',
        *akashic_tui.PLACES_BOOT_LINES,
    ]


def _run(places: list[str], checks: list[str]) -> str:
    """Run CHECKS on a fresh machine after PLACES, the boot's Practice
    provisioning, the boot's seed helper and Daybook's sample-day seed, and
    return what they printed after RESULT:."""

    program = [
        *places,
        *akashic_tui._DESK_PRACTICE_PROVISION.splitlines(),
        *akashic_tui._DESK_RECORDS_SEED.splitlines(),
        *akashic_tui.DAYBOOK_SAMPLE_DAY_SEED.forth.splitlines(),
        'T-DESCRIPTOR',
        '." RESULT: "',
        *checks,
        'CR',
    ]
    raw = SUITE.run(program, 400_000_000)
    text = "".join(chr(b) if 0x20 <= b < 0x7F or b in (9, 10) else "" for b in raw)
    assert "RESULT:" in text, text[-1200:]
    tail = text.rsplit("RESULT:", 1)[1]
    assert "??" not in tail and "records:" not in tail, tail
    return tail


def _values(tail: str) -> list[str]:
    """The words TAIL printed, each file's bytes kept whole."""

    values: list[str] = []
    while tail:
        head, marker, rest = tail.partition("<<")
        values.extend(head.split())
        if not marker:
            break
        content, _, tail = rest.partition(">>")
        values.append(content)
    return values


# What a seed's check prints: the stack depth is unchanged; the seed's home
# was writable; the boot's activation ended and its set was freed; Desk's
# activation afterwards is active over a sound Practice head, and the home it
# gives the component's stores holds the seed's file.
SEED_CHECKS = [
    # The second DEPTH counts the first one's result as well.
    'DEPTH ' "' T-SEED T-APP _boot-records-in DEPTH 1- = .",
    'SEEDED-WRITABLE @ .',
    '_boot-records-pact PACT-ACTIVE? 0= .  _boot-records-set @ 0= .',
    'T-PACT PACT-INIT  PLACES-DEFAULT T-PACT PACT-ACTIVATE PACT-S-OK = .',
    'T-PACT PACT.MODE @ PACT-M-ACTIVE = .',
    'T-COMP DUP COMP.ID-A @ SWAP COMP.ID-U @ T-PACT PACT-STORE-PLACES PLSET-HOME',
    'S" /seeded.txt" ROT PLACE-RESOLVE NIP 0= .',
]
SEED_PASSES = ["-1"] * 7


def test_a_seed_writes_in_its_applets_folder_under_records() -> None:
    """The shipping form: the seed's home is the folder named by the
    component's id in the records place, and nothing lands in the records
    place's own folder."""

    records = akashic_tui.USER_VOLUME_RECORDS[1]
    tail = _run(_shipping_places(), [
        *SEED_CHECKS,
        f'S" {records}/{COMPONENT}/seeded.txt" VOL @ VFS-RESOLVE 0<> .',
        f'S" {records}/seeded.txt" VOL @ VFS-RESOLVE 0= .',
        # Daybook's sample day, in the folder where the home holds none.
        "' _boot-sample-day T-APP _boot-records-in",
        f'S" {records}/{COMPONENT}/daybook.md" T-SHOW',
        f'S" {records}/daybook.md" T-SHOW',
    ])
    values = _values(tail)
    assert values == [
        *SEED_PASSES, "-1", "-1",
        akashic_tui.DAYBOOK_SAMPLE.decode(), "[absent]",
    ], values


def test_a_seed_writes_in_the_one_place_of_the_linked_form() -> None:
    """The linked form: the home is the documents place too, so components
    share it and the seed writes at its root.  The sample day is written
    there when Daybook keeps no document, and a document Daybook keeps, as
    the image's sample daybook.md is there, stays as it was."""

    tail = _run(_linked_places(), [
        *SEED_CHECKS,
        'S" /seeded.txt" VOL @ VFS-RESOLVE 0<> .',
        f'S" /{COMPONENT}" VOL @ VFS-RESOLVE 0= .',
        "' _boot-sample-day T-APP _boot-records-in",
        'S" /daybook.md" T-SHOW',
        'S" /daybook.md" VOL @ VFS-RM THROW',
        f': T-KEEP  ( -- ) S" {KEPT}" S" /daybook.md" T-PUT ;  T-KEEP',
        "' _boot-sample-day T-APP _boot-records-in",
        'S" /daybook.md" T-SHOW',
    ])
    values = _values(tail)
    assert values == [
        *SEED_PASSES, "-1", "-1",
        akashic_tui.DAYBOOK_SAMPLE.decode(), KEPT,
    ], values
