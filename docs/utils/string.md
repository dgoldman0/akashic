# akashic-string — Shared String Utilities for KDOS / Megapad-64

Common string operations shared across Akashic libraries. Eliminates
duplicate code previously found in `css.f`, `markup/core.f`, and
`net/headers.f`.

```forth
REQUIRE string.f
```

All words use the standard `( addr len )` string model.

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `/STRING` | `( addr len n -- addr+n len-n )` | Advance string pointer |
| `_STR-LC` | `( c -- c' )` | Lowercase a single ASCII char |
| `_STR-UC` | `( c -- c' )` | Uppercase a single ASCII char |
| `STR-TOLOWER` | `( addr len -- )` | In-place lowercase |
| `STR-TOUPPER` | `( addr len -- )` | In-place uppercase |
| `STR-STR=` | `( s1 l1 s2 l2 -- flag )` | Case-sensitive compare |
| `STR-STRI=` | `( s1 l1 s2 l2 -- flag )` | Case-insensitive compare |
| `STR-STARTS?` | `( str-a str-u pfx-a pfx-u -- flag )` | Case-sensitive prefix |
| `STR-STARTSI?` | `( str-a str-u pfx-a pfx-u -- flag )` | Case-insensitive prefix |
| `STR-ENDS?` | `( str-a str-u sfx-a sfx-u -- flag )` | Case-sensitive suffix |
| `STR-INDEX` | `( str-a str-u c -- idx \| -1 )` | First char occurrence |
| `STR-RINDEX` | `( str-a str-u c -- idx \| -1 )` | Last char occurrence |
| `STR-STR-CONTAINS` | `( hay-a hay-u ndl-a ndl-u -- flag )` | Case-sensitive substring search |
| `STR-STRI-CONTAINS` | `( hay-a hay-u ndl-a ndl-u -- flag )` | Case-insensitive substring search |
| `STR-SPLIT` | `( str-a str-u c -- pre-a pre-u post-a post-u flag )` | Split at delimiter |
| `STR-TRIM` | `( addr len -- addr' len' )` | Trim whitespace both ends |
| `STR-TRIM-L` | `( addr len -- addr' len' )` | Trim leading whitespace |
| `STR-TRIM-R` | `( addr len -- addr' len' )` | Trim trailing whitespace |
| `NUM>STR` | `( n -- addr len )` | Signed integer to decimal string |
| `STR>NUM` | `( addr len -- n flag )` | Decimal string to signed integer |
| `STR-SKIP-BL` | `( addr len -- addr' len' )` | Skip leading blanks (space/tab) |
| `STR-PARSE-TOKEN` | `( addr len -- tok-addr tok-len rest-addr rest-len )` | Extract next whitespace-delimited token |

Flags: `-1` = true, `0` = false.

---

## Case Conversion

### `_STR-LC` / `_STR-UC`

Internal char-level helpers. Convert a single ASCII character to
lower/upper case. Non-alpha characters pass through unchanged.

### `STR-TOLOWER` / `STR-TOUPPER`

Modify the string buffer in place. Only affect ASCII A–Z / a–z.

```forth
CREATE buf 5 ALLOT
S" Hello" buf SWAP CMOVE
buf 5 STR-TOLOWER   \ buf now contains "hello"
```

---

## Comparison

### `STR-STR=`

Byte-for-byte comparison. Returns `-1` if both strings have the same
length and identical content; `0` otherwise. Two zero-length strings
are equal.

### `STR-STRI=`

Like `STR-STR=` but compares ASCII letters case-insensitively.

```forth
S" Content-Type" S" content-type" STR-STRI=   \ → -1
S" Accept"       S" accept-encoding" STR-STRI= \ → 0
```

---

## Prefix / Suffix

### `STR-STARTS?` / `STR-STARTSI?`

Test whether `str` begins with `pfx`. The `I` variant is
case-insensitive. An empty prefix always matches.

```forth
S" Hello World" S" Hello" STR-STARTS?   \ → -1
S" hello world" S" Hello" STR-STARTSI?  \ → -1
```

### `STR-ENDS?`

Case-sensitive suffix test.

```forth
S" image.png" S" .png" STR-ENDS?   \ → -1
```

---

## Searching

### `STR-INDEX`

Returns the zero-based index of the first occurrence of char `c`, or
`-1` if not found.

### `STR-RINDEX`

Returns the index of the last occurrence of char `c`, or `-1`.

```forth
S" hello" 108 STR-INDEX   \ → 2  (first 'l')
S" hello" 108 STR-RINDEX  \ → 3  (last 'l')
```

### `STR-STR-CONTAINS` / `STR-STRI-CONTAINS`

Substring search. Returns `-1` if needle is found anywhere in the
haystack, `0` otherwise. The `I` variant is case-insensitive.

```forth
S" underline line-through" S" underline" STR-STR-CONTAINS  \ → -1
S" Hello World" S" WORLD" STR-STRI-CONTAINS               \ → -1
S" solid" S" dashed" STR-STR-CONTAINS                     \ → 0
```

---

## Splitting

### `STR-SPLIT`

Splits at the first occurrence of delimiter char `c`. Returns the
pre-delimiter and post-delimiter substrings plus a flag. Both
substrings point into the original buffer (no allocation).

```forth
S" key=value" 61 STR-SPLIT
\ → pre-a pre-u post-a post-u -1
\ pre = "key", post = "value"
```

If the delimiter is not found, returns the full string as `pre`,
`0 0` as `post`, and `0` as the flag.

---

## Trimming

### `STR-TRIM` / `STR-TRIM-L` / `STR-TRIM-R`

Remove whitespace (space, tab, CR, LF) from the left, right, or both
ends. Returns adjusted `addr len` — no allocation, just pointer
arithmetic into the original buffer.

---

## Number Conversion

### `NUM>STR`

Convert a signed 64-bit integer to a decimal ASCII string. Uses a
static 24-byte internal buffer — **not re-entrant**.

```forth
-42 NUM>STR TYPE   \ prints "-42"
```

### `STR>NUM`

Parse a decimal string (optional leading `-` or `+`) into an integer.
Returns `( n -1 )` on success, `( 0 0 )` on failure (empty, or
invalid character).

```forth
S" 1234" STR>NUM   \ → 1234 -1
S" -99"  STR>NUM   \ → -99  -1
S" abc"  STR>NUM   \ → 0    0
```

---

## Tokenizer

### `STR-SKIP-BL`

Skip leading blanks (ASCII 32 and 9/tab) from a string. Returns
adjusted `addr len` pointing past the whitespace.

### `STR-PARSE-TOKEN`

Extract the next whitespace-delimited token from a string. Returns
the token (addr len) and the remainder of the input string.

```forth
S"   hello world" STR-PARSE-TOKEN
\ → tok-addr 5 rest-addr 5   (tok="hello", rest="world")
```

If the input is empty or all blanks, returns `0 0` for the token and
the remaining (empty) string.

Used by `utils/itc.f` for tokenizing ITC source text.

---

## Dependencies

None. `string.f` is a leaf library with no `REQUIRE` directives.

## Consumers

- `utils/css/css.f` — replaces `_CSS-STR=`, `_CSS-STRI=`, `_CSS-TOLOWER`
- `utils/markup/core.f` — replaces `_MU-STR=`, `_MU-STRI=`, `_MU-TOLOWER`
- `utils/net/headers.f` — replaces `_CI-LOWER`, `_CI-EQ`, `_CI-PREFIX`

## Internal State

Uses module-level `VARIABLE`s to avoid R-stack conflicts inside
`DO…LOOP` (the KDOS `R@` inside a loop reads the loop index, not a
user-saved value). Prefixed `_S*-`:

- `_SI-*` — STR-INDEX
- `_SR-*` — STR-RINDEX
- `_SS-*` — STR-STARTS?
- `_SE-*` — STR-ENDS?
- `_SP-*` — STR-SPLIT
- `_S2N-*` — STR>NUM
- `_N2S-*` — NUM>STR
