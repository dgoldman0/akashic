\ =====================================================================
\  segment.f - Neutral checked-record segment storage
\ =====================================================================
\  A segment is an explicitly addressed sequence of eight-byte-aligned
\  framed checked records.  It has no append cursor and no implicit path:
\  callers supply the absolute VFS path, the committed tail, and every
\  write offset.  Bytes beyond the committed tail are therefore harmless
\  failed-transaction suffixes and may be overwritten by the next writer.
\
\  File descriptors, operation workspaces, record buffers, references,
\  statistics, and locking all remain caller-owned.  One PSEG-WORK may be
\  used by only one active operation.  The enclosing store supplies the
\  transaction guard when several calls form one logical commit.
\ =====================================================================

PROVIDED akashic-persist-segment

REQUIRE core.f
REQUIRE ../utils/checked-record.f
REQUIRE ../utils/fs/vfs-access.f

8 CONSTANT PSEG-ALIGNMENT

\ This is serialized record identity, not mutable scratch.
CREATE _PSEG-RECORD-MAGIC
    0x50 C, 0x53 C, 0x45 C, 0x47 C, 0x52 C, 0x45 C, 0x43 C, 0x31 C,

1 CONSTANT _PSEG-RECORD-FORMAT

: _PSEG-DROP3  ( x1 x2 x3 -- ) 2DROP DROP ;
: _PSEG-DROP5  ( x1 x2 x3 x4 x5 -- ) 2DROP 2DROP DROP ;
: _PSEG-DROP6  ( x1 x2 x3 x4 x5 x6 -- ) 2DROP 2DROP 2DROP ;

: _PSEG-BUFFER?  ( address length -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF DROP DROP -1 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _PSEG-ALIGNED?  ( u -- flag )
    PSEG-ALIGNMENT 1- AND 0= ;

: _PSEG-ADD?  ( nonnegative-a nonnegative-b -- sum flag )
    OVER 0< OVER 0< OR IF 2DROP 0 0 EXIT THEN
    2DUP + DUP 0< IF DROP 2DROP 0 0 EXIT THEN
    DUP 3 PICK U< IF DROP 2DROP 0 0 EXIT THEN
    >R 2DROP R> -1 ;

: _PSEG-CREC>STATUS  ( crec-status -- persist-status )
    DUP CREC-S-OK = IF DROP PERSIST-S-OK EXIT THEN
    DUP CREC-S-INVALID = IF DROP PERSIST-S-INVALID EXIT THEN
    DUP CREC-S-CAPACITY = IF DROP PERSIST-S-CAPACITY EXIT THEN
    DUP CREC-S-BUSY = IF DROP PERSIST-S-BUSY EXIT THEN
    DUP CREC-S-CALLBACK = OVER CREC-S-FAULT = OR IF
        DROP PERSIST-S-FAULT EXIT
    THEN
    DROP PERSIST-S-CORRUPT ;

: _PSEG-IOR>STATUS  ( ior -- persist-status )
    DUP 0= IF DROP PERSIST-S-OK EXIT THEN
    VFS-IOR-REASON VFS-R-NOENT = IF
        PERSIST-S-ABSENT
    ELSE
        PERSIST-S-IO
    THEN ;

: _PSEG-NOENT?  ( ior -- flag )
    VFS-IOR-REASON VFS-R-NOENT = ;

: _PSEG-VFS-STATS-DISJOINT?  ( vfs stats|0 -- flag )
    DUP 0= IF 2DROP -1 EXIT THEN
    SWAP VFS-DESC-SIZE ROT PERSIST-STATS-SIZE MSPAN-OVERLAP? 0= ;

\ Checked-record callbacks.  The encoder copies exactly the caller's
\ context span; checked-record owns and canonicalizes header and padding.
: _PSEG-ENCODE-PAYLOAD
  ( source-a source-u destination-a payload-u tag -- crec-status )
    >R
    2 PICK 1 PICK <> IF
        2DROP 2DROP R> DROP CREC-S-SEMANTIC EXIT
    THEN
    R@ 0> 0= IF
        2DROP 2DROP R> DROP CREC-S-SEMANTIC EXIT
    THEN
    DUP 0> IF
        3 PICK 0= 2 PICK 0= OR IF
            2DROP 2DROP R> DROP CREC-S-SEMANTIC EXIT
        THEN
    THEN
    >R SWAP DROP R@ MOVE
    R> DROP R> DROP CREC-S-OK ;

: _PSEG-VALIDATE-PAYLOAD
  ( context-a context-u payload-a payload-u tag -- crec-status )
    >R 2DROP 2DROP
    R> 0> IF CREC-S-OK ELSE CREC-S-SEMANTIC THEN ;

\ =====================================================================
\  Caller-owned file descriptor
\ =====================================================================

0x5053454746494C31 CONSTANT _PSEG-FILE-MAGIC  \ "PSEGFIL1"

  0 CONSTANT _PSEG-F-MAGIC
  8 CONSTANT _PSEG-F-SELF
 16 CONSTANT _PSEG-F-VFS
 24 CONSTANT _PSEG-F-PATH-U
 32 CONSTANT _PSEG-F-STATS
 40 CONSTANT _PSEG-F-MAX-PAYLOAD
 48 CONSTANT _PSEG-F-FLAGS
 56 CONSTANT _PSEG-F-RESERVED
 64 CONSTANT _PSEG-F-SPEC
176 CONSTANT _PSEG-F-PATH
432 CONSTANT PSEG-FILE-SIZE

: _PSEG-F.MAGIC        ( file -- a ) _PSEG-F-MAGIC + ;
: _PSEG-F.SELF         ( file -- a ) _PSEG-F-SELF + ;
: _PSEG-F.VFS          ( file -- a ) _PSEG-F-VFS + ;
: _PSEG-F.PATH-U       ( file -- a ) _PSEG-F-PATH-U + ;
: _PSEG-F.STATS        ( file -- a ) _PSEG-F-STATS + ;
: _PSEG-F.MAX-PAYLOAD  ( file -- a ) _PSEG-F-MAX-PAYLOAD + ;
: _PSEG-F.FLAGS        ( file -- a ) _PSEG-F-FLAGS + ;
: _PSEG-F.RESERVED     ( file -- a ) _PSEG-F-RESERVED + ;
: _PSEG-F.SPEC         ( file -- a ) _PSEG-F-SPEC + ;
: _PSEG-F.PATH         ( file -- a ) _PSEG-F-PATH + ;

: PSEG-FILE-PATH$  ( file -- path-a path-u )
    DUP _PSEG-F.PATH SWAP _PSEG-F.PATH-U @ ;

: PSEG-FILE-VFS@  ( file -- vfs|0 )
    DUP 0= IF DROP 0 EXIT THEN _PSEG-F.VFS @ ;

: PSEG-MAX-PAYLOAD@  ( file -- u|0 )
    DUP 0= IF DROP 0 EXIT THEN _PSEG-F.MAX-PAYLOAD @ ;

: _PSEG-FILE-ARGS?
  ( path-a path-u max-payload vfs stats|0 file -- flag )
    >R
    R@ 0= IF _PSEG-DROP5 R> DROP 0 EXIT THEN
    R@ PSEG-FILE-SIZE MSPAN-NONWRAPPING? 0= IF
        _PSEG-DROP5 R> DROP 0 EXIT
    THEN
    3 PICK DUP 0> SWAP PERSIST-PATH-MAX <= AND 0= IF
        _PSEG-DROP5 R> DROP 0 EXIT
    THEN
    4 PICK 4 PICK _PSEG-BUFFER? 0= IF
        _PSEG-DROP5 R> DROP 0 EXIT
    THEN
    4 PICK C@ [CHAR] / <> IF _PSEG-DROP5 R> DROP 0 EXIT THEN
    2 PICK 0> 0= IF _PSEG-DROP5 R> DROP 0 EXIT THEN
    1 PICK DUP 0= IF DROP _PSEG-DROP5 R> DROP 0 EXIT THEN
    VFS-DESC-SIZE MSPAN-NONWRAPPING? 0= IF
        _PSEG-DROP5 R> DROP 0 EXIT
    THEN
    DUP IF
        DUP PERSIST-STATS-SIZE MSPAN-NONWRAPPING? 0= IF
            _PSEG-DROP5 R> DROP 0 EXIT
        THEN
    THEN
    1 PICK 1 PICK _PSEG-VFS-STATS-DISJOINT? 0= IF
        _PSEG-DROP5 R> DROP 0 EXIT
    THEN
    4 PICK 4 PICK R@ PSEG-FILE-SIZE MSPAN-OVERLAP? IF
        _PSEG-DROP5 R> DROP 0 EXIT
    THEN
    1 PICK VFS-DESC-SIZE R@ PSEG-FILE-SIZE MSPAN-OVERLAP? IF
        _PSEG-DROP5 R> DROP 0 EXIT
    THEN
    DUP IF
        DUP PERSIST-STATS-SIZE R@ PSEG-FILE-SIZE MSPAN-OVERLAP? IF
            _PSEG-DROP5 R> DROP 0 EXIT
        THEN
    THEN
    _PSEG-DROP5 R> DROP -1 ;

: PSEG-FILE-VALID?  ( file -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP PSEG-FILE-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP _PSEG-F.MAGIC @ _PSEG-FILE-MAGIC <> IF DROP 0 EXIT THEN
    DUP _PSEG-F.SELF @ OVER <> IF DROP 0 EXIT THEN
    DUP _PSEG-F.VFS @ DUP 0= IF 2DROP 0 EXIT THEN
    VFS-DESC-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP _PSEG-F.PATH-U @ DUP 0> SWAP PERSIST-PATH-MAX <= AND 0= IF
        DROP 0 EXIT
    THEN
    DUP _PSEG-F.PATH C@ [CHAR] / <> IF DROP 0 EXIT THEN
    DUP _PSEG-F.MAX-PAYLOAD @ 0> 0= IF DROP 0 EXIT THEN
    DUP _PSEG-F.FLAGS @ IF DROP 0 EXIT THEN
    DUP _PSEG-F.RESERVED @ IF DROP 0 EXIT THEN
    DUP _PSEG-F.STATS @ ?DUP IF
        PERSIST-STATS-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    THEN
    DUP _PSEG-F.VFS @ OVER _PSEG-F.STATS @
        _PSEG-VFS-STATS-DISJOINT? 0= IF DROP 0 EXIT THEN
    DUP _PSEG-F.SPEC CREC-SPEC-VALID? 0= IF DROP 0 EXIT THEN
    DUP _PSEG-F.SPEC CREC-SPEC-MODE@ CREC-MODE-FRAMED <> IF
        DROP 0 EXIT
    THEN
    DUP _PSEG-F.SPEC CREC-SPEC-FORMAT@ _PSEG-RECORD-FORMAT <> IF
        DROP 0 EXIT
    THEN
    DUP _PSEG-F.SPEC CREC-SPEC-PAYLOAD-MIN@ IF DROP 0 EXIT THEN
    DUP _PSEG-F.SPEC CREC-SPEC-PAYLOAD-MAX@
        OVER _PSEG-F.MAX-PAYLOAD @ <> IF DROP 0 EXIT THEN
    DUP _PSEG-F.SPEC CREC-SPEC-ALIGNMENT@ PSEG-ALIGNMENT <> IF
        DROP 0 EXIT
    THEN
    _PSEG-F.SPEC CREC-SPEC-TAG-POLICY@ CREC-TAG-POSITIVE = ;

: PSEG-FILE-INIT
  ( path-a path-u max-payload vfs stats|0 file -- persist-status )
    5 PICK 5 PICK 5 PICK 5 PICK 5 PICK 5 PICK
        _PSEG-FILE-ARGS? 0= IF
        _PSEG-DROP6 PERSIST-S-INVALID EXIT
    THEN
    DUP >R
    R@ PSEG-FILE-SIZE 0 FILL
    _PSEG-FILE-MAGIC R@ _PSEG-F.MAGIC !
    R@ R@ _PSEG-F.SELF !
    1 PICK R@ _PSEG-F.STATS !
    2 PICK R@ _PSEG-F.VFS !
    3 PICK R@ _PSEG-F.MAX-PAYLOAD !
    4 PICK R@ _PSEG-F.PATH-U !
    5 PICK R@ _PSEG-F.PATH 6 PICK MOVE

    _PSEG-RECORD-MAGIC 8 _PSEG-RECORD-FORMAT CREC-TAG-POSITIVE
        ['] _PSEG-ENCODE-PAYLOAD ['] _PSEG-VALIDATE-PAYLOAD
        R@ _PSEG-F.SPEC CREC-SPEC-INIT
    DUP IF
        _PSEG-CREC>STATUS R> DUP PSEG-FILE-SIZE 0 FILL DROP
        >R _PSEG-DROP6 R> EXIT
    THEN DROP
    3 PICK 0 SWAP PSEG-ALIGNMENT
        R@ _PSEG-F.SPEC CREC-SPEC-FRAMED!
    DUP IF
        _PSEG-CREC>STATUS R> DUP PSEG-FILE-SIZE 0 FILL DROP
        >R _PSEG-DROP6 R> EXIT
    THEN DROP
    R@ _PSEG-F.SPEC CREC-SPEC-SEAL
    DUP IF
        _PSEG-CREC>STATUS R> DUP PSEG-FILE-SIZE 0 FILL DROP
        >R _PSEG-DROP6 R> EXIT
    THEN DROP
    R> DROP _PSEG-DROP6 PERSIST-S-OK ;

: PSEG-MEASURE  ( payload-u file -- record-u persist-status )
    DUP PSEG-FILE-VALID? 0= IF 2DROP 0 PERSIST-S-INVALID EXIT THEN
    _PSEG-F.SPEC CREC-MEASURE
    DUP IF _PSEG-CREC>STATUS ELSE DROP PERSIST-S-OK THEN ;

: PSEG-MAX-RECORD-U@  ( file -- record-u|0 )
    DUP PSEG-FILE-VALID? 0= IF DROP 0 EXIT THEN
    DUP _PSEG-F.MAX-PAYLOAD @ SWAP PSEG-MEASURE
    IF DROP 0 THEN ;

\ =====================================================================
\  Caller-owned operation workspace and record buffer
\ =====================================================================

0x50534547574F5231 CONSTANT _PSEG-WORK-MAGIC  \ "PSEGWOR1"

  0 CONSTANT _PSEG-W-MAGIC
  8 CONSTANT _PSEG-W-SELF
 16 CONSTANT _PSEG-W-BUSY
 24 CONSTANT _PSEG-W-BUFFER
 32 CONSTANT _PSEG-W-CAPACITY
 40 CONSTANT _PSEG-W-FILE
 48 CONSTANT _PSEG-W-FD
 56 CONSTANT _PSEG-W-OFFSET
 64 CONSTANT _PSEG-W-TAIL
 72 CONSTANT _PSEG-W-ORDINAL
 80 CONSTANT _PSEG-W-RECORD-U
 88 CONSTANT _PSEG-W-PAYLOAD-A
 96 CONSTANT _PSEG-W-PAYLOAD-U
104 CONSTANT _PSEG-W-REF
112 CONSTANT _PSEG-W-STATUS
120 CONSTANT _PSEG-W-RESERVED
128 CONSTANT _PSEG-W-SCOPE
240 CONSTANT _PSEG-W-CREC
376 CONSTANT PSEG-WORK-SIZE

: _PSEG-W.MAGIC      ( work -- a ) _PSEG-W-MAGIC + ;
: _PSEG-W.SELF       ( work -- a ) _PSEG-W-SELF + ;
: _PSEG-W.BUSY       ( work -- a ) _PSEG-W-BUSY + ;
: _PSEG-W.BUFFER     ( work -- a ) _PSEG-W-BUFFER + ;
: _PSEG-W.CAPACITY   ( work -- a ) _PSEG-W-CAPACITY + ;
: _PSEG-W.FILE       ( work -- a ) _PSEG-W-FILE + ;
: _PSEG-W.FD         ( work -- a ) _PSEG-W-FD + ;
: _PSEG-W.OFFSET     ( work -- a ) _PSEG-W-OFFSET + ;
: _PSEG-W.TAIL       ( work -- a ) _PSEG-W-TAIL + ;
: _PSEG-W.ORDINAL    ( work -- a ) _PSEG-W-ORDINAL + ;
: _PSEG-W.RECORD-U   ( work -- a ) _PSEG-W-RECORD-U + ;
: _PSEG-W.PAYLOAD-A  ( work -- a ) _PSEG-W-PAYLOAD-A + ;
: _PSEG-W.PAYLOAD-U  ( work -- a ) _PSEG-W-PAYLOAD-U + ;
: _PSEG-W.REF        ( work -- a ) _PSEG-W-REF + ;
: _PSEG-W.STATUS     ( work -- a ) _PSEG-W-STATUS + ;
: _PSEG-W.RESERVED   ( work -- a ) _PSEG-W-RESERVED + ;
: _PSEG-W.SCOPE      ( work -- a ) _PSEG-W-SCOPE + ;
: _PSEG-W.CREC       ( work -- a ) _PSEG-W-CREC + ;

: _PSEG-WORK-ARGS?  ( buffer-a buffer-u work -- flag )
    >R
    R@ 0= IF 2DROP R> DROP 0 EXIT THEN
    R@ PSEG-WORK-SIZE MSPAN-NONWRAPPING? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    DUP PERSIST-RECORD-HEADER-SIZE < IF 2DROP R> DROP 0 EXIT THEN
    2DUP _PSEG-BUFFER? 0= IF 2DROP R> DROP 0 EXIT THEN
    2DUP R@ PSEG-WORK-SIZE MSPAN-OVERLAP? IF
        2DROP R> DROP 0 EXIT
    THEN
    2DROP R> DROP -1 ;

: PSEG-WORK-VALID?  ( work -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP PSEG-WORK-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP _PSEG-W.MAGIC @ _PSEG-WORK-MAGIC <> IF DROP 0 EXIT THEN
    DUP _PSEG-W.SELF @ OVER <> IF DROP 0 EXIT THEN
    DUP _PSEG-W.BUSY @ DUP 0= SWAP 1 = OR 0= IF DROP 0 EXIT THEN
    DUP _PSEG-W.BUFFER @ OVER _PSEG-W.CAPACITY @
        _PSEG-BUFFER? 0= IF DROP 0 EXIT THEN
    DUP _PSEG-W.CAPACITY @ PERSIST-RECORD-HEADER-SIZE < IF
        DROP 0 EXIT
    THEN
    DUP _PSEG-W.BUFFER @ OVER _PSEG-W.CAPACITY @
        2 PICK PSEG-WORK-SIZE MSPAN-OVERLAP? IF DROP 0 EXIT THEN
    DUP _PSEG-W.STATUS @ DUP PERSIST-S-OK >=
        SWAP PERSIST-S-FAULT <= AND 0= IF DROP 0 EXIT THEN
    DUP _PSEG-W.RESERVED @ IF DROP 0 EXIT THEN
    _PSEG-W.CREC CREC-WORK-VALID? ;

: PSEG-WORK-INIT  ( buffer-a buffer-u work -- persist-status )
    2 PICK 2 PICK 2 PICK _PSEG-WORK-ARGS? 0= IF
        _PSEG-DROP3 PERSIST-S-INVALID EXIT
    THEN
    DUP >R R@ PSEG-WORK-SIZE 0 FILL
    _PSEG-WORK-MAGIC R@ _PSEG-W.MAGIC !
    R@ R@ _PSEG-W.SELF !
    2 PICK R@ _PSEG-W.BUFFER !
    1 PICK R@ _PSEG-W.CAPACITY !
    PERSIST-S-INVALID R@ _PSEG-W.STATUS !
    R@ _PSEG-W.CREC CREC-WORK-INIT
    DUP IF
        _PSEG-CREC>STATUS R> DUP PSEG-WORK-SIZE 0 FILL DROP
        >R _PSEG-DROP3 R> EXIT
    THEN DROP
    R> DROP _PSEG-DROP3 PERSIST-S-OK ;

: PSEG-WORK-STATUS@  ( work -- persist-status )
    DUP PSEG-WORK-VALID? IF _PSEG-W.STATUS @
    ELSE DROP PERSIST-S-INVALID THEN ;

: PSEG-RECORD-U@  ( work -- record-u|0 )
    DUP PSEG-WORK-VALID? 0= IF DROP 0 EXIT THEN
    DUP _PSEG-W.STATUS @ IF DROP 0 EXIT THEN
    _PSEG-W.RECORD-U @ ;

: PSEG-PAYLOAD$  ( work -- payload-a payload-u )
    DUP PSEG-WORK-VALID? 0= IF DROP 0 0 EXIT THEN
    DUP _PSEG-W.STATUS @ IF DROP 0 0 EXIT THEN
    _PSEG-W.CREC CREC-PAYLOAD$ ;

: _PSEG-FILE-WORK-DISJOINT?  ( file work -- flag )
    >R
    DUP PSEG-FILE-SIZE R@ PSEG-WORK-SIZE MSPAN-OVERLAP? IF
        DROP R> DROP 0 EXIT
    THEN
    DUP PSEG-FILE-SIZE R@ _PSEG-W.BUFFER @ R@ _PSEG-W.CAPACITY @
        MSPAN-OVERLAP? IF DROP R> DROP 0 EXIT THEN
    DUP _PSEG-F.VFS @ VFS-DESC-SIZE R@ PSEG-WORK-SIZE
        MSPAN-OVERLAP? IF DROP R> DROP 0 EXIT THEN
    DUP _PSEG-F.VFS @ VFS-DESC-SIZE
        R@ _PSEG-W.BUFFER @ R@ _PSEG-W.CAPACITY @
        MSPAN-OVERLAP? IF DROP R> DROP 0 EXIT THEN
    DUP _PSEG-F.STATS @ ?DUP IF
        DUP PERSIST-STATS-SIZE R@ PSEG-WORK-SIZE
            MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
        DUP PERSIST-STATS-SIZE
            R@ _PSEG-W.BUFFER @ R@ _PSEG-W.CAPACITY @
            MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
        DROP
    THEN
    DROP R> DROP -1 ;

: _PSEG-WORK-BEGIN  ( file work -- persist-status )
    DUP PSEG-WORK-VALID? 0= IF 2DROP PERSIST-S-INVALID EXIT THEN
    DUP _PSEG-W.BUSY @ IF 2DROP PERSIST-S-BUSY EXIT THEN
    OVER PSEG-FILE-VALID? 0= IF 2DROP PERSIST-S-INVALID EXIT THEN
    2DUP _PSEG-FILE-WORK-DISJOINT? 0= IF
        2DROP PERSIST-S-INVALID EXIT
    THEN
    1 OVER _PSEG-W.BUSY !
    SWAP OVER _PSEG-W.FILE !
    0 OVER _PSEG-W.FD !
    0 OVER _PSEG-W.RECORD-U !
    PERSIST-S-INVALID SWAP _PSEG-W.STATUS !
    PERSIST-S-OK ;

: _PSEG-WORK-END  ( persist-status work -- persist-status )
    >R
    DUP R@ _PSEG-W.STATUS !
    0 R@ _PSEG-W.FD !
    0 R@ _PSEG-W.BUSY !
    R> DROP ;

: _PSEG-OPEN  ( flags work -- fd ior )
    >R
    R@ _PSEG-W.FILE @ _PSEG-F.VFS @
        R@ _PSEG-W.SCOPE VFA-SCOPE-INIT
    DUP IF
        NIP 0 SWAP R> DROP EXIT
    THEN DROP
    R@ _PSEG-W.FILE @ PSEG-FILE-PATH$ ROT
        R@ _PSEG-W.SCOPE VFA-SCOPE-OPEN?
    R> DROP ;

\ A cleanup failure is reported separately from the primary byte or
\ validation result because the scope's FD/CWD state is then uncertain.
: _PSEG-CLOSE  ( primary-status work -- final-status )
    >R
    R@ _PSEG-W.SCOPE VFA-SCOPE-CLOSE?
    IF DROP PERSIST-S-UNCERTAIN THEN
    R> DROP ;

\ Run a work-based operation with its caller-owned descriptor still present
\ at the CATCH boundary.  If an underlying VFS binding throws, CATCH restores
\ that work pointer and this wrapper retires any open scope before reporting
\ a contained persistence fault.
: _PSEG-RUN-CATCH  ( work body-xt -- persist-status )
    >R DUP R> CATCH DUP IF
        DROP DROP
        DUP _PSEG-W.SCOPE VFA-SCOPE-VALID? IF
            PERSIST-S-FAULT SWAP _PSEG-CLOSE
        ELSE
            DROP PERSIST-S-FAULT
        THEN
    ELSE
        DROP NIP
    THEN ;

: _PSEG-NOTE-WRITE  ( bytes work -- )
    _PSEG-W.FILE @ _PSEG-F.STATS @ ?DUP IF
        _PSTAT-NOTE-SEGMENT-WRITE
    ELSE DROP THEN ;

: _PSEG-NOTE-READ  ( bytes work -- )
    _PSEG-W.FILE @ _PSEG-F.STATS @ ?DUP IF
        _PSTAT-NOTE-SEGMENT-READ
    ELSE DROP THEN ;

: _PSEG-NOTE-VERIFY  ( work -- )
    _PSEG-W.FILE @ _PSEG-F.STATS @ ?DUP IF
        _PSTAT-NOTE-VERIFY
    THEN ;

\ =====================================================================
\  Provisioning and physical-size access
\ =====================================================================

: _PSEG-ENSURE-RUN  ( work -- persist-status )
    >R
    VFS-FF-READ VFS-FF-WRITE OR R@ _PSEG-OPEN
    DUP 0= IF
        DROP DROP PERSIST-S-OK R> _PSEG-CLOSE EXIT
    THEN
    DUP _PSEG-NOENT? 0= IF
        NIP _PSEG-IOR>STATUS R> DROP EXIT
    THEN
    2DROP
    R@ _PSEG-W.FILE @ PSEG-FILE-PATH$
        R@ _PSEG-W.FILE @ _PSEG-F.VFS @ VFS-CREATE 0= IF
        R> DROP PERSIST-S-IO EXIT
    THEN
    VFS-FF-READ VFS-FF-WRITE OR R@ _PSEG-OPEN
    DUP IF
        NIP _PSEG-IOR>STATUS R> DROP EXIT
    THEN
    2DROP PERSIST-S-OK R> _PSEG-CLOSE ;

: PSEG-ENSURE  ( file work -- persist-status )
    >R
    R@ PSEG-WORK-VALID? 0= IF DROP R> DROP PERSIST-S-INVALID EXIT THEN
    DUP R@ _PSEG-WORK-BEGIN DUP IF
        >R DROP R> R> DROP EXIT
    THEN DROP DROP
    R@ ['] _PSEG-ENSURE-RUN _PSEG-RUN-CATCH
    R> _PSEG-WORK-END ;

: _PSEG-SIZE-RUN  ( work -- persist-status )
    >R
    VFS-FF-READ R@ _PSEG-OPEN
    DUP IF
        NIP _PSEG-IOR>STATUS R> DROP EXIT
    THEN
    DROP DUP R@ _PSEG-W.FD !
    VFA-FILE-SIZE?
    DUP IF
        2DROP PERSIST-S-IO R> _PSEG-CLOSE EXIT
    THEN
    DROP R@ _PSEG-W.RECORD-U !
    PERSIST-S-OK R> _PSEG-CLOSE ;

: PSEG-FILE-SIZE?  ( file work -- bytes persist-status )
    >R
    R@ PSEG-WORK-VALID? 0= IF DROP R> DROP 0 PERSIST-S-INVALID EXIT THEN
    DUP R@ _PSEG-WORK-BEGIN DUP IF
        >R DROP R> R> DROP 0 SWAP EXIT
    THEN DROP DROP
    R@ ['] _PSEG-SIZE-RUN _PSEG-RUN-CATCH R@ _PSEG-WORK-END
    DUP IF
        0 SWAP
    ELSE
        R@ _PSEG-W.RECORD-U @ SWAP
    THEN
    R> DROP ;

\ Reconcile a failed-transaction suffix with the atomic root's authoritative
\ committed tail.  Truncation may only shrink (or confirm) an existing file;
\ it never manufactures a hole when committed bytes are missing.
: _PSEG-TRUNCATE-RUN  ( work -- persist-status )
    >R
    R@ _PSEG-W.TAIL @ DUP 0< SWAP _PSEG-ALIGNED? 0= OR IF
        R> DROP PERSIST-S-INVALID EXIT
    THEN
    VFS-FF-READ VFS-FF-WRITE OR R@ _PSEG-OPEN
    DUP IF NIP _PSEG-IOR>STATUS R> DROP EXIT THEN
    DROP DUP R@ _PSEG-W.FD !
    VFA-FILE-SIZE?
    DUP IF 2DROP PERSIST-S-IO R> _PSEG-CLOSE EXIT THEN
    DROP
    DUP R@ _PSEG-W.TAIL @ < IF
        DROP PERSIST-S-CORRUPT R> _PSEG-CLOSE EXIT
    THEN
    R@ _PSEG-W.TAIL @ = IF
        PERSIST-S-OK R> _PSEG-CLOSE EXIT
    THEN
    R@ _PSEG-W.TAIL @ R@ _PSEG-W.FD @ VFS-TRUNCATE IF
        PERSIST-S-IO R> _PSEG-CLOSE EXIT
    THEN
    R@ _PSEG-W.FD @ VFA-FILE-SIZE?
    DUP IF 2DROP PERSIST-S-IO R> _PSEG-CLOSE EXIT THEN
    DROP R@ _PSEG-W.TAIL @ <> IF
        PERSIST-S-IO R> _PSEG-CLOSE EXIT
    THEN
    PERSIST-S-OK R> _PSEG-CLOSE ;

: PSEG-TRUNCATE  ( committed-tail file work -- persist-status )
    >R
    R@ PSEG-WORK-VALID? 0= IF 2DROP R> DROP PERSIST-S-INVALID EXIT THEN
    DUP R@ _PSEG-WORK-BEGIN DUP IF
        >R 2DROP R> R> DROP EXIT
    THEN DROP
    DROP R@ _PSEG-W.TAIL !
    R@ ['] _PSEG-TRUNCATE-RUN _PSEG-RUN-CATCH
    R> _PSEG-WORK-END ;

\ Creation is intentionally not an implicit durability barrier.  A store
\ provisions all of its files, then calls PSEG-SYNC at the chosen boundary.
: _PSEG-SYNC-RUN  ( file -- persist-status )
    DUP _PSEG-F.VFS @ VFS-SYNC IF DROP PERSIST-S-IO EXIT THEN
    _PSEG-F.STATS @ ?DUP IF _PSTAT-NOTE-SYNC THEN
    PERSIST-S-OK ;

: PSEG-SYNC  ( file -- persist-status )
    DUP PSEG-FILE-VALID? 0= IF DROP PERSIST-S-INVALID EXIT THEN
    DUP ['] _PSEG-SYNC-RUN CATCH
    DUP IF
        DROP 2DROP PERSIST-S-FAULT
    ELSE
        DROP NIP
    THEN ;

\ =====================================================================
\  Explicit-offset record writes
\ =====================================================================

: _PSEG-OUTPUT-REF?  ( work -- flag )
    >R
    R@ _PSEG-W.REF @ DUP 0= IF DROP R> DROP 0 EXIT THEN
    DUP PERSIST-REF-SIZE MSPAN-NONWRAPPING? 0= IF
        DROP R> DROP 0 EXIT
    THEN
    DUP PERSIST-REF-SIZE R@ PSEG-WORK-SIZE MSPAN-OVERLAP? IF
        DROP R> DROP 0 EXIT
    THEN
    DUP PERSIST-REF-SIZE R@ _PSEG-W.FILE @ PSEG-FILE-SIZE
        MSPAN-OVERLAP? IF DROP R> DROP 0 EXIT THEN
    DUP PERSIST-REF-SIZE R@ _PSEG-W.BUFFER @ R@ _PSEG-W.CAPACITY @
        MSPAN-OVERLAP? IF DROP R> DROP 0 EXIT THEN
    DUP PERSIST-REF-SIZE
        R@ _PSEG-W.FILE @ _PSEG-F.VFS @ VFS-DESC-SIZE
        MSPAN-OVERLAP? IF DROP R> DROP 0 EXIT THEN
    R@ _PSEG-W.FILE @ _PSEG-F.STATS @ ?DUP IF
        DUP PERSIST-STATS-SIZE 3 PICK PERSIST-REF-SIZE
            MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
        DROP
    THEN
    R@ _PSEG-W.PAYLOAD-U @ ?DUP IF
        R@ _PSEG-W.PAYLOAD-A @ SWAP 2 PICK PERSIST-REF-SIZE
            MSPAN-OVERLAP? IF DROP R> DROP 0 EXIT THEN
    THEN
    DROP R> DROP -1 ;

: _PSEG-PAYLOAD-DISJOINT?  ( work -- flag )
    >R
    R@ _PSEG-W.PAYLOAD-U @ 0= IF
        R@ _PSEG-W.PAYLOAD-A @ 0= R> DROP EXIT
    THEN
    R@ _PSEG-W.PAYLOAD-A @ R@ _PSEG-W.PAYLOAD-U @
        R@ PSEG-WORK-SIZE MSPAN-OVERLAP? IF R> DROP 0 EXIT THEN
    R@ _PSEG-W.PAYLOAD-A @ R@ _PSEG-W.PAYLOAD-U @
        R@ _PSEG-W.FILE @ PSEG-FILE-SIZE MSPAN-OVERLAP? IF
        R> DROP 0 EXIT
    THEN
    R@ _PSEG-W.PAYLOAD-A @ R@ _PSEG-W.PAYLOAD-U @
        R@ _PSEG-W.BUFFER @ R@ _PSEG-W.CAPACITY @
        MSPAN-OVERLAP? IF R> DROP 0 EXIT THEN
    R@ _PSEG-W.PAYLOAD-A @ R@ _PSEG-W.PAYLOAD-U @
        R@ _PSEG-W.FILE @ _PSEG-F.VFS @ VFS-DESC-SIZE
        MSPAN-OVERLAP? IF R> DROP 0 EXIT THEN
    R@ _PSEG-W.FILE @ _PSEG-F.STATS @ ?DUP IF
        PERSIST-STATS-SIZE R@ _PSEG-W.PAYLOAD-A @
            R@ _PSEG-W.PAYLOAD-U @ MSPAN-OVERLAP? IF
            R> DROP 0 EXIT
        THEN
    THEN
    R> DROP -1 ;

: _PSEG-WRITE-ARGS?  ( work -- flag )
    >R
    R@ _PSEG-W.PAYLOAD-A @ R@ _PSEG-W.PAYLOAD-U @
        _PSEG-BUFFER? 0= IF R> DROP 0 EXIT THEN
    R@ _PSEG-PAYLOAD-DISJOINT? 0= IF R> DROP 0 EXIT THEN
    R@ _PSEG-W.ORDINAL @ 0> 0= IF R> DROP 0 EXIT THEN
    R@ _PSEG-W.OFFSET @ DUP 0< SWAP _PSEG-ALIGNED? 0= OR IF
        R> DROP 0 EXIT
    THEN
    R@ _PSEG-OUTPUT-REF? R> DROP ;

: _PSEG-WRITE-RUN  ( work -- persist-status )
    >R
    R@ _PSEG-WRITE-ARGS? 0= IF R> DROP PERSIST-S-INVALID EXIT THEN
    R@ _PSEG-W.REF @ PERSIST-REF-INIT
    R@ _PSEG-W.PAYLOAD-U @ R@ _PSEG-W.FILE @ PSEG-MEASURE
    DUP IF NIP R> DROP EXIT THEN
    DROP DUP R@ _PSEG-W.RECORD-U !
    R@ _PSEG-W.CAPACITY @ > IF R> DROP PERSIST-S-CAPACITY EXIT THEN
    R@ _PSEG-W.OFFSET @ R@ _PSEG-W.RECORD-U @ _PSEG-ADD?
    0= IF DROP R> DROP PERSIST-S-CAPACITY EXIT THEN DROP

    R@ _PSEG-W.PAYLOAD-A @ R@ _PSEG-W.PAYLOAD-U @
    R@ _PSEG-W.PAYLOAD-U @ R@ _PSEG-W.ORDINAL @
    R@ _PSEG-W.BUFFER @ R@ _PSEG-W.CAPACITY @
    R@ _PSEG-W.FILE @ _PSEG-F.SPEC R@ _PSEG-W.CREC CREC-ENCODE
    DUP IF NIP _PSEG-CREC>STATUS R> DROP EXIT THEN
    DROP R@ _PSEG-W.RECORD-U @ <> IF
        R> DROP PERSIST-S-CORRUPT EXIT
    THEN

    VFS-FF-READ VFS-FF-WRITE OR R@ _PSEG-OPEN
    DUP IF NIP _PSEG-IOR>STATUS R> DROP EXIT THEN
    DROP DUP R@ _PSEG-W.FD !
    VFA-FILE-SIZE?
    DUP IF
        2DROP PERSIST-S-IO R> _PSEG-CLOSE EXIT
    THEN
    DROP
    DUP R@ _PSEG-W.OFFSET @ = IF DROP ELSE
        DUP R@ _PSEG-W.OFFSET @ < IF
            DROP PERSIST-S-CORRUPT R> _PSEG-CLOSE EXIT
        THEN
        _PSEG-ALIGNED? IF
            PERSIST-S-CONFLICT R> _PSEG-CLOSE EXIT
        THEN
        PERSIST-S-CORRUPT R> _PSEG-CLOSE EXIT
    THEN
    R@ _PSEG-W.OFFSET @ R@ _PSEG-W.FD @ VFS-SEEK? IF
        PERSIST-S-IO R> _PSEG-CLOSE EXIT
    THEN
    R@ _PSEG-W.BUFFER @ R@ _PSEG-W.RECORD-U @
        R@ _PSEG-W.FD @ VFS-WRITE-EXACT IF
        PERSIST-S-IO R> _PSEG-CLOSE EXIT
    THEN
    R@ _PSEG-W.RECORD-U @ R@ _PSEG-NOTE-WRITE
    PERSIST-S-OK R@ _PSEG-CLOSE DUP IF R> DROP EXIT THEN DROP

    R@ _PSEG-W.OFFSET @ R@ _PSEG-W.REF @ PREF.OFFSET !
    R@ _PSEG-W.RECORD-U @ R@ _PSEG-W.REF @ PREF.SPAN !
    R@ _PSEG-W.ORDINAL @ R@ _PSEG-W.REF @ PREF.ORDINAL !
    R> DROP PERSIST-S-OK ;

: PSEG-WRITE
  ( payload-a payload-u ordinal offset output-ref file work -- status )
    >R
    R@ PSEG-WORK-VALID? 0= IF _PSEG-DROP6 R> DROP PERSIST-S-INVALID EXIT THEN
    DUP R@ _PSEG-WORK-BEGIN DUP IF
        >R _PSEG-DROP6 R> R> DROP EXIT
    THEN DROP
    DROP
    R@ _PSEG-W.REF !
    R@ _PSEG-W.OFFSET !
    R@ _PSEG-W.ORDINAL !
    R@ _PSEG-W.PAYLOAD-U !
    R@ _PSEG-W.PAYLOAD-A !
    R@ ['] _PSEG-WRITE-RUN _PSEG-RUN-CATCH
    R> _PSEG-WORK-END ;

\ =====================================================================
\  Committed-tail-bounded reads and readback verification
\ =====================================================================

: _PSEG-READ-ARGS?  ( work -- flag )
    >R
    R@ _PSEG-W.REF @ DUP PERSIST-REF-VALID? 0= IF
        DROP R> DROP 0 EXIT
    THEN DROP
    R@ _PSEG-W.REF @ PERSIST-REF-SIZE
        R@ PSEG-WORK-SIZE MSPAN-OVERLAP? IF R> DROP 0 EXIT THEN
    R@ _PSEG-W.REF @ PERSIST-REF-SIZE
        R@ _PSEG-W.FILE @ PSEG-FILE-SIZE
        MSPAN-OVERLAP? IF R> DROP 0 EXIT THEN
    R@ _PSEG-W.REF @ PERSIST-REF-SIZE
        R@ _PSEG-W.BUFFER @ R@ _PSEG-W.CAPACITY @
        MSPAN-OVERLAP? IF R> DROP 0 EXIT THEN
    R@ _PSEG-W.REF @ PERSIST-REF-SIZE
        R@ _PSEG-W.FILE @ _PSEG-F.VFS @ VFS-DESC-SIZE
        MSPAN-OVERLAP? IF R> DROP 0 EXIT THEN
    R@ _PSEG-W.FILE @ _PSEG-F.STATS @ ?DUP IF
        PERSIST-STATS-SIZE R@ _PSEG-W.REF @ PERSIST-REF-SIZE
            MSPAN-OVERLAP? IF R> DROP 0 EXIT THEN
    THEN
    R@ _PSEG-W.TAIL @ DUP 0< SWAP _PSEG-ALIGNED? 0= OR IF
        R> DROP 0 EXIT
    THEN
    R@ _PSEG-W.REF @ PREF.OFFSET @ _PSEG-ALIGNED? 0= IF
        R> DROP 0 EXIT
    THEN
    R@ _PSEG-W.REF @ PREF.SPAN @ DUP _PSEG-ALIGNED? 0= IF
        DROP R> DROP 0 EXIT
    THEN
    R@ _PSEG-W.CAPACITY @ > IF R> DROP 0 EXIT THEN
    R@ _PSEG-W.REF @ PREF.OFFSET @
        R@ _PSEG-W.REF @ PREF.SPAN @ _PSEG-ADD?
    0= IF DROP R> DROP 0 EXIT THEN
    R@ _PSEG-W.TAIL @ <= R> DROP ;

: _PSEG-READ-RUN  ( work -- persist-status )
    >R
    R@ _PSEG-READ-ARGS? 0= IF R> DROP PERSIST-S-INVALID EXIT THEN
    VFS-FF-READ R@ _PSEG-OPEN
    DUP IF NIP _PSEG-IOR>STATUS R> DROP EXIT THEN
    DROP DUP R@ _PSEG-W.FD !
    VFA-FILE-SIZE?
    DUP IF
        2DROP PERSIST-S-IO R> _PSEG-CLOSE EXIT
    THEN
    DROP R@ _PSEG-W.TAIL @ < IF
        PERSIST-S-CORRUPT R> _PSEG-CLOSE EXIT
    THEN

    R@ _PSEG-W.BUFFER @ PERSIST-RECORD-HEADER-SIZE
        R@ _PSEG-W.REF @ PREF.OFFSET @ R@ _PSEG-W.FD @
        VFA-READ-RANGE? IF
        PERSIST-S-IO R> _PSEG-CLOSE EXIT
    THEN
    R@ _PSEG-W.BUFFER @ PERSIST-RECORD-HEADER-SIZE
        R@ _PSEG-W.FILE @ _PSEG-F.SPEC R@ _PSEG-W.CREC
        CREC-INSPECT-HEADER
    DUP IF _PSEG-CREC>STATUS R> _PSEG-CLOSE EXIT THEN DROP
    R@ _PSEG-W.CREC CREC-RECORD-U@
        R@ _PSEG-W.REF @ PREF.SPAN @ <> IF
        PERSIST-S-CORRUPT R> _PSEG-CLOSE EXIT
    THEN
    R@ _PSEG-W.CREC CREC-TAG@
        R@ _PSEG-W.REF @ PREF.ORDINAL @ <> IF
        PERSIST-S-CORRUPT R> _PSEG-CLOSE EXIT
    THEN

    R@ _PSEG-W.BUFFER @ R@ _PSEG-W.REF @ PREF.SPAN @
        R@ _PSEG-W.REF @ PREF.OFFSET @ R@ _PSEG-W.FD @
        VFA-READ-RANGE? IF
        PERSIST-S-IO R> _PSEG-CLOSE EXIT
    THEN
    0 0 R@ _PSEG-W.BUFFER @ R@ _PSEG-W.REF @ PREF.SPAN @
        R@ _PSEG-W.FILE @ _PSEG-F.SPEC R@ _PSEG-W.CREC CREC-VALIDATE
    DUP IF _PSEG-CREC>STATUS R> _PSEG-CLOSE EXIT THEN DROP
    R@ _PSEG-W.CREC CREC-RECORD-U@
        R@ _PSEG-W.REF @ PREF.SPAN @ <> IF
        PERSIST-S-CORRUPT R> _PSEG-CLOSE EXIT
    THEN
    R@ _PSEG-W.CREC CREC-TAG@
        R@ _PSEG-W.REF @ PREF.ORDINAL @ <> IF
        PERSIST-S-CORRUPT R> _PSEG-CLOSE EXIT
    THEN
    R@ _PSEG-W.REF @ PREF.SPAN @ R@ _PSEG-W.RECORD-U !
    R@ _PSEG-W.REF @ PREF.SPAN @ PERSIST-RECORD-HEADER-SIZE +
        R@ _PSEG-NOTE-READ
    R@ _PSEG-NOTE-VERIFY
    PERSIST-S-OK R> _PSEG-CLOSE ;

: PSEG-READ  ( ref committed-tail file work -- persist-status )
    >R
    R@ PSEG-WORK-VALID? 0= IF _PSEG-DROP3 R> DROP PERSIST-S-INVALID EXIT THEN
    DUP R@ _PSEG-WORK-BEGIN DUP IF
        >R _PSEG-DROP3 R> R> DROP EXIT
    THEN DROP
    DROP
    R@ _PSEG-W.TAIL !
    R@ _PSEG-W.REF !
    R@ ['] _PSEG-READ-RUN _PSEG-RUN-CATCH
    R> _PSEG-WORK-END ;

\ Verification deliberately performs the same two-stage physical read as
\ PSEG-READ.  Pass the proposed new tail to verify a just-written suffix
\ before the store publishes that tail in its atomic root.
: PSEG-VERIFY  ( ref proposed-tail file work -- persist-status )
    PSEG-READ ;
