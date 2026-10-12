# Library projection fixture: external memory and run time (2026-10-12)

## What failed

On main at `f815466e`, `library-projection-owner-contracts` failed before its
first assertion. `VFS-NEW` could not get the 64 MiB arena that holds the
fixture's corpus.

## Why

Commit `4b1838b2` ("Budget complete Desk histories within an explicit
external-memory partition") added a userland partition to KDOS boot. Unless a
profile sets a general-XMEM reserve, the userland dictionary takes half of the
available external memory, and the general allocator gets the rest. With the
default 128 MiB, the general allocator had about 53 MB free when the fixture
asked for its arena.

A run with a 32 MiB arena got further, but failed four assertions in
`_lpo-seed-lifecycle`: the corpus does not fit a 32 MiB disk.

## Fix

The profile now defaults to 256 MiB of external memory. The fixture and its
assertions are unchanged. The packaging test pins the new default.

## Measured runs

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
