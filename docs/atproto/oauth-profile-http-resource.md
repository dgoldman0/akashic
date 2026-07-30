# AT OAuth discovery over HTTP resources

`atproto/oauth-profile-hres.f` composes the transport-neutral AT OAuth
discovery profile with a caller-owned generic HTTPS resource. It owns no DNS,
socket, TLS, browser, token, session, XRPC, Streams, or application state.
The exact JSON response policy and retained-envelope checks are shared with
other AT OAuth resources through `atproto/oauth-hres.f`; they remain
AT-specific policy over the generic `net/http-resource.f` owner.

The public API is:

```forth
AT-OAUTH-HRES-WORKSPACE-SIZE

AT-OAUTH-HRES-WORKSPACE-CLEAR
  ( workspace -- profile-status )

AT-OAUTH-HRES-SPEC-POLICY!
  ( spec -- hres-status )

AT-OAUTH-HRES-RESOURCE!
  ( resource workspace profile -- profile-status )

AT-OAUTH-HRES-AUTHORIZATION-SERVER!
  ( resource workspace profile -- profile-status )
```

## Caller-owned workspace

The adapter workspace is transient, eight-byte-aligned caller storage. It
contains one generic metadata result and parser workspace large enough for
either discovery stage. The complete workspace is cleared before parsing and
again before an admitted operation returns. A qualified geometry or alias
rejection occurs before any mutation.

`AT-OAUTH-HRES-WORKSPACE-CLEAR` explicitly clears a qualified workspace.
Callers should use it before releasing storage after a request that was
rejected before parsing.

The resource, workspace, profile, and complete configured response-buffer
storage must be mutually disjoint. The adapter qualifies every complete fixed
span and the full `HRES-BODY-STORAGE@` span before clearing or parsing
anything. Checking only the used `HRES-BODY@` bytes would miss an alias in the
unused buffer tail. This closes aliases that neither the generic HTTP resource
nor either metadata parser can detect in isolation.

## HTTP policy

Call `AT-OAUTH-HRES-SPEC-POLICY!` on an initialized, unsealed `HRES`
specification. It installs:

- `Accept: application/json`;
- exact success status `200`;
- a redirect maximum of zero;
- required response media; and
- a pure media callback accepting only the case-insensitive base media type
  `application/json`.

Syntactically valid media parameters such as `charset=utf-8` are admitted.
Vendor `+json`, `text/json`, missing, duplicate, or malformed content types are
not admitted.

The helper stops at the first exact `HRES` setter failure. Like the underlying
pre-seal setters, it is not an atomic transaction and does not seal the
specification. The caller still installs the exact target and its bind/release
provider before sealing.

The bind provider remains responsible for hardened DNS resolution,
public-address policy, authenticated TLS hostname verification, deadlines,
and lease ownership. The adapter does not infer those properties from an
HTTPS URI.

## Discovery flow

After `AT-OAUTH-PROFILE-BEGIN`, obtain
`AT-OAUTH-PROFILE-RESOURCE-METADATA-TARGET@`, configure an `HRES` request for
that exact target, and run it to a retained result. Submit the result with
`AT-OAUTH-HRES-RESOURCE!`.

On success the profile advances to
`AT-OAUTH-PROFILE-PHASE-AUTHORIZATION-SERVER-METADATA`. Obtain
`AT-OAUTH-PROFILE-AUTHORIZATION-SERVER-METADATA-TARGET@`, fetch it with a
freshly configured resource, and submit it with
`AT-OAUTH-HRES-AUTHORIZATION-SERVER!`.

The second success advances the profile to `AT-OAUTH-PROFILE-PHASE-READY` and
unlocks its authorization, token, and PAR target accessors.

The adapter does not trust the caller to have used its policy helper. Before
either parser runs it independently requires all of the following from the
retained resource:

- a valid admitted `HRES` result;
- exact HTTP status `200`;
- redirect count zero;
- requested target exactly equal to the profile's current metadata target;
- effective target exactly equal to the same target; and
- parsed base media type `application/json`.

Both target checks are intentional. `HTARGET-EQUAL?` compares canonical URI
bytes, while the separate redirect-count check retains redirect provenance.

## Failure semantics

Invalid ownership geometry returns the corresponding profile `INVALID`,
`ALIAS`, `RANGE`, `PROTECTED`, or `PLATFORM` status without mutation.
Wrong profile phase and corrupted profile state propagate the phase-gated
target accessor status.

An invalid resource or HTTP-envelope mismatch returns
`AT-OAUTH-PROFILE-S-HTTP`. A syntactically invalid protected-resource document
returns `AT-OAUTH-PROFILE-S-RESOURCE-METADATA`; a syntactically invalid
authorization-server document returns
`AT-OAUTH-PROFILE-S-AUTHORIZATION-SERVER`. Capacity, platform, and internal
parser failures map to their corresponding profile status.

Envelope and parser failures leave the pending profile phase unchanged, so a
caller may fetch a fresh response and retry. A parser result is never submitted
after a non-OK parse; the transient result is wiped before return, preventing
a prior valid document from being reused accidentally.

Once a document parses successfully, the adapter calls the pure profile
transition. Resource binding, issuer binding, AT OAuth capability, and endpoint
failures therefore publish the profile's terminal `FAILED` phase exactly as
documented by `oauth-profile.f`.

Unexpected parser or transition throws are rethrown only after the complete
adapter workspace is wiped. The adapter never wipes or deconfigures the
`HRES` object; retained-resource and cleanup-quarantine ownership stays with
its caller.
