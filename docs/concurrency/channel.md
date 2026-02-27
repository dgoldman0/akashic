# akashic-channel — Go-Style Bounded Channels for KDOS / Megapad-64

CSP-style bounded channels for inter-task communication.  The
primary cross-task data-passing mechanism in the concurrency library.

```forth
REQUIRE channel.f
```

`PROVIDED akashic-channel` — safe to include multiple times.
Automatically requires `event.f`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Memory Layout](#memory-layout)
- [Creation](#creation)
- [1-Cell Send & Receive](#1-cell-send--receive)
- [Non-Blocking Operations](#non-blocking-operations)
- [Addr-Based Send & Receive](#addr-based-send--receive)
- [Closing a Channel](#closing-a-channel)
- [Multiplexing with SELECT](#multiplexing-with-select)
- [Debug](#debug)
- [Concurrency Model](#concurrency-model)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Bounded buffer** | Inline circular ring — fixed capacity, back-pressure via blocking. |
| **Custom ring ops** | Direct `!`/`@`/`CMOVE` under the channel lock. No `RING-PUSH`/`RING-POP`. |
| **Per-channel lock** | Each channel stores its own spinlock number (like `rwlock.f`). |
| **Two events** | `evt-not-full` for senders, `evt-not-empty` for receivers. |
| **Two API flavors** | `CHAN-SEND`/`CHAN-RECV` for 1-cell values; `-BUF` variants for arbitrary elem-size. |
| **Prefix convention** | Public: `CHAN-`. Internal: `_CHAN-`. |

---

## Memory Layout

A channel occupies 15 cells = 120 bytes (fixed) + a variable-size
data area of `capacity × elem-size` bytes:

```
Offset  Size    Field
──────  ──────  ──────────────────────────
0       8       lock#          spinlock number (0–7)
8       8       closed         0 = open, -1 = closed
16      8       elem-size      bytes per element
24      8       capacity       max elements
32      8       head           read index
40      8       tail           write index
48      8       count          current elements
56      32      evt-not-full   (4-cell event, initially SET)
88      32      evt-not-empty  (4-cell event, initially UNSET)
120     var     data area      (capacity × elem-size bytes)
```

Both events are standard `EVENT` structures embedded inline — same
pattern as `semaphore.f` and `rwlock.f`.

---

## Creation

### `CHANNEL`

```forth
CHANNEL ( lock# elem-size capacity "name" -- )
```

Create a named bounded channel.

- **lock#**: hardware spinlock number (0–7).  `EVT-LOCK` (6) is a
  reasonable default; multiple channels can share the same spinlock.
- **elem-size**: bytes per element.  Use `1 CELLS` (= 8) for
  single 64-bit values (the common case).
- **capacity**: maximum number of buffered items.

```forth
6 1 CELLS 8 CHANNEL work-queue     \ 8-slot, 1-cell channel
6 1 CELLS 4 CHANNEL results        \ 4-slot, 1-cell channel
6 16 32 CHANNEL packet-buf         \ 32 slots of 16-byte packets
```

---

## 1-Cell Send & Receive

### `CHAN-SEND`

```forth
CHAN-SEND ( val ch -- )
```

Send a single 64-bit cell value into the channel.  Blocks if the
buffer is full (yield-aware spin loop).  THROWs `-1` if the channel
is closed.

```forth
42 work-queue CHAN-SEND         \ enqueue the value 42
```

### `CHAN-RECV`

```forth
CHAN-RECV ( ch -- val )
```

Receive a single 64-bit cell value from the channel.  Blocks if
the buffer is empty.  Returns `0` if the channel is closed and
empty (sentinel for "no more data").

```forth
work-queue CHAN-RECV .          \ dequeue and print
```

### `CHAN-COUNT`

```forth
CHAN-COUNT ( ch -- n )
```

Number of items currently buffered.  Lock-free single-cell read.

```forth
work-queue CHAN-COUNT .         \ show queue depth
```

---

## Non-Blocking Operations

### `CHAN-TRY-SEND`

```forth
CHAN-TRY-SEND ( val ch -- flag )
```

Try to send without blocking.  Returns TRUE (−1) if the value was
enqueued, FALSE (0) if the channel is full or closed.

```forth
42 work-queue CHAN-TRY-SEND IF
    ." sent" CR
ELSE
    ." queue full" CR
THEN
```

### `CHAN-TRY-RECV`

```forth
CHAN-TRY-RECV ( ch -- val flag )
```

Try to receive without blocking.  Returns `( val TRUE )` on success,
`( 0 0 )` if the channel is empty.

```forth
work-queue CHAN-TRY-RECV IF
    ." got: " .
ELSE
    DROP ." empty" CR
THEN
```

---

## Addr-Based Send & Receive

For elements larger than one cell (e.g., structs, multi-byte packets),
use the `-BUF` variants which copy `elem-size` bytes via `CMOVE`.

### `CHAN-SEND-BUF`

```forth
CHAN-SEND-BUF ( addr ch -- )
```

Send `elem-size` bytes from `addr` into the channel.  Blocks if full.
THROWs `-1` if closed.

```forth
my-packet packet-buf CHAN-SEND-BUF
```

### `CHAN-RECV-BUF`

```forth
CHAN-RECV-BUF ( addr ch -- flag )
```

Receive `elem-size` bytes into `addr`.  Blocks if empty.  Returns
TRUE (−1) on success, FALSE (0) if the channel is closed and empty
(the buffer at `addr` is left untouched).

```forth
CREATE pkt 16 ALLOT
pkt packet-buf CHAN-RECV-BUF IF
    pkt 16 TYPE
ELSE
    ." channel done" CR
THEN
```

---

## Closing a Channel

### `CHAN-CLOSE`

```forth
CHAN-CLOSE ( ch -- )
```

Mark the channel as closed.  Items already in the buffer can still
be received.  Both events are signaled to wake any blocked senders
or receivers.

After closing:
- `CHAN-SEND` / `CHAN-SEND-BUF` will THROW `-1`.
- `CHAN-TRY-SEND` returns FALSE.
- `CHAN-RECV` returns `0` once the buffer drains.
- `CHAN-TRY-RECV` returns `( 0 0 )` once drained.

```forth
work-queue CHAN-CLOSE
```

### `CHAN-CLOSED?`

```forth
CHAN-CLOSED? ( ch -- flag )
```

TRUE (−1) if the channel has been closed.

```forth
work-queue CHAN-CLOSED? IF ." closed" CR THEN
```

---

## Multiplexing with SELECT

### `CHAN-SELECT`

```forth
CHAN-SELECT ( chan1 chan2 ... chanN n -- idx val )
```

Wait on N channels simultaneously.  Polls each channel using
`CHAN-TRY-RECV` in round-robin order, calling `YIELD?` between
rounds.  Returns the 0-based index (matching push order) and
the 1-cell value from the first channel with data.

Returns `( -1 0 )` if **all** channels are closed and empty.

Only works with 1-cell channels.  For addr-based channels, poll
manually with `CHAN-TRY-RECV` and `YIELD?`.

```forth
6 1 CELLS 8 CHANNEL ch-net
6 1 CELLS 8 CHANNEL ch-timer
6 1 CELLS 8 CHANNEL ch-user

: event-loop
    BEGIN
        ch-net ch-timer ch-user 3 CHAN-SELECT
        DUP -1 = IF  2DROP EXIT  THEN     \ all closed
        CASE
            0 OF  handle-network  ENDOF
            1 OF  handle-timer    ENDOF
            2 OF  handle-user     ENDOF
        ENDCASE
    AGAIN ;
```

---

## Debug

### `CHAN-INFO`

```forth
CHAN-INFO ( ch -- )
```

Print channel status to UART:

```
[channel lock#=6 open esize=8 cap=8 count=3 head=0 tail=3
  nf:[event SET waiters=0]
  ne:[event SET waiters=0]
]
```

---

## Concurrency Model

### Producer-Consumer (Primary Use Case)

```forth
6 1 CELLS 16 CHANNEL jobs

: producer
    BEGIN  next-job  DUP 0<> WHILE
        jobs CHAN-SEND
    REPEAT
    DROP  jobs CHAN-CLOSE ;

: consumer
    BEGIN  jobs CHAN-RECV  DUP 0<> WHILE
        process-job
    REPEAT
    DROP ;
```

### Fan-Out

```forth
6 1 CELLS 8 CHANNEL work
6 1 CELLS 8 CHANNEL done

: worker
    BEGIN  work CHAN-RECV  DUP 0= IF DROP EXIT THEN
        process  done CHAN-SEND
    AGAIN ;

: fan-out  4 0 DO ['] worker SPAWN LOOP ;
```

### Multiple Sources via SELECT

```forth
6 1 CELLS 4 CHANNEL sensor-a
6 1 CELLS 4 CHANNEL sensor-b

: monitor
    sensor-a sensor-b 2 CHAN-SELECT
    CASE
        0 OF  ." sensor A: " . CR  ENDOF
        1 OF  ." sensor B: " . CR  ENDOF
    ENDCASE ;
```

### Implementation Notes

- **Per-channel spinlock** protects the inline ring (head, tail,
  count).  The lock is held only during the push/pop operation,
  then released before signaling events.

- **EVT-SET** is used (not `EVT-PULSE`) to signal the not-full
  and not-empty events.  Waiters call `EVT-WAIT` followed by
  `EVT-RESET` before re-checking the condition under the lock.

- **CHAN-SELECT** uses `CHAN-TRY-RECV` in a `BEGIN ... YIELD? AGAIN`
  loop.  It tracks how many channels are closed+empty; when all N
  are dead, it returns `( -1 0 )`.

- **No global variables** in the ring path — unlike `RING-PUSH`/
  `RING-POP` which use a global `_RP-RING` variable, the channel's
  inline push/pop work entirely via the return stack (`>R` / `R@`).

---

## Quick Reference

| Word              | Signature                            | Behavior                              |
|-------------------|--------------------------------------|---------------------------------------|
| `CHANNEL`         | `( lock# esize cap "name" -- )`      | Create bounded channel                |
| `CHAN-SEND`        | `( val ch -- )`                     | Send 1-cell; block if full            |
| `CHAN-RECV`        | `( ch -- val )`                     | Recv 1-cell; block if empty           |
| `CHAN-TRY-SEND`    | `( val ch -- flag )`                | Non-blocking 1-cell send              |
| `CHAN-TRY-RECV`    | `( ch -- val flag )`                | Non-blocking 1-cell recv              |
| `CHAN-SEND-BUF`    | `( addr ch -- )`                    | Send elem-size bytes; blocking        |
| `CHAN-RECV-BUF`    | `( addr ch -- flag )`               | Recv elem-size bytes; blocking        |
| `CHAN-CLOSE`       | `( ch -- )`                         | Close channel                         |
| `CHAN-CLOSED?`     | `( ch -- flag )`                    | Is closed?                            |
| `CHAN-COUNT`       | `( ch -- n )`                       | Items buffered                        |
| `CHAN-SELECT`      | `( ch1..chN n -- idx val )`         | Wait on N channels                    |
| `CHAN-INFO`        | `( ch -- )`                         | Debug display                         |

### Internal Words

| Word              | Signature            | Behavior                              |
|-------------------|----------------------|---------------------------------------|
| `_CHAN-LOCK#`      | `( ch -- addr )`    | Address of lock# field (+0)           |
| `_CHAN-CLOSED`     | `( ch -- addr )`    | Address of closed flag (+8)           |
| `_CHAN-ESIZE`      | `( ch -- addr )`    | Address of elem-size (+16)            |
| `_CHAN-CAP`        | `( ch -- addr )`    | Address of capacity (+24)             |
| `_CHAN-HEAD`       | `( ch -- addr )`    | Address of head index (+32)           |
| `_CHAN-TAIL`       | `( ch -- addr )`    | Address of tail index (+40)           |
| `_CHAN-CNT`        | `( ch -- addr )`    | Address of count (+48)                |
| `_CHAN-EVT-NF`     | `( ch -- ev )`      | Not-full event at +56                 |
| `_CHAN-EVT-NE`     | `( ch -- ev )`      | Not-empty event at +88                |
| `_CHAN-DATA`       | `( ch -- addr )`    | Data area at +120                     |
| `_CHAN-PUSH-CELL`  | `( val ch -- )`     | Push 1-cell (under lock)              |
| `_CHAN-POP-CELL`   | `( ch -- val )`     | Pop 1-cell (under lock)               |
| `_CHAN-PUSH-BUF`   | `( addr ch -- )`    | Push elem-size bytes (under lock)     |
| `_CHAN-POP-BUF`    | `( addr ch -- )`    | Pop elem-size bytes (under lock)      |
| `_CHAN-FULL?`      | `( ch -- flag )`    | Is buffer full?                       |
| `_CHAN-EMPTY?`     | `( ch -- flag )`    | Is buffer empty?                      |

### Constants

| Name               | Value | Meaning                          |
|--------------------|-------|----------------------------------|
| `_CHAN-FIXED-CELLS` | 15    | Fixed cells per channel          |
| `_CHAN-FIXED-SIZE`  | 120   | Fixed bytes per channel          |
