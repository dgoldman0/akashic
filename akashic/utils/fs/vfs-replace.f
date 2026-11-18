\ =====================================================================
\  vfs-replace.f - Checked, recoverable replacement for VFS files
\ =====================================================================
\  This module protects an existing file while new bytes are staged.  A
\  replacement owns four absolute paths in one directory:
\
\      target       application-visible file
\      stage        fully written and read-back-verified candidate
\      backup       old target while publication is in progress
\      marker       fixed-size, checksummed rollback intent
\
\  A path follows its volume's rules: each name at most as long as the
\  volume takes (VFS-NAME-LIMIT), the whole at most VFS-PATH-MAX bytes.
\  The descriptor keeps the four paths end to end in one block allocated
\  at their lengths, which VREPL-FINI gives back.
\
\  Every replacement recovers, runs the precondition, writes the stage and
\  reads it back.  The filesystem under the target then decides how the
\  stage is published.
\
\  A binding with VFS-CAP-DURABLE-MUTATIONS and VFS-CAP-RENAME-REPLACE, as
\  ext4's staged-write binding has, keeps each completed mutation across a
\  power cut and renames over an existing file as one such mutation.  There
\  the stage is renamed over the target.  That rename is the commit point,
\  and the backup and the marker are never created.
\
\  Any other binding, as MP64FS and the RAM binding, publishes through the
\  marker and the backup.  Barriers (VFS-BARRIER) separate stage, intent,
\  rotation, commit, and cleanup.  A durable marker means recovery rolls
\  back.  Marker removal followed by a successful barrier is the commit
\  point; an orphan backup after that point is cleanup state and the
\  target wins.  This is crash-recoverable ordering over the VFS contract,
\  not a claim of sector-atomic power-loss behavior.  In particular, MP64FS
\  writes cached bitmap and directory regions separately.  Torn/corrupt
\  metadata below the VFS layer can still require filesystem repair.
\
\  One recovery serves both.  Recover/replace hold one VFS-TRANSACTION
\  across all phases, and every phase works on the descriptor's own VFS.
\
\  A replacement marked read-only (VREPL-READ-ONLY!) changes nothing: it
\  refuses to replace, and its recovery only says whether the target as
\  found is the committed file.
\
\  Public API:
\    VREPL-INIT              ( vfs replacement -- status )
\    VREPL-FINI              ( replacement -- status )
\    VREPL-PATHS!            ( ta tu sa su ba bu ma mu repl -- status )
\    VREPL-DERIVE-PATHS!     ( target-a target-u repl -- status )
\    VREPL-PRECONDITION!     ( xt data replacement -- status )
\    VREPL-READ-ONLY!        ( flag replacement -- status )
\    VREPL-RECOVER           ( replacement -- status )
\    VREPL-REPLACE           ( data length replacement -- status )
\
\  The optional precondition has stack effect ( target-inode|0 data --
\  status ).  It runs immediately before staging.  The VFS has no generic
\  per-file revision, so resource owners supply their own revision check.
\  Callers must still serialize all direct writers through the owner.
\  Public RECOVER and REPLACE wipe the read-back verification buffer on
\  normal, status-failure, and exception paths.
\ =====================================================================

PROVIDED akashic-vfs-replace

REQUIRE vfs.f
REQUIRE ../../math/crc.f
REQUIRE ../../math/sha3.f
REQUIRE ../../concurrency/guard.f

\ =====================================================================
\  Status values
\ =====================================================================

0 CONSTANT VREPL-S-OK
1 CONSTANT VREPL-S-ROLLED-BACK
2 CONSTANT VREPL-S-COMMITTED-CLEANUP
3 CONSTANT VREPL-S-INVALID
4 CONSTANT VREPL-S-IO
5 CONSTANT VREPL-S-CONFLICT
6 CONSTANT VREPL-S-BUSY
7 CONSTANT VREPL-S-RECOVERY
8 CONSTANT VREPL-S-MARKER-CORRUPT
9 CONSTANT VREPL-S-UNCERTAIN
10 CONSTANT VREPL-S-READ-ONLY
11 CONSTANT VREPL-S-NOMEM

1 CONSTANT VREPL-F-CONFIGURED
2 CONSTANT VREPL-F-BUSY
4 CONSTANT VREPL-F-READ-ONLY

1 CONSTANT _VREPL-MF-ORIGINAL

\ =====================================================================
\  Descriptor (96 bytes)
\ =====================================================================
\  The four paths share one folder, so each path's final name starts at
\  the same offset, BASE.  They lie end to end in the block PATHS points
\  at: target, stage, backup, marker.

0x565245504C303031 CONSTANT _VREPL-DESC-MAGIC  \ "VREPL001"

  0 CONSTANT _VR-D-MAGIC
  8 CONSTANT _VR-D-VFS
 16 CONSTANT _VR-D-FLAGS
 24 CONSTANT _VR-D-PRE-XT
 32 CONSTANT _VR-D-PRE-DATA
 40 CONSTANT _VR-D-TARGET-LEN
 48 CONSTANT _VR-D-STAGE-LEN
 56 CONSTANT _VR-D-BACKUP-LEN
 64 CONSTANT _VR-D-MARKER-LEN
 72 CONSTANT _VR-D-BASE
 80 CONSTANT _VR-D-LAST-STATUS
 88 CONSTANT _VR-D-PATHS
96 CONSTANT VREPL-SIZE

: VREPL.MAGIC          ( r -- a ) _VR-D-MAGIC + ;
: VREPL.VFS            ( r -- a ) _VR-D-VFS + ;
: VREPL.FLAGS          ( r -- a ) _VR-D-FLAGS + ;
: VREPL.PRE-XT         ( r -- a ) _VR-D-PRE-XT + ;
: VREPL.PRE-DATA       ( r -- a ) _VR-D-PRE-DATA + ;
: VREPL.TARGET-LEN     ( r -- a ) _VR-D-TARGET-LEN + ;
: VREPL.STAGE-LEN      ( r -- a ) _VR-D-STAGE-LEN + ;
: VREPL.BACKUP-LEN     ( r -- a ) _VR-D-BACKUP-LEN + ;
: VREPL.MARKER-LEN     ( r -- a ) _VR-D-MARKER-LEN + ;
: VREPL.BASE           ( r -- a ) _VR-D-BASE + ;
: VREPL.LAST-STATUS    ( r -- a ) _VR-D-LAST-STATUS + ;
: VREPL.PATHS          ( r -- a ) _VR-D-PATHS + ;

: VREPL-TARGET$  ( r -- a u )
    DUP VREPL.PATHS @ SWAP VREPL.TARGET-LEN @ ;

: VREPL-STAGE$  ( r -- a u )
    DUP VREPL-TARGET$ + SWAP VREPL.STAGE-LEN @ ;

: VREPL-BACKUP$  ( r -- a u )
    DUP VREPL-STAGE$ + SWAP VREPL.BACKUP-LEN @ ;

: VREPL-MARKER$  ( r -- a u )
    DUP VREPL-BACKUP$ + SWAP VREPL.MARKER-LEN @ ;

\ The folder of a path whose final name starts at BASE: "/" for the root.
: _VREPL-PARENT-LEN  ( base-offset -- u )
    DUP 1 = IF DROP 1 ELSE 1- THEN ;

\ VREPL-FOLDER$ ( r -- a u )   The folder the four paths are in.
: VREPL-FOLDER$  ( r -- a u )
    DUP VREPL.PATHS @ SWAP VREPL.BASE @ _VREPL-PARENT-LEN ;

\ The final name of one of the descriptor's paths.
: _VREPL-NAME-OF  ( r a u -- a' u' )  ROT VREPL.BASE @ TUCK - >R + R> ;

\ VREPL-TARGET-NAME$ and VREPL-STAGE-NAME$ ( r -- a u )   Final names.
: VREPL-TARGET-NAME$  ( r -- a u )  DUP VREPL-TARGET$ _VREPL-NAME-OF ;
: VREPL-STAGE-NAME$   ( r -- a u )  DUP VREPL-STAGE$ _VREPL-NAME-OF ;

: VREPL-VALID?  ( r -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP VREPL.MAGIC @ _VREPL-DESC-MAGIC =
    SWAP VREPL.VFS @ 0<> AND ;

: VREPL-CONFIGURED?  ( r -- flag )
    DUP VREPL-VALID? 0= IF DROP 0 EXIT THEN
    VREPL.FLAGS @ VREPL-F-CONFIGURED AND 0<> ;

\ =====================================================================
\  Configuration and path validation
\ =====================================================================

GUARD _vrepl-guard

VARIABLE _VRI-VFS
VARIABLE _VRI-R

\ A descriptor that is valid already gives its paths back first, so one
\ descriptor can be pointed at another volume.  Memory that was never a
\ descriptor must not happen to hold one's magic and VFS cell.
: _VREPL-INIT  ( vfs replacement -- status )
    _VRI-R ! _VRI-VFS !
    _VRI-VFS @ 0= _VRI-R @ 0= OR IF VREPL-S-INVALID EXIT THEN
    _VRI-R @ VREPL-VALID? IF
        _VRI-R @ VREPL.FLAGS @ VREPL-F-BUSY AND IF VREPL-S-BUSY EXIT THEN
        _VRI-R @ VREPL.PATHS @ ?DUP IF FREE THEN
    THEN
    _VRI-R @ VREPL-SIZE 0 FILL
    _VREPL-DESC-MAGIC _VRI-R @ VREPL.MAGIC !
    _VRI-VFS @ _VRI-R @ VREPL.VFS !
    VREPL-S-OK ;

: _VREPL-FINI  ( replacement -- status )
    DUP VREPL-VALID? 0= IF DROP VREPL-S-INVALID EXIT THEN
    DUP VREPL.FLAGS @ VREPL-F-BUSY AND IF DROP VREPL-S-BUSY EXIT THEN
    DUP VREPL.PATHS @ ?DUP IF FREE THEN
    VREPL-SIZE 0 FILL
    VREPL-S-OK ;

VARIABLE _VPC-A
VARIABLE _VPC-U
\ The longest name the descriptor's volume takes, read before validation.
VARIABLE _VPV-LIMIT

: _VREPL-LIMIT!  ( replacement -- )
    VREPL.VFS @ VFS-NAME-LIMIT _VPV-LIMIT ! ;

: _VREPL-COMPONENT-VALID?  ( a u -- flag )
    _VPC-U ! _VPC-A !
    _VPC-U @ 0= IF 0 EXIT THEN
    _VPC-U @ _VPV-LIMIT @ > IF 0 EXIT THEN
    _VPC-U @ 1 = IF
        _VPC-A @ C@ [CHAR] . = IF 0 EXIT THEN
    THEN
    _VPC-U @ 2 = IF
        _VPC-A @ C@ [CHAR] . =
        _VPC-A @ 1+ C@ [CHAR] . = AND IF 0 EXIT THEN
    THEN
    -1 ;

VARIABLE _VPV-A
VARIABLE _VPV-U
VARIABLE _VPV-START
VARIABLE _VPV-SPLIT

: _VREPL-PATH-VALID?  ( a u -- base-offset flag )
    _VPV-U ! _VPV-A !
    _VPV-U @ 2 < _VPV-U @ VFS-PATH-MAX > OR IF 0 0 EXIT THEN
    _VPV-A @ C@ [CHAR] / <> IF 0 0 EXIT THEN
    1 _VPV-START ! 0 _VPV-SPLIT !
    _VPV-U @ 1 DO
        _VPV-A @ I + C@ [CHAR] / = IF
            _VPV-A @ _VPV-START @ +
            I _VPV-START @ - _VREPL-COMPONENT-VALID? 0= IF
                0 0 UNLOOP EXIT
            THEN
            I _VPV-SPLIT !
            I 1+ _VPV-START !
        THEN
    LOOP
    _VPV-A @ _VPV-START @ +
    _VPV-U @ _VPV-START @ - _VREPL-COMPONENT-VALID? 0= IF
        0 0 EXIT
    THEN
    _VPV-SPLIT @ 1+ -1 ;

VARIABLE _VPP-TA
VARIABLE _VPP-TU
VARIABLE _VPP-SA
VARIABLE _VPP-SU
VARIABLE _VPP-BA
VARIABLE _VPP-BU
VARIABLE _VPP-MA
VARIABLE _VPP-MU
VARIABLE _VPP-R
VARIABLE _VPP-TBASE
VARIABLE _VPP-SBASE
VARIABLE _VPP-BBASE
VARIABLE _VPP-MBASE
VARIABLE _VPP-PLEN

\ The companions' final names, which _VREPL-INSTALL puts in the
\ target's folder.
VARIABLE _VIN-SA   VARIABLE _VIN-SU
VARIABLE _VIN-BA   VARIABLE _VIN-BU
VARIABLE _VIN-MA   VARIABLE _VIN-MU
VARIABLE _VIN-AT

: _VREPL-PUT  ( a u -- )  >R _VIN-AT @ R@ CMOVE  R> _VIN-AT +! ;

\ The target's folder with its slash, which leads each companion path.
: _VREPL-PUT-FOLDER  ( -- )  _VPP-TA @ _VPP-TBASE @ _VREPL-PUT ;

\ _VREPL-INSTALL ( -- status )
\   Give the descriptor _VPP-R the target _VPP-TA/_VPP-TU, whose final
\   name starts at _VPP-TBASE, and the three companions named in _VIN-*,
\   each in the target's folder.  The paths go into a new block sized to
\   them, written before the block the descriptor held is given back, so
\   the target may lie in that old block.
: _VREPL-INSTALL  ( -- status )
    _VPP-TU @ _VPP-TBASE @ 3 * +
    _VIN-SU @ + _VIN-BU @ + _VIN-MU @ +
    ALLOCATE IF DROP VREPL-S-NOMEM EXIT THEN
    DUP _VIN-AT !                                   ( block )
    _VPP-TA @ _VPP-TU @ _VREPL-PUT
    _VREPL-PUT-FOLDER  _VIN-SA @ _VIN-SU @ _VREPL-PUT
    _VREPL-PUT-FOLDER  _VIN-BA @ _VIN-BU @ _VREPL-PUT
    _VREPL-PUT-FOLDER  _VIN-MA @ _VIN-MU @ _VREPL-PUT
    _VPP-R @ VREPL.PATHS @ ?DUP IF FREE THEN
    _VPP-R @ VREPL.PATHS !
    _VPP-TU @ _VPP-R @ VREPL.TARGET-LEN !
    _VPP-TBASE @ _VIN-SU @ + _VPP-R @ VREPL.STAGE-LEN !
    _VPP-TBASE @ _VIN-BU @ + _VPP-R @ VREPL.BACKUP-LEN !
    _VPP-TBASE @ _VIN-MU @ + _VPP-R @ VREPL.MARKER-LEN !
    _VPP-TBASE @ _VPP-R @ VREPL.BASE !
    _VPP-R @ VREPL.FLAGS @ VREPL-F-CONFIGURED OR
    _VPP-R @ VREPL.FLAGS !
    VREPL-S-OK ;

: _VREPL-SAME-PARENT?  ( a u base-offset -- flag )
    _VREPL-PARENT-LEN
    DUP _VPP-PLEN @ <> IF DROP 2DROP 0 EXIT THEN
    SWAP DROP _VPP-TA @ _VPP-PLEN @ COMPARE 0= ;

: _VREPL-SAME-PATH?  ( a1 u1 a2 u2 -- flag )
    COMPARE 0= ;

\ The descriptor may be configured: it is valid and no operation runs.
: _VREPL-CONFIGURABLE  ( replacement -- status )
    DUP VREPL-VALID? 0= IF DROP VREPL-S-INVALID EXIT THEN
    VREPL.FLAGS @ VREPL-F-BUSY AND IF VREPL-S-BUSY EXIT THEN
    VREPL-S-OK ;

: _VREPL-PATHS!  ( ta tu sa su ba bu ma mu repl -- status )
    _VPP-R ! _VPP-MU ! _VPP-MA ! _VPP-BU ! _VPP-BA !
    _VPP-SU ! _VPP-SA ! _VPP-TU ! _VPP-TA !
    _VPP-R @ _VREPL-CONFIGURABLE ?DUP IF EXIT THEN
    _VPP-R @ _VREPL-LIMIT!
    _VPP-TA @ _VPP-TU @ _VREPL-PATH-VALID? 0= IF
        DROP VREPL-S-INVALID EXIT
    THEN _VPP-TBASE !
    _VPP-SA @ _VPP-SU @ _VREPL-PATH-VALID? 0= IF
        DROP VREPL-S-INVALID EXIT
    THEN _VPP-SBASE !
    _VPP-BA @ _VPP-BU @ _VREPL-PATH-VALID? 0= IF
        DROP VREPL-S-INVALID EXIT
    THEN _VPP-BBASE !
    _VPP-MA @ _VPP-MU @ _VREPL-PATH-VALID? 0= IF
        DROP VREPL-S-INVALID EXIT
    THEN _VPP-MBASE !
    _VPP-TBASE @ _VREPL-PARENT-LEN _VPP-PLEN !
    _VPP-SA @ _VPP-SU @ _VPP-SBASE @ _VREPL-SAME-PARENT? 0= IF
        VREPL-S-INVALID EXIT
    THEN
    _VPP-BA @ _VPP-BU @ _VPP-BBASE @ _VREPL-SAME-PARENT? 0= IF
        VREPL-S-INVALID EXIT
    THEN
    _VPP-MA @ _VPP-MU @ _VPP-MBASE @ _VREPL-SAME-PARENT? 0= IF
        VREPL-S-INVALID EXIT
    THEN
    _VPP-TA @ _VPP-TU @ _VPP-SA @ _VPP-SU @ _VREPL-SAME-PATH? IF
        VREPL-S-INVALID EXIT
    THEN
    _VPP-TA @ _VPP-TU @ _VPP-BA @ _VPP-BU @ _VREPL-SAME-PATH? IF
        VREPL-S-INVALID EXIT
    THEN
    _VPP-TA @ _VPP-TU @ _VPP-MA @ _VPP-MU @ _VREPL-SAME-PATH? IF
        VREPL-S-INVALID EXIT
    THEN
    _VPP-SA @ _VPP-SU @ _VPP-BA @ _VPP-BU @ _VREPL-SAME-PATH? IF
        VREPL-S-INVALID EXIT
    THEN
    _VPP-SA @ _VPP-SU @ _VPP-MA @ _VPP-MU @ _VREPL-SAME-PATH? IF
        VREPL-S-INVALID EXIT
    THEN
    _VPP-BA @ _VPP-BU @ _VPP-MA @ _VPP-MU @ _VREPL-SAME-PATH? IF
        VREPL-S-INVALID EXIT
    THEN
    _VPP-SA @ _VPP-SBASE @ + _VIN-SA !  _VPP-SU @ _VPP-SBASE @ - _VIN-SU !
    _VPP-BA @ _VPP-BBASE @ + _VIN-BA !  _VPP-BU @ _VPP-BBASE @ - _VIN-BU !
    _VPP-MA @ _VPP-MBASE @ + _VIN-MA !  _VPP-MU @ _VPP-MBASE @ - _VIN-MU !
    _VREPL-INSTALL ;

\ Derive MP64FS-safe companion components from SHA3-256(full target path).
\ The reserved names are exactly 23 bytes and carry 100 digest bits:
\
\     .s-<20 base32 chars>   stage
\     .b-<20 base32 chars>   backup
\     .m-<20 base32 chars>   marker
\
\ Keeping companions independent of target basename length avoids suffix
\ overflow and makes recovery stable across descriptor re-instantiation.
\ Every volume takes names of 23 bytes.

23 CONSTANT VREPL-DERIVED-NAME-LEN

CREATE _VDP-NAMES VREPL-DERIVED-NAME-LEN 3 * ALLOT
CREATE _VDP-DIGEST SHA3-256-LEN ALLOT

\ RFC 4648 lowercase alphabet.  Twenty symbols encode the first 100 bits.
CREATE _VDP-B32
  97 C, 98 C, 99 C, 100 C, 101 C, 102 C, 103 C, 104 C,
  105 C, 106 C, 107 C, 108 C, 109 C, 110 C, 111 C, 112 C,
  113 C, 114 C, 115 C, 116 C, 117 C, 118 C, 119 C, 120 C,
  121 C, 122 C, 50 C, 51 C, 52 C, 53 C, 54 C, 55 C,

VARIABLE _VDP-B32-SRC
VARIABLE _VDP-B32-DST
VARIABLE _VDP-B32-ACC
VARIABLE _VDP-B32-BITS
VARIABLE _VDP-B32-INDEX
VARIABLE _VDP-PREFIX

: _VREPL-DERIVE-BASE32  ( digest destination -- )
    _VDP-B32-DST ! _VDP-B32-SRC !
    0 _VDP-B32-ACC ! 0 _VDP-B32-BITS ! 0 _VDP-B32-INDEX !
    20 0 DO
        BEGIN _VDP-B32-BITS @ 5 < WHILE
            _VDP-B32-ACC @ 8 LSHIFT
            _VDP-B32-SRC @ _VDP-B32-INDEX @ + C@ OR
            _VDP-B32-ACC !
            1 _VDP-B32-INDEX +! 8 _VDP-B32-BITS +!
        REPEAT
        _VDP-B32-ACC @ _VDP-B32-BITS @ 5 - RSHIFT 31 AND
        _VDP-B32 + C@ _VDP-B32-DST @ I + C!
        -5 _VDP-B32-BITS +!
    LOOP ;

: _VREPL-DERIVED-PREFIX?  ( component-a -- flag )
    _VDP-PREFIX !
    _VDP-PREFIX @ C@ [CHAR] . <> IF 0 EXIT THEN
    _VDP-PREFIX @ 2 + C@ [CHAR] - <> IF 0 EXIT THEN
    _VDP-PREFIX @ 1+ C@ [CHAR] s =
    _VDP-PREFIX @ 1+ C@ [CHAR] b = OR
    _VDP-PREFIX @ 1+ C@ [CHAR] m = OR ;

\ _VREPL-DERIVE-NAME ( role index -- a u )
\   The INDEXth derived name, for the role letter ROLE, from the digest.
: _VREPL-DERIVE-NAME  ( role index -- a u )
    VREPL-DERIVED-NAME-LEN * _VDP-NAMES + >R
    46 R@ C!  R@ 1+ C!  45 R@ 2 + C!          \ .<role>-
    _VDP-DIGEST R@ 3 + _VREPL-DERIVE-BASE32
    R> VREPL-DERIVED-NAME-LEN ;

: _VREPL-DERIVE-PATHS!  ( target-a target-u replacement -- status )
    _VPP-R ! _VPP-TU ! _VPP-TA !
    _VPP-R @ _VREPL-CONFIGURABLE ?DUP IF EXIT THEN
    _VPP-R @ _VREPL-LIMIT!
    _VPP-TA @ _VPP-TU @ _VREPL-PATH-VALID? 0= IF
        DROP VREPL-S-INVALID EXIT
    THEN _VPP-TBASE !
    _VPP-TBASE @ VREPL-DERIVED-NAME-LEN + VFS-PATH-MAX > IF
        VREPL-S-INVALID EXIT
    THEN
    VREPL-DERIVED-NAME-LEN _VPV-LIMIT @ > IF VREPL-S-INVALID EXIT THEN
    \ The three role prefixes are a reserved same-directory transaction
    \ namespace.  A target there could masquerade as a companion.
    _VPP-TU @ _VPP-TBASE @ - 3 >= IF
        _VPP-TA @ _VPP-TBASE @ + _VREPL-DERIVED-PREFIX? IF
            VREPL-S-INVALID EXIT
        THEN
    THEN
    _VPP-TA @ _VPP-TU @ _VDP-DIGEST SHA3-256-HASH
    115 0 _VREPL-DERIVE-NAME _VIN-SU ! _VIN-SA !
    98  1 _VREPL-DERIVE-NAME _VIN-BU ! _VIN-BA !
    109 2 _VREPL-DERIVE-NAME _VIN-MU ! _VIN-MA !
    _VREPL-INSTALL ;

VARIABLE _VRPRE-XT
VARIABLE _VRPRE-DATA
VARIABLE _VRPRE-R

: _VREPL-PRECONDITION!  ( xt data replacement -- status )
    _VRPRE-R ! _VRPRE-DATA ! _VRPRE-XT !
    _VRPRE-R @ _VREPL-CONFIGURABLE ?DUP IF EXIT THEN
    _VRPRE-XT @ _VRPRE-R @ VREPL.PRE-XT !
    _VRPRE-DATA @ _VRPRE-R @ VREPL.PRE-DATA !
    VREPL-S-OK ;

: _VREPL-READ-ONLY!  ( flag replacement -- status )
    DUP _VREPL-CONFIGURABLE ?DUP IF NIP NIP EXIT THEN
    VREPL.FLAGS SWAP IF
        DUP @ VREPL-F-READ-ONLY OR
    ELSE
        DUP @ VREPL-F-READ-ONLY INVERT AND
    THEN SWAP !
    VREPL-S-OK ;

\ =====================================================================
\  Serialized operation helpers
\ =====================================================================

VARIABLE _VRO-R
VARIABLE _VRO-DATA
VARIABLE _VRO-LEN
VARIABLE _VRO-ORIGINAL
VARIABLE _VRO-MUTATED

: _VRO-VFS  ( -- vfs ) _VRO-R @ VREPL.VFS @ ;

: _VRO-READ-ONLY?  ( -- flag )
    _VRO-R @ VREPL.FLAGS @ VREPL-F-READ-ONLY AND 0<> ;

: _VRO-RESOLVE-NOFOLLOW  ( path-a path-u -- inode|0 )
    VFS-RP-NOFOLLOW-FINAL _VRO-VFS VFS-RESOLVE-POLICY?
    DUP IF
        DUP VFS-IOR-REASON VFS-R-NOENT = IF 2DROP 0 EXIT THEN
        NIP THROW
    THEN DROP
    DUP IF
        DUP IN.TYPE @ VFS-T-FILE <> IF DROP VFS-E-CORRUPT THROW THEN
    THEN ;

: _VRO-TARGET?  ( -- inode|0 )
    _VRO-R @ VREPL-TARGET$ _VRO-RESOLVE-NOFOLLOW ;

: _VRO-STAGE?  ( -- inode|0 )
    _VRO-R @ VREPL-STAGE$ _VRO-RESOLVE-NOFOLLOW ;

: _VRO-BACKUP?  ( -- inode|0 )
    _VRO-R @ VREPL-BACKUP$ _VRO-RESOLVE-NOFOLLOW ;

: _VRO-MARKER?  ( -- inode|0 )
    _VRO-R @ VREPL-MARKER$ _VRO-RESOLVE-NOFOLLOW ;

\ A missing reserved leaf is valid state only after its shared lexical parent
\ resolves to a directory.  Intermediate links retain ordinary VFS traversal
\ semantics; only a transaction role's terminal name is never followed.
: _VRO-PARENT-VALID?  ( -- flag )
    _VRO-R @ VREPL-FOLDER$
    VFS-RP-FOLLOW-FINAL _VRO-VFS VFS-RESOLVE-POLICY?
    IF DROP 0 EXIT THEN
    DUP 0= IF DROP 0 EXIT THEN
    IN.TYPE @ VFS-T-DIR = ;

: _VRO-REGULAR-OR-ABSENT?  ( path-a path-u -- flag )
    _VRO-RESOLVE-NOFOLLOW
    DUP 0= IF DROP -1 EXIT THEN
    IN.TYPE @ VFS-T-FILE = ;

: _VRO-NAMESPACE-VALID?  ( -- flag )
    _VRO-PARENT-VALID? 0= IF 0 EXIT THEN
    _VRO-R @ VREPL-TARGET$ _VRO-REGULAR-OR-ABSENT? 0= IF 0 EXIT THEN
    _VRO-R @ VREPL-STAGE$ _VRO-REGULAR-OR-ABSENT? 0= IF 0 EXIT THEN
    _VRO-R @ VREPL-BACKUP$ _VRO-REGULAR-OR-ABSENT? 0= IF 0 EXIT THEN
    _VRO-R @ VREPL-MARKER$ _VRO-REGULAR-OR-ABSENT? ;

: _VRO-TARGET-NAME$  ( -- a u )  _VRO-R @ VREPL-TARGET-NAME$ ;

: _VRO-BACKUP-NAME$  ( -- a u )
    _VRO-R @ DUP VREPL-BACKUP$ _VREPL-NAME-OF ;

VARIABLE _VRPL-RN-IN
VARIABLE _VRPL-RN-FLAGS

: _VRO-TARGET>BACKUP  ( -- ior )
    _VRO-TARGET? DUP 0= IF DROP -1 EXIT THEN _VRPL-RN-IN !
    _VRO-BACKUP-NAME$ _VRPL-RN-IN @ _VRO-VFS VFS-RENAME ;

: _VRO-BACKUP>TARGET  ( -- ior )
    _VRO-BACKUP? DUP 0= IF DROP -1 EXIT THEN _VRPL-RN-IN !
    _VRO-TARGET-NAME$ _VRPL-RN-IN @ _VRO-VFS VFS-RENAME ;

\ Give the stage the target's name.  Under VFS-RN-NOREPLACE a name that is
\ still held refuses the rename; without the flag the rename takes the
\ holder as its victim.
: _VRO-STAGE-RENAME  ( flags -- ior )
    _VRPL-RN-FLAGS !
    _VRO-STAGE? DUP 0= IF DROP -1 EXIT THEN _VRPL-RN-IN !
    _VRO-TARGET-NAME$ _VRPL-RN-IN @ DUP IN.PARENT @
    _VRPL-RN-FLAGS @ _VRO-VFS VFS-RENAME-AT ;

: _VRO-STAGE>TARGET  ( -- ior )
    VFS-RN-NOREPLACE _VRO-STAGE-RENAME ;

: _VRO-STAGE-OVER-TARGET  ( -- ior )
    0 _VRO-STAGE-RENAME ;

: _VRO-RM-TARGET  ( -- ior )
    _VRO-R @ VREPL-TARGET$ _VRO-VFS VFS-RM ;

: _VRO-RM-STAGE  ( -- ior )
    _VRO-R @ VREPL-STAGE$ _VRO-VFS VFS-RM ;

: _VRO-RM-BACKUP  ( -- ior )
    _VRO-R @ VREPL-BACKUP$ _VRO-VFS VFS-RM ;

: _VRO-RM-MARKER  ( -- ior )
    _VRO-R @ VREPL-MARKER$ _VRO-VFS VFS-RM ;

\ =====================================================================
\  Exact file creation and read-back verification
\ =====================================================================

VARIABLE _VRW-A
VARIABLE _VRW-U
VARIABLE _VRW-PA
VARIABLE _VRW-PU
VARIABLE _VRW-FD

: _VREPL-CREATE-WRITE  ( data len path-a path-u -- status )
    _VRW-PU ! _VRW-PA ! _VRW-U ! _VRW-A !
    _VRW-PA @ _VRW-PU @ _VRO-VFS VFS-CREATE DUP 0= IF
        DROP VREPL-S-IO EXIT
    THEN DROP
    _VRW-PA @ _VRW-PU @ _VRO-VFS VFS-OPEN DUP _VRW-FD ! 0= IF
        _VRW-PA @ _VRW-PU @ _VRO-VFS VFS-RM DROP
        VREPL-S-IO EXIT
    THEN
    _VRW-A @ _VRW-U @ _VRW-FD @ VFS-WRITE-EXACT IF
        _VRW-FD @ VFS-CLOSE
        _VRW-PA @ _VRW-PU @ _VRO-VFS VFS-RM DROP
        VREPL-S-IO EXIT
    THEN
    _VRW-FD @ VFS-SIZE _VRW-U @ <> IF
        _VRW-FD @ VFS-CLOSE
        _VRW-PA @ _VRW-PU @ _VRO-VFS VFS-RM DROP
        VREPL-S-IO EXIT
    THEN
    _VRW-FD @ VFS-CLOSE
    VREPL-S-OK ;

1024 CONSTANT _VREPL-CHECK-SIZE
CREATE _VREPL-CHECK-BUFFER _VREPL-CHECK-SIZE ALLOT

VARIABLE _VRV-A
VARIABLE _VRV-U
VARIABLE _VRV-PA
VARIABLE _VRV-PU
VARIABLE _VRV-FD
VARIABLE _VRV-POS
VARIABLE _VRV-REM
VARIABLE _VRV-WANT

: _VREPL-VERIFY-FILE  ( data len path-a path-u -- status )
    _VRV-PU ! _VRV-PA ! _VRV-U ! _VRV-A !
    _VRV-PA @ _VRV-PU @ _VRO-VFS VFS-OPEN DUP _VRV-FD ! 0= IF
        VREPL-S-IO EXIT
    THEN
    _VRV-FD @ VFS-SIZE _VRV-U @ <> IF
        _VRV-FD @ VFS-CLOSE VREPL-S-IO EXIT
    THEN
    0 _VRV-POS ! _VRV-U @ _VRV-REM !
    BEGIN _VRV-REM @ 0> WHILE
        _VRV-REM @ _VREPL-CHECK-SIZE MIN DUP _VRV-WANT !
        _VREPL-CHECK-BUFFER SWAP _VRV-FD @ VFS-READ-EXACT IF
            _VRV-FD @ VFS-CLOSE VREPL-S-IO EXIT
        THEN
        _VREPL-CHECK-BUFFER _VRV-WANT @
        _VRV-A @ _VRV-POS @ + _VRV-WANT @ COMPARE 0<> IF
            _VRV-FD @ VFS-CLOSE VREPL-S-IO EXIT
        THEN
        _VRV-WANT @ _VRV-POS +!
        _VRV-WANT @ NEGATE _VRV-REM +!
    REPEAT
    _VRV-FD @ VFS-CLOSE
    VREPL-S-OK ;

\ =====================================================================
\  Durable rollback marker
\ =====================================================================

2  CONSTANT _VREPL-MARKER-FORMAT
64 CONSTANT _VREPL-MARKER-SIZE
16 CONSTANT _VREPL-MARKER-TARGET-HASH-SIZE

 0 CONSTANT _VR-M-MAGIC
 8 CONSTANT _VR-M-FORMAT
16 CONSTANT _VR-M-FLAGS
24 CONSTANT _VR-M-DATA-LEN
32 CONSTANT _VR-M-DATA-CRC
40 CONSTANT _VR-M-TARGET-HASH
56 CONSTANT _VR-M-RECORD-CRC

CREATE _VREPL-MARKER-MAGIC
65 C, 75 C, 86 C, 82 C, 80 C, 48 C, 48 C, 49 C,  \ "AKVRP001"

CREATE _VREPL-MARKER-BUFFER _VREPL-MARKER-SIZE ALLOT
CREATE _VREPL-TARGET-HASH SHA3-256-LEN ALLOT

: _VREPL-ENCODE-MARKER  ( -- )
    _VREPL-MARKER-BUFFER _VREPL-MARKER-SIZE 0 FILL
    _VREPL-MARKER-MAGIC
    _VREPL-MARKER-BUFFER _VR-M-MAGIC + 8 CMOVE
    _VREPL-MARKER-FORMAT
    _VREPL-MARKER-BUFFER _VR-M-FORMAT + !
    _VRO-ORIGINAL @ IF _VREPL-MF-ORIGINAL ELSE 0 THEN
    _VREPL-MARKER-BUFFER _VR-M-FLAGS + !
    _VRO-LEN @ _VREPL-MARKER-BUFFER _VR-M-DATA-LEN + !
    _VRO-DATA @ _VRO-LEN @ CRC32
    _VREPL-MARKER-BUFFER _VR-M-DATA-CRC + !
    _VRO-R @ VREPL-TARGET$ _VREPL-TARGET-HASH SHA3-256-HASH
    _VREPL-TARGET-HASH
    _VREPL-MARKER-BUFFER _VR-M-TARGET-HASH +
    _VREPL-MARKER-TARGET-HASH-SIZE CMOVE
    _VREPL-MARKER-BUFFER _VR-M-RECORD-CRC CRC32
    _VREPL-MARKER-BUFFER _VR-M-RECORD-CRC + ! ;

: _VREPL-DECODE-MARKER  ( -- status )
    _VREPL-MARKER-BUFFER _VR-M-MAGIC + 8
    _VREPL-MARKER-MAGIC 8 COMPARE 0<> IF
        VREPL-S-MARKER-CORRUPT EXIT
    THEN
    _VREPL-MARKER-BUFFER _VR-M-FORMAT + @
        _VREPL-MARKER-FORMAT <>
    _VREPL-MARKER-BUFFER _VR-M-FLAGS + @
        _VREPL-MF-ORIGINAL INVERT AND 0<> OR
    _VREPL-MARKER-BUFFER _VR-M-DATA-LEN + @ 0< OR IF
        VREPL-S-MARKER-CORRUPT EXIT
    THEN
    _VRO-R @ VREPL-TARGET$ _VREPL-TARGET-HASH SHA3-256-HASH
    _VREPL-TARGET-HASH _VREPL-MARKER-TARGET-HASH-SIZE
    _VREPL-MARKER-BUFFER _VR-M-TARGET-HASH +
    _VREPL-MARKER-TARGET-HASH-SIZE COMPARE 0<> IF
        VREPL-S-MARKER-CORRUPT EXIT
    THEN
    _VREPL-MARKER-BUFFER _VR-M-RECORD-CRC CRC32
    _VREPL-MARKER-BUFFER _VR-M-RECORD-CRC + @ <> IF
        VREPL-S-MARKER-CORRUPT EXIT
    THEN
    _VREPL-MARKER-BUFFER _VR-M-FLAGS + @
        _VREPL-MF-ORIGINAL AND 0<> _VRO-ORIGINAL !
    VREPL-S-OK ;

VARIABLE _VRM-FD

: _VREPL-READ-MARKER  ( -- status )
    _VRO-R @ VREPL-MARKER$ _VRO-VFS VFS-OPEN DUP _VRM-FD ! 0= IF
        VREPL-S-IO EXIT
    THEN
    _VRM-FD @ VFS-SIZE _VREPL-MARKER-SIZE <> IF
        _VRM-FD @ VFS-CLOSE VREPL-S-MARKER-CORRUPT EXIT
    THEN
    _VREPL-MARKER-BUFFER _VREPL-MARKER-SIZE
    _VRM-FD @ VFS-READ-EXACT IF
        _VRM-FD @ VFS-CLOSE VREPL-S-MARKER-CORRUPT EXIT
    THEN
    _VRM-FD @ VFS-CLOSE
    _VREPL-DECODE-MARKER ;

: _VREPL-WRITE-MARKER  ( -- status )
    _VREPL-ENCODE-MARKER
    _VREPL-MARKER-BUFFER _VREPL-MARKER-SIZE
    _VRO-R @ VREPL-MARKER$ _VREPL-CREATE-WRITE DUP IF EXIT THEN
    DROP
    _VREPL-MARKER-BUFFER _VREPL-MARKER-SIZE
    _VRO-R @ VREPL-MARKER$ _VREPL-VERIFY-FILE ;

\ =====================================================================
\  Recovery state machine
\ =====================================================================

\ What the filesystem under the target promises about a power cut.  With
\ VFS-CAP-DURABLE-MUTATIONS each completed mutation is already on the
\ medium, so the barrier between two steps (VFS-BARRIER) needs no sync.
\ With VFS-CAP-RENAME-REPLACE as well, a rename over the target is one
\ such mutation and can publish the stage by itself.
: _VRO-RENAME-PUBLISHES?  ( -- flag )
    _VRO-VFS VFS-CAPS@
    DUP VFS-CAP-DURABLE-MUTATIONS AND 0<>
    SWAP VFS-CAP-RENAME-REPLACE AND 0<> AND ;

: _VRO-SYNC  ( -- status )
    _VRO-VFS VFS-BARRIER IF VREPL-S-IO ELSE VREPL-S-OK THEN ;

: _VRO-REMOVE-STAGE?  ( -- status )
    _VRO-STAGE? IF
        _VRO-RM-STAGE IF VREPL-S-IO EXIT THEN
        -1 _VRO-MUTATED !
    THEN VREPL-S-OK ;

: _VRO-REMOVE-BACKUP?  ( -- status )
    _VRO-BACKUP? IF
        _VRO-RM-BACKUP IF VREPL-S-IO EXIT THEN
        -1 _VRO-MUTATED !
    THEN VREPL-S-OK ;

: _VRO-REMOVE-MARKER?  ( -- status )
    _VRO-MARKER? IF
        _VRO-RM-MARKER IF VREPL-S-IO EXIT THEN
        -1 _VRO-MUTATED !
    THEN VREPL-S-OK ;

: _VREPL-RECOVER-MARKED-ORIGINAL  ( -- status )
    _VRO-BACKUP? IF
        _VRO-TARGET? IF
            _VRO-RM-TARGET IF VREPL-S-RECOVERY EXIT THEN
        THEN
        _VRO-BACKUP>TARGET IF VREPL-S-RECOVERY EXIT THEN
        _VRO-REMOVE-STAGE? DUP IF
            DROP VREPL-S-RECOVERY EXIT
        THEN DROP
        _VRO-REMOVE-MARKER? DUP IF
            DROP VREPL-S-RECOVERY EXIT
        THEN DROP
        _VRO-SYNC IF VREPL-S-RECOVERY ELSE VREPL-S-ROLLED-BACK THEN
        EXIT
    THEN
    \ Without a backup, rollback is provable only before rotation:
    \ both the original target and the verified stage still exist.
    _VRO-TARGET? 0= IF VREPL-S-RECOVERY EXIT THEN
    _VRO-STAGE? 0= IF VREPL-S-RECOVERY EXIT THEN
    _VRO-REMOVE-STAGE? DUP IF DROP VREPL-S-RECOVERY EXIT THEN DROP
    _VRO-REMOVE-MARKER? DUP IF DROP VREPL-S-RECOVERY EXIT THEN DROP
    _VRO-SYNC IF VREPL-S-RECOVERY ELSE VREPL-S-ROLLED-BACK THEN ;

: _VREPL-RECOVER-MARKED-ABSENT  ( -- status )
    \ A backup is impossible when the pre-transaction target was absent.
    \ Preserve it for manual inspection instead of guessing.
    _VRO-BACKUP? IF VREPL-S-RECOVERY EXIT THEN
    _VRO-TARGET? IF
        _VRO-RM-TARGET IF VREPL-S-RECOVERY EXIT THEN
    THEN
    _VRO-REMOVE-STAGE? DUP IF DROP VREPL-S-RECOVERY EXIT THEN DROP
    _VRO-REMOVE-MARKER? DUP IF DROP VREPL-S-RECOVERY EXIT THEN DROP
    _VRO-SYNC IF VREPL-S-RECOVERY ELSE VREPL-S-ROLLED-BACK THEN ;

: _VREPL-RECOVER-MARKED  ( -- status )
    _VREPL-READ-MARKER DUP IF EXIT THEN DROP
    _VRO-ORIGINAL @ IF
        _VREPL-RECOVER-MARKED-ORIGINAL
    ELSE
        _VREPL-RECOVER-MARKED-ABSENT
    THEN ;

: _VREPL-RECOVER-UNMARKED  ( -- status )
    0 _VRO-MUTATED !
    _VRO-TARGET? IF
        \ No marker means a visible target is committed.  Companions are
        \ stale cleanup only; target always wins.
        _VRO-REMOVE-STAGE? DUP IF EXIT THEN DROP
        _VRO-REMOVE-BACKUP? DUP IF EXIT THEN DROP
        _VRO-MUTATED @ IF
            _VRO-SYNC IF VREPL-S-IO EXIT THEN
        THEN
        VREPL-S-OK EXIT
    THEN
    _VRO-BACKUP? IF
        \ Target vanished before the marker was durable or after an
        \ interrupted cleanup.  A known-good backup is the safest result.
        _VRO-BACKUP>TARGET IF VREPL-S-RECOVERY EXIT THEN
        _VRO-REMOVE-STAGE? DUP IF EXIT THEN DROP
        _VRO-SYNC IF VREPL-S-RECOVERY ELSE VREPL-S-ROLLED-BACK THEN
        EXIT
    THEN
    \ Neither target nor backup.  A stage here was written for a target
    \ that did not exist and was cut off before either publication moved
    \ it, so the absence stands and the stage goes.
    _VRO-REMOVE-STAGE? DUP IF EXIT THEN DROP
    _VRO-MUTATED @ IF
        _VRO-SYNC IF VREPL-S-IO EXIT THEN
    THEN
    VREPL-S-OK ;

\ A read-only replacement changes nothing.  The target as found is the
\ committed file, or the committed absence of one, unless a save was cut
\ off where only a change settles it: a marker stands, or a backup stands
\ in place of a missing target.  Those answer VREPL-S-READ-ONLY.  Stale
\ companions beside a committed target stay where they are.
: _VREPL-RECOVER-READ-ONLY  ( -- status )
    _VRO-NAMESPACE-VALID? 0= IF VREPL-S-RECOVERY EXIT THEN
    _VRO-MARKER? IF VREPL-S-READ-ONLY EXIT THEN
    _VRO-TARGET? 0= _VRO-BACKUP? 0<> AND IF VREPL-S-READ-ONLY EXIT THEN
    VREPL-S-OK ;

: _VREPL-RECOVER-BODY  ( -- status )
    _VRO-READ-ONLY? IF _VREPL-RECOVER-READ-ONLY EXIT THEN
    _VRO-NAMESPACE-VALID? 0= IF VREPL-S-RECOVERY EXIT THEN
    _VRO-MARKER? IF
        _VREPL-RECOVER-MARKED
    ELSE
        _VREPL-RECOVER-UNMARKED
    THEN ;

\ =====================================================================
\  Replacement transaction
\ =====================================================================

: _VREPL-CALL-PRECHECK  ( -- status )
    _VRO-TARGET? _VRO-R @ VREPL.PRE-DATA @
    _VRO-R @ VREPL.PRE-XT @ EXECUTE ;

: _VREPL-PRECHECK  ( -- status )
    _VRO-R @ VREPL.PRE-XT @ 0= IF VREPL-S-OK EXIT THEN
    \ Keep callback arguments inside a no-input wrapper.  If it throws,
    \ CATCH restores the wrapper's empty input stack rather than leaking the
    \ borrowed inode and owner data into the replacement caller.
    ['] _VREPL-CALL-PRECHECK CATCH
    DUP IF DROP VREPL-S-CONFLICT EXIT THEN
    DROP DUP IF DROP VREPL-S-CONFLICT ELSE DROP VREPL-S-OK THEN ;

: _VREPL-ROLLBACK-IO  ( -- status )
    _VREPL-RECOVER-BODY DUP VREPL-S-OK =
    OVER VREPL-S-ROLLED-BACK = OR IF
        DROP VREPL-S-IO
    ELSE
        DROP VREPL-S-RECOVERY
    THEN ;

\ Publish by one rename.  The rename of the verified stage over the target
\ is the commit point: a power cut before it leaves the old target and a
\ stage that recovery removes, and one after it leaves the new target and
\ no companion.  A refused rename has changed nothing, so recovery removes
\ the stage and the old target stands.
: _VREPL-PUBLISH-RENAME  ( -- status )
    _VRO-STAGE-OVER-TARGET IF _VREPL-ROLLBACK-IO EXIT THEN
    VREPL-S-OK ;

\ Publish through the marker and the backup, for a filesystem that does not
\ keep a rename whole across a power cut.
: _VREPL-PUBLISH-MARKED  ( -- status )
    \ A checksummed, synced marker makes all following states rollback
    \ states until marker removal itself has been synced.
    _VREPL-WRITE-MARKER DUP IF
        DROP _VRO-RM-STAGE DROP _VRO-SYNC DROP VREPL-S-IO EXIT
    THEN DROP
    _VRO-SYNC IF _VREPL-ROLLBACK-IO EXIT THEN

    _VRO-ORIGINAL @ IF
        _VRO-TARGET>BACKUP IF _VREPL-ROLLBACK-IO EXIT THEN
        _VRO-SYNC IF _VREPL-ROLLBACK-IO EXIT THEN
    THEN
    _VRO-STAGE>TARGET IF _VREPL-ROLLBACK-IO EXIT THEN
    _VRO-SYNC IF _VREPL-ROLLBACK-IO EXIT THEN

    \ Publication commit point.
    _VRO-RM-MARKER IF _VREPL-ROLLBACK-IO EXIT THEN
    _VRO-SYNC IF
        \ The marker removal may or may not be durable.  Do not guess and
        \ do not delete the known-good backup.
        VREPL-S-UNCERTAIN EXIT
    THEN

    _VRO-ORIGINAL @ IF
        _VRO-RM-BACKUP IF VREPL-S-COMMITTED-CLEANUP EXIT THEN
        _VRO-SYNC IF VREPL-S-COMMITTED-CLEANUP EXIT THEN
    THEN
    VREPL-S-OK ;

: _VREPL-REPLACE-BODY  ( -- status )
    _VRO-READ-ONLY? IF VREPL-S-READ-ONLY EXIT THEN
    _VREPL-RECOVER-BODY DUP VREPL-S-OK <>
    OVER VREPL-S-ROLLED-BACK <> AND IF EXIT THEN DROP
    _VREPL-PRECHECK DUP IF EXIT THEN DROP
    _VRO-TARGET? 0<> _VRO-ORIGINAL !

    \ Stage and verify every byte before the target can move.
    _VRO-DATA @ _VRO-LEN @ _VRO-R @ VREPL-STAGE$
    _VREPL-CREATE-WRITE DUP IF EXIT THEN DROP
    _VRO-DATA @ _VRO-LEN @ _VRO-R @ VREPL-STAGE$
    _VREPL-VERIFY-FILE DUP IF
        DROP _VRO-RM-STAGE DROP _VRO-SYNC DROP VREPL-S-IO EXIT
    THEN DROP
    _VRO-SYNC IF
        _VRO-RM-STAGE DROP _VRO-SYNC DROP VREPL-S-IO EXIT
    THEN

    _VRO-RENAME-PUBLISHES? IF
        _VREPL-PUBLISH-RENAME
    ELSE
        _VREPL-PUBLISH-MARKED
    THEN ;

\ =====================================================================
\  Public guarded entry points
\ =====================================================================

VARIABLE _vrepl-operation-active

: _VREPL-ENTER  ( r -- status )
    DUP VREPL-CONFIGURED? 0= IF DROP VREPL-S-INVALID EXIT THEN
    _vrepl-operation-active @ IF DROP VREPL-S-BUSY EXIT THEN
    DUP VREPL.FLAGS @ VREPL-F-BUSY AND IF DROP VREPL-S-BUSY EXIT THEN
    -1 _vrepl-operation-active !
    DUP _VRO-R !
    VREPL-F-BUSY SWAP VREPL.FLAGS DUP @ ROT OR SWAP !
    VREPL-S-OK ;

: _VREPL-LEAVE  ( status -- status )
    _VRO-R @ VREPL.FLAGS @ VREPL-F-BUSY INVERT AND
    _VRO-R @ VREPL.FLAGS !
    0 _vrepl-operation-active !
    DUP _VRO-R @ VREPL.LAST-STATUS ! ;

VARIABLE _VRPUB-R
VARIABLE _VRPUB-THROW

: _VREPL-RECOVER-TRANSACTION  ( -- status )
    _VRPUB-R @ _VREPL-ENTER DUP IF EXIT THEN DROP
    ['] _VREPL-RECOVER-BODY CATCH DUP _VRPUB-THROW !
    IF VREPL-S-RECOVERY THEN
    _VREPL-LEAVE ;

: _VREPL-RECOVER  ( replacement -- status )
    _VRPUB-R !
    ['] _VREPL-RECOVER-TRANSACTION VFS-TRANSACTION ;

: _VREPL-REPLACE-TRANSACTION  ( -- status )
    _VRPUB-R @ _VREPL-ENTER DUP IF EXIT THEN DROP
    ['] _VREPL-REPLACE-BODY CATCH DUP _VRPUB-THROW !
    IF VREPL-S-RECOVERY THEN
    _VREPL-LEAVE ;

: _VREPL-REPLACE  ( data length replacement -- status )
    _VRPUB-R ! _VRO-LEN ! _VRO-DATA !
    _VRO-LEN @ 0<
    _VRO-LEN @ 0> _VRO-DATA @ 0= AND OR IF
        VREPL-S-INVALID EXIT
    THEN
    ['] _VREPL-REPLACE-TRANSACTION VFS-TRANSACTION ;

\ The verification buffer holds caller data, not merely transaction
\ metadata.  Public operations therefore contain it behind no-input CATCH
\ shims and wipe all of it before returning or rethrowing.

: _VREPL-CHECK-BUFFER-WIPE  ( -- )
    _VREPL-CHECK-BUFFER _VREPL-CHECK-SIZE 0 FILL ;

VARIABLE _VRCL-RECOVER-R

: _VREPL-RECOVER-CLEAN-CALL  ( -- status )
    _VRCL-RECOVER-R @ _VREPL-RECOVER ;

: _VREPL-RECOVER-PUBLIC  ( replacement -- status )
    _VRCL-RECOVER-R !
    ['] _VREPL-RECOVER-CLEAN-CALL CATCH
    _VREPL-CHECK-BUFFER-WIPE
    DUP IF THROW THEN DROP ;

VARIABLE _VRCL-REPLACE-DATA
VARIABLE _VRCL-REPLACE-LEN
VARIABLE _VRCL-REPLACE-R

: _VREPL-REPLACE-CLEAN-CALL  ( -- status )
    _VRCL-REPLACE-DATA @ _VRCL-REPLACE-LEN @ _VRCL-REPLACE-R @
        _VREPL-REPLACE ;

: _VREPL-REPLACE-PUBLIC  ( data length replacement -- status )
    _VRCL-REPLACE-R ! _VRCL-REPLACE-LEN ! _VRCL-REPLACE-DATA !
    ['] _VREPL-REPLACE-CLEAN-CALL CATCH
    _VREPL-CHECK-BUFFER-WIPE
    DUP IF THROW THEN DROP ;

' _VREPL-INIT          CONSTANT _vrepl-init-xt
' _VREPL-FINI          CONSTANT _vrepl-fini-xt
' _VREPL-PATHS!        CONSTANT _vrepl-paths-xt
' _VREPL-DERIVE-PATHS! CONSTANT _vrepl-derive-paths-xt
' _VREPL-PRECONDITION! CONSTANT _vrepl-precondition-xt
' _VREPL-READ-ONLY!    CONSTANT _vrepl-read-only-xt
' _VREPL-RECOVER-PUBLIC CONSTANT _vrepl-recover-xt
' _VREPL-REPLACE-PUBLIC CONSTANT _vrepl-replace-xt

: VREPL-INIT
    _vrepl-init-xt _vrepl-guard WITH-GUARD ;

\ VREPL-FINI ( replacement -- status )
\   Give back the block that holds the descriptor's paths and clear the
\   descriptor, which VREPL-INIT then makes ready again.  An owner calls
\   it before it lets go of a descriptor.
: VREPL-FINI
    _vrepl-fini-xt _vrepl-guard WITH-GUARD ;

: VREPL-PATHS!
    _vrepl-paths-xt _vrepl-guard WITH-GUARD ;

: VREPL-DERIVE-PATHS!
    _vrepl-derive-paths-xt _vrepl-guard WITH-GUARD ;

: VREPL-PRECONDITION!
    _vrepl-precondition-xt _vrepl-guard WITH-GUARD ;

\ VREPL-READ-ONLY! ( flag replacement -- status )
\   Mark the replacement read-only, or writable again with 0.  A
\   read-only replacement refuses to replace with VREPL-S-READ-ONLY.
: VREPL-READ-ONLY!
    _vrepl-read-only-xt _vrepl-guard WITH-GUARD ;

: VREPL-RECOVER
    _vrepl-recover-xt _vrepl-guard WITH-GUARD ;

: VREPL-REPLACE
    _vrepl-replace-xt _vrepl-guard WITH-GUARD ;
