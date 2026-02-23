\ dag-cbor.f — DAG-CBOR for AT Protocol / KDOS / Megapad-64
\
\ DAG-CBOR is a restricted CBOR subset used by IPLD and AT Protocol.
\ Key constraints:
\   - Map keys must be text strings, sorted by byte length then
\     lexicographic order (DAG-CBOR canonical ordering).
\   - CID links use tag 42 wrapping a byte string (with 0x00 prefix).
\   - No indefinite-length items.
\   - No floating point.
\
\ REQUIRE cbor.f
\
\ Prefix: DCBOR-   (public API)
\         _DCB-    (internal helpers)
\
\ Load with:   REQUIRE dag-cbor.f

PROVIDED akashic-dag-cbor

\ =====================================================================
\  CID Link Encoding
\ =====================================================================

\ DCBOR-CID ( addr len -- )
\   Encode a CID link as tag(42) + byte string.
\   The CID bytes at addr/len should be the raw CID (typically
\   a multihash).  DAG-CBOR spec requires a 0x00 identity multibase
\   prefix byte before the CID in the byte string.
\
\   Wire format:  D8 2A <bstr-head+1+len> 00 <cid-bytes...>
\
VARIABLE _DCB-CID-LEN

: DCBOR-CID  ( addr len -- )
    DUP 1+ _DCB-CID-LEN !       \ total bstr length = 1 + cid-len
    42 CBOR-TAG                  \ tag 42
    _DCB-CID-LEN @ 2 SWAP _CB-ARG  \ bstr header (major 2, length)
    0 _CB-EMIT                   \ 0x00 identity multibase prefix
    _CB-EMITCPY ;                \ CID bytes

\ =====================================================================
\  Map Key Ordering Validation
\ =====================================================================

\ DAG-CBOR canonical map key ordering (RFC 7049 §3.9 deterministic):
\   1. Shorter keys sort before longer keys.
\   2. Keys of equal length sort lexicographically.
\
\ _DCB-KEYCMP ( a1 l1 a2 l2 -- n )
\   Compare two key strings using DAG-CBOR ordering.
\   Returns: -1 if key1 < key2, 0 if equal, 1 if key1 > key2.

VARIABLE _DCB-A1
VARIABLE _DCB-L1
VARIABLE _DCB-A2
VARIABLE _DCB-L2

: _DCB-KEYCMP  ( a1 l1 a2 l2 -- n )
    _DCB-L2 ! _DCB-A2 ! _DCB-L1 ! _DCB-A1 !
    \ Compare lengths first
    _DCB-L1 @ _DCB-L2 @ < IF -1 EXIT THEN
    _DCB-L1 @ _DCB-L2 @ > IF  1 EXIT THEN
    \ Equal length — lexicographic comparison
    _DCB-L1 @ 0 ?DO
        _DCB-A1 @ I + C@
        _DCB-A2 @ I + C@
        OVER OVER < IF 2DROP -1 UNLOOP EXIT THEN
        >       IF  1 UNLOOP EXIT THEN
    LOOP
    0 ;

\ DCBOR-SORT-MAP ( addr len -- flag )
\   Validate that the next CBOR map in the input has keys in
\   DAG-CBOR canonical order.  Does NOT advance the decoder cursor
\   beyond the map.
\   addr/len = the raw CBOR data to check.
\   Returns -1 if keys are correctly sorted, 0 if not.
\
\   Note: This reads map keys (text strings) from the decode stream.
\   The caller should CBOR-PARSE the data before calling.

VARIABLE _DCB-PREV-A
VARIABLE _DCB-PREV-L
VARIABLE _DCB-CUR-A
VARIABLE _DCB-CUR-L
VARIABLE _DCB-PAIRS
VARIABLE _DCB-OK

: DCBOR-SORT-MAP  ( -- flag )
    -1 _DCB-OK !
    CBOR-NEXT-MAP _DCB-PAIRS !
    _DCB-PAIRS @ 0= IF -1 EXIT THEN   \ empty map = trivially sorted
    \ Read first key
    CBOR-NEXT-TSTR _DCB-PREV-L ! _DCB-PREV-A !
    CBOR-SKIP                          \ skip first value
    _DCB-PAIRS @ 1 ?DO
        CBOR-NEXT-TSTR _DCB-CUR-L ! _DCB-CUR-A !
        CBOR-SKIP                      \ skip value
        _DCB-PREV-A @ _DCB-PREV-L @
        _DCB-CUR-A @  _DCB-CUR-L @
        _DCB-KEYCMP
        DUP 0 > IF DROP 0 _DCB-OK ! LEAVE THEN
        0 = IF 0 _DCB-OK ! LEAVE THEN  \ duplicates not allowed
        \ key was < previous — move current to prev
        _DCB-CUR-A @ _DCB-PREV-A !
        _DCB-CUR-L @ _DCB-PREV-L !
    LOOP
    _DCB-OK @ ;
