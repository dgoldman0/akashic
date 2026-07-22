# Immutable chunked blobs

`persistence/blob.f` is a neutral, caller-owned layer over the transactional
record store. It has no path, applet, filesystem-driver, publication, or
retention policy. Library and later consumers attach the returned descriptor
to their own records and roots.

Content is split into 32 KiB logical chunks. Every chunk is a checked segment
record, so normal `PSTORE-READ-RECORD` validation checks its envelope, payload
checksum, ordinal, span, and committed-tail containment. A fixed
72-byte immutable descriptor contains the total byte length, derived chunk
count, minimal manifest level, and one record reference. Empty content has a
canonical descriptor with no record reference.

The manifest is an immutable 64-way tree of checked records. Leaves contain
chunk references and internal nodes contain references to the next level. The
root level is minimal for the chunk count. Levels zero through seven cover the
full nonnegative signed byte range without a larger-content special case.

## Ownership and transactions

One `PBLOB-WORK-SIZE` object is initialized with `PBLOB-WORK-INIT`. Its fixed
46,936-byte footprint contains one 32 KiB transfer buffer, a bounded manifest
frontier, temporary references, and operation counters. There is no mutable
module state. Work objects, descriptors, callbacks, stores, and store
workspaces may therefore be interleaved by independent callers.

`PBLOB-WRITE` requires an already active `PSTORE` transaction. It calls only
`PSTORE-APPEND-RECORD`; it never begins, commits, aborts, publishes an
application root, or chooses recovery policy. Before clearing the output
descriptor or invoking the source, it verifies that the supplied store and
workspace are the exact active transaction pair. A valid workspace owned by a
different store is rejected without callback or output mutation. A source
callback has the contract:

```forth
( logical-offset destination-a exact-u context -- actual-u status )
```

It is called once per chunk and must fill the exact requested span. Returned
errors are propagated and throws are contained as `PERSIST-S-FAULT`. A failed
write leaves the output descriptor invalid. Validation and source failures
before the first record emission are no-effect. Once any chunk or manifest has
been appended successfully, a later source, frontier, capacity, descriptor, or
storage failure poisons the paired transaction through `PSTORE-TX-POISON`.
The original blob status is retained, commit is rejected, and the surrounding
caller must abort so the next begin can reconcile the uncommitted record
suffix.

## Bounded reads

`PBLOB-READ-RANGE` performs current-authority reads outside or inside the
caller's broader workflow:

```forth
( blob offset requested-u sink-xt sink-context store store-work blob-work
  -- status )
```

Offsets beyond EOF return `PERSIST-S-NOT-FOUND`. A valid request is clamped at
EOF, including a zero-byte result at exactly EOF. Negative offsets or request
lengths are invalid; clamping uses remaining length rather than overflowing an
`offset + request` sum. The sink is invoked once for each touched chunk with:

```forth
( logical-offset payload-a payload-u context -- status )
```

The payload view is borrowed from the supplied store workspace. `PBLOB-STREAM`
is the convenience form that requests all remaining bytes from an offset.
Sink delivery is intentionally progressive: if a later storage or callback
failure occurs, earlier successful sink calls are not rolled back. Consumers
therefore publish their own accumulated result only after the final success.

The current range walker resolves each touched chunk independently, reading
one complete manifest path and one data record per chunk. `PBLOB-BYTES@`
reports actual sourced or delivered bytes;
chunk-read/write, manifest-read/write, callback, and fixed working-set
accessors expose the remaining operation costs. No whole-blob materialization
is required.

The linked RAM-VFS qualification covers empty and multi-chunk descriptors,
EOF clamping, complete streams across both a three-chunk blob and every chunk
of a 65-chunk level-one tree, cross-chunk ranges, progressive second-callback
failure, cold reopen,
malformed descriptors and manifest targets, storage and callback faults,
alias/busy cleanup, mismatched active store/work ownership without callback,
exact stacks and descriptors, file-descriptor cleanup, and four independently
interleaved stores.
