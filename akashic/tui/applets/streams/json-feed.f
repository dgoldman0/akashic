\ =====================================================================
\ json-feed.f - strict transactional JSON Feed decoder for Streams
\ =====================================================================
\ Supported versions are exactly https://jsonfeed.org/version/1 and
\ https://jsonfeed.org/version/1.1.  Version 1's singular author and 1.1's
\ authors array are both admitted; when both are present, authors wins as
\ required by JSON Feed 1.1.  This bounded codec retains the syndication
\ fields represented by syndication-model.f and ignores extension fields.
\ Attachment size_in_bytes is the bounded non-negative integer subset;
\ duration_in_seconds retains its exact non-negative JSON number lexeme.
\ No decoded field borrows storage from the input document.
\ A normal commit requires a destination plus one transactional temporary:
\ 2 * SYN-FEED-SIZE = 909632 bytes of external-arena headroom.
\ =====================================================================

PROVIDED akashic-json-feed

REQUIRE syndication-model.f
REQUIRE ../../../utils/json.f
REQUIRE ../../../utils/string.f
REQUIRE ../../../text/utf8.f

1048576 CONSTANT JSON-FEED-DOCUMENT-CAP

\ ---------------------------------------------------------------------
\ Duplicate-aware object and owned-string primitives.
\ ---------------------------------------------------------------------

VARIABLE _JF-OA
VARIABLE _JF-OU
VARIABLE _JF-KA
VARIABLE _JF-KU
VARIABLE _JF-VA
VARIABLE _JF-VU
VARIABLE _JF-FOUND
VARIABLE _JF-IOR

: _JF-FIELD  ( object-a object-u key-a key-u -- value-a value-u found status )
    _JF-KU ! _JF-KA ! _JF-OU ! _JF-OA !
    _JF-OA @ _JF-OU @ _JF-KA @ _JF-KU @ JSON-FIELD
    _JF-IOR ! _JF-FOUND ! _JF-VU ! _JF-VA !
    _JF-IOR @ IF 0 0 0 SYN-S-INVALID EXIT THEN
    _JF-VA @ _JF-VU @ _JF-FOUND @ SYN-S-OK ;

VARIABLE _JF-SA
VARIABLE _JF-SU
VARIABLE _JF-SD
VARIABLE _JF-SMAX
VARIABLE _JF-SLEN

: _JF-UNESCAPE-CALL  ( -- len ior )
    _JF-SA @ _JF-SU @ _JF-SD @ _JF-SMAX @
    JSON-UNESCAPE-CHECKED ;

: _JF-COPY-STRING  ( value-a value-u destination max length-cell -- status )
    _JF-SLEN ! _JF-SMAX ! _JF-SD ! _JF-SU ! _JF-SA !
    0 _JF-SLEN @ !
    _JF-SA @ _JF-SU @ JSON-STRING? 0= IF SYN-S-TYPE EXIT THEN
    _JF-SA @ _JF-SU @ JSON-GET-STRING _JF-SU ! _JF-SA !
    ['] _JF-UNESCAPE-CALL CATCH ?DUP IF
        DROP SYN-S-CAPACITY EXIT
    THEN
    ?DUP IF
        SWAP DROP JSON-E-OVERFLOW = IF
            SYN-S-CAPACITY
        ELSE
            SYN-S-INVALID
        THEN
        EXIT
    THEN
    DUP _JF-SMAX @ > IF DROP SYN-S-CAPACITY EXIT THEN
    DUP _JF-SD @ SWAP UTF8-VALID? 0= IF
        DROP SYN-S-INVALID EXIT
    THEN
    _JF-SLEN @ ! SYN-S-OK ;

VARIABLE _JF-ROA
VARIABLE _JF-ROU
VARIABLE _JF-RKA
VARIABLE _JF-RKU
VARIABLE _JF-RD
VARIABLE _JF-RMAX
VARIABLE _JF-RLEN

: _JF-REQUIRED-STRING
    ( object-a object-u key-a key-u destination max length-cell -- status )
    _JF-RLEN ! _JF-RMAX ! _JF-RD !
    _JF-RKU ! _JF-RKA ! _JF-ROU ! _JF-ROA !
    _JF-ROA @ _JF-ROU @ _JF-RKA @ _JF-RKU @ _JF-FIELD
    DUP IF >R 2DROP DROP R> EXIT THEN DROP
    0= IF 2DROP SYN-S-MISSING EXIT THEN
    _JF-RD @ _JF-RMAX @ _JF-RLEN @ _JF-COPY-STRING ;

: _JF-REQUIRED-NONEMPTY
    ( object-a object-u key-a key-u destination max length-cell -- status )
    DUP >R _JF-REQUIRED-STRING ?DUP IF R> DROP EXIT THEN
    R> @ IF SYN-S-OK ELSE SYN-S-INVALID THEN ;

VARIABLE _JF-XOA
VARIABLE _JF-XOU
VARIABLE _JF-XKA
VARIABLE _JF-XKU
VARIABLE _JF-XD
VARIABLE _JF-XMAX
VARIABLE _JF-XLEN

: _JF-OPTIONAL-STRING
    ( object-a object-u key-a key-u destination max length-cell -- status )
    _JF-XLEN ! _JF-XMAX ! _JF-XD !
    _JF-XKU ! _JF-XKA ! _JF-XOU ! _JF-XOA !
    0 _JF-XLEN @ !
    _JF-XOA @ _JF-XOU @ _JF-XKA @ _JF-XKU @ _JF-FIELD
    DUP IF >R 2DROP DROP R> EXIT THEN DROP
    0= IF 2DROP SYN-S-OK EXIT THEN
    _JF-XD @ _JF-XMAX @ _JF-XLEN @ _JF-COPY-STRING ;

VARIABLE _JF-NACC
VARIABLE _JF-NDIGIT

: _JF-PARSE-UINT  ( addr len -- n status )
    DUP 0= IF 2DROP 0 SYN-S-INVALID EXIT THEN
    0 _JF-NACC !
    0 ?DO
        DUP I + C@ DUP 48 < OVER 57 > OR IF
            2DROP 0 SYN-S-INVALID UNLOOP EXIT
        THEN
        48 - _JF-NDIGIT !
        _JF-NACC @ 0x7FFFFFFFFFFFFFFF _JF-NDIGIT @ - 10 / > IF
            DROP 0 SYN-S-CAPACITY UNLOOP EXIT
        THEN
        _JF-NACC @ 10 * _JF-NDIGIT @ + _JF-NACC !
    LOOP
    DROP _JF-NACC @ SYN-S-OK ;

\ ---------------------------------------------------------------------
\ Authors.  Each defined member uses JSON-FIELD, so escaped spellings and
\ repeated definitions cannot evade duplicate detection.
\ ---------------------------------------------------------------------

VARIABLE _JF-AUTH-OA
VARIABLE _JF-AUTH-OU
VARIABLE _JF-AUTH-DEST

: _JF-DECODE-AUTHOR  ( object-a object-u author -- status )
    _JF-AUTH-DEST ! _JF-AUTH-OU ! _JF-AUTH-OA !
    _JF-AUTH-DEST @ SYN-AUTHOR-SIZE 0 FILL
    _JF-AUTH-OA @ _JF-AUTH-OU @ JSON-OBJECT? 0= IF SYN-S-TYPE EXIT THEN
    _JF-AUTH-OA @ _JF-AUTH-OU @ S" name"
        _JF-AUTH-DEST @ _SYN-AUTHOR-NAME + SYN-AUTHOR-NAME-CAP
        _JF-AUTH-DEST @ _SYN-AUTHOR-NAME-U +
        _JF-OPTIONAL-STRING ?DUP IF EXIT THEN
    _JF-AUTH-OA @ _JF-AUTH-OU @ S" url"
        _JF-AUTH-DEST @ _SYN-AUTHOR-URL + SYN-URL-CAP
        _JF-AUTH-DEST @ _SYN-AUTHOR-URL-U +
        _JF-OPTIONAL-STRING ?DUP IF EXIT THEN
    _JF-AUTH-OA @ _JF-AUTH-OU @ S" avatar"
        _JF-AUTH-DEST @ _SYN-AUTHOR-AVATAR + SYN-URL-CAP
        _JF-AUTH-DEST @ _SYN-AUTHOR-AVATAR-U +
        _JF-OPTIONAL-STRING ?DUP IF EXIT THEN
    _JF-AUTH-DEST @ _SYN-AUTHOR-NAME-U + @
    _JF-AUTH-DEST @ _SYN-AUTHOR-URL-U + @ OR
    _JF-AUTH-DEST @ _SYN-AUTHOR-AVATAR-U + @ OR
    IF SYN-S-OK ELSE SYN-S-INVALID THEN ;

VARIABLE _JF-AA
VARIABLE _JF-AU
VARIABLE _JF-ABASE
VARIABLE _JF-ACOUNT-CELL
VARIABLE _JF-ACUR-A
VARIABLE _JF-ACUR-U
VARIABLE _JF-ACOUNT

: _JF-DECODE-AUTHORS
    ( array-a array-u author-base author-count-cell -- status )
    _JF-ACOUNT-CELL ! _JF-ABASE ! _JF-AU ! _JF-AA !
    0 _JF-ACOUNT-CELL @ !
    _JF-ABASE @ SYN-MAX-AUTHORS SYN-AUTHOR-SIZE * 0 FILL
    _JF-AA @ _JF-AU @ JSON-ARRAY? 0= IF SYN-S-TYPE EXIT THEN
    _JF-AA @ _JF-AU @ JSON-ENTER _JF-ACUR-U ! _JF-ACUR-A !
    0 _JF-ACOUNT !
    BEGIN
        _JF-ACUR-U @ 0> IF _JF-ACUR-A @ C@ 93 <> ELSE 0 THEN
    WHILE
        _JF-ACOUNT @ SYN-MAX-AUTHORS >= IF SYN-S-CAPACITY EXIT THEN
        _JF-ACUR-A @ _JF-ACUR-U @ JSON-VALUE-SPAN
        _JF-ACOUNT @ SYN-AUTHOR-SIZE * _JF-ABASE @ +
        _JF-DECODE-AUTHOR ?DUP IF EXIT THEN
        1 _JF-ACOUNT +!
        _JF-ACUR-A @ _JF-ACUR-U @ JSON-NEXT DROP
        _JF-ACUR-U ! _JF-ACUR-A !
    REPEAT
    _JF-ACOUNT @ _JF-ACOUNT-CELL @ ! SYN-S-OK ;

VARIABLE _JF-AS-OA
VARIABLE _JF-AS-OU
VARIABLE _JF-AS-BASE
VARIABLE _JF-AS-COUNT

: _JF-DECODE-AUTHOR-SET
    ( object-a object-u author-base author-count-cell -- status )
    _JF-AS-COUNT ! _JF-AS-BASE ! _JF-AS-OU ! _JF-AS-OA !
    0 _JF-AS-COUNT @ !
    _JF-AS-BASE @ SYN-MAX-AUTHORS SYN-AUTHOR-SIZE * 0 FILL

    \ Validate and retain the deprecated singular form first.
    _JF-AS-OA @ _JF-AS-OU @ S" author" _JF-FIELD
    DUP IF >R 2DROP DROP R> EXIT THEN DROP
    0= IF
        2DROP
    ELSE
        _JF-AS-BASE @ _JF-DECODE-AUTHOR ?DUP IF EXIT THEN
        1 _JF-AS-COUNT @ !
    THEN

    \ The plural form, if present, is authoritative and replaces singular.
    _JF-AS-OA @ _JF-AS-OU @ S" authors" _JF-FIELD
    DUP IF >R 2DROP DROP R> EXIT THEN DROP
    0= IF
        2DROP SYN-S-OK
    ELSE
        _JF-AS-BASE @ _JF-AS-COUNT @ _JF-DECODE-AUTHORS
    THEN ;

\ ---------------------------------------------------------------------
\ Tags and attachments.
\ ---------------------------------------------------------------------

VARIABLE _JF-TA
VARIABLE _JF-TU
VARIABLE _JF-TENTRY
VARIABLE _JF-TCUR-A
VARIABLE _JF-TCUR-U
VARIABLE _JF-TCOUNT
VARIABLE _JF-TSLOT

: _JF-DECODE-TAGS  ( array-a array-u entry -- status )
    _JF-TENTRY ! _JF-TU ! _JF-TA !
    0 _JF-TENTRY @ SYN.ENTRY.TAG-COUNT !
    _JF-TENTRY @ _SYN-ENTRY-TAGS + SYN-MAX-TAGS SYN-TAG-SIZE * 0 FILL
    _JF-TA @ _JF-TU @ JSON-ARRAY? 0= IF SYN-S-TYPE EXIT THEN
    _JF-TA @ _JF-TU @ JSON-ENTER _JF-TCUR-U ! _JF-TCUR-A !
    0 _JF-TCOUNT !
    BEGIN
        _JF-TCUR-U @ 0> IF _JF-TCUR-A @ C@ 93 <> ELSE 0 THEN
    WHILE
        _JF-TCOUNT @ SYN-MAX-TAGS >= IF SYN-S-CAPACITY EXIT THEN
        _JF-TCOUNT @ _JF-TENTRY @ _SYN-ENTRY-TAG _JF-TSLOT !
        _JF-TCUR-A @ _JF-TCUR-U @ JSON-VALUE-SPAN
        _JF-TSLOT @ 8 + SYN-TAG-CAP _JF-TSLOT @
        _JF-COPY-STRING ?DUP IF EXIT THEN
        1 _JF-TCOUNT +!
        _JF-TCUR-A @ _JF-TCUR-U @ JSON-NEXT DROP
        _JF-TCUR-U ! _JF-TCUR-A !
    REPEAT
    _JF-TCOUNT @ _JF-TENTRY @ SYN.ENTRY.TAG-COUNT ! SYN-S-OK ;

VARIABLE _JF-AT-OA
VARIABLE _JF-AT-OU
VARIABLE _JF-AT-DEST

: _JF-DECODE-ATTACHMENT  ( object-a object-u attachment -- status )
    _JF-AT-DEST ! _JF-AT-OU ! _JF-AT-OA !
    _JF-AT-DEST @ SYN-ATTACHMENT-SIZE 0 FILL
    _JF-AT-OA @ _JF-AT-OU @ JSON-OBJECT? 0= IF SYN-S-TYPE EXIT THEN
    _JF-AT-OA @ _JF-AT-OU @ S" url"
        _JF-AT-DEST @ _SYN-ATTACHMENT-URL + SYN-URL-CAP
        _JF-AT-DEST @ _SYN-ATTACHMENT-URL-U +
        _JF-REQUIRED-NONEMPTY ?DUP IF EXIT THEN
    _JF-AT-OA @ _JF-AT-OU @ S" mime_type"
        _JF-AT-DEST @ _SYN-ATTACHMENT-MIME + SYN-MIME-CAP
        _JF-AT-DEST @ _SYN-ATTACHMENT-MIME-U +
        _JF-REQUIRED-NONEMPTY ?DUP IF EXIT THEN
    _JF-AT-OA @ _JF-AT-OU @ S" title"
        _JF-AT-DEST @ _SYN-ATTACHMENT-TITLE + SYN-TITLE-CAP
        _JF-AT-DEST @ _SYN-ATTACHMENT-TITLE-U +
        _JF-OPTIONAL-STRING ?DUP IF EXIT THEN

    _JF-AT-OA @ _JF-AT-OU @ S" size_in_bytes" _JF-FIELD
    DUP IF >R 2DROP DROP R> EXIT THEN DROP
    0= IF
        2DROP
    ELSE
        2DUP JSON-NUMBER? 0= IF 2DROP SYN-S-TYPE EXIT THEN
        JSON-VALUE-SPAN _JF-PARSE-UINT DUP IF NIP EXIT THEN
        DROP _JF-AT-DEST @ SYN.ATTACHMENT.SIZE-IN-BYTES !
        SYN-ATTACHMENT-HAS-SIZE
            _JF-AT-DEST @ SYN.ATTACHMENT.FLAGS +!
    THEN

    _JF-AT-OA @ _JF-AT-OU @ S" duration_in_seconds" _JF-FIELD
    DUP IF >R 2DROP DROP R> EXIT THEN DROP
    0= IF
        2DROP
    ELSE
        2DUP JSON-NUMBER? 0= IF 2DROP SYN-S-TYPE EXIT THEN
        JSON-VALUE-SPAN
        DUP SYN-NUMBER-CAP > IF 2DROP SYN-S-CAPACITY EXIT THEN
        DUP 0= IF 2DROP SYN-S-INVALID EXIT THEN
        OVER C@ 45 = IF 2DROP SYN-S-INVALID EXIT THEN
        DUP _JF-AT-DEST @ _SYN-ATTACHMENT-DURATION-U + !
        _JF-AT-DEST @ _SYN-ATTACHMENT-DURATION + SWAP CMOVE
        SYN-ATTACHMENT-HAS-DURATION
            _JF-AT-DEST @ SYN.ATTACHMENT.FLAGS +!
    THEN
    SYN-S-OK ;

VARIABLE _JF-ATA
VARIABLE _JF-ATU
VARIABLE _JF-ATENTRY
VARIABLE _JF-ATCUR-A
VARIABLE _JF-ATCUR-U
VARIABLE _JF-ATCOUNT

: _JF-DECODE-ATTACHMENTS  ( array-a array-u entry -- status )
    _JF-ATENTRY ! _JF-ATU ! _JF-ATA !
    0 _JF-ATENTRY @ SYN.ENTRY.ATTACHMENT-COUNT !
    _JF-ATENTRY @ _SYN-ENTRY-ATTACHMENTS +
        SYN-MAX-ATTACHMENTS SYN-ATTACHMENT-SIZE * 0 FILL
    _JF-ATA @ _JF-ATU @ JSON-ARRAY? 0= IF SYN-S-TYPE EXIT THEN
    _JF-ATA @ _JF-ATU @ JSON-ENTER _JF-ATCUR-U ! _JF-ATCUR-A !
    0 _JF-ATCOUNT !
    BEGIN
        _JF-ATCUR-U @ 0> IF _JF-ATCUR-A @ C@ 93 <> ELSE 0 THEN
    WHILE
        _JF-ATCOUNT @ SYN-MAX-ATTACHMENTS >= IF SYN-S-CAPACITY EXIT THEN
        _JF-ATCUR-A @ _JF-ATCUR-U @ JSON-VALUE-SPAN
        _JF-ATCOUNT @ _JF-ATENTRY @ _SYN-ENTRY-ATTACHMENT
        _JF-DECODE-ATTACHMENT ?DUP IF EXIT THEN
        1 _JF-ATCOUNT +!
        _JF-ATCUR-A @ _JF-ATCUR-U @ JSON-NEXT DROP
        _JF-ATCUR-U ! _JF-ATCUR-A !
    REPEAT
    _JF-ATCOUNT @ _JF-ATENTRY @ SYN.ENTRY.ATTACHMENT-COUNT !
    SYN-S-OK ;

\ ---------------------------------------------------------------------
\ Entry and feed decoding.
\ ---------------------------------------------------------------------

VARIABLE _JF-EA
VARIABLE _JF-EU
VARIABLE _JF-ENTRY

: _JF-DECODE-ENTRY  ( object-a object-u entry -- status )
    _JF-ENTRY ! _JF-EU ! _JF-EA !
    _JF-ENTRY @ SYN-ENTRY-SIZE 0 FILL
    _JF-EA @ _JF-EU @ JSON-OBJECT? 0= IF SYN-S-TYPE EXIT THEN

    _JF-EA @ _JF-EU @ S" id"
        _JF-ENTRY @ _SYN-ENTRY-ID + SYN-ID-CAP
        _JF-ENTRY @ _SYN-ENTRY-ID-U +
        _JF-REQUIRED-NONEMPTY ?DUP IF EXIT THEN
    _JF-EA @ _JF-EU @ S" url"
        _JF-ENTRY @ _SYN-ENTRY-URL + SYN-URL-CAP
        _JF-ENTRY @ _SYN-ENTRY-URL-U +
        _JF-OPTIONAL-STRING ?DUP IF EXIT THEN
    _JF-EA @ _JF-EU @ S" title"
        _JF-ENTRY @ _SYN-ENTRY-TITLE + SYN-TITLE-CAP
        _JF-ENTRY @ _SYN-ENTRY-TITLE-U +
        _JF-OPTIONAL-STRING ?DUP IF EXIT THEN
    _JF-EA @ _JF-EU @ S" summary"
        _JF-ENTRY @ _SYN-ENTRY-SUMMARY + SYN-SUMMARY-CAP
        _JF-ENTRY @ _SYN-ENTRY-SUMMARY-U +
        _JF-OPTIONAL-STRING ?DUP IF EXIT THEN
    _JF-EA @ _JF-EU @ S" date_published"
        _JF-ENTRY @ _SYN-ENTRY-PUBLISHED + SYN-DATETIME-CAP
        _JF-ENTRY @ _SYN-ENTRY-PUBLISHED-U +
        _JF-OPTIONAL-STRING ?DUP IF EXIT THEN
    _JF-EA @ _JF-EU @ S" date_modified"
        _JF-ENTRY @ _SYN-ENTRY-MODIFIED + SYN-DATETIME-CAP
        _JF-ENTRY @ _SYN-ENTRY-MODIFIED-U +
        _JF-OPTIONAL-STRING ?DUP IF EXIT THEN

    0 _JF-ENTRY @ SYN.ENTRY.CONTENT-REP !
    _JF-EA @ _JF-EU @ S" content_text" _JF-FIELD
    DUP IF >R 2DROP DROP R> EXIT THEN DROP
    0= IF
        2DROP
    ELSE
        _JF-ENTRY @ _SYN-ENTRY-CONTENT-TEXT + SYN-CONTENT-CAP
        _JF-ENTRY @ _SYN-ENTRY-CONTENT-TEXT-U +
        _JF-COPY-STRING ?DUP IF EXIT THEN
        SYN-CONTENT-TEXT _JF-ENTRY @ SYN.ENTRY.CONTENT-REP +!
    THEN
    _JF-EA @ _JF-EU @ S" content_html" _JF-FIELD
    DUP IF >R 2DROP DROP R> EXIT THEN DROP
    0= IF
        2DROP
    ELSE
        _JF-ENTRY @ _SYN-ENTRY-CONTENT-HTML + SYN-CONTENT-CAP
        _JF-ENTRY @ _SYN-ENTRY-CONTENT-HTML-U +
        _JF-COPY-STRING ?DUP IF EXIT THEN
        SYN-CONTENT-HTML _JF-ENTRY @ SYN.ENTRY.CONTENT-REP +!
    THEN
    _JF-ENTRY @ SYN.ENTRY.CONTENT-REP @ SYN-CONTENT-NONE = IF
        SYN-S-MISSING EXIT
    THEN

    _JF-EA @ _JF-EU @ _JF-ENTRY @ _SYN-ENTRY-AUTHORS +
        _JF-ENTRY @ SYN.ENTRY.AUTHOR-COUNT
        _JF-DECODE-AUTHOR-SET ?DUP IF EXIT THEN

    _JF-EA @ _JF-EU @ S" tags" _JF-FIELD
    DUP IF >R 2DROP DROP R> EXIT THEN DROP
    0= IF
        2DROP
    ELSE
        _JF-ENTRY @ _JF-DECODE-TAGS ?DUP IF EXIT THEN
    THEN

    _JF-EA @ _JF-EU @ S" attachments" _JF-FIELD
    DUP IF >R 2DROP DROP R> EXIT THEN DROP
    0= IF
        2DROP SYN-S-OK
    ELSE
        _JF-ENTRY @ _JF-DECODE-ATTACHMENTS
    THEN ;

VARIABLE _JF-UQ-INDEX
VARIABLE _JF-UQ-FEED
VARIABLE _JF-UQ-ID-A
VARIABLE _JF-UQ-ID-U

: _JF-ENTRY-ID-UNIQUE?  ( index feed -- flag )
    _JF-UQ-FEED ! _JF-UQ-INDEX !
    _JF-UQ-INDEX @ _JF-UQ-FEED @ _SYN-FEED-ENTRY SYN.ENTRY.ID
    _JF-UQ-ID-U ! _JF-UQ-ID-A !
    _JF-UQ-INDEX @ 0 ?DO
        I _JF-UQ-FEED @ _SYN-FEED-ENTRY SYN.ENTRY.ID
        _JF-UQ-ID-A @ _JF-UQ-ID-U @ STR-STR= IF
            0 UNLOOP EXIT
        THEN
    LOOP
    -1 ;

CREATE _JF-VERSION-BUF 64 ALLOT
VARIABLE _JF-VERSION-U

: _JF-DECODE-VERSION  ( object-a object-u feed -- status )
    >R S" version" _JF-FIELD
    DUP IF >R 2DROP DROP R> R> DROP EXIT THEN DROP
    0= IF 2DROP R> DROP SYN-S-MISSING EXIT THEN
    _JF-VERSION-BUF 64 _JF-VERSION-U _JF-COPY-STRING
    ?DUP IF R> DROP EXIT THEN
    _JF-VERSION-BUF _JF-VERSION-U @
    S" https://jsonfeed.org/version/1" STR-STR= IF
        SYN-VERSION-JSON-FEED-1 R> SYN.FEED.VERSION ! SYN-S-OK EXIT
    THEN
    _JF-VERSION-BUF _JF-VERSION-U @
    S" https://jsonfeed.org/version/1.1" STR-STR= IF
        SYN-VERSION-JSON-FEED-1_1 R> SYN.FEED.VERSION ! SYN-S-OK EXIT
    THEN
    R> DROP SYN-S-UNSUPPORTED ;

VARIABLE _JF-DA
VARIABLE _JF-DU
VARIABLE _JF-DEST
VARIABLE _JF-ITEMS-A
VARIABLE _JF-ITEMS-U
VARIABLE _JF-CUR-A
VARIABLE _JF-CUR-U
VARIABLE _JF-COUNT

: _JF-DECODE-INTO  ( json-a json-u feed -- status )
    _JF-DEST ! _JF-DU ! _JF-DA !
    _JF-DA @ _JF-DU @ JSON-FEED-DOCUMENT-CAP JSON-VALID-LIMIT?
    0= IF SYN-S-INVALID EXIT THEN
    _JF-DA @ _JF-DU @ JSON-OBJECT? 0= IF SYN-S-TYPE EXIT THEN

    _JF-DA @ _JF-DU @ _JF-DEST @ _JF-DECODE-VERSION ?DUP IF EXIT THEN
    _JF-DA @ _JF-DU @ S" title"
        _JF-DEST @ _SYN-FEED-TITLE + SYN-TITLE-CAP
        _JF-DEST @ _SYN-FEED-TITLE-U +
        _JF-REQUIRED-STRING ?DUP IF EXIT THEN
    _JF-DA @ _JF-DU @ S" home_page_url"
        _JF-DEST @ _SYN-FEED-HOME + SYN-URL-CAP
        _JF-DEST @ _SYN-FEED-HOME-U +
        _JF-OPTIONAL-STRING ?DUP IF EXIT THEN
    _JF-DA @ _JF-DU @ S" feed_url"
        _JF-DEST @ _SYN-FEED-URL + SYN-URL-CAP
        _JF-DEST @ _SYN-FEED-URL-U +
        _JF-OPTIONAL-STRING ?DUP IF EXIT THEN
    _JF-DA @ _JF-DU @ S" next_url"
        _JF-DEST @ _SYN-FEED-NEXT + SYN-URL-CAP
        _JF-DEST @ _SYN-FEED-NEXT-U +
        _JF-OPTIONAL-STRING ?DUP IF EXIT THEN
    _JF-DA @ _JF-DU @ S" description"
        _JF-DEST @ _SYN-FEED-DESCRIPTION + SYN-DESCRIPTION-CAP
        _JF-DEST @ _SYN-FEED-DESCRIPTION-U +
        _JF-OPTIONAL-STRING ?DUP IF EXIT THEN
    _JF-DA @ _JF-DU @ _JF-DEST @ _SYN-FEED-AUTHORS +
        _JF-DEST @ SYN.FEED.AUTHOR-COUNT
        _JF-DECODE-AUTHOR-SET ?DUP IF EXIT THEN

    _JF-DEST @ SYN.FEED.FEED-URL NIP 0<>
    _JF-DEST @ SYN.FEED.NEXT-URL NIP 0<> AND IF
        _JF-DEST @ SYN.FEED.FEED-URL
        _JF-DEST @ SYN.FEED.NEXT-URL STR-STR= IF
            SYN-S-INVALID EXIT
        THEN
    THEN

    _JF-DA @ _JF-DU @ S" items" _JF-FIELD
    DUP IF >R 2DROP DROP R> EXIT THEN DROP
    0= IF 2DROP SYN-S-MISSING EXIT THEN
    2DUP JSON-ARRAY? 0= IF 2DROP SYN-S-TYPE EXIT THEN
    JSON-ENTER _JF-ITEMS-U ! _JF-ITEMS-A !
    _JF-ITEMS-A @ _JF-ITEMS-U @ JSON-SKIP-WS
        _JF-CUR-U ! _JF-CUR-A !
    0 _JF-COUNT !
    BEGIN
        _JF-CUR-U @ 0> IF _JF-CUR-A @ C@ 93 <> ELSE 0 THEN
    WHILE
        _JF-COUNT @ SYN-MAX-ENTRIES >= IF SYN-S-CAPACITY EXIT THEN
        _JF-CUR-A @ _JF-CUR-U @ JSON-VALUE-SPAN
        _JF-COUNT @ _JF-DEST @ _SYN-FEED-ENTRY
        _JF-DECODE-ENTRY ?DUP IF EXIT THEN
        _JF-COUNT @ _JF-DEST @ _JF-ENTRY-ID-UNIQUE? 0= IF
            SYN-S-INVALID EXIT
        THEN
        1 _JF-COUNT +!
        _JF-CUR-A @ _JF-CUR-U @ JSON-NEXT DROP
        _JF-CUR-U ! _JF-CUR-A !
    REPEAT
    _JF-COUNT @ _JF-DEST @ SYN.FEED.COUNT ! SYN-S-OK ;

VARIABLE _JF-TEMP
VARIABLE _JF-TEMP-STATUS

: JSON-FEED-DECODE  ( json-a json-u feed -- status )
    DUP 0= IF DROP 2DROP SYN-S-INVALID EXIT THEN
    >R
    DUP 0< IF 2DROP R> DROP SYN-S-INVALID EXIT THEN
    DUP JSON-FEED-DOCUMENT-CAP > IF
        2DROP R> DROP SYN-S-CAPACITY EXIT
    THEN
    OVER 0= IF 2DROP R> DROP SYN-S-INVALID EXIT THEN
    SYN-FEED-SIZE ALLOCATE DUP IF
        2DROP 2DROP R> DROP SYN-S-CAPACITY EXIT
    THEN
    DROP _JF-TEMP !
    _JF-TEMP @ SYN-FEED-INIT
    _JF-TEMP @ _JF-DECODE-INTO _JF-TEMP-STATUS !
    _JF-TEMP-STATUS @ SYN-S-OK = IF
        _JF-TEMP @ R@ SYN-FEED-SIZE CMOVE
    THEN
    _JF-TEMP @ SYN-FEED-SIZE 0 FILL
    \ KDOS FREE is ( addr -- ); no ANS-style ior remains on the stack.
    _JF-TEMP @ FREE
    R> DROP _JF-TEMP-STATUS @ ;

\ JSON navigation uses bounded module scratch.  Ordinary use must decode on
\ its owner context.  GUARDED builds serialize callers additionally; network
\ workers should still return bytes for an owner-committed decode.
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../../concurrency/guard.f
GUARD _json-feed-guard
' JSON-FEED-DECODE CONSTANT _json-feed-decode-xt
: JSON-FEED-DECODE  _json-feed-decode-xt _json-feed-guard WITH-GUARD ;
[THEN] [THEN]
