# Immutable OAuth client configuration

`security/oauth2/client-config.f` is the provider-neutral runtime owner for
one exact OAuth authorization-code client selection. It resolves an opaque
durable binding to the client identifier, selected redirect URI, requested
scope, token-endpoint authentication method, optional authentication signing
algorithm, application type, refresh capability, and DPoP-bound-token
declaration.

The record is generic OAuth infrastructure. It contains no AT Protocol,
Streams, provider, browser, HTTP, endpoint-discovery, token, nonce, or private
key state.

## Purpose and boundary

The authorization-code transaction deliberately stores only a bounded opaque
binding. A durable owner uses that binding to recover this immutable record
and the separate key owners selected for the attempt. The same binding may
also be installed in a durable OAuth session.

The binding is not a secret and is not private-key storage. In production it
must identify everything whose substitution would make the authorization or
grant unsafe to continue, including the deployed client registration and the
selected client-authentication and DPoP key identities. Private keys and
credentials remain in their dedicated hardware, vault, or session owners.

For ES256 client authentication and DPoP, the opaque binding can use the
canonical address-free record provided by
[`security/oauth2/key-p256.f`](oauth2-key-p256.md). That owner pins each role
to a credential RID, generation, and RFC 7638 thumbprint while keeping the
private scalar behind the credential-vault boundary.

This module is not a Client ID Metadata Document parser or serializer. An
authorization server fetches that published document, while the local
deployment owner is responsible for ensuring this exact runtime selection is
declared by it. Provider policy adapters can impose a metadata profile without
coupling this generic record to JSON or transport.

## Geometry and lifecycle

Allocate the published fixed sizes on an eight-byte boundary:

| Word | Bytes |
|---|---:|
| `OAUTH2-CLIENT-CONFIG-INPUT-SIZE` | 104 |
| `OAUTH2-CLIENT-CONFIG-SIZE` | 11072 |

The retained capacities are:

| Field | Capacity |
|---|---:|
| opaque binding | 256 |
| client identifier | 2048 |
| exact selected redirect URI | 4096 |
| requested scope | 4096 |
| token authentication method | 256 |
| authentication signing algorithm | 256 |

Clear and populate the pointer-bearing input descriptor:

```forth
input OAUTH2-CLIENT-CONFIG-INPUT-CLEAR

binding-a binding-u
input OAUTH2-CLIENT-CONFIG-I.BINDING-U !
input OAUTH2-CLIENT-CONFIG-I.BINDING-A !

client-id-a client-id-u
input OAUTH2-CLIENT-CONFIG-I.CLIENT-ID-U !
input OAUTH2-CLIENT-CONFIG-I.CLIENT-ID-A !

redirect-a redirect-u
input OAUTH2-CLIENT-CONFIG-I.REDIRECT-URI-U !
input OAUTH2-CLIENT-CONFIG-I.REDIRECT-URI-A !

scope-a scope-u
input OAUTH2-CLIENT-CONFIG-I.SCOPE-U !
input OAUTH2-CLIENT-CONFIG-I.SCOPE-A !

auth-method-a auth-method-u
input OAUTH2-CLIENT-CONFIG-I.AUTH-METHOD-U !
input OAUTH2-CLIENT-CONFIG-I.AUTH-METHOD-A !

auth-algorithm-a auth-algorithm-u
input OAUTH2-CLIENT-CONFIG-I.AUTH-ALGORITHM-U !
input OAUTH2-CLIENT-CONFIG-I.AUTH-ALGORITHM-A !

flags input OAUTH2-CLIENT-CONFIG-I.FLAGS !

input config OAUTH2-CLIENT-CONFIG-INIT
```

`INIT` requires a completely zero destination. It validates all lengths,
source spans, syntax, flags, and alias geometry before mutation, then copies
all retained bytes and publishes the record magic last. Replacing a live
configuration therefore means building another candidate or explicitly
wiping the old record; accidental in-place reconfiguration returns
`OAUTH2-CLIENT-CONFIG-S-STATE`.

`OAUTH2-CLIENT-CONFIG-WIPE ( config -- status )` clears the complete fixed
record even when its former contents are corrupt. `VALID?` and every accessor
fail closed if the record header, lengths, values, flags, or zero padding are
not canonical.

## Flags and value rules

The flags are:

| Flag | Meaning |
|---|---|
| `OAUTH2-CLIENT-CONFIG-F-NATIVE` | application type is native; absence means web |
| `OAUTH2-CLIENT-CONFIG-F-REFRESH` | the selected deployment declares and will use refresh |
| `OAUTH2-CLIENT-CONFIG-F-DPOP-BOUND` | the deployment declares DPoP-bound access tokens |

The opaque binding, client identifier, redirect URI, and authentication
method are required. Scope is generically optional and uses `(0,0)` when
absent. A present scope must follow the RFC 6749 scope grammar exactly:
nonempty tokens separated by single spaces, with no leading or trailing
space. The redirect URI and authentication identifiers are restricted to
visible, space-free ASCII; a generic client identifier admits visible ASCII
including space because its server-defined syntax remains opaque at this
layer.

The authentication algorithm is optional and also uses `(0,0)` when absent.
The explicit `none` authentication method requires it to be absent. Other
method/algorithm relationships belong to a provider profile. In particular,
the generic owner does not silently apply RFC metadata defaults.

## Accessors

All string accessors return `( address length status )`:

```forth
OAUTH2-CLIENT-CONFIG-BINDING@
OAUTH2-CLIENT-CONFIG-CLIENT-ID@
OAUTH2-CLIENT-CONFIG-REDIRECT-URI@
OAUTH2-CLIENT-CONFIG-SCOPE@
OAUTH2-CLIENT-CONFIG-AUTH-METHOD@
OAUTH2-CLIENT-CONFIG-AUTH-ALGORITHM@
```

The returned address is borrowed from the immutable record and remains valid
until wipe. Invalid records return `0 0` plus the failure status.

Scalar accessors are:

```forth
OAUTH2-CLIENT-CONFIG-FLAGS@
OAUTH2-CLIENT-CONFIG-APPLICATION-TYPE@
OAUTH2-CLIENT-CONFIG-REFRESH?
OAUTH2-CLIENT-CONFIG-DPOP-BOUND?
```

Application type is either
`OAUTH2-CLIENT-CONFIG-APPLICATION-WEB` or
`OAUTH2-CLIENT-CONFIG-APPLICATION-NATIVE`.

Each ordinary accessor independently validates the complete record before
returning a borrowed value. Code which needs several fields in one operation
should validate once with the callback-scoped view:

```forth
config callback context OAUTH2-CLIENT-CONFIG-WITH
  ( -- callback-status config-status )
```

The callback receives `( view context -- callback-status )`. During that
callback only, it may use:

```forth
OAUTH2-CLIENT-VIEW-BINDING@
OAUTH2-CLIENT-VIEW-CLIENT-ID@
OAUTH2-CLIENT-VIEW-REDIRECT-URI@
OAUTH2-CLIENT-VIEW-SCOPE@
OAUTH2-CLIENT-VIEW-AUTH-METHOD@
OAUTH2-CLIENT-VIEW-AUTH-ALGORITHM@
OAUTH2-CLIENT-VIEW-FLAGS@
OAUTH2-CLIENT-VIEW-APPLICATION-TYPE@
OAUTH2-CLIENT-VIEW-REFRESH?
OAUTH2-CLIENT-VIEW-DPOP-BOUND?
```

String view accessors return `( address length )`; scalar view accessors
return one value. They deliberately do not revalidate the record. The view
must not be retained or used outside the callback, and the caller must keep
the configuration stable and unmodified until the callback returns. `WITH`
rejects a zero callback or invalid record before invocation and converts a
callback throw or stack-shape violation to
`( 0 OAUTH2-CLIENT-CONFIG-S-CALLBACK )`.

## Statuses

| Status | Meaning |
|---|---|
| `OAUTH2-CLIENT-CONFIG-S-OK` | operation completed |
| `OAUTH2-CLIENT-CONFIG-S-INVALID` | pointer shape, flags, syntax, or record shape is invalid |
| `OAUTH2-CLIENT-CONFIG-S-CAPACITY` | a retained field exceeds its public capacity |
| `OAUTH2-CLIENT-CONFIG-S-ALIAS` | input descriptor or a retained source overlaps the destination |
| `OAUTH2-CLIENT-CONFIG-S-STATE` | destination is not completely zero |
| `OAUTH2-CLIENT-CONFIG-S-RANGE` | caller span has invalid physical geometry |
| `OAUTH2-CLIENT-CONFIG-S-PROTECTED` | caller span intersects platform-private storage |
| `OAUTH2-CLIENT-CONFIG-S-PLATFORM` | caller-memory qualification failed unexpectedly |
| `OAUTH2-CLIENT-CONFIG-S-CALLBACK` | a `WITH` callback threw or returned the wrong stack shape |

Source/source overlap is accepted because every source is borrowed
read-only. No source pointer survives successful initialization.
