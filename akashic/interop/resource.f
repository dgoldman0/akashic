\ =====================================================================
\  resource.f - Common resource URI helpers
\ =====================================================================

PROVIDED akashic-interop-resource

REQUIRE value.f

: IRES-VFS-PATH  ( uri-a uri-u -- path-a path-u flag )
    DUP 4 < IF 2DROP 0 0 0 EXIT THEN
    OVER C@ [CHAR] v =
    2 PICK 1+ C@ [CHAR] f = AND
    2 PICK 2 + C@ [CHAR] s = AND
    2 PICK 3 + C@ [CHAR] : = AND 0= IF
        2DROP 0 0 0 EXIT
    THEN
    4 /STRING -1 ;

VARIABLE _IRV-A
VARIABLE _IRV-U
VARIABLE _IRV-V
VARIABLE _IRV-P

: IRES-VFS!  ( path-a path-u value -- ior )
    _IRV-V ! _IRV-U ! _IRV-A !
    _IRV-U @ 4 + ALLOCATE
    DUP IF SWAP DROP EXIT THEN
    DROP DUP _IRV-P !
    [CHAR] v OVER C! [CHAR] f OVER 1+ C!
    [CHAR] s OVER 2 + C! [CHAR] : OVER 3 + C!
    _IRV-A @ OVER 4 + _IRV-U @ CMOVE DROP
    _IRV-P @ _IRV-U @ 4 + _IRV-V @ CV-RESOURCE!
    _IRV-P @ FREE ;
