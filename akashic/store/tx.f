\ =================================================================
\  tx.f  —  Blockchain Transaction Structure
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: TX-  / _TX-
\  Depends on: ed25519.f sphincs-plus.f sha3.f cbor.f
\
\  Transaction structure with hybrid Ed25519 + SPHINCS+ signatures.
\  CBOR-encoded, SHA3-256 hashed, suitable for inclusion in blocks.
\
\  Public API:
\   TX-INIT          ( tx -- )               zero a transaction buffer
\   TX-SET-FROM      ( pubkey tx -- )         set sender Ed25519 key
\   TX-SET-FROM-PQ   ( pq-pubkey tx -- )      set sender SPHINCS+ key
\   TX-SET-TO        ( pubkey tx -- )          set recipient Ed25519 key
\   TX-SET-AMOUNT    ( amount tx -- )          set transfer amount
\   TX-SET-NONCE     ( nonce tx -- )           set sequence number
\   TX-SET-CHAIN-ID  ( chain-id tx -- )        set chain identifier
\   TX-SET-FEE       ( fee tx -- )             set transaction fee
\   TX-SET-VALID-UNTIL ( slot tx -- )          set expiry slot
\   TX-SET-DATA      ( addr len tx -- )        set optional payload
\   TX-HASH          ( tx hash -- )            SHA3-256 of unsigned fields
\   TX-SIGN          ( tx ed-priv ed-pub -- )  sign with Ed25519
\   TX-SIGN-PQ       ( tx spx-sec -- )         sign with SPHINCS+
\   TX-SIGN-HYBRID   ( tx ed-priv ed-pub spx-sec -- ) sign with both
\   TX-VERIFY        ( tx -- flag )            verify signature(s)
\   TX-ENCODE        ( tx buf max -- len )     serialize to CBOR
\   TX-DECODE        ( buf len tx -- flag )    deserialize from CBOR
\   TX-VALID?        ( tx -- flag )            structural validity check
\   TX-HASH=         ( tx1 tx2 -- flag )       compare tx hashes
\   TX-CHAIN-ID@     ( tx -- chain-id )        read chain identifier
\   TX-FEE@          ( tx -- fee )             read transaction fee
\   TX-VALID-UNTIL@  ( tx -- slot )            read expiry slot
\
\  Constants:
\   TX-BUF-SIZE      ( -- 8320 )    buffer size per transaction
\   TX-SIG-ED25519   ( -- 0 )       sig mode: Ed25519 only
\   TX-SIG-SPHINCS   ( -- 1 )       sig mode: SPHINCS+ only
\   TX-SIG-HYBRID    ( -- 2 )       sig mode: both
\   TX-MAX-DATA      ( -- 256 )     max data payload bytes
\
\  Not reentrant.
\ =================================================================

REQUIRE ed25519.f
REQUIRE sphincs-plus.f
REQUIRE sha3.f
REQUIRE cbor.f
REQUIRE fmt.f

PROVIDED akashic-tx

\ =====================================================================
\  1. Constants
\ =====================================================================

8320 CONSTANT TX-BUF-SIZE

\ Signature modes
0 CONSTANT TX-SIG-ED25519
1 CONSTANT TX-SIG-SPHINCS
2 CONSTANT TX-SIG-HYBRID

256 CONSTANT TX-MAX-DATA

\ Transaction types (encoded in data[0]; data_len=0 ⇒ transfer)
3 CONSTANT TX-STAKE           \ move balance → staked-amount
4 CONSTANT TX-UNSTAKE         \ initiate unstaking (lock period)

\ =====================================================================
\  2. Transaction Buffer Layout
\ =====================================================================
\
\  Offset  Size    Field
\  ------  ------  -----
\    0     32      from       (sender Ed25519 public key)
\   32     32      from_pq   (sender SPHINCS+ public key, optional)
\   64     32      to         (recipient public key)
\   96      8      amount     (u64 transfer value)
\  104      8      nonce      (u64 sender sequence number)
\  112      8      chain_id   (u64 chain identifier — A03)
\  120      8      fee        (u64 transaction fee — C05)
\  128      8      valid_until (u64 TTL block height — C06)
\  136      2      data_len   (u16 payload length, 0..256)
\  138    256      data       (optional payload bytes)
\  394     64      sig        (Ed25519 signature)
\  458   7856      sig_pq     (SPHINCS+ signature)
\ 8314      1      sig_mode   (0=Ed25519, 1=SPHINCS+, 2=hybrid)
\ 8315      1      _flags     (internal: bit 0 = signed, bit 1 = PQ-signed)
\ 8316      4      _pad       (alignment padding)
\ ------
\ 8320 total (8-byte aligned)
\

0    CONSTANT _TX-OFF-FROM
32   CONSTANT _TX-OFF-FROM-PQ
64   CONSTANT _TX-OFF-TO
96   CONSTANT _TX-OFF-AMOUNT
104  CONSTANT _TX-OFF-NONCE
112  CONSTANT _TX-OFF-CHAIN-ID
120  CONSTANT _TX-OFF-FEE
128  CONSTANT _TX-OFF-VALID-UNTIL
136  CONSTANT _TX-OFF-DLEN
138  CONSTANT _TX-OFF-DATA
394  CONSTANT _TX-OFF-SIG
458  CONSTANT _TX-OFF-SIG-PQ
8314 CONSTANT _TX-OFF-SIG-MODE
8315 CONSTANT _TX-OFF-FLAGS

\ Internal flag bits
1 CONSTANT _TX-FL-SIGNED      \ Ed25519 signature present
2 CONSTANT _TX-FL-PQ-SIGNED   \ SPHINCS+ signature present

\ 16-bit store/fetch helpers (KDOS has no W! / W@)
: _TX-W!  ( n addr -- )  OVER 255 AND OVER C!  SWAP 8 RSHIFT SWAP 1+ C! ;
: _TX-W@  ( addr -- n )  DUP C@ SWAP 1+ C@ 8 LSHIFT OR ;

\ =====================================================================
\  3. Scratch buffers
\ =====================================================================

\ CBOR encoding scratch (16 KB — more than enough for hybrid tx)
CREATE _TX-CBUF  16384 ALLOT
16384 CONSTANT _TX-CBUF-SZ

\ SHA3-256 hash scratch
CREATE _TX-HASH-TMP  32 ALLOT

\ =====================================================================
\  4. Buffer accessors (internal)
\ =====================================================================

: _TX-FROM      ( tx -- addr )  _TX-OFF-FROM + ;
: _TX-FROM-PQ   ( tx -- addr )  _TX-OFF-FROM-PQ + ;
: _TX-TO        ( tx -- addr )  _TX-OFF-TO + ;
: _TX-AMOUNT    ( tx -- addr )  _TX-OFF-AMOUNT + ;
: _TX-NONCE     ( tx -- addr )  _TX-OFF-NONCE + ;
: _TX-CHAIN-ID  ( tx -- addr )  _TX-OFF-CHAIN-ID + ;
: _TX-FEE       ( tx -- addr )  _TX-OFF-FEE + ;
: _TX-VALID-UNT ( tx -- addr )  _TX-OFF-VALID-UNTIL + ;
: _TX-DLEN      ( tx -- addr )  _TX-OFF-DLEN + ;
: _TX-DATA      ( tx -- addr )  _TX-OFF-DATA + ;
: _TX-SIG       ( tx -- addr )  _TX-OFF-SIG + ;
: _TX-SIG-PQ    ( tx -- addr )  _TX-OFF-SIG-PQ + ;
: _TX-SIG-MODE  ( tx -- addr )  _TX-OFF-SIG-MODE + ;
: _TX-FLAGS     ( tx -- addr )  _TX-OFF-FLAGS + ;

\ =====================================================================
\  5. TX-INIT — zero a transaction buffer
\ =====================================================================

: TX-INIT  ( tx -- )
    TX-BUF-SIZE 0 FILL ;

\ =====================================================================
\  6. Setters
\ =====================================================================

: TX-SET-FROM  ( pubkey tx -- )
    _TX-FROM  ED25519-KEY-LEN CMOVE ;

: TX-SET-FROM-PQ  ( pq-pubkey tx -- )
    _TX-FROM-PQ  SPX-PK-LEN CMOVE ;

: TX-SET-TO  ( pubkey tx -- )
    _TX-TO  ED25519-KEY-LEN CMOVE ;

\ ── P10: reject negative amounts; zero is allowed (Phase 7 contracts) ──
: TX-SET-AMOUNT  ( amount tx -- )
    OVER 0< IF 2DROP EXIT THEN
    _TX-AMOUNT ! ;

: TX-SET-NONCE  ( nonce tx -- )
    _TX-NONCE ! ;

: TX-SET-CHAIN-ID  ( id tx -- )
    _TX-CHAIN-ID ! ;

: TX-SET-FEE  ( fee tx -- )
    OVER 0< IF 2DROP EXIT THEN
    _TX-FEE ! ;

: TX-SET-VALID-UNTIL  ( block# tx -- )
    _TX-VALID-UNT ! ;

VARIABLE _TX-SD-LEN
VARIABLE _TX-SD-TX

: TX-SET-DATA  ( addr len tx -- )
    _TX-SD-TX !                                \ save tx
    DUP TX-MAX-DATA > IF 2DROP EXIT THEN       \ reject if too long
    _TX-SD-LEN !                               \ save len; ( addr )
    _TX-SD-TX @ _TX-DATA                       \ ( addr data_addr )
    _TX-SD-LEN @ CMOVE                         \ copy payload
    _TX-SD-LEN @ _TX-SD-TX @ _TX-DLEN _TX-W! ; \ store 16-bit length

\ =====================================================================
\  7. Getters (convenience)
\ =====================================================================

: TX-FROM@      ( tx -- addr )   _TX-FROM ;
: TX-FROM-PQ@   ( tx -- addr )   _TX-FROM-PQ ;
: TX-TO@        ( tx -- addr )   _TX-TO ;
: TX-AMOUNT@    ( tx -- n )      _TX-AMOUNT @ ;
: TX-NONCE@     ( tx -- n )      _TX-NONCE @ ;
: TX-CHAIN-ID@  ( tx -- n )      _TX-CHAIN-ID @ ;
: TX-FEE@       ( tx -- n )      _TX-FEE @ ;
: TX-VALID-UNTIL@ ( tx -- n )    _TX-VALID-UNT @ ;
: TX-DATA-LEN@  ( tx -- n )     _TX-DLEN _TX-W@ ;
: TX-DATA@      ( tx -- addr )   _TX-DATA ;
: TX-SIG-MODE@  ( tx -- n )     _TX-SIG-MODE C@ ;

\ =====================================================================
\  8. CBOR key string constants (DAG-CBOR canonical order: by length
\     then lexicographic).
\
\     Sorted keys:  "to" < "fee" < "sig" < "data" < "from" < "nonce" <
\                   "amount" < "sig_pq" < "from_pq" < "chain_id" <
\                   "sig_mode" < "valid_until"
\
\     For the unsigned hash we use 9 keys (to, fee, data, from,
\     nonce, amount, from_pq, chain_id, valid_until).
\     For encoded form we use all 12 (incl sig, sig_pq, sig_mode).
\
\     We store keys as counted strings in CREATE/ALLOT buffers since
\     S" inside : definitions is transient in some Forth systems.
\ =====================================================================

: _TX-KEY  ( "name" len -- )  CREATE DUP C, 0 ?DO KEY C, LOOP ;

\ Manually create key strings as byte sequences
CREATE _TXK-TO       2 C, 116 C, 111 C,                           \ "to"
CREATE _TXK-FEE      3 C, 102 C, 101 C, 101 C,                    \ "fee"
CREATE _TXK-SIG      3 C, 115 C, 105 C, 103 C,                    \ "sig"
CREATE _TXK-DATA     4 C, 100 C,  97 C, 116 C,  97 C,            \ "data"
CREATE _TXK-FROM     4 C, 102 C, 114 C, 111 C, 109 C,            \ "from"
CREATE _TXK-NONCE    5 C, 110 C, 111 C, 110 C,  99 C, 101 C,     \ "nonce"
CREATE _TXK-AMOUNT   6 C,  97 C, 109 C, 111 C, 117 C, 110 C, 116 C, \ "amount"
CREATE _TXK-SIGPQ    6 C, 115 C, 105 C, 103 C,  95 C, 112 C, 113 C,  \ "sig_pq"
CREATE _TXK-FROMPQ   7 C, 102 C, 114 C, 111 C, 109 C,  95 C, 112 C, 113 C, \ "from_pq"
CREATE _TXK-CHAINID  8 C,  99 C, 104 C,  97 C, 105 C, 110 C,  95 C, 105 C, 100 C, \ "chain_id"
CREATE _TXK-SIGMODE  8 C, 115 C, 105 C, 103 C,  95 C, 109 C, 111 C, 100 C, 101 C, \ "sig_mode"
CREATE _TXK-VU      11 C, 118 C,  97 C, 108 C, 105 C, 100 C,  95 C, 117 C, 110 C, 116 C, 105 C, 108 C, \ "valid_until"

\ Helper: push counted string as ( addr len )
: _TXK>  ( cstr -- addr len )  DUP 1+ SWAP C@ ;

\ =====================================================================
\  9. _TX-ENCODE-UNSIGNED — encode hash-relevant fields to CBOR
\     (excludes sig, sig_pq, sig_mode)
\
\     Keys in DAG-CBOR canonical order (shorter first, then lex):
\       "to"  "fee"  "data"  "from"  "nonce"  "amount"  "from_pq"
\       "chain_id"  "valid_until"
\ =====================================================================

VARIABLE _TX-ENC-TX

: _TX-ENCODE-UNSIGNED  ( tx buf max -- len )
    CBOR-RESET
    _TX-ENC-TX !                         \ save tx* in variable

    9 CBOR-MAP                           \ 9-entry map

    \ Key: "to" (2 bytes)
    _TXK-TO _TXK>  CBOR-TSTR
    _TX-ENC-TX @ _TX-TO  ED25519-KEY-LEN  CBOR-BSTR

    \ Key: "fee" (3 bytes)
    _TXK-FEE _TXK> CBOR-TSTR
    _TX-ENC-TX @ TX-FEE@  CBOR-UINT

    \ Key: "data" (4 bytes)
    _TXK-DATA _TXK> CBOR-TSTR
    _TX-ENC-TX @ _TX-DATA
    _TX-ENC-TX @ TX-DATA-LEN@  CBOR-BSTR

    \ Key: "from" (4 bytes)
    _TXK-FROM _TXK> CBOR-TSTR
    _TX-ENC-TX @ _TX-FROM  ED25519-KEY-LEN  CBOR-BSTR

    \ Key: "nonce" (5 bytes)
    _TXK-NONCE _TXK> CBOR-TSTR
    _TX-ENC-TX @ TX-NONCE@  CBOR-UINT

    \ Key: "amount" (6 bytes)
    _TXK-AMOUNT _TXK> CBOR-TSTR
    _TX-ENC-TX @ TX-AMOUNT@  CBOR-UINT

    \ Key: "from_pq" (7 bytes)
    _TXK-FROMPQ _TXK> CBOR-TSTR
    _TX-ENC-TX @ _TX-FROM-PQ  SPX-PK-LEN  CBOR-BSTR

    \ Key: "chain_id" (8 bytes)
    _TXK-CHAINID _TXK> CBOR-TSTR
    _TX-ENC-TX @ TX-CHAIN-ID@  CBOR-UINT

    \ Key: "valid_until" (11 bytes)
    _TXK-VU _TXK> CBOR-TSTR
    _TX-ENC-TX @ TX-VALID-UNTIL@  CBOR-UINT

    \ ── P11: check CBOR overflow ──
    CBOR-OK? 0= IF 0 EXIT THEN
    CBOR-RESULT NIP ;                    \ -- len

\ =====================================================================
\  10. TX-HASH — SHA3-256 of unsigned CBOR encoding
\ =====================================================================

: TX-HASH  ( tx hash -- )
    SWAP
    _TX-CBUF _TX-CBUF-SZ _TX-ENCODE-UNSIGNED   \ -- hash len
    _TX-CBUF SWAP                               \ -- hash cbuf len
    ROT SHA3-256-HASH ;                         \ SHA3-256(cbuf, len) -> hash

\ =====================================================================
\  11. TX-SIGN — Ed25519 signing
\ =====================================================================

VARIABLE _TX-SIGN-TX
VARIABLE _TX-SIGN-PRIV
VARIABLE _TX-SIGN-PUB

: TX-SIGN  ( tx ed-priv ed-pub -- )
    _TX-SIGN-PUB !
    _TX-SIGN-PRIV !
    _TX-SIGN-TX !

    \ Hash the unsigned transaction
    _TX-SIGN-TX @ _TX-HASH-TMP TX-HASH

    \ Sign the 32-byte hash
    _TX-HASH-TMP 32
    _TX-SIGN-PRIV @
    _TX-SIGN-PUB @
    _TX-SIGN-TX @ _TX-SIG
    ED25519-SIGN

    \ Set sig_mode based on current state
    _TX-SIGN-TX @ _TX-FLAGS DUP C@
    _TX-FL-SIGNED OR  SWAP C!             \ mark Ed25519 signed

    \ If PQ already signed -> hybrid, else Ed25519-only
    _TX-SIGN-TX @ _TX-FLAGS C@
    _TX-FL-PQ-SIGNED AND IF
        TX-SIG-HYBRID
    ELSE
        TX-SIG-ED25519
    THEN
    _TX-SIGN-TX @ _TX-SIG-MODE C! ;

\ =====================================================================
\  12. TX-SIGN-PQ — SPHINCS+ signing
\ =====================================================================

VARIABLE _TX-SIGNPQ-TX
VARIABLE _TX-SIGNPQ-SEC

: TX-SIGN-PQ  ( tx spx-sec -- )
    _TX-SIGNPQ-SEC !
    _TX-SIGNPQ-TX !

    \ Hash the unsigned transaction
    _TX-SIGNPQ-TX @ _TX-HASH-TMP TX-HASH

    \ Sign the 32-byte hash with SPHINCS+
    _TX-HASH-TMP 32
    _TX-SIGNPQ-SEC @
    _TX-SIGNPQ-TX @ _TX-SIG-PQ
    SPX-SIGN

    \ Update flags
    _TX-SIGNPQ-TX @ _TX-FLAGS DUP C@
    _TX-FL-PQ-SIGNED OR  SWAP C!

    \ If Ed25519 already signed -> hybrid, else SPHINCS+-only
    _TX-SIGNPQ-TX @ _TX-FLAGS C@
    _TX-FL-SIGNED AND IF
        TX-SIG-HYBRID
    ELSE
        TX-SIG-SPHINCS
    THEN
    _TX-SIGNPQ-TX @ _TX-SIG-MODE C! ;

\ =====================================================================
\  13. TX-SIGN-HYBRID — both signatures in one call
\ =====================================================================

VARIABLE _TX-SH-TX
VARIABLE _TX-SH-EPRIV
VARIABLE _TX-SH-EPUB
VARIABLE _TX-SH-SSEC

: TX-SIGN-HYBRID  ( tx ed-priv ed-pub spx-sec -- )
    _TX-SH-SSEC !
    _TX-SH-EPUB !
    _TX-SH-EPRIV !
    _TX-SH-TX !
    _TX-SH-TX @ _TX-SH-EPRIV @ _TX-SH-EPUB @ TX-SIGN
    _TX-SH-TX @ _TX-SH-SSEC @ TX-SIGN-PQ ;

\ =====================================================================
\  14. TX-VERIFY — verify signature(s) per sig_mode
\ =====================================================================

VARIABLE _TX-VER-TX
VARIABLE _TX-HYB-TX

\ _TX-VERIFY-ED ( tx -- flag )  verify Ed25519 signature
: _TX-VERIFY-ED  ( tx -- flag )
    _TX-VER-TX !
    _TX-VER-TX @ _TX-HASH-TMP TX-HASH
    _TX-HASH-TMP 32
    _TX-VER-TX @ _TX-FROM
    _TX-VER-TX @ _TX-SIG
    ED25519-VERIFY ;

\ _TX-VERIFY-PQ ( tx -- flag )  verify SPHINCS+ signature
: _TX-VERIFY-PQ  ( tx -- flag )
    _TX-VER-TX !
    _TX-VER-TX @ _TX-HASH-TMP TX-HASH
    _TX-HASH-TMP 32
    _TX-VER-TX @ _TX-FROM-PQ
    _TX-VER-TX @ _TX-SIG-PQ SPX-SIG-LEN
    SPX-VERIFY ;

: TX-VERIFY  ( tx -- flag )
    DUP _TX-SIG-MODE C@
    DUP TX-SIG-ED25519 = IF
        DROP _TX-VERIFY-ED EXIT
    THEN
    DUP TX-SIG-SPHINCS = IF
        DROP _TX-VERIFY-PQ EXIT
    THEN
    TX-SIG-HYBRID = IF
        \ ── P09: Hybrid mode requires BOTH signatures valid ──
        DUP _TX-HYB-TX !              \ save tx (stack survives CATCH)
        _TX-VERIFY-ED 0= IF 0 EXIT THEN
        _TX-HYB-TX @ _TX-VERIFY-PQ EXIT
    THEN
    \ Unknown sig_mode — reject
    DROP 0 ;

\ =====================================================================
\  15. TX-VALID? — structural validity (no crypto, just format)
\ =====================================================================

: TX-VALID?  ( tx -- flag )
    DUP TX-DATA-LEN@ TX-MAX-DATA > IF DROP 0 EXIT THEN
    DUP _TX-SIG-MODE C@ DUP TX-SIG-ED25519 <
    SWAP TX-SIG-HYBRID > OR IF DROP 0 EXIT THEN
    \ Check from key is not all-zero (must have a sender)
    DUP _TX-FROM 32 0                     \ tx addr 32 0
    SWAP 0 ?DO                            \ tx addr
        OVER I + C@ OR
    LOOP
    NIP                                    \ tx or-result
    0= IF DROP 0 EXIT THEN               \ all zeroes -> invalid
    \ Check to key is not all-zero
    DUP _TX-TO 32 0
    SWAP 0 ?DO
        OVER I + C@ OR
    LOOP
    NIP
    0= IF DROP 0 EXIT THEN
    DROP -1 ;

\ =====================================================================
\  16. TX-ENCODE — full CBOR serialization (including sigs)
\ =====================================================================

VARIABLE _TX-E-TX

: TX-ENCODE  ( tx buf max -- len )
    CBOR-RESET
    _TX-E-TX !                           \ save tx (buf/max already in CBOR state)

    \ Determine number of map entries based on sig_mode
    \ Base: to, fee, data, from, nonce, amount, from_pq, chain_id, sig_mode,
    \       valid_until = 10
    \ + sig if Ed25519 or hybrid
    \ + sig_pq if SPHINCS+ or hybrid

    \ Count map entries based on sig_mode
    _TX-E-TX @ _TX-SIG-MODE C@
    DUP TX-SIG-ED25519 = IF
        DROP 11 CBOR-MAP                 \ base + sig
    ELSE DUP TX-SIG-SPHINCS = IF
        DROP 11 CBOR-MAP                 \ base + sig_pq
    ELSE TX-SIG-HYBRID = IF
        12 CBOR-MAP                      \ base + sig + sig_pq
    ELSE
        10 CBOR-MAP                      \ base only (unsigned)
    THEN THEN THEN

    \ Keys in DAG-CBOR canonical order:
    \   "to"(2) "fee"(3) "sig"(3) "data"(4) "from"(4) "nonce"(5)
    \   "amount"(6) "sig_pq"(6) "from_pq"(7) "chain_id"(8)
    \   "sig_mode"(8) "valid_until"(11)

    \ 1. "to" (2 bytes)
    _TXK-TO _TXK>  CBOR-TSTR
    _TX-E-TX @ _TX-TO  ED25519-KEY-LEN  CBOR-BSTR

    \ 2. "fee" (3 bytes)
    _TXK-FEE _TXK> CBOR-TSTR
    _TX-E-TX @ TX-FEE@  CBOR-UINT

    \ 3. "sig" (3 bytes) — present if Ed25519 or hybrid
    _TX-E-TX @ _TX-SIG-MODE C@
    DUP TX-SIG-ED25519 = SWAP TX-SIG-HYBRID = OR IF
        _TXK-SIG _TXK> CBOR-TSTR
        _TX-E-TX @ _TX-SIG  ED25519-SIG-LEN  CBOR-BSTR
    THEN

    \ 4. "data" (4 bytes)
    _TXK-DATA _TXK> CBOR-TSTR
    _TX-E-TX @ _TX-DATA
    _TX-E-TX @ TX-DATA-LEN@  CBOR-BSTR

    \ 5. "from" (4 bytes)
    _TXK-FROM _TXK> CBOR-TSTR
    _TX-E-TX @ _TX-FROM  ED25519-KEY-LEN  CBOR-BSTR

    \ 6. "nonce" (5 bytes)
    _TXK-NONCE _TXK> CBOR-TSTR
    _TX-E-TX @ TX-NONCE@  CBOR-UINT

    \ 7. "amount" (6 bytes)
    _TXK-AMOUNT _TXK> CBOR-TSTR
    _TX-E-TX @ TX-AMOUNT@  CBOR-UINT

    \ 8. "sig_pq" (6 bytes) — present if SPHINCS+ or hybrid
    _TX-E-TX @ _TX-SIG-MODE C@
    DUP TX-SIG-SPHINCS = SWAP TX-SIG-HYBRID = OR IF
        _TXK-SIGPQ _TXK> CBOR-TSTR
        _TX-E-TX @ _TX-SIG-PQ  SPX-SIG-LEN  CBOR-BSTR
    THEN

    \ 9. "from_pq" (7 bytes)
    _TXK-FROMPQ _TXK> CBOR-TSTR
    _TX-E-TX @ _TX-FROM-PQ  SPX-PK-LEN  CBOR-BSTR

    \ 10. "chain_id" (8 bytes)
    _TXK-CHAINID _TXK> CBOR-TSTR
    _TX-E-TX @ TX-CHAIN-ID@  CBOR-UINT

    \ 11. "sig_mode" (8 bytes)
    _TXK-SIGMODE _TXK> CBOR-TSTR
    _TX-E-TX @ _TX-SIG-MODE C@  CBOR-UINT

    \ 12. "valid_until" (11 bytes)
    _TXK-VU _TXK> CBOR-TSTR
    _TX-E-TX @ TX-VALID-UNTIL@  CBOR-UINT

    CBOR-RESULT NIP ;                    \ -- len

\ =====================================================================
\  17. TX-DECODE — deserialize from CBOR
\ =====================================================================
\
\  Parse a CBOR map and populate a transaction buffer.
\  Returns -1 (TRUE) on success, 0 (FALSE) on parse error.
\  Strategy: iterate map keys, match against known strings,
\  populate the corresponding tx field.

VARIABLE _TX-D-TX
VARIABLE _TX-D-PAIRS
VARIABLE _TX-D-I
VARIABLE _TX-D-KA
VARIABLE _TX-D-KL
VARIABLE _TX-D-VA
VARIABLE _TX-D-VL

\ Helper: compare two byte sequences ( a1 l1 a2 l2 -- flag )
: _TX-STREQ  ( a1 l1 a2 l2 -- flag )
    ROT OVER <> IF 2DROP DROP 0 EXIT THEN
    \ lengths match; compare bytes
    0 ?DO
        OVER I + C@  OVER I + C@
        <> IF 2DROP 0 UNLOOP EXIT THEN
    LOOP
    2DROP -1 ;

: TX-DECODE  ( buf len tx -- flag )
    _TX-D-TX !
    _TX-D-TX @ TX-INIT

    CBOR-PARSE DROP
    CBOR-TYPE 5 <> IF 0 EXIT THEN       \ must be a map
    CBOR-NEXT-MAP _TX-D-PAIRS !

    _TX-D-PAIRS @ 0 ?DO
        \ Read key (must be text string)
        CBOR-TYPE 3 <> IF 0 UNLOOP EXIT THEN
        CBOR-NEXT-TSTR _TX-D-KL ! _TX-D-KA !

        \ Match key and read value
        _TX-D-KA @ _TX-D-KL @
        _TXK-TO _TXK> _TX-STREQ IF
            CBOR-NEXT-BSTR _TX-D-VL ! _TX-D-VA !
            _TX-D-VL @ ED25519-KEY-LEN <> IF 0 UNLOOP EXIT THEN
            _TX-D-VA @ _TX-D-TX @ _TX-TO ED25519-KEY-LEN CMOVE
        ELSE _TX-D-KA @ _TX-D-KL @
        _TXK-FROM _TXK> _TX-STREQ IF
            CBOR-NEXT-BSTR _TX-D-VL ! _TX-D-VA !
            _TX-D-VL @ ED25519-KEY-LEN <> IF 0 UNLOOP EXIT THEN
            _TX-D-VA @ _TX-D-TX @ _TX-FROM ED25519-KEY-LEN CMOVE
        ELSE _TX-D-KA @ _TX-D-KL @
        _TXK-FROMPQ _TXK> _TX-STREQ IF
            CBOR-NEXT-BSTR _TX-D-VL ! _TX-D-VA !
            _TX-D-VL @ SPX-PK-LEN <> IF 0 UNLOOP EXIT THEN
            _TX-D-VA @ _TX-D-TX @ _TX-FROM-PQ SPX-PK-LEN CMOVE
        ELSE _TX-D-KA @ _TX-D-KL @
        _TXK-AMOUNT _TXK> _TX-STREQ IF
            CBOR-NEXT-UINT _TX-D-TX @ _TX-AMOUNT !
        ELSE _TX-D-KA @ _TX-D-KL @
        _TXK-NONCE _TXK> _TX-STREQ IF
            CBOR-NEXT-UINT _TX-D-TX @ _TX-NONCE !
        ELSE _TX-D-KA @ _TX-D-KL @
        _TXK-DATA _TXK> _TX-STREQ IF
            CBOR-NEXT-BSTR _TX-D-VL ! _TX-D-VA !
            _TX-D-VL @ TX-MAX-DATA > IF 0 UNLOOP EXIT THEN
            _TX-D-VA @ _TX-D-TX @ _TX-DATA _TX-D-VL @ CMOVE
            _TX-D-VL @ _TX-D-TX @ _TX-DLEN _TX-W!
        ELSE _TX-D-KA @ _TX-D-KL @
        _TXK-SIG _TXK> _TX-STREQ IF
            CBOR-NEXT-BSTR _TX-D-VL ! _TX-D-VA !
            _TX-D-VL @ ED25519-SIG-LEN <> IF 0 UNLOOP EXIT THEN
            _TX-D-VA @ _TX-D-TX @ _TX-SIG ED25519-SIG-LEN CMOVE
            _TX-D-TX @ _TX-FLAGS DUP C@ _TX-FL-SIGNED OR SWAP C!
        ELSE _TX-D-KA @ _TX-D-KL @
        _TXK-SIGMODE _TXK> _TX-STREQ IF
            CBOR-NEXT-UINT _TX-D-TX @ _TX-SIG-MODE C!
        ELSE _TX-D-KA @ _TX-D-KL @
        _TXK-SIGPQ _TXK> _TX-STREQ IF
            CBOR-NEXT-BSTR _TX-D-VL ! _TX-D-VA !
            _TX-D-VL @ SPX-SIG-LEN <> IF 0 UNLOOP EXIT THEN
            _TX-D-VA @ _TX-D-TX @ _TX-SIG-PQ SPX-SIG-LEN CMOVE
            _TX-D-TX @ _TX-FLAGS DUP C@ _TX-FL-PQ-SIGNED OR SWAP C!
        ELSE _TX-D-KA @ _TX-D-KL @
        _TXK-CHAINID _TXK> _TX-STREQ IF
            CBOR-NEXT-UINT _TX-D-TX @ _TX-CHAIN-ID !
        ELSE _TX-D-KA @ _TX-D-KL @
        _TXK-FEE _TXK> _TX-STREQ IF
            CBOR-NEXT-UINT _TX-D-TX @ _TX-FEE !
        ELSE _TX-D-KA @ _TX-D-KL @
        _TXK-VU _TXK> _TX-STREQ IF
            CBOR-NEXT-UINT _TX-D-TX @ _TX-VALID-UNT !
        ELSE
            \ Unknown key — skip the value
            CBOR-SKIP
        THEN THEN THEN THEN THEN THEN THEN THEN THEN THEN THEN THEN
    LOOP

    -1 ;                                 \ success

\ =====================================================================
\  18. TX-HASH= — compare two transaction hashes
\ =====================================================================

CREATE _TX-H1  32 ALLOT
CREATE _TX-H2  32 ALLOT

: TX-HASH=  ( tx1 tx2 -- flag )
    _TX-H2 TX-HASH
    _TX-H1 TX-HASH
    _TX-H1 _TX-H2 SHA3-256-COMPARE ;

\ =====================================================================
\  19. TX-PRINT — debug display (optional)
\ =====================================================================

\ Private hex-byte emitter removed — uses FMT-.HEX from utils/fmt.f

: TX-PRINT  ( tx -- )
    DUP ." TX{ from=" _TX-FROM 8 FMT-.HEX ." .."
    DUP ."  to=" _TX-TO 8 FMT-.HEX ." .."
    DUP ."  amt=" TX-AMOUNT@ .
    DUP ."  n=" TX-NONCE@ .
    DUP ."  dlen=" TX-DATA-LEN@ .
        ."  mode=" _TX-SIG-MODE C@ . ." }" CR ;

\ =====================================================================
\  20. Concurrency guard
\ =====================================================================

REQUIRE ../concurrency/guard.f
GUARD _tx-guard

' TX-HASH           CONSTANT _tx-hash-xt
' TX-SIGN           CONSTANT _tx-sign-xt
' TX-SIGN-PQ        CONSTANT _tx-sign-pq-xt
' TX-SIGN-HYBRID    CONSTANT _tx-sign-hybrid-xt
' TX-VERIFY         CONSTANT _tx-verify-xt
' TX-ENCODE         CONSTANT _tx-encode-xt
' TX-DECODE         CONSTANT _tx-decode-xt
' TX-HASH=          CONSTANT _tx-hasheq-xt

: TX-HASH           _tx-hash-xt        _tx-guard WITH-GUARD ;
: TX-SIGN           _tx-sign-xt        _tx-guard WITH-GUARD ;
: TX-SIGN-PQ        _tx-sign-pq-xt     _tx-guard WITH-GUARD ;
: TX-SIGN-HYBRID    _tx-sign-hybrid-xt _tx-guard WITH-GUARD ;
: TX-VERIFY         _tx-verify-xt      _tx-guard WITH-GUARD ;
: TX-ENCODE         _tx-encode-xt      _tx-guard WITH-GUARD ;
: TX-DECODE         _tx-decode-xt      _tx-guard WITH-GUARD ;
: TX-HASH=          _tx-hasheq-xt      _tx-guard WITH-GUARD ;

\ =====================================================================
\  Done.
\ =====================================================================
