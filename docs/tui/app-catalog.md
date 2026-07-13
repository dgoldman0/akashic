# Durable applet catalog

`akashic/tui/app-catalog.f` owns the installed-applet index at
`/app-catalog.bin`.  It is bounded to 32 rows and uses a strict version-one
binary codec: exact file length, CRC-32, canonical zero padding, valid UTF-8,
one built-in/package kind bit, known flags only, and unique nonempty component
IDs.  Decode rejects trailing data and publishes no partial candidate.

Catalog mutations copy the live table into a candidate, encode it, and publish
it through `VREPL-REPLACE`.  Live memory changes only after the replacement's
commit point.  An uncertain replacement or invalid on-disk catalog enters
read-only recovery rather than guessing which state won.

Each 496-byte runtime row contains a 464-byte persistent prefix (flags,
quarantine reason, lengths, and fixed copied buffers for ID, title, version,
and installed-manifest path) plus runtime-only descriptor, load state, error,
and Desk slot fields.  Callers should use `ACE-ID$`, `ACE-TITLE$`,
`ACE-VERSION$`, `ACE-MANIFEST$`, `ACE.FLAGS`, `ACE.DESC`, `ACE.STATE`,
`ACE.ERROR`, and `ACE.SLOT` rather than depending on offsets.

## Main API

| Word | Stack | Meaning |
|---|---|---|
| `ACAT-NEW` | `( vfs -- catalog status )` | Allocate/configure a catalog. |
| `ACAT-ACTIVATE` | `( catalog -- status )` | Recover VREPL state and strictly load the target.  Missing is an empty usable catalog. |
| `ACAT-BIND-BUILTIN` | `( desc default-flags catalog -- status )` | Bind by exact descriptor component ID; a missing row is committed first. |
| `ACAT-UPSERT-PACKAGE` | `( ia iu ta tu va vu ma mu flags catalog -- status )` | Insert or transactionally update copied package metadata. |
| `ACAT-INSTALL-PACKAGE` | same | Alias of package upsert. |
| `ACAT-SET-FLAGS` | `( flags entry catalog -- status )` | Persist policy flags without changing kind. |
| `ACAT-QUARANTINE` | `( reason entry catalog -- status )` | Persist quarantine and disable the row. |
| `ACAT-RESOLVER!` | `( xt context catalog -- )` | Set lazy hook `( entry context -- desc status )`. |
| `ACAT-RELEASER!` | `( xt context catalog -- )` | Set its companion ownership hook `( desc context -- )`. |
| `ACAT-RESOLVE` | `( entry catalog -- desc status )` | Enforce policy, resolve lazily, validate APP-DESC and exact component ID, then cache. |
| `ACAT-ENCODE` | `( buffer capacity catalog -- length status )` | Encode the live table. |
| `ACAT-DECODE` | `( buffer length catalog -- status )` | Strictly decode and atomically replace the live table on success. |

Package upsert rejects a built-in ID collision.  Updating a package whose
`ACE.SLOT` is live returns `ACAT-S-BUSY`; a closed update replaces metadata and
clears its cached runtime descriptor only after persistence succeeds.  Existing
enabled/pinned/autostart/quarantine policy and quarantine reason survive an
update.  The catalog owns copies of all strings, so source/manifest buffers can
be released after a successful call.

Package descriptors returned by the resolver are cached until a successful
closed-package replacement or catalog teardown.  The releaser is called once
at that boundary and also discards a resolver result that fails descriptor or
exact-ID validation.  Failed persistence retains both the old row and cached
descriptor.  Built-in/static descriptors never pass through the releaser.

The module never evaluates manifest text and never loads an image.  Desk's
default resolver passes the copied `ACE-MANIFEST$` to the trusted-local app
loader only when a user/autostart action actually opens a package, and its
companion releaser calls `ALOAD-DESC-FREE`.
