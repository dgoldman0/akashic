# Semantic resource acquisition

`akashic/interop/resource-acquisition.f` is the activation-local retain and
attachment boundary for a QLOC. Acquisition always calls the semantic owner's
root, even when the RID is already published in `RREG`; registry presence is
not ownership or a retain.

A root descriptor names one owner contract and supplies acquire, quiescence,
and release callbacks. A successful acquire returns a semantic RREF and one
self-bound token in a caller-owned result. `RACQ-ATTACH` then attaches an
LBIND through the normal live registry. If attachment fails, acquisition
rolls the owner retain back.

Before initializing either output or invoking an owner callback,
`RACQ-ATTACH` validates the nonwrapping fixed spans it knows for locator, RACQ
root, Context, resource registry, binding, and result. Binding and result must
be disjoint from one another and from every known input span. This generic
preflight deliberately knows only the 88-byte RACQ root ABI. An owner whose
RACQ header prefixes a larger root or whose safety depends on a reachable
borrowed graph must expose an owner-specific wrapper that validates those
larger spans before delegating to `RACQ-ATTACH`. The neutral resource-owner
pool does so for its complete header and caller-owned slot/lease arrays with
`ROPOOL-ATTACH`; the Library projection owner adds its larger root and borrowed
store/runtime graph checks before delegating to that pool boundary.

The pool's `ROFFER` is only the discovery descriptor for one named resource:
it pairs an exact RID with the pool that owns it. It does not replace the RACQ
root, token ledger, or attachment check and grants no retain by itself. A
resource session validates an owner-lent offer against its discovered runtime,
copies those two values, and performs the ordinary `ROPOOL-ATTACH` transaction.
No global-pool service participates in acquisition.

Tokens contain live root and self pointers, a private-owner cookie, and a
generation, so they are never persistent. Copying token bytes changes their
self address and makes the copy stale. The owner must additionally compare the
original token address, cookie, and generation with its private active slot;
the portable predicate alone is not the owner's complete check.

Release has strict retry behavior:

- an empty token is idempotently successful;
- a copied, malformed, or owner-rejected token is not released;
- normal release waits through `BUSY` quiescence responses;
- quiescence or owner-release failure restores the original active token;
- the token is cleared only after the owner accepts exactly one release.

The same rule covers rollback. If cleanup fails after attachment or a partial
owner callback, the result retains its original active token so the caller can
retry. `RACQ-DETACH` clears the LBIND only after release succeeds.

Owner qualification status is explicit: unavailable, RID/owner mismatch,
unqualified, revision mismatch, digest mismatch, generic gone, tombstoned RID,
pruned exact revision, or capacity. Tombstone and pruning are distinct closed
terminal statuses; neither is silently retried as identity/current. If a
partial owner failure then suffers cleanup failure, the primary result becomes
`RELEASE-FAILED` while `DETAIL` preserves the original terminal owner status.
