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
