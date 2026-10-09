\ Test support: the scalar-qualification profile.  Its descriptor is the
\ production pure-computation descriptor with its own identifier and the
\ scalar-qualification semantics (docs/sandbox/profile-format.md), which
\ also enables signature-zero scalar entries.  Only executor qualification
\ uses it; no product host accepts it.

PROVIDED sbox-qual-profile

CREATE _SQP-DESCRIPTOR SBOX-PROFILE-PURE-DESCRIPTOR NIP 64 + ALLOT
VARIABLE _SQP-U
VARIABLE _SQP-LINES

: _SQP+  ( address length -- )
    _SQP-DESCRIPTOR _SQP-U @ + SWAP DUP _SQP-U +! MOVE ;

: _SQP-RECORD+  ( address length -- )
    _SQP+ 10 _SQP-DESCRIPTOR _SQP-U @ + C! 1 _SQP-U +! ;

\ The offset just past the Nth record of the pure descriptor.
: _SQP-AFTER  ( n -- offset )
    _SQP-LINES !
    SBOX-PROFILE-PURE-DESCRIPTOR
    0 ?DO
        DUP I + C@ 10 = IF
            -1 _SQP-LINES +!
            _SQP-LINES @ 0= IF DROP I 1+ UNLOOP EXIT THEN
        THEN
    LOOP
    DROP -1 ;

\ Records three and four, profile and semantics, are replaced.
: _SQP-BUILD  ( -- )
    0 _SQP-U !
    SBOX-PROFILE-PURE-DESCRIPTOR DROP 2 _SQP-AFTER _SQP+
    S" profile org.akashic.sandbox.scalar-qualification" _SQP-RECORD+
    S" semantics org.akashic.sandbox.semantics.scalar-qualification"
        _SQP-RECORD+
    SBOX-PROFILE-PURE-DESCRIPTOR 4 _SQP-AFTER TUCK - >R + R> _SQP+ ;

\ Loads the scalar-qualification profile into PROFILE.
: SBOX-QUALIFICATION-INIT  ( profile workspace -- status )
    _SQP-BUILD
    >R >R _SQP-DESCRIPTOR _SQP-U @ R> R> SBOX-PROFILE-LOAD ;
