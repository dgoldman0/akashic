\ =====================================================================
\  identity.f - Fixed-size durable identities and commitments
\ =====================================================================
\  RID values are opaque 32-byte byte strings.  This module does not
\  prescribe how they are generated or verified and therefore has no
\  dependency on a particular hash, signature, store, or UI layer.
\ =====================================================================

PROVIDED akashic-runtime-identity

32 CONSTANT RID-SIZE

: RID-CLEAR  ( id -- )
    RID-SIZE 0 FILL ;

: RID-COPY  ( source destination -- )
    2DUP = IF 2DROP EXIT THEN
    RID-SIZE CMOVE ;

: RID=  ( a b -- flag )
    2DUP = IF 2DROP -1 EXIT THEN
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    SWAP RID-SIZE ROT RID-SIZE COMPARE 0= ;

: RID-ZERO?  ( id -- flag )
    DUP 0= IF DROP -1 EXIT THEN
    DUP @ 0=
    OVER 8 + @ 0= AND
    OVER 16 + @ 0= AND
    SWAP 24 + @ 0= AND ;

: RID-PRESENT?  ( id -- flag )
    RID-ZERO? 0= ;
