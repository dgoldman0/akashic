# akashic-uri — Generic RFC 3986 URI Parser for KDOS / Megapad-64

Scheme-agnostic URI decomposition and reconstruction.  Works with any
URI scheme — `https:`, `at:`, `did:`, `ipfs:`, `urn:`, `mailto:`,
custom, etc.

```forth
REQUIRE uri.f
```

`PROVIDED akashic-uri` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Parsing](#parsing)
- [Result Variables](#result-variables)
- [Building](#building)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)
- [Dependencies](#dependencies)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Zero-copy** | All result pointers reference the original input string. No buffers are allocated for parsed components. |
| **Scheme-agnostic** | No hard-coded scheme list. Parses any valid URI regardless of scheme. |
| **RFC 3986** | Follows the generic URI syntax: `scheme ":" hier-part [ "?" query ] [ "#" fragment ]`. |
| **Complements url.f** | `url.f` provides scheme-aware HTTP/FTP/etc. parsing with features like default ports and percent-encoding. `uri.f` provides lightweight generic decomposition. |

---

## Parsing

### URI-PARSE

```forth
URI-PARSE  ( addr len -- ior )
```

Parse a URI string into its components.  Returns `0` on success,
`-1` on failure (empty input, missing colon, empty scheme).

Results are stored in the `URI-*-A` / `URI-*-L` variable pairs.
All pointers reference the **original input string** — do not modify
or free the input while results are in use.

Parsing stages:

1. **Scheme** — text before first `:`
2. **Authority** — present if `://` follows the scheme; decomposed
   into optional userinfo (`@`), host, and port (`:`)
3. **Path** — text after authority up to `?` or `#`
4. **Query** — text after `?` up to `#`
5. **Fragment** — text after `#` to end

---

## Result Variables

Each component is stored as an `(address, length)` pair in two
`VARIABLE`s.  A length of `0` means the component is absent.

| Address Variable | Length Variable | Component |
|---|---|---|
| `URI-SCHEME-A` | `URI-SCHEME-L` | Scheme (e.g. `https`, `at`, `urn`) |
| `URI-AUTH-A` | `URI-AUTH-L` | Full authority (e.g. `user:pass@host:8080`) |
| `URI-UINFO-A` | `URI-UINFO-L` | Userinfo before `@` |
| `URI-HOST-A` | `URI-HOST-L` | Host |
| `URI-PORT-A` | `URI-PORT-L` | Port (string, not numeric) |
| `URI-PATH-A` | `URI-PATH-L` | Path (includes leading `/` if present) |
| `URI-QUERY-A` | `URI-QUERY-L` | Query (without leading `?`) |
| `URI-FRAG-A` | `URI-FRAG-L` | Fragment (without leading `#`) |

---

## Building

### URI-BUILD

```forth
URI-BUILD  ( dst max -- written )
```

Reconstruct a URI string from the current result variables into `dst`.
Returns the number of bytes written.  Assembles components in standard
order: `scheme://[userinfo@]host[:port]path[?query][#fragment]`.

Typical use: parse a URI, modify one component, then rebuild.

---

## Quick Reference

| Word | Stack | Purpose |
|---|---|---|
| `URI-PARSE` | `( addr len -- ior )` | Parse URI into components |
| `URI-BUILD` | `( dst max -- written )` | Reconstruct URI from components |
| `URI-SCHEME-A` / `L` | VARIABLE | Scheme component |
| `URI-AUTH-A` / `L` | VARIABLE | Full authority |
| `URI-UINFO-A` / `L` | VARIABLE | Userinfo (before `@`) |
| `URI-HOST-A` / `L` | VARIABLE | Host |
| `URI-PORT-A` / `L` | VARIABLE | Port (string) |
| `URI-PATH-A` / `L` | VARIABLE | Path |
| `URI-QUERY-A` / `L` | VARIABLE | Query (without `?`) |
| `URI-FRAG-A` / `L` | VARIABLE | Fragment (without `#`) |

---

## Cookbook

### Parse HTTPS URL

```forth
CREATE _BUF 256 ALLOT
S" https://example.com:8080/path?q=1#top" URI-PARSE DROP
URI-SCHEME-A @ URI-SCHEME-L @ TYPE   \ → https
URI-HOST-A   @ URI-HOST-L   @ TYPE   \ → example.com
URI-PORT-A   @ URI-PORT-L   @ TYPE   \ → 8080
URI-PATH-A   @ URI-PATH-L   @ TYPE   \ → /path
URI-QUERY-A  @ URI-QUERY-L  @ TYPE   \ → q=1
URI-FRAG-A   @ URI-FRAG-L   @ TYPE   \ → top
```

### Parse AT URI

```forth
S" at://did:plc:abc/app.bsky.feed.post/rk1" URI-PARSE DROP
URI-SCHEME-A @ URI-SCHEME-L @ TYPE   \ → at
URI-AUTH-A   @ URI-AUTH-L   @ TYPE   \ → did:plc:abc
URI-PATH-A   @ URI-PATH-L   @ TYPE   \ → /app.bsky.feed.post/rk1
```

### Parse opaque URI (no authority)

```forth
S" mailto:user@host.com" URI-PARSE DROP
URI-SCHEME-A @ URI-SCHEME-L @ TYPE   \ → mailto
URI-PATH-A   @ URI-PATH-L   @ TYPE   \ → user@host.com
URI-AUTH-L   @ .                      \ → 0  (no authority)
```

### Round-trip

```forth
CREATE _BUF 256 ALLOT
S" https://user:pw@host:443/p?q=1#f" URI-PARSE DROP
_BUF 256 URI-BUILD
_BUF SWAP TYPE
\ → https://user:pw@host:443/p?q=1#f
```

---

## Dependencies

- `string.f` — uses `STR-INDEX` for delimiter scanning.

## Internal State

Variable-based state prefixed `_URI-`:

- `_URI-PTR` / `_URI-REM` — parser cursor and remaining length
- `_UB-DST` / `_UB-MAX` / `_UB-POS` — builder state
