\ did.f — DID Validation for KDOS / Megapad-64
\
\ DID (Decentralized Identifier) utilities.
\ Validates did:plc: and did:web: format DIDs.
\
\ Prefix: DID-   (public API)
\         _DID-  (internal helpers)
\
\ Load with:   REQUIRE did.f

PROVIDED akashic-did

\ =====================================================================
\  DID-VALID?
\ =====================================================================

VARIABLE _DID-PTR
VARIABLE _DID-LEN

\ _DID-MATCH ( addr len prefix-a prefix-len -- flag )
\   Check if addr/len starts with prefix.
: _DID-MATCH  ( addr len pfx-a pfx-len -- flag )
    _DID-LEN !
    \ Stack: addr len pfx-a
    SWAP                  \ addr pfx-a len
    DUP _DID-LEN @ < IF  \ len < pfx-len?
        DROP 2DROP 0 EXIT
    THEN
    DROP                  \ addr pfx-a
    _DID-LEN @ 0 ?DO
        OVER I + C@       \ input char
        OVER I + C@       \ prefix char
        <> IF 2DROP 0 UNLOOP EXIT THEN
    LOOP
    2DROP -1 ;

\ DID-VALID? ( addr len -- flag )
\   True if string is a valid DID (did:plc:... or did:web:...).
\   Minimal validation: checks prefix and minimum length.
: DID-VALID?  ( addr len -- flag )
    DUP 8 < IF 2DROP 0 EXIT THEN    \ minimum: "did:plc:" = 8 + content
    2DUP S" did:plc:" _DID-MATCH IF 2DROP -1 EXIT THEN
    S" did:web:" _DID-MATCH ;

\ =====================================================================
\  DID-METHOD
\ =====================================================================

\ DID-METHOD ( addr len -- method-a method-u )
\   Extract method portion ("plc" or "web") from a DID.
\   Assumes valid DID (starts with "did:").
\   Returns pointer into the original string.

VARIABLE _DM-SRC
VARIABLE _DM-LEN
VARIABLE _DM-I

: DID-METHOD  ( addr len -- method-a method-u )
    _DM-LEN ! _DM-SRC !
    _DM-LEN @ 4 < IF _DM-SRC @ 0 EXIT THEN
    \ method starts at offset 4 (after "did:")
    _DM-SRC @ 4 +               \ method-start
    0 _DM-I !
    BEGIN
        _DM-I @ _DM-LEN @ 4 - < IF
            _DM-SRC @ 4 + _DM-I @ + C@ 58 = IF  \ ':'
                _DM-SRC @ 4 + _DM-I @
                EXIT
            THEN
            1 _DM-I +!
            DROP _DM-SRC @ 4 +    \ keep method-start on stack
            0
        ELSE
            _DM-LEN @ 4 - -1     \ no colon — rest is method
        THEN
    UNTIL ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _did-guard

' DID-VALID?      CONSTANT _did-valid-q-xt
' DID-METHOD      CONSTANT _did-method-xt

: DID-VALID?      _did-valid-q-xt _did-guard WITH-GUARD ;
: DID-METHOD      _did-method-xt _did-guard WITH-GUARD ;
[THEN] [THEN]
