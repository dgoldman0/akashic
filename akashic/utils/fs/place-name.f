\ =====================================================================
\  place-name.f - The rule for a place's name
\ =====================================================================
\  A place is named in the registry (places.f) and in the resource form
\  vfs://<place>/<path> (interop/resource.f).  Both apply this one rule,
\  so a name the registry accepts is a name a URI can carry.
\
\  A name is 1 to PLACE-NAME-MAX bytes of lowercase letters, digits,
\  `-`, `.` and `_`, and is neither `.` nor `..`, which a reader could
\  take for path steps.  The limit is one component of a URI and equals
\  ext4's file-name limit, so any such folder name can be a place name.
\ =====================================================================

PROVIDED akashic-place-name

255 CONSTANT PLACE-NAME-MAX

: _PLN-CHAR?  ( c -- flag )
    DUP [CHAR] a >= OVER [CHAR] z <= AND IF DROP -1 EXIT THEN
    DUP [CHAR] 0 >= OVER [CHAR] 9 <= AND IF DROP -1 EXIT THEN
    DUP [CHAR] - = OVER [CHAR] . = OR SWAP [CHAR] _ = OR ;

: PLACE-NAME-VALID?  ( name-a name-u -- flag )
    OVER 0= IF 2DROP 0 EXIT THEN
    DUP 1 < OVER PLACE-NAME-MAX > OR IF 2DROP 0 EXIT THEN
    DUP 2 > 0= IF
        \ `.` and `..` are the only names made of dots alone this short
        OVER C@ [CHAR] . = IF
            DUP 1 = IF 2DROP 0 EXIT THEN
            OVER 1+ C@ [CHAR] . = IF 2DROP 0 EXIT THEN
        THEN
    THEN
    0 ?DO
        DUP I + C@ _PLN-CHAR? 0= IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;
