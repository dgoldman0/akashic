"""A boot from token forms builds the dictionary its source boot builds.

A module's token form is the record of what the interpreter did with its
source (MegaPad's docs/token-modules-proposal-2026-11-11.md).  This test is
the proof that replaying the records gives what the source gives.  For the
Desktop, linked and from its system volume, it builds one image from source
and one with ``--token-modules``, boots both on the emulator until
everything is loaded and the prompt returns, and compares what the two boots
built: every dictionary entry, the pointers, the terminal output, and every
byte of both dictionary regions.

The image is ``desktop-apt1`` with one line added to its boot script, before
the last: a definition that hides the session entry with a word that prints
a mark and returns.  The modules, their order and every chunk are the
Desktop's own.  The system-volume pair's token image is the one that ships:
a volume of token files and no source.

What makes it fail
------------------
The two boots must agree on the structure outright:

* the entries of the dictionary: every address, every name, every flag
  byte, in the same order;
* ``HERE``, ``LATEST`` and the system dictionary's ``HERE``;
* the terminal output, byte for byte.

They do not agree on every byte, and cannot: a token file is smaller than
its source, so the loader's buffers are other sizes and what the load
allocates lies at other addresses, and the loader's own cursors and counts
describe other files.  Every byte that differs must therefore be one of
three things, and the test fails on any other:

``address``
    The bytes lie in one cell, and the cell's value in each boot is an
    address that boot's load allocated: it lies in the external memory the
    allocator had handed out when the boot reached the prompt, below the
    userland dictionary or between its limit and ``XMEM-HERE``.  A cell
    whose value in either boot lies anywhere else fails.

``state``
    The bytes lie in the data field of a ``VARIABLE`` or ``CREATE``d word
    that ``STATE`` below lists, each with the reason its data follows the
    files that were read.  The data field is found from the word's own
    code, so a byte that differs in a colon definition, in a name or in a
    link fails whatever the word is called.

``clock``
    The same, for the one word in ``CLOCK``, whose data is set from a clock
    when its module loads.

The lists are closed in both directions: a listed word that explains no
byte in the pair it is listed for fails too, so an entry that is no longer
needed cannot stay.

Running it
----------
The test builds four images and boots each on the emulator, about seven
minutes and 1.5 GiB at its peak, so it is a heavyweight run: one at a time.
It needs the pinned e2fsprogs that ``AKASHIC_E2FSPROGS_TOOL_DIR`` names for
the system-volume pair.  Each pair's report is printed, and written to the
folder ``AKASHIC_TOKEN_EQUIVALENCE_REPORTS`` names when it is set.  The
reports of the run of record are in
``local_testing/evidence/token-equivalence-20261111.md``.
"""

from __future__ import annotations

import bisect
import os
import time
from dataclasses import dataclass, field, replace
from pathlib import Path

import pytest

MARK = "[token-eq] boot loaded"
PROFILE = "desktop-apt1"
EQUIVALENCE_PROFILE = "desktop-apt1-eq"
LINKED = "linked"
VOLUME = "system volume"
BOTH = (LINKED, VOLUME)

# Words whose data follows the files that were read.  A name that ends in
# an asterisk stands for the words that begin with it; each such family is
# one module's private scratch, named with the module's prefix.
#
#   (word, the pairs it differs in, why)
STATE: tuple[tuple[str, tuple[str, ...], str], ...] = (
    # KDOS: the allocator.
    ("XMEM-HERE", BOTH,
     "the allocator's high-water mark: a source load's buffers are larger than a token load's"),
    ("XMEM-FLOOR", (LINKED,),
     "a copy of that mark, taken when a module reserved a buffer during the load"),
    # KDOS: the boot volume.  The two images hold other files on it.
    ("BOOT-BD", BOTH, "the boot disk's record of its last request: the sector of another file"),
    ("FSCRATCH", BOTH, "MP64FS's one-sector scratch: the sector read last"),
    ("FS-BMAP", BOTH,
     "the boot volume's allocation bitmap, read into memory: files of other sizes fill it"),
    ("FS-DIR", BOTH,
     "the boot volume's directory, read into memory: each file's sectors, length, time and checksum"),
    ("FD-POOL", BOTH, "the file descriptors: the place and length of the file opened last"),
    ("FR-LEN", BOTH, "FREAD's cell for the length asked for last"),
    ("FR-REM", BOTH, "FREAD's cell for the bytes that remained"),
    ("FR-POS", BOTH, "FREAD's cell for its place in the file"),
    # KDOS: the loader.
    ("_LD-RUN-SEC", BOTH, "the first sector of the run the loader read last"),
    ("_LD-RUN-CNT", BOTH, "the sectors of that run"),
    ("_LD-FILE", BOTH, "the record of the file resolved last: its identity, length and handle"),
    ("_LD-TNAME", (VOLUME,), "the path resolved last, with the t that ends a token form's name"),
    ("_LD-TOKENS-CHOSEN", (VOLUME,), "set when the last resolution found a token form"),
    ("_LD-NAMES", (VOLUME,), "the name each loader frame's file was found by: with the t in the token boot"),
    ("_LD-STK", (VOLUME,),
     "the loader's saved frames: the cursor and remaining length of a file that was loading"),
    ("MODULE-TOKENS", (VOLUME,), "the switch that the token boot's script sets"),
    ("LOAD-STAMP", BOTH, "the stamp of the load, which only a boot that meets a token file starts"),
    ("_TKF-A", BOTH, "the token file whose header was checked last; the source boot checks none"),
    ("_TKF-U", BOTH, "that file's length"),
    ("_SEC-CUR", BOTH, "the checked source evaluator's cursor; the token boot walks no source chunk"),
    ("_SEC-RAW-LEN", BOTH, "the length of the last line it walked"),
    ("_SEC-EVAL-LEN", BOTH, "that length without the line's CR"),
    ("_SEC-LINE", BOTH, "that line's number"),
    ("_PS-REM", BOTH,
     "the module prescan's count of bytes left; a token file's header names its module instead"),
    # KDOS: the registry of loaded files.
    ("_MOD-FILE-KEY", BOTH, "the key of the file noted last: the identity of another file"),
    ("_MOD-INLINE", (VOLUME,),
     "the registry's first buckets, which chain the files' keys: other identities hash elsewhere"),
    ("_MF-H", (VOLUME,), "the hash of the key looked up last"),
    # Akashic: the cold-source loader's record of the container loaded last.
    ("_CSL-HEADER", BOTH, "that container's header: its sizes and checksum"),
    ("_CSL-FILE-U", BOTH, "its length"),
    ("_CSL-PAYLOAD-U", BOTH, "its payload's length"),
    ("_CSL-RAW-U", BOTH, "its content's length"),
    ("_CSL-CRC", BOTH, "its content's checksum"),
    ("_CSL-READ-U", BOTH, "the bytes read from it"),
    # Akashic: the ext4 driver.  The two boots mount different volumes, one
    # of source files and one of token files, and each routine of the driver
    # keeps what it worked on last in cells named with the routine's prefix.
    ("_EXT4-SV-*", (VOLUME,), "the superblock check: the volume's stored checksum"),
    ("_EXT4-GDC-*", (VOLUME,), "the group descriptor check: its stored and computed checksums"),
    ("_EXT4-VG-*", (VOLUME,), "the group validation: the group's count of free blocks"),
    ("_EXT4-BM-*", (VOLUME,), "the block bitmap check: the bitmap's stored checksum"),
    ("_EXT4-OCV-*", (VOLUME,), "the orphan file check: its block's stored checksum"),
    ("_EXT4-CRC-STATE", (VOLUME,), "the CRC-32C of the block checked last"),
    ("_EXT4-BX-*", (VOLUME,), "the length of the span comparison made last"),
    ("_EXT4-RAR-*", (VOLUME,), "the block range whose allocation was checked last"),
    ("_EXT4-IR-*", (VOLUME,), "the inode loaded last: its number, place and checksum"),
    ("_EXT4-EV-*", (VOLUME,), "the extents of the file whose extent tree was walked last"),
    ("_EXT4-RD-*", (VOLUME,), "the descriptor of the file read last"),
    ("_EXT4-DR-*", (VOLUME,), "the read made last: its blocks, offset and lengths"),
    ("_EXT4-DS-*", (VOLUME,), "the directory search made last: the name's length and the inode found"),
    ("_EXT4-DN-*", (VOLUME,), "the length of the directory entry's name compared last"),
    ("_EXT4-DV-*", (VOLUME,), "the directory block checked last: its stored checksum and last record"),
    ("_EXT4-PS-*", (VOLUME,), "the driver's copies of the blocks it read last"),
    ("_EXT4-JMM-*", (VOLUME,), "the key of the journal snapshot: the volume's journal tuple and sizes"),
    # Akashic: the VFS over those volumes, and its MP64FS binding.
    ("_VR-PATH-A", (VOLUME,), "the path resolved last"),
    ("_VFC-H", BOTH, "the hash of the name looked up last"),
    ("_VUC-U", (VOLUME,), "the length of the name looked up last"),
    ("_VCDN-*", (VOLUME,), "the directory entry cached last: its name's length and its file's id"),
    ("_VFV-*", (VOLUME,), "the file looked up last: its id and that id's hash"),
    ("_VRD-*", (VOLUME,), "the read made last: the length asked for and the bytes given"),
    ("_VRE-ACT", (VOLUME,), "the bytes the last exact read gave"),
    ("_VMRW-SSEC", BOTH, "the first sector of the last transfer on the boot volume"),
    ("_VMZR-START", BOTH, "the first sector of the run the MP64FS binding cleared last"),
)

# Words whose data is set from a clock when their module loads.
CLOCK: tuple[tuple[str, tuple[str, ...], str], ...] = (
    ("DNS-ID", BOTH, "the next DNS query's identifier, taken from the timer when networking loads"),
)


@dataclass
class Snapshot:
    """What one boot built, taken when it idles at the prompt."""

    image: Path
    instructions: int
    cycles: int
    seconds: float
    here: int
    latest: int
    system_here: int
    entries: tuple[tuple[int, int, str], ...]
    ranges: dict[str, tuple[int, int]]
    bytes: dict[str, bytes]
    allocated: tuple[tuple[int, int], ...]
    uart: str


def build(directory: Path, layout: str, *, token_modules: bool) -> Path:
    """Build the Desktop for LAYOUT with the boot that stops at the prompt."""

    import akashic_tui as tui

    profile = tui.PROFILES[PROFILE]
    lines = profile.autoexec.splitlines()
    assert lines[-1].strip() == profile.session_entry
    lines[-1:] = [
        f': {profile.session_entry}  ( -- ) ." {MARK}" CR TX-FLUSH ;',
        profile.session_entry,
    ]
    tui.PROFILES[EQUIVALENCE_PROFILE] = replace(
        profile, autoexec="\n".join(lines) + "\n"
    )
    try:
        return tui.build_image(
            EQUIVALENCE_PROFILE,
            directory / ("tokens.img" if token_modules else "source.img"),
            backend="emulator",
            system_volume=layout == VOLUME,
            token_modules=token_modules,
        )
    finally:
        del tui.PROFILES[EQUIVALENCE_PROFILE]


def snapshot(image: Path, *, wall: float = 840.0) -> Snapshot:
    """Boot IMAGE on the emulator until it idles at the prompt and take
    what the load built."""

    import akashic_tui as tui
    from emulator.session import MachineSession, _load_bios
    from emulator.system import EXT_MEM_BASE

    megapad = Path(os.environ["MEGAPAD_ROOT"]) if "MEGAPAD_ROOT" in os.environ else tui.MEGAPAD_ROOT
    companions = {
        name: image.with_name(f"{image.stem}-{name}{image.suffix}")
        for name in ("settings", "system")
    }
    profile = tui.PROFILES[PROFILE]
    code, labels = _load_bios(megapad / "bios.asm")
    started = time.perf_counter()
    total = 0
    with MachineSession.from_bios(
        megapad / "bios.asm",
        storage_image=image,
        settings_image=companions["settings"] if companions["settings"].is_file() else None,
        system_image=companions["system"] if companions["system"].is_file() else None,
        cols=tui.DESKTOP_ACCEPTANCE_COLS,
        rows=tui.DESKTOP_ACCEPTANCE_ROWS,
        batch_steps=500_000,
        ext_mem_size=profile.default_ext_mem_mib << 20,
    ) as session:
        system = session.system
        session.boot()
        marked = False
        quiet = 0
        loaded = False
        while total < tui.DESKTOP_SMOKE_MAX_STEPS and time.perf_counter() - started < wall:
            report = session.run(
                max_steps=2_000_000, wall_timeout_s=10.0, advance_idle=False
            )
            total += report.steps
            raw = session.raw_text()
            if "FAIL" in raw or "uncaught" in raw or " ? (not found)" in raw:
                break
            marked = marked or MARK in raw
            if marked:
                # The prompt follows the mark; the machine then waits.
                quiet = quiet + 1 if report.steps < 2_000_000 else 0
                if quiet >= 2 or report.reason in ("halted", "stalled", "idle"):
                    loaded = True
                    break
            elif report.reason == "halted":
                break
        raw = session.raw_text()
        assert loaded, f"{image.name} did not reach the prompt:\n{raw[-1200:]}"

        def span(start: int, end: int) -> bytes:
            if start >= EXT_MEM_BASE:
                return bytes(system._ext_mem[start - EXT_MEM_BASE : end - EXT_MEM_BASE])
            return bytes(system.cpu.mem[start:end])

        def cell(address: int) -> int:
            return int.from_bytes(span(address, address + 8), "little")

        entries = []
        entry = cell(labels["var_latest"])
        while entry:
            flags = span(entry + 8, entry + 9)[0]
            name = span(entry + 9, entry + 9 + (flags & 0x7F)).decode("latin-1")
            entries.append((entry, flags, name))
            entry = cell(entry)
        by_name: dict[str, int] = {}
        for address, _flags, name in entries:
            by_name.setdefault(name.upper(), address)

        def variable(name: str) -> int:
            address = by_name[name]
            flags = span(address + 8, address + 9)[0]
            # A VARIABLE's code begins `ldi64 r1, <address of its cell>`:
            # three bytes of opcode, then the address.
            return cell(cell(address + 9 + (flags & 0x7F) + 3))

        here = cell(labels["var_here"])
        system_here = variable("SYS-HERE-SAVE")
        bank0 = min(a for a, _f, _n in entries if len(code) <= a < EXT_MEM_BASE)
        ext = min(a for a, _f, _n in entries if a >= EXT_MEM_BASE)
        ranges = {"bank 0": (bank0, system_here), "external": (ext, here)}
        return Snapshot(
            image=image,
            instructions=total,
            cycles=int(system._native_system.system_cycles),
            seconds=round(time.perf_counter() - started, 1),
            here=here,
            latest=entries[0][0],
            system_here=system_here,
            entries=tuple(entries),
            ranges=ranges,
            bytes={region: span(*bounds) for region, bounds in ranges.items()},
            # What the allocator had handed out: external memory below the
            # userland dictionary, and from its limit to the high-water mark.
            allocated=(
                (EXT_MEM_BASE, variable("U-DICT-BASE")),
                (variable("U-DICT-LIMIT"), variable("XMEM-HERE")),
            ),
            uart=raw,
        )


def _listed(name: str, table) -> tuple[str, tuple[str, ...], str] | None:
    for entry in table:
        word = entry[0]
        if name == word or (word.endswith("*") and name.startswith(word[:-1])):
            return entry
    return None


@dataclass
class Comparison:
    lines: list[str] = field(default_factory=list)
    failures: list[str] = field(default_factory=list)
    words: dict[str, dict[str, int]] = field(default_factory=dict)

    def report(self) -> str:
        return "\n".join(self.lines + [f"FAIL: {failure}" for failure in self.failures])


def compare(
    source: Snapshot,
    tokens: Snapshot,
    layout: str,
    *,
    state=None,
    clock=None,
) -> Comparison:
    """Compare what two boots built and put every differing byte to its
    class.  The module's text says what fails."""

    state = STATE if state is None else state
    clock = CLOCK if clock is None else clock
    result = Comparison()
    say = result.lines.append
    fail = result.failures.append
    say(f"{layout}: source {source.instructions:,} instructions, {source.cycles:,} cycles; "
        f"tokens {tokens.instructions:,} instructions, {tokens.cycles:,} cycles")
    for what, a, b in (
        ("HERE", source.here, tokens.here),
        ("LATEST", source.latest, tokens.latest),
        ("the system dictionary's HERE", source.system_here, tokens.system_here),
        ("the dictionary regions", source.ranges, tokens.ranges),
    ):
        if a == b:
            say(f"  {what}: the same")
        else:
            fail(f"{what} differs: {a} / {b}")
    if source.entries == tokens.entries:
        say(f"  entries: {len(source.entries):,}, each at the same address "
            "with the same name and flags")
    else:
        fail(f"the entries differ ({len(source.entries):,} / {len(tokens.entries):,})")
    if source.uart == tokens.uart:
        say(f"  terminal output: identical, {len(source.uart):,} characters")
    else:
        fail("the terminal output differs")
    say(f"  allocated external memory: source {_spans(source.allocated)}, "
        f"tokens {_spans(tokens.allocated)}")

    starts = sorted(entry[0] for entry in source.entries)
    names = {entry[0]: entry[2] for entry in source.entries}
    flags = {entry[0]: entry[1] for entry in source.entries}

    def allocated(value: int, spans) -> bool:
        return any(low <= value < high for low, high in spans)

    used: set[str] = set()
    for region, (base, end) in source.ranges.items():
        da, db = source.bytes[region], tokens.bytes[region]
        if len(da) != len(db):
            fail(f"{region}: {len(da):,} bytes against {len(db):,}")
            continue
        size = len(da)

        def data_field(owner: int) -> int | None:
            """Where OWNER's data begins when it is a VARIABLE or CREATEd
            word: its code is `ldi64 r1, <data>; subi r14, 8; str r14, r1;
            ret.l`, and the data follows at once (VARIABLE) or after the
            room CREATE leaves for DOES>, 30 bytes from the code's start."""

            code = owner + 9 + (flags[owner] & 0x7F) - base
            stub = da[code : code + 17]
            if (
                len(stub) == 17
                and stub[:3] == b"\xf0\x60\x10"
                and stub[11:] == b"\x67\xe0\x08\x54\xe1\x0e"
                and db[code : code + 17] == stub
            ):
                data = int.from_bytes(stub[3:11], "little")
                if data in (base + code + 17, base + code + 30):
                    return data
            return None

        # Differing bytes fewer than eight apart are judged together, since
        # they may be one cell.
        runs = []
        index = 0
        while index < size:
            if da[index] == db[index]:
                index += 1
                continue
            last = index
            probe = index + 1
            while probe < size and probe - last < 8:
                if da[probe] != db[probe]:
                    last = probe
                probe += 1
            runs.append((index, last + 1))
            index = last + 1
        differing = sum(1 for x, y in zip(da, db) if x != y)
        counts = {"address": [0, 0, set()], "state": [0, 0, set()], "clock": [0, 0, set()]}
        for start, stop in runs:
            address = base + start
            at = bisect.bisect_right(starts, address) - 1
            owner = starts[at] if at >= 0 else None
            limit = starts[at + 1] if owner is not None and at + 1 < len(starts) else base + size
            name = names.get(owner, "?")
            kind = None
            if stop - start <= 8:
                for low in range(max(stop - 8, 0), start + 1):
                    if low + 8 > size:
                        break
                    if allocated(
                        int.from_bytes(da[low : low + 8], "little"), source.allocated
                    ) and allocated(
                        int.from_bytes(db[low : low + 8], "little"), tokens.allocated
                    ):
                        kind = "address"
                        break
            if kind is None and owner is not None:
                data = data_field(owner)
                if data is not None and data <= address and base + stop <= limit:
                    for table, table_kind in ((state, "state"), (clock, "clock")):
                        entry = _listed(name, table)
                        if entry is not None and layout in entry[1]:
                            kind = table_kind
                            used.add(entry[0])
                            break
            changed = sum(1 for x, y in zip(da[start:stop], db[start:stop]) if x != y)
            if kind is None:
                where = "its data" if owner is not None and data_field(owner) is not None \
                    and data_field(owner) <= address else "its header or code"
                fail(
                    f"{region}: {changed} bytes differ in {name} at +{address - (owner or 0)}, "
                    f"in {where}: {da[start:stop][:12].hex()} / {db[start:stop][:12].hex()}"
                )
                continue
            counts[kind][0] += 1
            counts[kind][1] += changed
            counts[kind][2].add(name)
            result.words.setdefault(kind, {})
            result.words[kind][name] = result.words[kind].get(name, 0) + changed
        say(f"  {region}: {differing:,} of {size:,} bytes differ")
        for kind, (places, changed, words) in counts.items():
            if places:
                say(f"    {kind}: {changed:,} bytes in {places:,} places of {len(words):,} words")
    for table in (state, clock):
        for word, pairs, _reason in table:
            if layout in pairs and word not in used:
                fail(f"{word} is listed for this pair and explains no byte")
    for kind in ("state", "clock"):
        for name, changed in sorted(result.words.get(kind, {}).items()):
            say(f"    {kind} word {name}: {changed} bytes")
    say("  " + ("NOT EQUIVALENT" if result.failures else
                "the two boots built the same dictionary"))
    return result


def _spans(spans) -> str:
    return " and ".join(f"{low:#x}..{high:#x}" for low, high in spans)


@pytest.mark.parametrize("layout", BOTH)
def test_a_token_boot_builds_the_dictionary_its_source_boot_builds(
    tmp_path: Path, layout: str
) -> None:
    if layout == VOLUME and not os.environ.get("AKASHIC_E2FSPROGS_TOOL_DIR"):
        pytest.skip("set AKASHIC_E2FSPROGS_TOOL_DIR to build a system volume")

    from_source = snapshot(build(tmp_path, layout, token_modules=False))
    from_tokens = snapshot(build(tmp_path, layout, token_modules=True))
    result = compare(from_source, from_tokens, layout)

    report = result.report()
    print(report)
    reports = os.environ.get("AKASHIC_TOKEN_EQUIVALENCE_REPORTS")
    if reports:
        folder = Path(reports)
        folder.mkdir(parents=True, exist_ok=True)
        (folder / f"{layout.replace(' ', '-')}.txt").write_text(report + "\n")
    assert result.failures == [], report
    # The comparison is of a real load: tens of thousands of entries, and a
    # token boot that did less work than its source boot.
    assert len(from_source.entries) > 40_000
    assert from_tokens.instructions < from_source.instructions


# ---- the comparison itself, on dictionaries small enough to read ------------
#
# Each test below plants one difference in a made-up dictionary of three
# words and holds the comparison to the class it must give it, so that the
# rules above are tested apart from the boots they are applied to.

_BASE = 0x20000
_ALLOCATED = ((0x100000, 0x200000), (0x8100000, 0x8200000))
_STUB_TAIL = b"\x67\xe0\x08\x54\xe1\x0e"


def _dictionary(cells: dict[str, bytes]) -> tuple[bytes, tuple]:
    """A region that holds a VARIABLE V, a CREATEd table T and a colon
    word C, each with the data CELLS gives it, and its entries."""

    region = bytearray()
    entries = []
    for name, lead in (("V", 17), ("T", 30), ("C", None)):
        start = _BASE + len(region)
        region += (entries[-1][0] if entries else 0).to_bytes(8, "little")
        region += bytes([len(name)]) + name.encode()
        code = _BASE + len(region)
        if lead is None:
            region += cells[name]
        else:
            region += b"\xf0\x60\x10" + (code + lead).to_bytes(8, "little") + _STUB_TAIL
            region += bytes(lead - 17) + cells[name]
        entries.append((start, len(name), name))
    return bytes(region), tuple(reversed(entries))


def _pair(source_cells: dict[str, bytes], token_cells: dict[str, bytes]):
    snapshots = []
    for cells in (source_cells, token_cells):
        region, entries = _dictionary(cells)
        snapshots.append(
            Snapshot(
                image=Path("made-up.img"), instructions=2, cycles=2, seconds=0.0,
                here=_BASE + len(region), latest=entries[0][0], system_here=_BASE,
                entries=entries,
                ranges={"bank 0": (_BASE, _BASE + len(region))},
                bytes={"bank 0": region},
                allocated=_ALLOCATED,
                uart="ok",
            )
        )
    return snapshots


_SAME = {"V": bytes(8), "T": bytes(16), "C": bytes(range(1, 25))}
_LISTED = (("V", (LINKED,), "a made-up reason"),)


def _differs(word: str, token_data: bytes, **tables) -> Comparison:
    source, tokens = _pair(_SAME, {**_SAME, word: token_data})
    return compare(source, tokens, LINKED, state=tables.get("state", ()), clock=())


def test_equal_dictionaries_compare_equal_and_a_listed_word_must_explain_a_byte() -> None:
    assert _differs("V", _SAME["V"]).failures == []
    unused = _differs("V", _SAME["V"], state=_LISTED)
    assert unused.failures == ["V is listed for this pair and explains no byte"]


def test_a_cell_is_an_address_only_where_both_values_were_allocated() -> None:
    inside_a = (0x150000).to_bytes(8, "little")
    inside_b = (0x8100040).to_bytes(8, "little")
    source, tokens = _pair({**_SAME, "T": inside_a + bytes(8)},
                           {**_SAME, "T": inside_b + bytes(8)})
    assert compare(source, tokens, LINKED, state=(), clock=()).failures == []
    # In a colon definition's code as well: a compiled literal.
    source, tokens = _pair({**_SAME, "C": bytes(8) + inside_a + bytes(8)},
                           {**_SAME, "C": bytes(8) + inside_b + bytes(8)})
    assert compare(source, tokens, LINKED, state=(), clock=()).failures == []
    # One value past the high-water mark, or in the dictionary, is no
    # address the load allocated.
    for outside in (0x8200000, _BASE + 8, 0x90000000):
        source, tokens = _pair({**_SAME, "T": inside_a + bytes(8)},
                               {**_SAME, "T": outside.to_bytes(8, "little") + bytes(8)})
        failures = compare(source, tokens, LINKED, state=(), clock=()).failures
        assert len(failures) == 1 and "differ in T" in failures[0], hex(outside)


def test_state_is_accepted_only_in_a_listed_words_data_and_for_its_pair() -> None:
    assert _differs("V", b"\x07" + bytes(7), state=_LISTED).failures == []
    # The same byte in a word that is not listed, or listed for the other
    # pair only.
    assert "differ in V" in _differs("V", b"\x07" + bytes(7)).failures[0]
    other = (("V", (VOLUME,), "a made-up reason"),)
    assert "differ in V" in _differs("V", b"\x07" + bytes(7), state=other).failures[0]
    # A listed name does not excuse a colon definition's code: C has no
    # data field.
    code = (("C", (LINKED,), "a made-up reason"),)
    changed = bytearray(_SAME["C"])
    changed[3] ^= 0xFF
    failures = _differs("C", bytes(changed), state=code).failures
    assert any("in its header or code" in failure for failure in failures)


def test_the_structure_and_the_output_must_agree_outright() -> None:
    source, tokens = _pair(_SAME, _SAME)
    tokens.uart = "other"
    assert compare(source, tokens, LINKED, state=(), clock=()).failures == [
        "the terminal output differs"
    ]
    source, tokens = _pair(_SAME, _SAME)
    tokens.entries = tokens.entries[:-1] + ((tokens.entries[-1][0], 1, "W"),)
    assert any(
        "entries differ" in failure
        for failure in compare(source, tokens, LINKED, state=(), clock=()).failures
    )
    source, tokens = _pair(_SAME, _SAME)
    tokens.here += 8
    assert any(
        failure.startswith("HERE differs")
        for failure in compare(source, tokens, LINKED, state=(), clock=()).failures
    )
