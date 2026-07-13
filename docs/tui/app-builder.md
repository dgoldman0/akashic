# Trusted-local applet builder

`akashic/tui/app-builder.f` implements the developer-facing Build and Install path from a format-1 project manifest to an immutable MF64 image, an installed manifest, and a durable app-catalog entry.

This workflow compiles trusted native Forth. The checked evaluator supplies bounded diagnostics and the image builder supplies structural verification, but neither is a sandbox. Source evaluation can call ambient words and perform arbitrary side effects before the builder rolls its temporary dictionary definitions back.

## Setup and API

Configure the catalog before installing anything:

```forth
ABUILD-CATALOG!  ( catalog -- )
```

The build operation is:

```forth
ABUILD-INSTALL  ( project-path-a project-path-u -- entry status )
```

On success, `entry` is the resulting app-catalog entry and `status` is `ABUILD-S-OK`. The pointer is owned by the catalog and remains stable only until the next catalog mutation. On failure, the builder returns `0 status` and owns no result buffers.

The module is synchronous and non-reentrant. A recursive or concurrent call returns `ABUILD-E-BUSY`. Callers must also respect the owner-context requirements of source evaluation and dictionary-image construction.

## Build and install pipeline

For one call, the builder:

1. exact-reads the project manifest through VFS, with a 4096-byte limit;
2. parses and validates it as a project manifest;
3. exact-reads its single declared source file, with a 512 KiB limit, and computes the source SHA3-256;
4. saves evaluator depth, starts `IMG-MARK`, and runs `SOURCE-EVALUATE-CHECKED`;
5. finds the exact declared `app.entry` among the live words and registers it with `IMG-ENTRY-NAMED`;
6. builds and verifies a version-2 MF64 image into a heap buffer;
7. calls `IMG-DISCARD`, removing the temporary source definitions and image-build relocation storage from the live dictionary;
8. computes the image SHA3-256 and serializes an installed manifest;
9. reparses and validates that generated installed manifest;
10. publishes the image, then the installed manifest, as immutable VFS objects;
11. upserts the package into the configured app catalog as the final transaction commit.

The declared entry is therefore a real version-2 named export bound to the exact dictionary word produced after `IMG-MARK`; the builder does not recover it later by evaluating text. The manifest selects one launch entry. It does not promise that trusted source has not explicitly registered other image exports.

Compilation rollback covers `HERE`, `LATEST`, image build state, and evaluator nesting state. It cannot undo ambient effects the source performed through VFS, devices, global variables outside the discarded region, or other services.

## Installed objects and commit boundary

The builder derives short immutable object names from the first six digest bytes:

```text
/.i<12 lowercase hex>.m64
/.m<12 lowercase hex>.toml
```

The image name is derived from the image digest. The manifest name is derived from the digest of the complete serialized installed manifest. These are truncated content-derived names, so publication checks the complete existing file byte-for-byte: an identical object is reused, while different bytes at the same name return `ABUILD-E-COLLISION`.

Publication order is image, installed manifest, catalog. The catalog upsert is the final visible commit. A failure after either immutable object is published can leave an unreferenced object behind, but it does not partially update the catalog. There is no rollback deletion of published immutable objects.

For a new catalog entry the builder requests `enabled` and `pinned`. Updating an existing package preserves the catalog's current user-policy flags and quarantine reason while replacing its package metadata. The catalog itself owns durability and recovery for its upsert.

The installed manifest records both the full source and image SHA3-256 values. The builder does not load or launch the resulting applet; that is the loader's separate trust and ownership boundary.

## Diagnostics

```forth
ABUILD-LAST-STATUS     ( -- status )
ABUILD-LAST-DETAIL     ( -- detail )
ABUILD-EVAL-STATUS     ( -- status )
ABUILD-EVAL-LINE       ( -- line )
ABUILD-EVAL-COLUMN     ( -- column )
ABUILD-EVAL-THROW      ( -- throw-code )
ABUILD-EVAL-TOKEN      ( -- addr len )
ABUILD-SOURCE-PATH     ( -- addr len )
ABUILD-INSTALLED-PATH  ( -- addr len )
```

`ABUILD-LAST-STATUS` reports the most recent completed non-busy build operation. `ABUILD-LAST-DETAIL` reports the lower-level manifest, evaluator, binimg, serializer, VFS-replace, catalog, or raw thrown status when that failure path supplies one; it may be zero for a direct builder error.

The evaluator accessors expose MegaPad's checked-evaluator diagnostics. Lines
are one-based and columns are zero-based byte offsets, matching
`SOURCE-EVALUATE-CHECKED`; presentation layers that display one-based columns
must normalize them. A source-level `THROW` is caught by the checked evaluator:
`ABUILD-INSTALL` returns `ABUILD-E-COMPILE`, `ABUILD-LAST-DETAIL` is
`EVAL-S-THROW` (`5`), and `ABUILD-EVAL-THROW` returns the original throw code.
`ABUILD-E-THROW` is reserved for an unexpected throw outside that checked
source-evaluation boundary.

A failed compilation leaves evaluator diagnostics readable after dictionary rollback. Reaching the checked-evaluation stage of the next build clears the evaluator status, so callers should consume diagnostics before retrying.

`ABUILD-SOURCE-PATH` returns a module-owned copy of the validated project
manifest's source path for the current or most recently completed non-busy
operation. A new non-busy operation clears it, then populates it after project
manifest validation and before the source is opened, read, or evaluated.
Cleanup preserves the copy on both success and failure, including compile
failure; failures before manifest validation leave it empty. A rejected busy
call does not alter it. The next non-busy operation may overwrite the storage,
so callers that need a longer lifetime must copy it.

`ABUILD-INSTALLED-PATH` returns module-owned storage for the installed-manifest path derived during the current or most recently completed operation. A new non-busy operation resets and may overwrite it; early failures return an empty path.

## Status values

| Value | Name | Meaning |
| ---: | --- | --- |
| 0 | `ABUILD-S-OK` | catalog commit succeeded |
| -200 | `ABUILD-E-SETUP` | no catalog has been configured |
| -201 | `ABUILD-E-BUSY` | recursive or concurrent operation |
| -202 | `ABUILD-E-IO` | VFS open or exact-read failure |
| -203 | `ABUILD-E-BOUNDS` | manifest or source is empty or exceeds its cap |
| -204 | `ABUILD-E-NOMEM` | heap allocation failed |
| -205 | `ABUILD-E-MANIFEST` | project manifest parse or validation failed |
| -206 | `ABUILD-E-COMPILE` | checked source evaluation failed, including a normalized source-level `THROW` |
| -207 | `ABUILD-E-ENTRY` | declared entry is absent or cannot be registered as the named entry export |
| -208 | `ABUILD-E-IMAGE` | image sizing, construction, verification, or discard failed |
| -209 | `ABUILD-E-SERIALIZE` | generated installed manifest could not be serialized or validated |
| -210 | `ABUILD-E-COLLISION` | an immutable object path already contains different bytes |
| -211 | `ABUILD-E-PUBLISH` | immutable VFS replacement or recovery failed |
| -212 | `ABUILD-E-CATALOG` | catalog upsert or result lookup failed |
| -213 | `ABUILD-E-THROW` | an unexpected throw occurred outside checked source evaluation |

Unexpected throws are caught, reported as `ABUILD-E-THROW`, and followed by normal cleanup. If cleanup itself cannot discard an otherwise live image build, the builder reports `ABUILD-E-IMAGE` when no earlier error was already established.
