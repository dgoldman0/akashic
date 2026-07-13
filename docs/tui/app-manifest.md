# Trusted-local applet manifests

`akashic/tui/app-manifest.f` parses and validates format-1 manifests for locally authored native applets. The manifest is an integrity and ABI contract. It is not a signature, permission model, capability declaration, or sandbox boundary.

## Manifest forms

A project manifest names the source to compile and the applet entry point:

```toml
[package]
format = 1
trust = "local"
source = "/apps/hello/hello.f"

[app]
id = "local.hello"
version = "0.1.0"
abi = 1
entry = "HELLO-ENTRY"
title = "Hello"
width = 40
height = 8
uidl-file = "/apps/hello/hello.uidl"
```

`title`, `width`, `height`, and `uidl-file` are optional. An omitted title defaults to `id`; omitted dimensions are zero, meaning automatic sizing. An omitted `uidl-file` is returned as an empty string.

Build and Install produces an installed manifest by adding three required package fields:

```toml
[package]
format = 1
trust = "local"
source = "/apps/hello/hello.f"
source-sha3 = "<64 lowercase hexadecimal characters>"
image = "/.i0123456789ab.m64"
image-sha3 = "<64 lowercase hexadecimal characters>"
```

The two digests are SHA3-256 encodings. `source-sha3` records the source used for the build; `image-sha3` is the digest the loader checks before loading the image.

## Field contract

| Field | Project | Installed | Contract |
| --- | --- | --- | --- |
| `package.format` | required | required | integer `1` |
| `package.trust` | required | required | string `"local"` |
| `package.source` | required | required | canonical absolute MP64FS path |
| `package.source-sha3` | not required | required | exactly 64 lowercase hexadecimal characters when installed |
| `package.image` | not required | required | canonical absolute MP64FS path when installed |
| `package.image-sha3` | not required | required | exactly 64 lowercase hexadecimal characters when installed |
| `app.id` | required | required | safe atom, 1--63 bytes |
| `app.version` | required | required | safe atom, 1--31 bytes |
| `app.abi` | required | required | integer `1` |
| `app.entry` | required | required | safe atom, 1--23 bytes |
| `app.title` | optional | optional | printable ASCII, 1--63 bytes; no quote or backslash |
| `app.width` | optional | optional | integer 0--4096 |
| `app.height` | optional | optional | integer 0--4096 |
| `app.uidl-file` | optional | optional | canonical absolute MP64FS path |

A safe atom contains only ASCII letters, digits, `.`, `-`, and `_`.

A canonical path is 2--255 bytes, begins with `/`, and uses only ASCII letters, digits, `.`, `-`, `_`, and `/`. Each component is 1--23 bytes. Empty, `.`, and `..` components are rejected, which also rejects repeated slashes and a trailing slash. `/` alone is not a valid manifest path.

## API

```forth
MFT-PARSE               ( doc-a doc-u -- mft status )
MFT-FREE                ( mft -- )
MFT-VALIDATE-PROJECT    ( mft -- status )
MFT-VALIDATE-INSTALLED  ( mft -- status )
```

`MFT-PARSE` requires both `[package]` and `[app]`, reads all known fields, applies defaults, and runs project validation. On failure it returns `0 status`; on success it returns a nonzero descriptor and `MFT-S-OK`.

Installed-only fields are optional while parsing. Code that consumes an installed manifest must call `MFT-VALIDATE-INSTALLED`; successful `MFT-PARSE` by itself does not establish that the three installed fields exist or satisfy their installed form.

String accessors have stack effect `( mft -- a u )`:

```forth
MFT-DOCUMENT       MFT-ID           MFT-TITLE
MFT-VERSION        MFT-ENTRY        MFT-SOURCE
MFT-SOURCE-SHA3    MFT-IMAGE        MFT-IMAGE-SHA3
MFT-TRUST          MFT-UIDL-FILE
```

Integer accessors have stack effect `( mft -- n )`:

```forth
MFT-FORMAT         MFT-ABI          MFT-WIDTH         MFT-HEIGHT
```

Compatibility names remain for the abandoned prototype:

```forth
MFT-NAME    ( mft -- a u )                 \ identical to MFT-ID
MFT-BINARY  ( mft -- a u )                 \ identical to MFT-IMAGE
MFT-DEP?    ( mft key-a key-u -- false )   \ dependencies are not implemented
```

## Ownership

The returned descriptor is a 256-byte heap allocation. `MFT-FREE` releases only that descriptor. Every returned string, including the value from `MFT-DOCUMENT`, points into the caller's TOML document; the caller must keep that document alive until it has finished using the descriptor.

`MFT-FREE` accepts zero. Do not use a descriptor or any accessor result after freeing either the descriptor or its backing document.

## Status values

| Value | Name | Meaning |
| ---: | --- | --- |
| 0 | `MFT-S-OK` | success |
| -110 | `MFT-E-NO-PACKAGE` | no `[package]` table |
| -111 | `MFT-E-NO-APP` | no `[app]` table |
| -112 | `MFT-E-MISSING` | required key absent |
| -113 | `MFT-E-TYPE` | field has the wrong TOML type |
| -114 | `MFT-E-BOUNDS` | empty, overlong, out-of-range, or unsafe value |
| -115 | `MFT-E-FORMAT` | unsupported package format |
| -116 | `MFT-E-TRUST` | trust is not `local` |
| -117 | `MFT-E-DIGEST` | installed digest is not exact lowercase SHA3-256 hex |
| -118 | `MFT-E-ABI` | unsupported app ABI |
| -119 | `MFT-E-ALLOC` | descriptor allocation failed |

When guards are enabled, parsing and the two validation words serialize their short shared-scratch sections. Manifest processing performs no file I/O and does not yield.
