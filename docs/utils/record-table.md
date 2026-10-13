# akashic-record-table — Growing tables of fixed-size records

`akashic/utils/record-table.f` keeps records of one fixed size in a table
that grows on the heap. Stores use it for the tables they read from their
files, edit in memory and write back whole, such as Daybook's
[automation store](../tui/applets/daybook/automation-store.md). Records
hold bytes of any length in [blob slots](blob-slot.md).

```forth
REQUIRE utils/record-table.f
```

`PROVIDED akashic-record-table`

It differs from [table.f](table.md). `table.f` gives fixed slot arrays in a
buffer the caller supplies, with a used flag per slot. Record tables have no
fixed capacity, keep their records contiguous and in the caller's order, and
can be written out and read back as plain bytes.

## The table

A table is three cells the caller owns (`RTAB-SIZE`, 24 bytes): the address
of the records, how many there are, and how many fit. A zeroed table is
empty. Every word takes the record size, so one module serves any record
layout.

The table grows by doubling, starting at room for 8, so memory bounds it,
not a count. The module has no global state; a table is serialized by its
caller.

Every word wipes the bytes it gives up:
- growing wipes the old array before freeing it;
- deleting wipes the slot it frees at the end;
- freeing wipes the whole array.

So a table that held secrets leaves nothing behind in freed memory.

## Words

```forth
RTAB-COUNT@   ( table -- n )
RTAB-NTH      ( index table element-u -- record )
RTAB-RESERVE  ( table element-u -- status )        \ room for one more
RTAB-INSERT   ( index table element-u -- slot )    \ zeroed slot; needs room
RTAB-DELETE   ( index table element-u -- )
RTAB-FREE     ( table element-u -- )
RTAB-TAKE     ( records n table element-u -- status )  \ copies into an empty table
RTAB-PUT      ( at table element-u -- at' )        \ copies the records to AT
```

`RTAB-RESERVE` and `RTAB-TAKE` return `RTAB-S-OK` (0), or `RTAB-S-NOMEM`
(1) when memory runs out. In that case the table is left exactly as it was.

## Sorted tables

A table the caller keeps sorted by a leading key can be searched:

```forth
RTAB-SEARCH          ( key records n element-u -- index found? )  \ 32-byte key
RTAB-RECORD          ( key records n element-u -- record|0 )
RTAB-SEARCH-ID       ( id records n element-u -- index found? )   \ leading u64
RTAB-ASCENDING?      ( records n element-u -- flag )
RTAB-IDS-ASCENDING?  ( records n element-u -- flag )
```

- The search words return the record's index and true, or the index where
  it belongs and false.
- Keys compare as bytes. Ids compare as numbers below 2^63.
- The ascending checks accept only strict order, so a store can refuse a
  file with a repeated key.

## Qualification

`local_testing/test_record_table.py` runs on the native executor. It covers:
- order kept as records are inserted, and the room doubling;
- zeroed inserted slots;
- deletes that move records down and wipe the freed slot;
- freeing;
- a byte-identical put and take;
- a table left unchanged when memory runs out;
- searches for present and missing keys and ids, and the ascending checks.

Disabling any one of twelve behaviors makes a check fail:
- zeroing an inserted slot;
- wiping a deleted slot;
- doubling;
- copying on growth;
- each search's direction;
- each ascending check;
- clearing on free;
- the count on take;
- the record address;
- the out-of-memory status.
