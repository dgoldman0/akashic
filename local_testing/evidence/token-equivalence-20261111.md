# Modules from token forms: the equivalence run and the journeys — 2026-11-11

A module's token form is a record of what the interpreter did with its
source, which KDOS replays through the interpreter's own steps (MegaPad's
`docs/token-modules-proposal-2026-11-11.md`). This note keeps the outputs
that say the form may be trusted: the strict comparison of a boot from
source with a boot from token forms, and the physical Desktop journeys run
from token forms. Both branches are `token-modules` and neither is merged.

Every run here was made on MegaPad d6f95654 and Akashic e15c8240, with both
trees clean before and after. Those commits hold the rule that says when a
token file is used as it was decided on 2026-11-11: a token file is used
when it was built for this system and, where its source ships beside it,
when that source is the one it was recorded from.

Every run was made one at a time. The equivalence test is
`local_testing/test_token_equivalence.py`, run by
`python3 -m fantasy_engine.testing`; it boots on the exact emulator. A
physical Desktop journey is `physical_desktop_acceptance.py`, under its
900-second watchdog and 3.5 GiB guard, on trees that were not touched
while it ran.

## The equivalence run

The unit passed in 292 seconds with a peak of 1,675 MiB: two pairs of
boots and four tests of the comparison's own rules on made-up
dictionaries.

The test's opening text says what makes it fail. In short: the entries of
the two dictionaries, the pointers and the terminal output must agree
outright, and every byte that differs must be an address the load
allocated, a listed word's data, or the one word set from a clock.

### The linked Desktop

```
linked: source 1,027,469,133 instructions, 1,334,606,589 cycles; tokens 428,801,246 instructions, 582,598,406 cycles
  HERE: the same
  LATEST: the same
  the system dictionary's HERE: the same
  the dictionary regions: the same
  entries: 50,500, each at the same address with the same name and flags
  terminal output: identical, 2,777 characters
  allocated external memory: source 0x100000..0x302610 and 0x8100000..0xbee0310, tokens 0x100000..0x302610 and 0x8100000..0xbe38ff0
  bank 0: 2,022 of 281,526 bytes differ
    address: 16 bytes in 6 places of 6 words
    state: 2,006 bytes in 129 places of 21 words
  external: 606 of 8,643,538 bytes differ
    address: 566 bytes in 156 places of 155 words
    state: 38 bytes in 9 places of 9 words
    clock: 2 bytes in 1 places of 1 words
    state word BOOT-BD: 2 bytes
    state word FD-POOL: 9 bytes
    state word FR-LEN: 3 bytes
    state word FR-POS: 2 bytes
    state word FR-REM: 1 bytes
    state word FS-BMAP: 906 bytes
    state word FS-DIR: 665 bytes
    state word FSCRATCH: 373 bytes
    state word XMEM-FLOOR: 3 bytes
    state word XMEM-HERE: 3 bytes
    state word _CSL-CRC: 4 bytes
    state word _CSL-FILE-U: 3 bytes
    state word _CSL-HEADER: 10 bytes
    state word _CSL-PAYLOAD-U: 3 bytes
    state word _CSL-RAW-U: 3 bytes
    state word _CSL-READ-U: 3 bytes
    state word _LD-FILE: 11 bytes
    state word _LD-RUN-CNT: 1 bytes
    state word _LD-RUN-SEC: 2 bytes
    state word _MOD-FILE-KEY: 9 bytes
    state word _PS-REM: 2 bytes
    state word _SEC-CUR: 4 bytes
    state word _SEC-EVAL-LEN: 1 bytes
    state word _SEC-LINE: 2 bytes
    state word _SEC-RAW-LEN: 1 bytes
    state word _TKF-A: 4 bytes
    state word _TKF-U: 2 bytes
    state word _VFC-H: 8 bytes
    state word _VMRW-SSEC: 2 bytes
    state word _VMZR-START: 2 bytes
    clock word DNS-ID: 2 bytes
  the two boots built the same dictionary
```

### The Desktop on its system volume, token files alone

```
system volume: source 1,441,525,023 instructions, 1,865,722,648 cycles; tokens 675,141,023 instructions, 898,271,034 cycles
  HERE: the same
  LATEST: the same
  the system dictionary's HERE: the same
  the dictionary regions: the same
  entries: 54,592, each at the same address with the same name and flags
  terminal output: identical, 1,167 characters
  allocated external memory: source 0x100000..0x301a10 and 0x8100000..0xc06e000, tokens 0x100000..0x301a10 and 0x8100000..0xbe73260
  bank 0: 1,020 of 281,526 bytes differ
    address: 55 bytes in 19 places of 9 words
    state: 965 bytes in 193 places of 27 words
  external: 1,350 of 9,697,286 bytes differ
    address: 922 bytes in 305 places of 303 words
    state: 426 bytes in 79 places of 57 words
    clock: 2 bytes in 1 places of 1 words
    state word BOOT-BD: 2 bytes
    state word FD-POOL: 9 bytes
    state word FR-LEN: 3 bytes
    state word FR-POS: 2 bytes
    state word FR-REM: 1 bytes
    state word FS-BMAP: 250 bytes
    state word FS-DIR: 336 bytes
    state word FSCRATCH: 124 bytes
    state word MODULE-TOKENS: 8 bytes
    state word XMEM-HERE: 4 bytes
    state word _CSL-CRC: 4 bytes
    state word _CSL-FILE-U: 3 bytes
    state word _CSL-HEADER: 10 bytes
    state word _CSL-PAYLOAD-U: 3 bytes
    state word _CSL-RAW-U: 3 bytes
    state word _CSL-READ-U: 3 bytes
    state word _EXT4-BM-STORED: 4 bytes
    state word _EXT4-BX-N: 1 bytes
    state word _EXT4-CRC-STATE: 4 bytes
    state word _EXT4-DN-NLEN: 1 bytes
    state word _EXT4-DR-ACT: 2 bytes
    state word _EXT4-DR-CHUNK: 2 bytes
    state word _EXT4-DR-LBLOCK: 1 bytes
    state word _EXT4-DR-LEN: 2 bytes
    state word _EXT4-DR-OFF: 2 bytes
    state word _EXT4-DR-PHYS: 2 bytes
    state word _EXT4-DS-CINO: 1 bytes
    state word _EXT4-DS-TARGET-U: 1 bytes
    state word _EXT4-DV-REC: 1 bytes
    state word _EXT4-DV-STORED: 4 bytes
    state word _EXT4-EV-LEN: 1 bytes
    state word _EXT4-EV-PHYS: 2 bytes
    state word _EXT4-EV-PREV: 1 bytes
    state word _EXT4-EV-SEEN: 3 bytes
    state word _EXT4-GDC-CALC: 2 bytes
    state word _EXT4-GDC-STORED: 2 bytes
    state word _EXT4-IR-BYTE: 1 bytes
    state word _EXT4-IR-CALC: 4 bytes
    state word _EXT4-IR-HI: 2 bytes
    state word _EXT4-IR-INDEX: 1 bytes
    state word _EXT4-IR-INO: 1 bytes
    state word _EXT4-IR-LO: 2 bytes
    state word _EXT4-IR-OFF: 1 bytes
    state word _EXT4-JMM-KEY: 6 bytes
    state word _EXT4-JMM-NOW: 6 bytes
    state word _EXT4-OCV-STORED: 4 bytes
    state word _EXT4-PS-DATA: 277 bytes
    state word _EXT4-RAR-CHUNK: 1 bytes
    state word _EXT4-RAR-COUNT: 1 bytes
    state word _EXT4-RAR-CURRENT: 2 bytes
    state word _EXT4-RAR-FIRST: 2 bytes
    state word _EXT4-RAR-INDEX: 2 bytes
    state word _EXT4-RD-DESC: 9 bytes
    state word _EXT4-SV-STORED: 4 bytes
    state word _EXT4-VG-FREE-BLOCKS: 2 bytes
    state word _LD-FILE: 16 bytes
    state word _LD-NAMES: 43 bytes
    state word _LD-RUN-CNT: 1 bytes
    state word _LD-RUN-SEC: 2 bytes
    state word _LD-STK: 103 bytes
    state word _LD-TNAME: 3 bytes
    state word _LD-TOKENS-CHOSEN: 8 bytes
    state word _MF-H: 4 bytes
    state word _MOD-FILE-KEY: 9 bytes
    state word _MOD-INLINE: 21 bytes
    state word _PS-REM: 2 bytes
    state word _SEC-CUR: 4 bytes
    state word _SEC-EVAL-LEN: 1 bytes
    state word _SEC-LINE: 2 bytes
    state word _SEC-RAW-LEN: 1 bytes
    state word _TKF-A: 4 bytes
    state word _TKF-U: 2 bytes
    state word _VCDN-BID: 1 bytes
    state word _VCDN-U: 1 bytes
    state word _VFC-H: 8 bytes
    state word _VFV-BID: 1 bytes
    state word _VFV-H: 8 bytes
    state word _VMRW-SSEC: 2 bytes
    state word _VMZR-START: 2 bytes
    state word _VR-PATH-A: 3 bytes
    state word _VRD-ACT: 2 bytes
    state word _VRD-LEN: 2 bytes
    state word _VRE-ACT: 2 bytes
    state word _VUC-U: 1 bytes
    clock word DNS-ID: 2 bytes
  the two boots built the same dictionary
```

### What the lists admit

The address class admits a cell only when its value in each boot lies in
the external memory that boot's allocator had handed out by the prompt:
below the userland dictionary, or between its limit and `XMEM-HERE`. Those
spans are the "allocated external memory" lines above.

The state list has 60 entries, in the test's `STATE`, each with the
pairs it differs in and its reason. Of them 29 differ in both pairs: the
allocator's mark, the boot volume's cached directory, bitmap and last
request, the loader's and the cold-source loader's record of the file read
last, and three cells of the VFS's MP64FS binding. One, a copy of the
allocator's mark, differs only in the linked pair. The other 30 differ
only with the system volume: the loader's frames and names, the switch
that turns token loading on, the registry's buckets, and the private cells
of the ext4 driver's and the VFS's routines, which describe a volume of
source files in one boot and a volume of token files in the other. An
entry is a word, or the prefix of one routine's cells; a difference counts
only in the data field of a `VARIABLE` or `CREATE`d word, read from the
word's own code; and an entry that explains no byte in a pair it is listed
for fails the test.

The state bytes vary a little from run to run, because the boot volume's
directory holds each file's time and the two images of a pair are built
seconds apart. The address and clock classes do not: a run on the same
code before it was committed gave the same 582 and 977 address bytes.

## The journeys

Each journey built its image with `--token-modules`.

| Journey | Result |
|---|---|
| linked Desktop, simulator | PASS, 177 s |
| Desktop on a system volume of token files alone, simulator | PASS, 201 s |
| linked Desktop, hybrid mode | PASS, 191 s |

## The other units

Run through `python3 -m fantasy_engine.testing`, each in a process of its
own:

- The recorded units, every one of MegaPad's, Akashic's and LM1's that the
  main record holds except the whole `test_vfs_ext4.py`, with the six
  units the two branches add: run 20261111-161724.988-57cf, against a copy
  of the main record, with fantasy-engine at 0e9da081 and LM1 at
  d2a09740. 295 units, 146 of MegaPad, 143 of Akashic and 6 of LM1,
  passed in 2,258 seconds, and none failed. Among them are
  `test_token_equivalence.py`, whose output is above,
  `test_token_modules_build.py` (162 s, 864 MiB),
  `test_cold_source_tokens.py`, `test_system_volume.py`,
  `test_vfs_module_source.py` and `test_akashic_tui_packaging.py`.
- The whole `test_vfs_ext4.py` unit was not run. The two branches change
  no file of the driver. The units that mount ext4 volumes on the changed
  KDOS and load modules from them, `test_system_volume.py` and
  `test_vfs_module_source.py`, are among those that passed.
- `local_testing/test_cold_source_loader.py`, the cold-source loader's
  contract script, on the emulator: it passed, and its five stages matched.
- The token cases, one table for both machines, with the tests of the
  replay and of `BOOT-ID`: 95 tests passed in the simulator with its
  native executor and 95 with its Python one, and 9 tests with
  72 subtests passed on the emulator.
- MegaPad's other emulator classes, one at a time: the BIOS classes
  (412 passed, with 56 subtests), `TestKDOSModuleSystem` (18),
  `TestModuleProvidedGuard` (53), `TestKDOSCheckedCompiler` (7),
  `TestAppLoad` (17), `TestKDOSLoadBuffer` (2) and the two tests of the
  dictionary chain's tail. The whole of `tests/test_system.py` was not
  run.
