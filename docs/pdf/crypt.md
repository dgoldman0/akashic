# akashic-pdf-crypt — PDF's standard security handler, with the empty password

Many PDFs are encrypted with an empty user password, to carry permissions
rather than to keep anyone out. This module opens them, as PDF 32000-1
section 7.6.3 has the standard security handler do, and decrypts their
strings and streams; `pdf/file.f` uses it whenever a trailer names an
`/Encrypt` dictionary.

```forth
REQUIRE pdf/crypt.f
```

`PROVIDED akashic-pdf-crypt`. It depends on `pdf/lexer.f`, `math/md5.f` and
`math/rc4.f`.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `PDF-S-LOCKED` | `( -- 6 )` | A status: the file needs a password, or a method this handler cannot read. |
| `PDF-CRYPT-SIZE` | `( -- 48 )` | An encryption's record. |
| `PDF-CRYPT-SETUP` | `( ea eu ida idu crypt -- status )` | Open the file the `/Encrypt` dictionary `ea eu` describes, with the first `/ID` string `ida idu`. |
| `PDF-CRYPT-STREAMS?` | `( crypt -- flag )` | Whether streams are encrypted. |
| `PDF-CRYPT-STRINGS?` | `( crypt -- flag )` | Whether strings are. |
| `PDF-CRYPT-LOCKED?` | `( crypt -- flag )` | Whether the file could not be opened. |
| `PDF-CRYPT-DATA` | `( a u num gen crypt -- )` | Decrypt `u` bytes at `a` in place with object `num gen`'s key. |
| `PDF-CRYPT-START` | `( num gen crypt rc4 -- )` | Start object `num gen`'s key stream in an RC4 record (`math/rc4.f`), for data decrypted in pieces with `RC4-XOR`. |

## What it opens

`PDF-CRYPT-SETUP` computes the key from the empty password by algorithm 2
(the padding, `/O`, `/P`, the first file ID, and for revision 4 the
`/EncryptMetadata` flag; fifty more rounds of MD5 from revision 3) and checks
it against `/U` by algorithm 4 for revision 2 or algorithm 5 for revisions 3
and 4. It reads:

- revision 2, RC4 with a 40-bit key;
- revision 3, RC4 with a key of `/Length` bits, 40 to 128;
- revision 4, through the crypt filters `/StmF` and `/StrF` name in `/CF`:
  `/V2` is RC4, `/None` and `/Identity` leave data as it is.

The file is locked, and `PDF-CRYPT-SETUP` gives `PDF-S-LOCKED`, when its
empty password is not its user password, when a crypt filter uses AES
(`/AESV2`, `/AESV3`), for revisions 5 and 6, which are AES's, or for a handler
other than `/Standard`. AES waits on part 14's decision between a software
inverse cipher and a CBC mode in MegaPad's engine.

`PDF-CRYPT-DATA` derives the object's key by algorithm 1: MD5 of the file
key, the object's number in three bytes and its generation in two, of which
the first `n + 5` bytes, at most 16, key RC4. RC4 decrypts as it encrypts,
in place. `PDF-CRYPT-START` derives the same key and starts its RC4 stream
in the caller's record instead, so `pdf/file.f` can decrypt a stream a
piece at a time as it reads it.

## In the file layer

`pdf/file.f` sets the encryption up when it opens a file and leaves alone
what is not encrypted: the `/Encrypt` dictionary itself, cross-reference
streams, and the objects inside an object stream, whose stream is decrypted
whole. An object read from the file has each string rewritten as a hex
string of its plain bytes, so every reader of the value sees plain text; a
stream's data is decrypted before its filters. A locked file still opens:
its structure and anything left unencrypted can be read, `PDF-FILE-LOCKED?`
says it is locked, and its encrypted streams give `PDF-S-LOCKED`.

## Cost

Opening costs 51 MD5 sums and twenty RC4 key schedules for revision 3 and
up; each object read with strings, or stream read, costs one MD5 sum and one
RC4 key schedule, and RC4 over its bytes. One call runs at a time.
