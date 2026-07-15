# Owner-pumped external I/O

`akashic/net/external-io.f` serializes cooperative external operations on one
owner core. It is the machine-service boundary for work such as DNS/TCP/TLS
opening whose implementation uses shared platform state. It is not a worker
pool, capability dispatcher, authority grant, or semantic job table.

The service admits one active operation. A host submits an operation and calls
`XIO-TICK` from its normal event loop; each tick invokes at most one start or
poll callback. The operation owns request, response, parser, transport, and
application-generation storage. The service owns only exclusive admission,
deadline and cancellation handling, exact-once cleanup, and terminal-state
publication.

```forth
CREATE service XIO-SERVICE-SIZE ALLOT
CREATE operation XIO-OP-SIZE ALLOT

service XIO-SERVICE-INIT
operation XIO-OP-INIT

service owner-id owner-generation request-generation deadline-ms context
    start-xt poll-xt cancel-xt wipe-xt operation XIO-OP-CONFIGURE

service operation XIO-SUBMIT
service XIO-TICK
service operation XIO-CANCEL
service operation XIO-RESET
```

Exactly one service descriptor can be bound machine-wide, and it is initialized
on core 0, matching the platform's network receive and TLS-scratch owner.
Initializing a second descriptor returns `XIO-S-BUSY`; `XIO-SERVICE-FINI`
unbinds an inactive service. The service and its callbacks run only on that
owner core. `XIO-SUBMIT` claims the slot without invoking application code.
`XIO-TICK` then invokes `start-xt` once and `poll-xt` on later ticks. Both have
the stack effect `( operation context -- step-status )` and return
`XIO-STEP-PENDING`, `XIO-STEP-SUCCEEDED`, or `XIO-STEP-FAILED`. They may store a
provider-specific result and error in `XIOO.RESULT` and `XIOO.ERROR`.

## Terminal and cleanup contract

Operation states are `RESET`, `ACTIVE`, `SUCCEEDED`, `FAILED`, `CANCELLED`, and
`TIMED-OUT`. Deadline values are absolute monotonic milliseconds; zero disables
the deadline. Expiration is checked before and after every callback with a
wrap-safe modular comparison. A callback throw or invalid step result becomes
`FAILED`.

Failure, timeout, and cancellation invoke the lower cancellation callback and
the wipe callback at most once, release the service slot, and publish the
terminal state last. Cleanup callbacks are attempted even when an earlier
cleanup callback throws. `XIOO.ERROR` retains the primary failure while
`XIOO.CLEANUP-ERROR` records the first cleanup throw.

A successful operation stops polling without wiping its caller-owned result,
but remains retained by the service. This prevents another request or service
teardown from stranding the result's wipe obligation. After the owner validates
and consumes—or deliberately discards—that result, `XIO-RESET` invokes the wipe
callback exactly once, releases the retained slot, and returns the descriptor
to `RESET`. Repeated cancellation of an already cancelled operation is
harmless. Resetting an active operation is rejected. Resetting any terminal
operation while a different operation is active or retained returns
`XIO-S-BUSY`.

Callbacks must be bounded, must not invoke `XIO-TICK`, `XIO-CANCEL`, or
`XIO-RESET` recursively, and must not commit application state. They may update
their own descriptor and buffers. Agent code is never given raw callback or
submission access; higher-level applet capabilities remain the authority
boundary.

## Stale results

`XIO-OP-CONFIGURE` requires the bound owner service and binds nonzero owner
identity, positive owner generation, and positive request generation to the
operation. `XIO-OP-MATCH?` compares all
three. The application must compare them with its live instance before decoding
or committing a successful response. Closing, relaunching, account changes, or
request replacement advance the applicable generation before cancellation, so
a late or retained success can only be discarded and wiped.

The service does not own the TLS trust store. Desk freezes the
[machine-owned trust registry](tls-trust-registry.md) before initializing this
service, and applets do not install or replace global trust as part of an
operation. Trust composition and external-I/O admission are separate machine
boundaries.

Run the deterministic contract profile with:

```sh
python local_testing/akashic_tui.py smoke --profile external-io
```

The profile covers one-step progress, exclusive admission, generation matching,
success observation, exact-once wipe, idempotent cancellation, pre- and
post-callback deadlines, callback faults, cleanup faults, and descriptor reuse.
