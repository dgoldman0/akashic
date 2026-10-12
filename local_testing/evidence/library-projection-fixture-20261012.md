# Library fixtures: external memory, disk and run time (2026-10-12)

Two Library profiles failed on main. Each needed a larger machine resource,
not a change to the fixture or the product.

## The projection owner fixture

### What failed

On main at `f815466e`, `library-projection-owner-contracts` failed before its
first assertion. `VFS-NEW` could not get the 64 MiB arena that holds the
fixture's corpus.

### Why

Commit `4b1838b2` ("Budget complete Desk histories within an explicit
external-memory partition") added a userland partition to KDOS boot. Unless a
profile sets a general-XMEM reserve, the userland dictionary takes half of the
available external memory, and the general allocator gets the rest. With the
default 128 MiB, the general allocator had about 53 MB free when the fixture
asked for its arena.

A run with a 32 MiB arena got further, but failed four assertions in
`_lpo-seed-lifecycle`: the corpus does not fit a 32 MiB disk.

### Fix

The profile now defaults to 256 MiB of external memory. The fixture and its
assertions are unchanged. The packaging test pins the new default.

### Measured runs

Two runs, one at a time, with nothing else heavy alongside. The first had
progress prints added to the fixture and asked for 256 MiB on the command
line; the second is the clean fixture with the profile's own default.

| | Measuring run | Clean run |
|---|---|---|
| Result | PASS: 871 assertions, 0 failures | PASS: 871 assertions, 0 failures |
| Guest steps | 59,507,379,096 | 59,506,213,733 |
| Host wall | 2,960 s | 3,220 s |
| Peak host memory | 353 MB | 362 MB |

Both stay within the 70 billion step ceiling. After the arena was
allocated, about 65 MB of general XMEM was still free.

On 2026-07-24 the same 871 assertions took 54.9 billion steps and 722 s.
This host ran about 18 to 20 million steps per second, against July's 76
million. That slowdown is a host matter, not investigated here. The
documented timeout is raised to 3,600 s to cover this host; the slower run
used 89% of it. The step ceiling is unchanged.

## The applet lifecycle fixture

### What failed

`library-applet-functional-contracts` failed on main with 57 of 322
assertions, from its first compaction on. Compaction bound and began, and its
fourth step answered `LIBRARY-SERVICE-S-IO`. That left the compaction open, so
every later operation answered busy. More external memory changed nothing: a
run with 256 MiB failed the same way at the same step.

### Why

The disk was full: 2 sectors free. The 4 MiB image holds the linked code, the
Library store's page bank (`pages-0`, 3,248 sectors, about 1.7 MB) and, during
compaction, a second bank as large (`pages-1`). The linked code has grown since
July, from 82 modules in 12 chunks to 114 in 19, about 2.3 MB, and the three no
longer fit.

### Fix

The profile's disk is now 8 MiB (`total_sectors=16384`), and the packaging
test pins it. The fixture and its assertions are unchanged.

### Measured run

| | |
|---|---|
| Result | PASS: 696 assertions, 0 failures |
| Guest steps | 49,492,418,858, within the 55 billion ceiling |
| Host wall | 2,780 s |
| Peak host memory | 236 MB |
| Free sectors at boot | 11,534 of 16,384 |

On 2026-07-24 the fixture's 694 assertions took 44.2 billion steps and 675 s.
The documented timeout is raised to 3,600 s for this host, as for the
projection fixture; the run used 77% of it. The step ceiling is unchanged.
