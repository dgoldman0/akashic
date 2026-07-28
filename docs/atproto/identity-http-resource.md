# AT Protocol identity over HTTP resources

`akashic/atproto/identity-hres.f` is the state-free composition
boundary between the transport-neutral AT identity resolver and one
caller-owned generic HTTPS resource. It does not own DNS, sockets, TLS,
credentials, retry state, caches, or application state.

The adapter provides two words:

```forth
ATID-HRES-SPEC-POLICY!  ( spec -- hres-status )
ATID-HRES-RESPONSE!     ( resource resolver -- atid-status )
```

## Resource policy

Call `ATID-HRES-SPEC-POLICY!` while the specification is still unsealed. It
installs the AT identity HTTP profile:

- any final status from 200 through 299 is admitted;
- `Content-Type` is ignored, including when it is absent or malformed;
- at most `ATID-HTTP-REDIRECT-MAX` (3) redirects are admitted;
- a cross-authority redirect is admitted only when both the current and
  candidate canonical targets use the default HTTPS port 443.

The generic resource still rejects malformed, non-HTTPS, oversized, looping,
or over-budget redirect chains. Same-origin redirects use the generic path;
cross-origin hops invoke the installed authority callback.

The caller must set the target, non-empty `Accept` value, and binding/release
callbacks before sealing the specification. Media is ignored, so no media
callback is required. For example:

```forth
spec HRES-SPEC-INIT
uri-a uri-u spec HRES-SPEC-TARGET! THROW
S" */*" spec HRES-SPEC-ACCEPT! THROW
spec ATID-HRES-SPEC-POLICY! THROW
context bind-xt release-xt spec HRES-SPEC-BINDING! THROW
spec HRES-SPEC-SEAL THROW
```

Every binding callback remains responsible for resolving the candidate host
under the deployment's public-address policy, opening TLS with that exact
hostname for SNI and certificate authentication, and returning a fresh
caller-owned port lease. The redirect callback does not replace those
network-bound checks.

## Response submission

After the resource reaches a valid admitted result, submit it with:

```forth
resource resolver ATID-HRES-RESPONSE!
```

The adapter first asks the resolver for its current exact HTTP action target.
It rejects a non-result resource and rejects a resource whose original
requested target does not exactly equal that action target. This binds an
admitted exchange to the resolver action that requested it and prevents a
completed resource from being replayed after the resolver advances.

On success, the adapter passes the resource's exact body, final HTTP status,
redirect count, and canonical effective target to `ATID-HTTP-RESPONSE!`.
Identity parsing and publication remain atomic in the resolver. The adapter
does not call `ATID-ACTION-FAIL`; the composition owns the decision that
transport retry policy has been exhausted.

`ATID-HRES-RESPONSE!` consumes any valid admitted generic resource result
bound to the current action. It cannot inspect how that resource's
specification was assembled. Production composition therefore uses
`ATID-HRES-SPEC-POLICY!` rather than substituting a weaker local profile.

`ATID-HRES-SPEC-POLICY!` returns the first exact `HRES` setter status that
fails. `ATID-HRES-RESPONSE!` propagates `ATID-HTTP-TARGET@` invalid/state
statuses, returns `ATID-S-HTTP` for a non-admitted or incorrectly bound
resource, and otherwise returns `ATID-HTTP-RESPONSE!` unchanged. A rejected
resource does not implicitly fail the resolver action; the caller invokes
`ATID-ACTION-FAIL` only after its transport policy is exhausted.

## Ownership

The specification, resource, response body, resolver, result, I/O port, and
transport context all remain caller-owned. They must satisfy the non-aliasing
contracts of both modules. Wipe and deconfigure the resource after the
resolver has consumed its borrowed body view; wipe the temporary resolver
after publication or terminal failure.
