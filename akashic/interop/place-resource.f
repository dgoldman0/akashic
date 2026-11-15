\ =====================================================================
\  place-resource.f - Files handed between components, by place
\ =====================================================================
\  A component names a file to another as vfs://<place>/<path>
\  (resource.f).  The words here make that text from a place and read it
\  back in the reader's own place set, so a resource that names a place
\  the reader was not given fails: that is where a Practice's choice of
\  places takes effect.  CINST-PLACES is how a component obtains its set.
\ =====================================================================

PROVIDED akashic-interop-place-resource

REQUIRE resource.f
REQUIRE service-endpoint.f
REQUIRE ../utils/fs/places.f

\ CINST-PLACES ( instance -- set | 0 )
\   The place set INSTANCE works in: what its endpoint lends it under the
\   service id org.akashic.fs.places.  A component that runs with no
\   endpoint, as a standalone shell run does, takes the registry's default
\   set.  A component whose endpoint answers nothing has no places.
: CINST-PLACES  ( instance -- set | 0 )
    DUP 0= IF DROP PLACES-DEFAULT EXIT THEN
    DUP CINST.ENDPOINT @ 0= IF DROP PLACES-DEFAULT EXIT THEN
    >R S" org.akashic.fs.places" R> CINST-SERVICE ;

\ CINST-HOME ( instance -- place | 0 )
\   The home of INSTANCE's set: where its own records go.
: CINST-HOME  ( instance -- place | 0 )
    CINST-PLACES DUP IF PLSET-HOME THEN ;

\ CINST-ORIGIN ( instance -- place | 0 )
\   The origin of INSTANCE's set: where its shipped files are read.
: CINST-ORIGIN  ( instance -- place | 0 )
    CINST-PLACES DUP IF PLSET-ORIGIN THEN ;

\ IRES-PLACE! ( path-a path-u place value -- ior )
\   Make VALUE the locator of PATH in PLACE.
: IRES-PLACE!  ( path-a path-u place value -- ior )
    >R DUP 0= IF DROP 2DROP R> DROP IRES-S-INVALID EXIT THEN
    PLACE-NAME 2SWAP R> IRES-VFS! ;

\ IRES-PLACE-PARSE ( uri-a uri-u set -- path-a path-u place ior )
\   The place of SET a locator names and the path in it.  The path lies in
\   the URI.  IRES-S-NO-PLACE when SET has no place of that name.
: IRES-PLACE-PARSE  ( uri-a uri-u set -- path-a path-u place ior )
    >R IRES-VFS-PARSE 0= IF
        2DROP 2DROP R> DROP 0 0 0 IRES-S-INVALID EXIT
    THEN                                        ( place-a place-u path-a path-u )
    2SWAP R> DUP 0= IF DROP 2DROP 2DROP 0 0 0 IRES-S-NO-PLACE EXIT THEN
    PLSET-FIND                                  ( path-a path-u place|0 )
    DUP 0= IF DROP 2DROP 0 0 0 IRES-S-NO-PLACE EXIT THEN
    IRES-S-OK ;

\ IRES-PLACE@ ( value set -- path-a path-u place ior )
\   The same for a resource value.  The path lies in the value.
: IRES-PLACE@  ( value set -- path-a path-u place ior )
    OVER 0= IF 2DROP 0 0 0 IRES-S-INVALID EXIT THEN
    OVER CV-TYPE@ CV-T-RESOURCE <> IF 2DROP 0 0 0 IRES-S-TYPE EXIT THEN
    >R DUP CV-DATA@ SWAP CV-LEN@ R> IRES-PLACE-PARSE ;
