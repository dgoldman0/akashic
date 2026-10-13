# akashic-pdf-crypt — PDF's standard security handler, with the empty password

Many PDFs are encrypted with an empty user password, to carry permissions
rather than to keep anyone out. This module opens them, as the standard
security handler has it (PDF 32000-1 section 7.6.3, ISO 32000-2 section
7.6.4), and decrypts their strings and streams; `pdf/file.f` uses it whenever
a trailer names an `/Encrypt` dictionary.

```forth
REQUIRE pdf/crypt.f
```

`PROVIDED akashic-pdf-crypt`. It depends on `pdf/lexer.f`, `math/md5.f`,
`math/rc4.f`, `math/aes.f`, `math/sha256.f`, `math/sha512.f` and
`utils/memory-source.f`.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `PDF-S-LOCKED` | `( -- 6 )` | A status: the file needs a password, or a method this handler cannot read. |
| `PDF-CRYPT-SIZE` | `( -- 64 )` | An encryption's record. |
| `PDF-CRYPT-SETUP` | `( ea eu ida idu msrc crypt -- status )` | Open the file the `/Encrypt` dictionary `ea eu` describes, with the first `/ID` string `ida idu`; algorithm 2.B borrows its working bytes from `msrc`. |
| `PDF-CRYPT-STREAMS?` | `( crypt -- flag )` | Whether streams are encrypted. |
| `PDF-CRYPT-STRINGS?` | `( crypt -- flag )` | Whether strings are. |
| `PDF-CRYPT-LOCKED?` | `( crypt -- flag )` | Whether the file could not be opened. |
| `PDF-CRYPT-STRING` | `( a u num gen crypt -- a' u' ok? )` | Decrypt object `num gen`'s string of `u` bytes at `a` in place: the span of its plain bytes. |
| `PDF-CRYPT-STREAM` | `( a u num gen crypt -- a' u' ok? )` | The same for a stream's data. |
| `PDF-CRYPT-READER-SIZE` | `( -- bytes )` | A record that decrypts a stream a piece at a time, eight-byte aligned. |
| `PDF-CRYPT-READER-START` | `( num gen crypt reader -- block )` | Begin object `num gen`'s stream: the pieces' block, 1, or 16 for AES. |
| `PDF-CRYPT-READER-RUN` | `( a u last? reader -- a' u' ok? )` | Decrypt the next piece in place: the span of its plain bytes. |

## What it opens

Revisions 2 to 4 compute the key from the empty password by algorithm 2 (the
padding, `/O`, `/P`, the first file ID, and for revision 4 the
`/EncryptMetadata` flag; fifty more rounds of MD5 from revision 3) and check
it against `/U` by algorithm 4 for revision 2 or algorithm 5 for revisions 3
and 4. Revisions 5 and 6 hash the empty password with `/U`'s 8-byte
validation salt, check the hash against `/U`'s first 32 bytes, then hash it
with the key salt and decrypt `/UE` with that hash, AES-256 in CBC from an
IV of zeros, into the 256-bit file key (algorithm 2.A). Revision 5's hash is
SHA-256; revision 6's is algorithm 2.B. It reads:

- revision 2, RC4 with a 40-bit key;
- revision 3, RC4 with a key of `/Length` bits, 40 to 128;
- revision 4, through the crypt filters `/StmF` and `/StrF` name in `/CF`:
  `/V2` is RC4 and `/AESV2` AES-128, with a key of `/Length` bits, 128 when
  it is absent; `/None` and `/Identity` leave data as it is;
- revisions 5 and 6, whose crypt filters are `/AESV3`, AES-256.

The file is locked, and `PDF-CRYPT-SETUP` gives `PDF-S-LOCKED`, when its
empty password is not its user password, when a crypt filter's method does
not match the version's key, or for a handler other than `/Standard`.

## Algorithm 2.B

Revision 6's hash starts from K, the SHA-256 of the password, the salt and
any user data, and runs rounds: E is the password, K and the user data 64
times, encrypted in place by AES-128 in CBC with K's first 16 bytes the key
and its next 16 the IV; K becomes E's SHA-256, SHA-384 or SHA-512 as E's
first 16 bytes, a big-endian number, are 0, 1 or 2 modulo 3, which the
bytes' sum is too, as 256 is 1 modulo 3. At least 64 rounds run, and then
until E's last byte is at most the number of rounds run less 32; K's first
32 bytes are the hash. With the empty password and no user data, E is K 64
times, at most 4096 bytes, which the handler borrows from the memory source
for the hash and gives back, wiped.

## Decrypting

An object's key is algorithm 1's: MD5 of the file key, the object's number in
three bytes and its generation in two, and for AES-128 the bytes `sAlT`, of
which the first `n + 5` bytes, at most 16, are the key; AES-256 uses the file
key itself. RC4 decrypts as it encrypts, in place, and the plain bytes are
all of them.

AES data is a 16-byte IV, then the ciphertext in CBC, padded to a whole block
(PKCS#5). `PDF-CRYPT-STRING` and `PDF-CRYPT-STREAM` take the IV, decrypt the
whole blocks in place and take the padding off: the plain bytes start 16
bytes in. The last byte says how many bytes pad, 1 to 16, and each of them
must say so too; padding that does not is taken to be data. Data too short
for an IV has no plain bytes, and a part of a block at the end is dropped.
`ok?` is false only when the AES engine refuses.

A reader decrypts a stream a piece at a time, as `pdf/file.f` reads one.
`PDF-CRYPT-READER-START` derives the object's key once and gives the block
its pieces come in. `PDF-CRYPT-READER-RUN` decrypts each piece in place:
RC4's continue its key stream; AES pieces are cut to whole blocks, the first
16 bytes the reader ever runs are the IV, the chain carries on from piece to
piece, and the last piece's padding comes off.

## In the file layer

`pdf/file.f` sets the encryption up when it opens a file and leaves alone
what is not encrypted: the `/Encrypt` dictionary itself, cross-reference
streams, and the objects inside an object stream, whose stream is decrypted
whole. An object read from the file has each string rewritten as a hex
string of its plain bytes, so every reader of the value sees plain text; a
stream's data is decrypted before its filters. A stream read in pieces takes
its IV when it starts, reads whole blocks straight into the caller's buffer,
and holds back the last block, whose padding comes off, and a block a
request smaller than one asks part of. A locked file still opens: its
structure and anything left unencrypted can be read, `PDF-FILE-LOCKED?` says
it is locked, and its encrypted streams give `PDF-S-LOCKED`.

## Cost

Measured in the hosted simulator on qpdf's one-page files, whose AES and SHA
words each count as one step, so these are guest Forth steps, not a device's
cycles: opening takes 1.0 million steps for RC4 of 128 bits, 1.1 million for
AES-128, 0.2 million for revision 5's AES-256 and 6.8 million for revision
6's, whose algorithm 2.B runs twice, at least 64 rounds each. Each object
read with strings, or stream read, costs one MD5 sum for RC4 and AES-128,
and then RC4 over its bytes or one AES engine pass over its blocks. One call
runs at a time.
