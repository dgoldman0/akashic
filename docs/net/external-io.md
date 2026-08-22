# Owner-pumped external I/O

`akashic/net/external-io.f` serializes cooperative external operations on one
owner core. It is the machine-service boundary for work such as DNS/TCP/TLS
opening whose implementation uses shared platform state. It is not a worker
pool, capability dispatcher, authority grant, or semantic job table.

The service admits one active operation. A host submits an operation and calls
`XIO-TICK` from its normal event loop; each tick invokes at most one start,
ordinary poll, or terminal-cleanup poll callback. The operation owns request,
response, parser, transport, and application-generation storage. The service
owns only exclusive admission, deadline and cancellation handling, cleanup
sequencing, and terminal-state publication.

```forth
CREATE service XIO-SERVICE-SIZE ALLOT
CREATE operation XIO-OP-SIZE ALLOT

service XIO-SERVICE-INIT
operation XIO-OP-INIT

service owner-id owner-generation request-generation deadline-ms context
    start-xt poll-xt cancel-xt wipe-xt operation XIO-OP-CONFIGURE

\ Optional, after XIO-OP-CONFIGURE and before XIO-SUBMIT:
service owner-id owner-generation request-generation cleanup-poll-xt operation
    XIO-OP-CONFIGURE-CLEANUP

service operation XIO-SUBMIT
service XIO-TICK
service operation XIO-CANCEL
service operation XIO-RESET
service owner-id owner-generation request-generation operation XIO-TAKE
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

By default, failure, timeout, and cancellation retain the original synchronous
behavior: invoke the lower cancellation callback and the wipe callback at most
once, release the service slot, and publish the terminal state last. Cleanup
callbacks are attempted even when an earlier cleanup callback throws.
`XIOO.ERROR` retains the primary failure while `XIOO.CLEANUP-ERROR` records the
first cleanup fault.

An operation whose lower authority can take more than one bounded attempt to
release may opt in with `XIO-OP-CONFIGURE-CLEANUP`. This second configurator is
accepted only while the operation is `RESET`, after ordinary configuration,
and only when its supplied owner identity, owner generation, and request
generation exactly match the configured operation. The configurator consumes
the two cells previously reserved in `XIO-OP-SIZE`; the operation size,
version, and existing configure/callback ABI do not change. Reset or ordinary
reconfiguration removes the opt-in.

For an opted-in operation, a terminal cause invokes `cancel-xt` once, records
the intended terminal state in `XIOO.PENDING-TERMINAL`, and leaves the operation
`ACTIVE` and the canonical service occupied. `XIO-CANCEL` returns
`XIO-S-PENDING`; repeated cancellation while cleanup is pending returns the
same status without invoking cancellation again or changing the original
terminal cause. Start and ordinary poll callbacks are never invoked while a
pending terminal target is present.

Each later `XIO-TICK` invokes `cleanup-poll-xt` at most once, with the same
`( operation context -- step-status )` stack contract as start and poll:

- `XIO-STEP-PENDING` retains the service and waits for another tick.
- `XIO-STEP-SUCCEEDED` proves lower authority settled. XIO then invokes wipe
  once, releases the service, and publishes the terminal state.
- `XIO-STEP-FAILED`, an invalid result, or a throw records the first cleanup
  fault, changes the eventual terminal state to `FAILED`, and retains the
  service. Later ticks retry the callback, allowing a transient fault to
  recover. The service is released only after a later `SUCCEEDED` result.

For a returned failure, the provider may first put its specific error in
`XIOO.CLEANUP-ERROR`; otherwise XIO records `XIO-E-STEP`. A throw records its
throw code. In either case the primary `XIOO.ERROR` is unchanged. There is no
force-release API for an authority whose cleanup poll never succeeds: such an
operation intentionally keeps the machine service busy until its provider can
establish terminal ownership. `XIO-CLEANUP-PENDING?` exposes that condition.
For failure, cancellation, or timeout, once a cleanup poll reports success, a
wipe fault is treated as a local cleanup fault under the legacy wipe contract;
lower authority has already been proven settled, so XIO can publish `FAILED`
and release the active service slot. Retained-success reset preserves its
retained wipe obligation on such a fault, as described below.

A successful operation stops polling without wiping its caller-owned result,
but remains retained by the service. This prevents another request or service
teardown from stranding the result's wipe obligation. With the legacy contract,
after the owner validates and consumes—or deliberately discards—that result,
`XIO-RESET` invokes the wipe callback exactly once, releases the retained slot,
and returns the descriptor to `RESET`.

For an opted-in successful operation, `XIO-RESET` instead arms
`XIO-PENDING-RESET`, makes the retained operation tickable, preserves its result,
and returns `XIO-S-PENDING`. A later `XIO-TICK` calls the cleanup poll before
wipe. A provider-specific `TAKE` operation should transfer result authority out
of its descriptor, after which its cleanup poll can immediately report success;
discarding an untaken result may cooperatively close or abort it first. A clean
poll result performs wipe and reset. If the poll faults and later recovers, XIO
publishes `FAILED`, clears the active slot, and leaves the result and retained
wipe obligation intact; a subsequent `XIO-RESET` performs that wipe and clears
the descriptor. Thus neither a callback fault nor a premature reset can lose a
published lower authority.

`XIO-TAKE` is the complementary retained-success operation. It requires the
exact owner, owner generation, request generation, operation, canonical
service, and retained `SUCCEEDED` state. A successful call returns the saved
result, invokes the ordinary wipe callback exactly once for transient request
state, clears the retained slot, and resets the operation immediately. It does
not invoke `cleanup-poll-xt`: the provider must validate and commit transfer of
any external result authority before calling `XIO-TAKE`. A stale generation or
wrong owner cannot consume the result. A wipe fault returns `XIO-S-CALLBACK`
and leaves the result and retained operation observable as `FAILED` for the
ordinary reset path. This gives resource-returning adapters an exact adoption
path without a provider-specific `TAKE`, `XIO-RESET`, then `XIO-TICK`
sequence; `XIO-RESET` remains the deliberate discard operation.

Repeated cancellation of an already cancelled operation is harmless. Resetting
an ordinarily active operation is rejected. Repeating reset while cooperative
reset cleanup is pending returns `XIO-S-PENDING`. Resetting any terminal
operation while a different operation is active or retained returns
`XIO-S-BUSY`.

The operation descriptor, its callback context, and every lower-authority
field consulted by cooperative cleanup must remain allocated and unchanged
until `XIO-CLEANUP-PENDING?` is false and XIO has published the terminal or
reset state. In particular, the current generic applet-host force-close path
does not defer instance reclamation merely because a release callback returns
`XIO-S-PENDING`. An applet may therefore opt in only when these records live in
persistent service-owned storage outside the closeable child instance, unless
that host lifecycle is first extended to await cooperative release. The
inbound listener transport follows the persistent-service rule.

Cancellation is tested before deadlines, both before and after an ordinary
callback. If both become observable together, cancellation is the retained
primary cause. Once terminal cleanup begins, later cancellation or deadline
changes cannot replace that cause.

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
post-callback deadlines, legacy cleanup behavior, pending cooperative cleanup,
retained-success cleanup, cleanup-fault recovery, cancellation/deadline
precedence, and descriptor reuse.
