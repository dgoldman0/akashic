# akashic-blob-slot — Bytes of any length held by fixed-size records

`akashic/utils/blob-slot.f` lets records of one fixed size hold bytes of
any length, and lets a store write those bytes into its file and read them
back safely. Stores keep the records in a [record table](record-table.md)
and the bytes in blob slots. Daybook's
[automation store](../tui/applets/daybook/automation-store.md) and the
Agent's [run store](../tui/applets/agent/dispatch-store.md) use it.

```forth
REQUIRE utils/blob-slot.f
```

`PROVIDED akashic-blob-slot`

## Slots

A blob slot (`BSLOT-SIZE`, 16 bytes) is two cells inside a record. In
memory they hold the address of bytes the record owns and their length.
An empty slot is zero and zero.

```forth
BSLOT$        ( slot -- address length )
BSLOT!        ( address length slot -- status )   \ its own copy; 0 bytes empty it
BSLOT-FREE    ( slot -- )
BSLOT-PADDED  ( length -- bytes )                 \ padded to a cell
```

`BSLOT!` copies the bytes first and only then frees what the slot held, so
the bytes may be the slot's own. It returns `BSLOT-S-OK` (0), or
`BSLOT-S-NOMEM` (1) when memory runs out, and the slot is then unchanged.
Freeing wipes the bytes before giving them back.

## The region

In a file, a slot holds an offset into a blob region instead of an
address. The region holds the bytes of each nonempty slot, in the order
the store puts them. Each part is zero-padded to a cell, and the region
holds nothing else. An empty slot is zero and zero in the file too.

A cursor (`BSLOT-CURSOR-SIZE`) walks a region. It holds the region's
address and size and the offset of the next part. The offset is -1 once a
slot was out of place.

```forth
BSLOT-CURSOR-INIT  ( region region-u cursor -- )
BSLOT-AT@          ( cursor -- offset )
BSLOT-PUT          ( slot cursor -- )
BSLOT-NEXT         ( slot cursor -- address length )
BSLOT-OWN          ( region slot -- status )
```

- **Writing a file.** The store copies its records into the file, then puts
  each slot with `BSLOT-PUT`. This copies the slot's bytes to the cursor,
  zeroes the padding, and sets the file record's slot to their offset.
- **Reading a file.** The store checks each record's slot with
  `BSLOT-NEXT`, in the order the parts were put. It returns the slot's
  bytes in the region only when they are exactly the next part, inside the
  region, with zero padding. Otherwise it returns `0 0`, the walk breaks,
  and every later slot also returns `0 0`. When the walk ends, the store
  compares `BSLOT-AT@` with the region's size, so no bytes are left over.
  A damaged file therefore cannot name bytes outside its region. It cannot
  hide bytes in the region, give a length that wraps, or overlap two parts.
- **Taking the records.** Once the file checks out, `BSLOT-OWN` gives a slot
  its own copy of its bytes.

## A table's slots

These words handle the slot at OFFSET inside each record of a record table
whose records are ELEMENT-U bytes:

```forth
BSLOT-TABLE-U       ( table element-u offset -- bytes )   \ region bytes they take
BSLOT-PUT-RECORDS   ( records n element-u offset cursor -- )
BSLOT-TABLE-FREE    ( table element-u offset -- )         \ the table stays
BSLOT-TABLE-FORGET  ( from table element-u offset -- )
BSLOT-TABLE-OWN     ( region table element-u offset -- status )
```

`BSLOT-TABLE-OWN` copies each slot's bytes out of the region. If memory
runs out, it empties the failed slot and every later one, which still hold
offsets, with `BSLOT-TABLE-FORGET`. So no slot is left holding an offset,
and the store can free the table as usual.

The module has no global state; slots and cursors are serialized by their
caller.

## Qualification

`local_testing/test_blob_slot.py` runs on the native executor. It covers:
- copies;
- setting a slot from its own bytes or to nothing;
- padding;
- writing a table's slots in order, with zeroed padding over a region that
  held other bytes;
- reading them back, and every way a slot can be out of place:
  - an empty slot with an offset;
  - an offset past or before the next part;
  - a length past the region, or one that wraps;
  - padding past the region;
  - bytes in the padding;
  - a slot claiming the broken walk's offset;
- bytes left over;
- taking records into owned copies;
- forgetting.

Disabling any one of the module's 25 guarded behaviors makes this suite or
Daybook's store suite fail, except one. The wipe before freeing cannot be
observed once the memory is freed.
