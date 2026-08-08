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

The generic result and revision contract and the Agent turn terminal-state
contract are qualified separately and must be run sequentially:

```bash
python3 local_testing/test_request_bus_reentrancy.py
python3 local_testing/akashic_tui.py smoke \
  --profile practice-contracts --max-steps 800000000 --timeout 60
```
