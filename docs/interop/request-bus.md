# Request-bus handler outcomes

`akashic/interop/request-bus.f` serializes capability dispatch through the
semantic owner. Policy, authority, target generation, expected revision, and
input-schema checks all complete before the handler runs. Handler results then
cross the output-schema and component-revision boundary while the same owner
guard remains held.

Two handler statuses are result-bearing:

- `CBUS-S-OK` reports a committed operation. The bus validates `CBR.RESULT`
  against `CAP.OUT-SCHEMA`, advances the component revision for state-changing
  effect classes, writes the resulting revision to `CBR.ACTUAL-REV`, and
  commits a running Agent Practice turn.
- `CBUS-S-NO-EFFECT` reports a completed operation that deliberately published
  no new owner state. The bus still validates and retains `CBR.RESULT`, writes
  the unchanged component revision to `CBR.ACTUAL-REV`, and never calls
  `CINST-TOUCH`. A running effectful Agent Practice turn becomes
  `PTURN-S-REJECTED`, records `CBUS-S-NO-EFFECT` in `PTURN.STATUS`, and receives
  its completion time in the same dispatch.

`CBUS-RESULT-BEARING? ( status -- flag )` is the public closed classifier for
these two outcomes. Adapters that translate owner results into another status
domain should use it to distinguish a typed no-effect receipt from an ordinary
failure, then inspect their application receipt to choose the precise external
status.

`NO-EFFECT` is not an authority or schema shortcut. A malformed output changes
the request result to `CBUS-S-FAILED` and frees the rejected value. Every other
non-result-bearing handler or bus status also frees `CBR.RESULT`; effectful
Agent failures follow the existing failed/indeterminate Practice-turn rules.

## Deferred completion

A handler for long-running work may return `CBUS-S-ACCEPTED`: its owner keeps
the request and completes it later. Only an observe-only capability
(`CAP-E-OBSERVE`) may do this, because it publishes no owner revision and needs
no Practice turn. Any other effect class that returns `ACCEPTED` fails with
`CBUS-S-FAILED` and an error code of `CBUS-S-ACCEPTED`. All dispatch checks and
any authority consumption have already happened when the handler runs.

An accepted request keeps `CBR.STATUS` at `CBUS-S-ACCEPTED`, carries
`CBR-F-DEFERRED`, and stays busy. It cannot be reset, queued or dispatched
again, and its completion callback does not run yet. Its requester must not
free it until the callback has run. `CBR-DEFERRED?` reports the state, and the
requester asks for cancellation with `CBR-CANCEL` as usual.

The owner finishes the request with
`CBUS-COMPLETE-DEFERRED ( status request instance -- ior )`:

- `INSTANCE` must be the request's target, and `STATUS` a final status, not
  `ACCEPTED`. Otherwise the call returns `CBUS-S-INVALID` and changes nothing.
  It also refuses a request that is no longer deferred, so a request completes
  once.
- A result-bearing status crosses `CAP.OUT-SCHEMA` exactly as at dispatch. A
  malformed result becomes `CBUS-S-FAILED`, and the bus frees it.
- A result-bearing completion records the owner's unchanged revision in
  `CBR.ACTUAL-REV`.
- The requester's callback runs after the bus guard is released. The owner
  must not touch the request after the call.

An owner polls `CBR-CANCEL-REQUESTED?` and completes a cancelled request,
normally with `CBUS-S-CANCELLED`. An owner that is closing must first complete
every request it still holds.

The generic result and revision contract and the Agent turn terminal-state
contract are qualified separately and must be run sequentially:

```bash
python3 local_testing/test_request_bus_reentrancy.py
python3 local_testing/akashic_tui.py smoke \
  --profile practice-contracts --max-steps 800000000 --timeout 60
```
