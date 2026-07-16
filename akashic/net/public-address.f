\ =====================================================================
\  public-address.f - Conservative public IPv4 destination admission
\ =====================================================================
\  The predicate consumes the four network-order bytes used by KDOS. It
\  performs no DNS, routing, transport, or policy mutation and owns no
\  storage. Callers must apply it to the address actually selected for a
\  connection, after resolution and before opening TCP.
\ =====================================================================

PROVIDED akashic-public-address

: _PUBLIC-IPV4@  ( ip-a -- u32 )
    DUP C@ 24 LSHIFT
    OVER 1+ C@ 16 LSHIFT OR
    OVER 2 + C@ 8 LSHIFT OR
    SWAP 3 + C@ OR ;

: _PUBLIC-IPV4-PREFIX?  ( u32 network mask -- flag )
    ROT AND = ;

: PUBLIC-IPV4?  ( ip-a -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    _PUBLIC-IPV4@

    \ 0.0.0.0/8: this network and unspecified forms.
    DUP 0x00000000 0xFF000000 _PUBLIC-IPV4-PREFIX? IF DROP 0 EXIT THEN

    \ RFC 1918 private-use networks.
    DUP 0x0A000000 0xFF000000 _PUBLIC-IPV4-PREFIX? IF DROP 0 EXIT THEN
    DUP 0xAC100000 0xFFF00000 _PUBLIC-IPV4-PREFIX? IF DROP 0 EXIT THEN
    DUP 0xC0A80000 0xFFFF0000 _PUBLIC-IPV4-PREFIX? IF DROP 0 EXIT THEN

    \ Shared address space, loopback, and IPv4 link-local.
    DUP 0x64400000 0xFFC00000 _PUBLIC-IPV4-PREFIX? IF DROP 0 EXIT THEN
    DUP 0x7F000000 0xFF000000 _PUBLIC-IPV4-PREFIX? IF DROP 0 EXIT THEN
    DUP 0xA9FE0000 0xFFFF0000 _PUBLIC-IPV4-PREFIX? IF DROP 0 EXIT THEN

    \ IETF protocol assignments and non-public transition/anycast blocks.
    DUP 0xC0000000 0xFFFFFF00 _PUBLIC-IPV4-PREFIX? IF DROP 0 EXIT THEN
    DUP 0xC0586300 0xFFFFFF00 _PUBLIC-IPV4-PREFIX? IF DROP 0 EXIT THEN
    DUP 0xC0AF3000 0xFFFFFF00 _PUBLIC-IPV4-PREFIX? IF DROP 0 EXIT THEN

    \ Documentation and benchmarking ranges.
    DUP 0xC0000200 0xFFFFFF00 _PUBLIC-IPV4-PREFIX? IF DROP 0 EXIT THEN
    DUP 0xC6120000 0xFFFE0000 _PUBLIC-IPV4-PREFIX? IF DROP 0 EXIT THEN
    DUP 0xC6336400 0xFFFFFF00 _PUBLIC-IPV4-PREFIX? IF DROP 0 EXIT THEN
    DUP 0xCB007100 0xFFFFFF00 _PUBLIC-IPV4-PREFIX? IF DROP 0 EXIT THEN

    \ Multicast and the reserved/class-E space, including limited broadcast.
    DUP 0xE0000000 0xF0000000 _PUBLIC-IPV4-PREFIX? IF DROP 0 EXIT THEN
        0xF0000000 0xF0000000 _PUBLIC-IPV4-PREFIX? IF 0 EXIT THEN

    -1 ;
