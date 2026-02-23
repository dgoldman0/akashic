\ tid.f — TID (Timestamp Identifier) for KDOS / Megapad-64
\
\ AT Protocol TID: 13-character base32-sortable identifier.
\ 64-bit value: bit 63 = 0, bits 62..10 = microseconds since epoch,
\ bits 9..0 = clock ID.
\
\ Base32-sort alphabet: 234567abcdefghijklmnopqrstuvwxyz
\ Each char encodes 5 bits.  13 chars × 5 = 65 bits (bit 64 unused).
\
\ BIOS provides EPOCH@ ( -- epoch-ms-u64 ).
\ We multiply by 1000 for approximate microseconds (ms resolution).
\
\ Prefix: TID-   (public API)
\         _TID-  (internal helpers)
\
\ Load with:   REQUIRE tid.f

PROVIDED akashic-tid

\ =====================================================================
\  Base32-Sort Alphabet
\ =====================================================================

\ "234567abcdefghijklmnopqrstuvwxyz" — 32 chars, index 0..31
CREATE _TID-ALPHA
    50 C,  51 C,  52 C,  53 C,  54 C,  55 C,     \ 2-7
    97 C,  98 C,  99 C, 100 C, 101 C, 102 C,      \ a-f
   103 C, 104 C, 105 C, 106 C, 107 C, 108 C,      \ g-l
   109 C, 110 C, 111 C, 112 C, 113 C, 114 C,      \ m-r
   115 C, 116 C, 117 C, 118 C, 119 C, 120 C,      \ s-x
   121 C, 122 C,                                    \ y-z

\ _TID-ALPHA@ ( 5bit -- char )
: _TID-ALPHA@  ( n -- c )
    31 AND _TID-ALPHA + C@ ;

\ _TID-RVAL ( char -- 5bit | -1 )
\   Reverse lookup: char → 5-bit value.
: _TID-RVAL  ( c -- n )
    DUP 50 >= OVER 55 <= AND IF 50 - EXIT THEN    \ '2'-'7' → 0-5
    DUP 97 >= OVER 122 <= AND IF 91 - EXIT THEN   \ 'a'-'z' → 6-31
    DROP -1 ;

\ =====================================================================
\  TID Encoding
\ =====================================================================

VARIABLE _TID-VAL      \ 64-bit value to encode
VARIABLE _TID-CLK      \ clock ID counter (0-1023)

0 _TID-CLK !

\ TID-NOW ( dst -- )
\   Generate a 13-char TID at dst.
\   Uses EPOCH@ for timestamp (ms → approximate µs).
\   Clock ID increments each call (wraps at 1023).
: TID-NOW  ( dst -- )
    \ Build 64-bit value: (µs << 10) | clock_id, bit 63 = 0
    EPOCH@ 1000 *                \ ms → µs (approximate)
    10 LSHIFT                    \ shift left 10 for clock ID
    _TID-CLK @ OR                \ OR in clock ID
    9223372036854775807 AND      \ clear bit 63
    _TID-VAL !
    \ Increment clock ID (wrap at 1024)
    _TID-CLK @ 1+ 1023 AND _TID-CLK !
    \ Encode 13 chars, most-significant first
    \ 13 × 5 = 65 bits.  We have 64 bits.
    \ char 0 = bits 64..60 (top 5), char 12 = bits 4..0
    13 0 ?DO
        12 I - 5 *              \ bit position for this char
        _TID-VAL @ SWAP RSHIFT
        31 AND
        _TID-ALPHA@
        OVER I + C!
    LOOP DROP ;

\ =====================================================================
\  TID Comparison
\ =====================================================================

\ TID-COMPARE ( tid1 tid2 -- n )
\   Lexicographic comparison of two 13-byte TIDs.
\   Returns: -1 if tid1 < tid2, 0 if equal, 1 if tid1 > tid2.
: TID-COMPARE  ( tid1 tid2 -- n )
    13 0 ?DO
        OVER I + C@
        OVER I + C@
        OVER OVER < IF 2DROP 2DROP -1 UNLOOP EXIT THEN
        >       IF       2DROP  1 UNLOOP EXIT THEN
    LOOP
    2DROP 0 ;
