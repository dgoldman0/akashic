\ test-root-place.f - a check's own RAM volume as a place
\
\ A check that keeps its records on a RAM volume of its own declares that
\ volume under a name no other volume or place of the check has, and one
\ writable place over its root.  _t-root-set answers a set of that one
\ place, which is its home, its origin and its documents place;
\ _t-root-place answers the place.
\ _t-root-set-free gives back what _t-root-set made: it detaches the
\ volume and frees the set.
\
\ An applet instance that runs with no endpoint takes the registry's
\ default set, as a standalone run takes the one composition declares.  A
\ check whose instances run that way makes its set the default with
\ _t-default-home, which answers the default it replaced, and gives that
\ one back with _t-default-restore.

: _t-root-set  ( vfs name-a name-u -- set )
    2DUP PLACES-VOLUME THROW >R
    ROT R@ PVOL-ATTACH THROW
    S" /" PLACE-WRITABLE R> PLACES-DECLARE THROW
    PLSET-NEW THROW >R PLACE-WRITABLE SWAP R@ PLSET-GRANT THROW
    DUP R@ PLSET-HOME!  DUP R@ PLSET-ORIGIN!  R@ PLSET-DOCUMENTS!  R> ;

: _t-root-place  ( vfs name-a name-u -- place )  _t-root-set PLSET-HOME ;

: _t-root-set-free  ( set name-a name-u -- )
    PLACES-VOLUME THROW PVOL-DETACH  PLSET-FREE ;

: _t-default-home  ( vfs name-a name-u -- prior )
    _t-root-set PLACES-DEFAULT SWAP PLACES-DEFAULT! ;

: _t-default-restore  ( prior name-a name-u -- )
    PLACES-DEFAULT -ROT _t-root-set-free  PLACES-DEFAULT! ;
