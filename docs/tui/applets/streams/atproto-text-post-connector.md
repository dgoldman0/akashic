# Streams AT Protocol text-post connector

`atproto-text-post-connector.f` is the caller-owned Streams output adapter for
one authenticated Bluesky text-post path. It copies an exact egress event
payload, samples a caller-injected trusted Unix-millisecond clock once,
formats the `app.bsky.feed.post` record, allocates a record-key TID from a
caller-owned clock, and prepares one already-bound `createRecord` owner.

The connector owns its Streams descriptor, a copied createRecord HTTPS
target, and all transient text, TID, record, and encoder storage. The caller
continues to own the TID clock, trusted-clock context, and complete
authenticated createRecord graph. Consequently there is no module-global
owner selector, instance pool, slot count, or live-connector limit. The fixed
3,000-byte text, 13-byte TID, target, and record workspaces are protocol
geometry rather than product concurrency limits.

## Construction and inspection

```forth
AT-TEXT-POST-CONNECTOR-SIZE  ( -- bytes )

AT-TEXT-POST-CONNECTOR-INIT
  ( id endpoint revision clock-context clock-xt tid-clock target
    create-owner owner -- status )

AT-TEXT-POST-CONNECTOR-VALID?          ( owner -- flag )
AT-TEXT-POST-CONNECTOR-CONNECTOR@      ( owner -- connector status )
AT-TEXT-POST-CONNECTOR-LAST-STATUS@    ( owner -- status )
AT-TEXT-POST-CONNECTOR-CLEANUP-ERROR@  ( owner -- error )
AT-TEXT-POST-CONNECTOR-CREATE-OUTCOME@ ( owner -- outcome status )
AT-TEXT-POST-CONNECTOR-URI@            ( owner -- address length status )
AT-TEXT-POST-CONNECTOR-CID@            ( owner -- address length status )
AT-TEXT-POST-CONNECTOR-LAST-EPOCH-MS@  ( owner -- epoch-ms status )
```

`clock-xt` has stack effect `( clock-context -- epoch-ms status )`. It is a
trusted wall-clock boundary and may throw; a nonzero status, throw, negative
time, or out-of-range time fails before createRecord can send. The connector
never derives record identity or `createdAt` from `SEVT.RECEIVED-MS`, which is
only Streams flow time.

Initialization is destination-atomic for rejected geometry. It requires an
idle, cleanup-clean createRecord owner, a valid monotonic TID clock, the exact
`com.atproto.repo.createRecord` target, present connector identities, and a
complete non-aliasing ownership graph. The target is copied during successful
initialization; the caller's target argument is not retained.

## Output lifecycle

The sealed Streams connector uses `XIO-OP-SIZE` operation storage. `START`
admits the complete event, operation, result, and dependency ownership graph,
then initializes the supplied operation before connector-local work. It copies
the event payload, samples time once, encodes the record, allocates the TID,
calls `AT-CREATE-RECORD-PREPARE`, wipes its transient buffers, and delegates to
createRecord.
A successful TID followed by a later prepare failure may leave a monotonic
TID gap; it never reuses an allocated identifier.

Only one flow operation may own a connector at a time. A second start reports
`BUSY` without disturbing the active operation, and cleanup for a mismatched
operation is a no-op. Distinct caller-owned connector instances remain
independent and may be interleaved.

createRecord truth maps directly onto Streams:

| createRecord outcome | Streams completion | Streams effect |
| --- | --- | --- |
| `PENDING` | `PENDING` | `UNCERTAIN` |
| `CREATED` | `DELIVERED` | `APPLIED` |
| `NO-EFFECT` | `FAILED`, or `CANCELLED` after cancellation | `NOT-APPLIED` |
| `UNCERTAIN` | `INDETERMINATE` | `UNCERTAIN` |

The connector does not retry a generally uncertain repository write. Cleanup
is separate from delivery truth: it wipes request and connector scratch,
records a cleanup throw independently, and releases the active operation.
The createRecord result owns the copied URI/CID receipt, so successful
inspection remains available after ordinary cleanup.
