\ =====================================================================
\  web-roots.f - The global TLS root set's contributor
\ =====================================================================
\  The machine's global trust anchors are the roots NSS trusts for TLS
\  server authentication, generated from NSS's certdata.txt into
\  net/web-roots/web-roots.mpta (local_testing/generate_web_roots.py) and
\  pinned by web-roots/web-roots-pin.f.  WEB-ROOTS-REGISTER registers the
\  one contributor that reads that file from a place, such as the origin
\  of the image's shipped files, when the trust registry composes the
\  machine's bundle; MTRUST-WEB-ROOTS+ then admits it only if it is the
\  exact pinned bundle.
\
\  An image built without the file has no global anchors, so its public
\  TLS fails closed; a file that is there must be the pinned one, or the
\  composition fails.
\
\  WEB-ROOTS-REGISTER ( place -- status )
\    An MTRUST-* status.  The place must stay open until MTRUST-FREEZE.
\ =====================================================================

PROVIDED akashic-net-web-roots

REQUIRE tls-trust-registry.f
REQUIRE ../utils/fs/places.f

: WEB-ROOTS-PATH  ( -- a u )  S" net/web-roots/web-roots.mpta" ;

VARIABLE _WRT-PLACE
VARIABLE _WRT-BUILDER
VARIABLE _WRT-FD
VARIABLE _WRT-BUF

: _WRT-CLOSE  ( -- )
    _WRT-FD @ ?DUP IF 0 _WRT-FD ! VFS-CLOSE? DROP THEN ;

: _WRT-FREE  ( -- )
    _WRT-BUF @ ?DUP IF 0 _WRT-BUF ! FREE THEN ;

\ Read the whole file into a buffer of its exact size and add it.  An
\ image built without the file adds nothing: it has no global anchors, and
\ its public TLS fails closed.
: _WRT-ADD  ( -- status )
    WEB-ROOTS-PATH VFS-FF-READ _WRT-PLACE @ PLACE-OPEN ?DUP IF
        NIP VFS-IOR-REASON VFS-R-NOENT = IF
            MTRUST-S-OK
        ELSE
            MTRUST-S-CONTRIBUTOR
        THEN EXIT
    THEN _WRT-FD !
    _WRT-FD @ VFS-SIZE WEB-ROOTS-BYTES <> IF MTRUST-S-INVALID EXIT THEN
    WEB-ROOTS-BYTES ALLOCATE IF DROP MTRUST-S-CAPACITY EXIT THEN _WRT-BUF !
    _WRT-BUF @ WEB-ROOTS-BYTES _WRT-FD @ VFS-READ-EXACT IF
        MTRUST-S-CONTRIBUTOR EXIT
    THEN
    _WRT-CLOSE
    _WRT-BUF @ WEB-ROOTS-BYTES _WRT-BUILDER @ MTRUST-WEB-ROOTS+ ;

\ The file and buffer are released however the read ends; a THROW passes
\ on to the registry, which fails the composition with its code.
: _WRT-EMIT  ( builder place -- status )
    _WRT-PLACE ! _WRT-BUILDER !
    0 _WRT-FD ! 0 _WRT-BUF !
    _WRT-PLACE @ 0= IF MTRUST-S-INVALID EXIT THEN
    ['] _WRT-ADD CATCH ?DUP IF _WRT-CLOSE _WRT-FREE THROW THEN
    _WRT-CLOSE _WRT-FREE ;

: WEB-ROOTS-REGISTER  ( place -- status )
    >R S" org.akashic.trust.web-roots" ['] _WRT-EMIT R> MTRUST-REGISTER ;
