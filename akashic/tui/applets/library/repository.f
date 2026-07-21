\ =====================================================================
\  repository.f - Sole VFS repository for the bounded Library store
\ =====================================================================
\  Library's four paths are private implementation details.  The VFSNAP
\  head is the only commit point; the two catalog banks and fixed content
\  arena are never selected by path discovery or by their own generation.
\
\  The owner validates a complete committed snapshot before publishing
\  any caller-visible fact.  Content mutations write and verify the immutable
\  frame first; every mutation then constructs and verifies one complete
\  inactive bank and publishes only by replacing the head.
\
\  L12-DELETION: this fixed-bank backend, its process-global transaction
\  workspace, and its private _LIBMU/_LIBAUTH/_LIBLOC/_LIBIX coupling are
\  bounded scaffolding for the L10-L11 vertical slices. L12 removes the
\  remaining implementation when the scalable Library repository takes over.
\
\  The composed Library service exposes these request/view constructors:
\    LIBRARY-MANAGED-CREATE-REQUEST-INIT  ( request -- )
\    LIBRARY-MANAGED-CREATE-OPERATION-KEY! ( key request -- status )
\    LIBRARY-MANAGED-CREATE-TITLE!         ( a u request -- status )
\    LIBRARY-MANAGED-CREATE-CONTENT!       ( a u request -- status )
\    LIBRARY-MANAGED-CREATE-REQUEST-VALID? ( request -- flag )
\    LIBRARY-CAPTURE-IMPORT-REQUEST-INIT / ...-VALID?
\    LIBRARY-METADATA-INIT / ...-VALID?
\    LIBRARY-COLLECTION-{CREATE,REPLACE}-REQUEST-INIT / ...-VALID?
\    LIBRARY-CORPUS-QUERY-REQUEST-INIT / ...-TERM! / ...-COLLECTION!
\      / ...-VALID?
\
\  The composed Library service exposes these document/capture operations:
\    LIBRARY-VFS-STORE-CREATE-MANAGED
\      ( request result-entry store -- status )
\    LIBRARY-VFS-STORE-IMPORT-CAPTURE
\      ( request result-entry store -- status )
\    LIBRARY-VFS-STORE-QUERY-ACTIVE
\      ( expected-catalog-generation start-slot summaries capacity store
\        -- count next-slot catalog-generation status )
\    LIBRARY-VFS-STORE-QUERY-CORPUS
\      ( request summaries capacity store
\        -- count next-slot catalog-generation status )
\    LIBRARY-VFS-STORE-QUERY-COLLECTIONS
\      ( expected-catalog-generation start-slot summaries capacity store
\        -- count next-slot catalog-generation status )
\    LIBRARY-VFS-STORE-READ-IDENTITY
\      ( rid entry store -- status )
\    LIBRARY-VFS-STORE-READ-EXACT
\      ( rid domain-revision bytes capacity entry content store
\        -- required-u status )
\    LIBRARY-VFS-STORE-READ-MANAGED-EXACT
\      ( rid domain-revision bytes capacity entry content store
\        -- required-u status )
\    LIBRARY-VFS-STORE-REPLACE-MANAGED
\      ( rid expected-domain a u result-entry store -- status )
\    LIBRARY-VFS-STORE-REPLACE-METADATA
\      ( rid expected-domain metadata result-entry store -- status )
\    LIBRARY-VFS-STORE-{ARCHIVE,UNARCHIVE,TOMBSTONE-DESTRUCTIVE}
\      ( rid expected-domain result-entry store -- status )
\    LIBRARY-VFS-STORE-LOOKUP-RECEIPT
\      ( operation-key rid-out receipt-out store -- status )
\
\  The composed Library service exposes these history/collection operations:
\    LIBRARY-VFS-STORE-LIST-RETAINED-REVISIONS
\      ( rid expected-current summaries capacity store -- required-n status )
\    LIBRARY-VFS-STORE-READ-RETAINED-EXACT
\      ( rid content-frame-domain bytes capacity content store
\        -- required-u status )
\    LIBRARY-VFS-STORE-COMPARE-RETAINED
\      ( rid left-domain right-domain store -- equal? status )
\    LIBRARY-VFS-STORE-RESTORE-RETAINED-EXACT
\      ( rid expected-current source-domain result-entry store -- status )
\    LIBRARY-VFS-STORE-{CREATE,REPLACE}-COLLECTION
\      ( request collection-view store -- status )
\    LIBRARY-VFS-STORE-READ-COLLECTION-EXACT
\      ( rid revision collection-view store -- status )
\
\  The composed Library service exposes these maintenance operations:
\    LIBRARY-VFS-STORE-INSPECT
\      ( inspection store -- call-status )
\    LIBRARY-VFS-STORE-REPAIR
\      ( prior-inspection store -- status )
\    LIBRARY-VFS-STORE-RAW-EXPORT
\      ( bytes capacity inspection store -- required-u status )
\
\  The bounded queries return caller-owned identity references plus small
\  summaries and use raw owner-slot cursors.  Expected generation 0 starts at
\  slot zero; every continuation passes the returned positive generation, so
\  pages cannot mix.  Next slot -1 is terminal.  Corpus search is exact UTF-8
\  byte search: title/body terms are substrings, tags are whole-value matches,
\  and no case folding or normalization is implied.  Exact reads copy bytes
\  into the caller's buffer and return a LIB-CONTENT view borrowing that buffer.
\  Targeted identity reads bypass query/index discovery and return the exact
\  authoritative active, archived, or explanatory tombstone entry for one RID.
\  Retained snapshots are addressed by the exact domain revision stored on
\  their immutable content frame; metadata-only domain revisions are not
\  content aliases.  No public operation exposes a private path or treats a
\  transient raw continuation slot as durable identity.
\ =====================================================================

PROVIDED akashic-tui-library-repository

REQUIRE store-format.f
REQUIRE ../../../utils/checked-record.f
REQUIRE ../../../utils/fs/vfs-fixed-snapshot.f
REQUIRE ../../../concurrency/guard.f

\ =====================================================================
\  One Library store status domain
\ =====================================================================

 0 CONSTANT LIBSTORE-S-OK
 1 CONSTANT LIBSTORE-S-ABSENT
 2 CONSTANT LIBSTORE-S-CORRUPT
 3 CONSTANT LIBSTORE-S-UNSUPPORTED
 4 CONSTANT LIBSTORE-S-INVALID
 5 CONSTANT LIBSTORE-S-CATALOG-FULL
 6 CONSTANT LIBSTORE-S-COLLECTION-FULL
 7 CONSTANT LIBSTORE-S-CONTENT-FULL
 8 CONSTANT LIBSTORE-S-ALLOCATION
 9 CONSTANT LIBSTORE-S-IO
10 CONSTANT LIBSTORE-S-RECOVERY
11 CONSTANT LIBSTORE-S-UNCERTAIN
12 CONSTANT LIBSTORE-S-BUSY
13 CONSTANT LIBSTORE-S-CONFLICT
14 CONSTANT LIBSTORE-S-IDEMPOTENCY-MISMATCH
15 CONSTANT LIBSTORE-S-NOT-FOUND
16 CONSTANT LIBSTORE-S-RETIRED
17 CONSTANT LIBSTORE-S-TOMBSTONED
18 CONSTANT LIBSTORE-S-GONE
19 CONSTANT LIBSTORE-S-OUTPUT-CAPACITY

\ =====================================================================
\  Caller-owned maintenance inspection and opaque evidence export
\ =====================================================================
\  Inspection names sealed object roles, never private paths.  The raw
\  export is one coherent, guarded concatenation in this exact object order;
\  each object record carries its offset and exact byte length.  Future or
\  damaged evidence exposes only checked envelope/header facts and opaque
\  bytes.  Semantic fields remain zero unless one complete V1 corpus (or the
\  deterministic VREPL result of one) has passed full validation.

0 CONSTANT LIBRARY-EVIDENCE-HEAD
1 CONSTANT LIBRARY-EVIDENCE-HEAD-STAGE
2 CONSTANT LIBRARY-EVIDENCE-HEAD-BACKUP
3 CONSTANT LIBRARY-EVIDENCE-HEAD-MARKER
4 CONSTANT LIBRARY-EVIDENCE-BANK-A
5 CONSTANT LIBRARY-EVIDENCE-BANK-B
6 CONSTANT LIBRARY-EVIDENCE-CONTENT
7 CONSTANT LIBRARY-EVIDENCE-OBJECT-N

0 CONSTANT LIBRARY-EVIDENCE-S-ABSENT
1 CONSTANT LIBRARY-EVIDENCE-S-RECOGNIZED
2 CONSTANT LIBRARY-EVIDENCE-S-FUTURE
3 CONSTANT LIBRARY-EVIDENCE-S-CORRUPT
4 CONSTANT LIBRARY-EVIDENCE-S-RECOVERY

1 CONSTANT LIBRARY-EVIDENCE-F-PRESENT
2 CONSTANT LIBRARY-EVIDENCE-F-SELECTED
4 CONSTANT LIBRARY-EVIDENCE-F-COMMITTED
8 CONSTANT LIBRARY-EVIDENCE-F-OPAQUE

1 CONSTANT LIBRARY-INSPECTION-F-RECOGNIZED-V1
1 CONSTANT LIBRARY-REPAIR-F-HEAD-TRANSACTION

\ Three possible 512-byte head images, one 64-byte VREPL marker, two
\ 403,968-byte banks, and the 655,360-byte arena.  Oversized evidence is
\ retained but cannot be materialized through this bounded V1 maintenance ABI.
1464896 CONSTANT LIBRARY-RAW-EXPORT-MAX

\ One fixed object record (96 bytes).
 0 CONSTANT _LIBEO-STATE
 8 CONSTANT _LIBEO-FLAGS
16 CONSTANT _LIBEO-RAW-OFFSET
24 CONSTANT _LIBEO-RAW-U
32 CONSTANT _LIBEO-ENVELOPE-FORMAT
40 CONSTANT _LIBEO-STORE-FORMAT
48 CONSTANT _LIBEO-GENERATION
56 CONSTANT _LIBEO-SHA
88 CONSTANT _LIBEO-RESERVED
96 CONSTANT LIBRARY-EVIDENCE-OBJECT-SIZE

: LIBEO.STATE            ( object -- a ) _LIBEO-STATE + ;
: LIBEO.FLAGS            ( object -- a ) _LIBEO-FLAGS + ;
: LIBEO.RAW-OFFSET       ( object -- a ) _LIBEO-RAW-OFFSET + ;
: LIBEO.RAW-U            ( object -- a ) _LIBEO-RAW-U + ;
: LIBEO.ENVELOPE-FORMAT  ( object -- a ) _LIBEO-ENVELOPE-FORMAT + ;
: LIBEO.STORE-FORMAT     ( object -- a ) _LIBEO-STORE-FORMAT + ;
: LIBEO.GENERATION       ( object -- a ) _LIBEO-GENERATION + ;
: LIBEO.SHA              ( object -- digest ) _LIBEO-SHA + ;

\ One complete report (160-byte header plus seven object records).
  0 CONSTANT _LIBINS-HEALTH
  8 CONSTANT _LIBINS-REPAIR-MASK
 16 CONSTANT _LIBINS-RAW-REQUIRED
 24 CONSTANT _LIBINS-FLAGS
 32 CONSTANT _LIBINS-HEAD-GENERATION
 40 CONSTANT _LIBINS-SELECTED-BANK
 48 CONSTANT _LIBINS-CATALOG-COUNT
 56 CONSTANT _LIBINS-COLLECTION-COUNT
 64 CONSTANT _LIBINS-MUTATION-SEQUENCE
 72 CONSTANT _LIBINS-CONTENT-TAIL
 80 CONSTANT _LIBINS-CONTENT-RECORD-COUNT
 88 CONSTANT _LIBINS-RESERVED
 96 CONSTANT _LIBINS-EVIDENCE-SEAL
128 CONSTANT _LIBINS-REPAIRED-SEAL
160 CONSTANT _LIBINS-OBJECTS
832 CONSTANT LIBRARY-INSPECTION-SIZE

: LIBINS.HEALTH               ( inspection -- a ) _LIBINS-HEALTH + ;
: LIBINS.REPAIR-MASK          ( inspection -- a ) _LIBINS-REPAIR-MASK + ;
: LIBINS.RAW-REQUIRED         ( inspection -- a ) _LIBINS-RAW-REQUIRED + ;
: LIBINS.FLAGS                ( inspection -- a ) _LIBINS-FLAGS + ;
: LIBINS.HEAD-GENERATION      ( inspection -- a ) _LIBINS-HEAD-GENERATION + ;
: LIBINS.SELECTED-BANK        ( inspection -- a ) _LIBINS-SELECTED-BANK + ;
: LIBINS.CATALOG-COUNT        ( inspection -- a ) _LIBINS-CATALOG-COUNT + ;
: LIBINS.COLLECTION-COUNT     ( inspection -- a ) _LIBINS-COLLECTION-COUNT + ;
: LIBINS.MUTATION-SEQUENCE    ( inspection -- a ) _LIBINS-MUTATION-SEQUENCE + ;
: LIBINS.CONTENT-TAIL         ( inspection -- a ) _LIBINS-CONTENT-TAIL + ;
: LIBINS.CONTENT-RECORD-COUNT ( inspection -- a ) _LIBINS-CONTENT-RECORD-COUNT + ;
: LIBINS.EVIDENCE-SEAL        ( inspection -- digest )
    _LIBINS-EVIDENCE-SEAL + ;
: LIBINS.REPAIRED-SEAL        ( inspection -- digest )
    _LIBINS-REPAIRED-SEAL + ;
: LIBINS-OBJECT  ( object-id inspection -- object )
    _LIBINS-OBJECTS + SWAP LIBRARY-EVIDENCE-OBJECT-SIZE * + ;

: LIBRARY-INSPECTION-INIT  ( inspection -- )
    LIBRARY-INSPECTION-SIZE 0 FILL ;

\ =====================================================================
\  Caller-owned managed-document create request
\ =====================================================================
\  Content bytes are borrowed only for the synchronous create call.  The
\  operation key and title are inline so retry comparison never depends on
\  mutable caller pointers after validation begins.

  0 CONSTANT _LIBMCR-OPERATION-KEY
 32 CONSTANT _LIBMCR-EXPECTED-CATALOG-GENERATION
 40 CONSTANT _LIBMCR-MEDIA
 48 CONSTANT _LIBMCR-TITLE-U
 56 CONSTANT _LIBMCR-CONTENT-A
 64 CONSTANT _LIBMCR-CONTENT-U
 72 CONSTANT _LIBMCR-FLAGS
 80 CONSTANT _LIBMCR-TITLE
208 CONSTANT LIBRARY-MANAGED-CREATE-REQUEST-SIZE

: LIBMCR.OPERATION-KEY       ( request -- key ) _LIBMCR-OPERATION-KEY + ;
: LIBMCR.EXPECTED-CATALOG-GENERATION  ( request -- a )
    _LIBMCR-EXPECTED-CATALOG-GENERATION + ;
: LIBMCR.MEDIA               ( request -- a ) _LIBMCR-MEDIA + ;
: LIBMCR.TITLE-U             ( request -- a ) _LIBMCR-TITLE-U + ;
: LIBMCR.CONTENT-A           ( request -- a ) _LIBMCR-CONTENT-A + ;
: LIBMCR.CONTENT-U           ( request -- a ) _LIBMCR-CONTENT-U + ;
: LIBMCR.FLAGS               ( request -- a ) _LIBMCR-FLAGS + ;
: LIBMCR.TITLE               ( request -- a ) _LIBMCR-TITLE + ;
: LIBMCR-TITLE$  ( request -- a u ) DUP LIBMCR.TITLE SWAP LIBMCR.TITLE-U @ ;
: LIBMCR-CONTENT$  ( request -- a u )
    DUP LIBMCR.CONTENT-A @ SWAP LIBMCR.CONTENT-U @ ;

: LIBRARY-MANAGED-CREATE-REQUEST-INIT  ( request -- )
    LIBRARY-MANAGED-CREATE-REQUEST-SIZE 0 FILL ;

\ =====================================================================
\  Caller-owned immutable-capture import request
\ =====================================================================
\  The exact origin is copied inline.  Content bytes are borrowed only for
\  the synchronous call; the owner derives every persisted provenance and
\  receipt fact from the closed origin union.

  0 CONSTANT _LIBCIR-OPERATION-KEY
 32 CONSTANT _LIBCIR-EXPECTED-CATALOG-GENERATION
 40 CONSTANT _LIBCIR-MEDIA
 48 CONSTANT _LIBCIR-TITLE-U
 56 CONSTANT _LIBCIR-CONTENT-A
 64 CONSTANT _LIBCIR-CONTENT-U
 72 CONSTANT _LIBCIR-FLAGS
 80 CONSTANT _LIBCIR-TITLE
208 CONSTANT _LIBCIR-ORIGIN
536 CONSTANT LIBRARY-CAPTURE-IMPORT-REQUEST-SIZE

: LIBCIR.OPERATION-KEY      ( request -- key ) _LIBCIR-OPERATION-KEY + ;
: LIBCIR.EXPECTED-CATALOG-GENERATION  ( request -- a )
    _LIBCIR-EXPECTED-CATALOG-GENERATION + ;
: LIBCIR.MEDIA              ( request -- a ) _LIBCIR-MEDIA + ;
: LIBCIR.TITLE-U            ( request -- a ) _LIBCIR-TITLE-U + ;
: LIBCIR.CONTENT-A          ( request -- a ) _LIBCIR-CONTENT-A + ;
: LIBCIR.CONTENT-U          ( request -- a ) _LIBCIR-CONTENT-U + ;
: LIBCIR.FLAGS              ( request -- a ) _LIBCIR-FLAGS + ;
: LIBCIR.TITLE              ( request -- a ) _LIBCIR-TITLE + ;
: LIBCIR.ORIGIN             ( request -- origin ) _LIBCIR-ORIGIN + ;
: LIBCIR-TITLE$  ( request -- a u )
    DUP LIBCIR.TITLE SWAP LIBCIR.TITLE-U @ ;
: LIBCIR-CONTENT$  ( request -- a u )
    DUP LIBCIR.CONTENT-A @ SWAP LIBCIR.CONTENT-U @ ;

: LIBRARY-CAPTURE-IMPORT-REQUEST-INIT  ( request -- )
    LIBRARY-CAPTURE-IMPORT-REQUEST-SIZE 0 FILL ;

\ =====================================================================
\  Caller-owned whole metadata replacement
\ =====================================================================
\  Metadata contains only the mutable descriptive fields.  Kind, media,
\  content identity, origin, clocks, lifecycle, and receipt remain owner
\  controlled and cannot be smuggled through this shape.

   0 CONSTANT _LIBMD-TITLE-U
   8 CONSTANT _LIBMD-TAG-N
  16 CONSTANT _LIBMD-LINEAGE-N
  24 CONSTANT _LIBMD-FLAGS
  32 CONSTANT _LIBMD-TITLE
 160 CONSTANT _LIBMD-TAGS
 672 CONSTANT _LIBMD-LINEAGE
1984 CONSTANT LIBRARY-METADATA-SIZE

: LIBMD.TITLE-U    ( metadata -- a ) _LIBMD-TITLE-U + ;
: LIBMD.TAG-N      ( metadata -- a ) _LIBMD-TAG-N + ;
: LIBMD.LINEAGE-N  ( metadata -- a ) _LIBMD-LINEAGE-N + ;
: LIBMD.FLAGS      ( metadata -- a ) _LIBMD-FLAGS + ;
: LIBMD.TITLE      ( metadata -- a ) _LIBMD-TITLE + ;
: LIBMD-TAG  ( index metadata -- tag )
    _LIBMD-TAGS + SWAP LIB-TAG-SIZE * + ;
: LIBMD-LINEAGE  ( index metadata -- lineage )
    _LIBMD-LINEAGE + SWAP LIB-LINEAGE-SIZE * + ;
: LIBMD-TITLE$  ( metadata -- a u )
    DUP LIBMD.TITLE SWAP LIBMD.TITLE-U @ ;
: LIBRARY-METADATA-INIT  ( metadata -- )
    LIBRARY-METADATA-SIZE 0 FILL ;

\ =====================================================================
\  Public retained-revision summary
\ =====================================================================

 0 CONSTANT _LIBRS-DOMAIN-REVISION
 8 CONSTANT _LIBRS-CONTENT-REVISION
16 CONSTANT _LIBRS-MEDIA
24 CONSTANT _LIBRS-CONTENT-U
32 CONSTANT _LIBRS-DIGEST
64 CONSTANT LIBRARY-REVISION-SUMMARY-SIZE

: LIBRS.DOMAIN-REVISION   ( summary -- a ) _LIBRS-DOMAIN-REVISION + ;
: LIBRS.CONTENT-REVISION  ( summary -- a ) _LIBRS-CONTENT-REVISION + ;
: LIBRS.MEDIA             ( summary -- a ) _LIBRS-MEDIA + ;
: LIBRS.CONTENT-U         ( summary -- a ) _LIBRS-CONTENT-U + ;
: LIBRS.DIGEST            ( summary -- digest ) _LIBRS-DIGEST + ;
: LIBRARY-REVISION-SUMMARY-INIT  ( summary -- )
    LIBRARY-REVISION-SUMMARY-SIZE 0 FILL ;

\ =====================================================================
\  RID-based collection requests and semantic view
\ =====================================================================
\  Persistent membership is a private slot bitmap.  Callers supply and
\  receive stable RIDs; no catalog slot or path crosses this boundary.

  0 CONSTANT _LIBCCR-OPERATION-KEY
 32 CONSTANT _LIBCCR-EXPECTED-CATALOG-GENERATION
 40 CONSTANT _LIBCCR-TITLE-U
 48 CONSTANT _LIBCCR-MEMBERS-A
 56 CONSTANT _LIBCCR-MEMBER-N
 64 CONSTANT _LIBCCR-FLAGS
 72 CONSTANT _LIBCCR-TITLE
136 CONSTANT LIBRARY-COLLECTION-CREATE-REQUEST-SIZE

: LIBCCR.OPERATION-KEY  ( request -- key ) _LIBCCR-OPERATION-KEY + ;
: LIBCCR.EXPECTED-CATALOG-GENERATION  ( request -- a )
    _LIBCCR-EXPECTED-CATALOG-GENERATION + ;
: LIBCCR.TITLE-U       ( request -- a ) _LIBCCR-TITLE-U + ;
: LIBCCR.MEMBERS-A     ( request -- a ) _LIBCCR-MEMBERS-A + ;
: LIBCCR.MEMBER-N      ( request -- a ) _LIBCCR-MEMBER-N + ;
: LIBCCR.FLAGS         ( request -- a ) _LIBCCR-FLAGS + ;
: LIBCCR.TITLE         ( request -- a ) _LIBCCR-TITLE + ;
: LIBCCR-TITLE$  ( request -- a u )
    DUP LIBCCR.TITLE SWAP LIBCCR.TITLE-U @ ;
: LIBCCR-MEMBERS$  ( request -- a count )
    DUP LIBCCR.MEMBERS-A @ SWAP LIBCCR.MEMBER-N @ ;
: LIBRARY-COLLECTION-CREATE-REQUEST-INIT  ( request -- )
    LIBRARY-COLLECTION-CREATE-REQUEST-SIZE 0 FILL ;

  0 CONSTANT _LIBCRR-ID
 32 CONSTANT _LIBCRR-EXPECTED-REVISION
 40 CONSTANT _LIBCRR-TITLE-U
 48 CONSTANT _LIBCRR-MEMBERS-A
 56 CONSTANT _LIBCRR-MEMBER-N
 64 CONSTANT _LIBCRR-FLAGS
 72 CONSTANT _LIBCRR-TITLE
136 CONSTANT LIBRARY-COLLECTION-REPLACE-REQUEST-SIZE

: LIBCRR.ID             ( request -- id ) _LIBCRR-ID + ;
: LIBCRR.EXPECTED-REVISION  ( request -- a ) _LIBCRR-EXPECTED-REVISION + ;
: LIBCRR.TITLE-U        ( request -- a ) _LIBCRR-TITLE-U + ;
: LIBCRR.MEMBERS-A      ( request -- a ) _LIBCRR-MEMBERS-A + ;
: LIBCRR.MEMBER-N       ( request -- a ) _LIBCRR-MEMBER-N + ;
: LIBCRR.FLAGS          ( request -- a ) _LIBCRR-FLAGS + ;
: LIBCRR.TITLE          ( request -- a ) _LIBCRR-TITLE + ;
: LIBCRR-TITLE$  ( request -- a u )
    DUP LIBCRR.TITLE SWAP LIBCRR.TITLE-U @ ;
: LIBCRR-MEMBERS$  ( request -- a count )
    DUP LIBCRR.MEMBERS-A @ SWAP LIBCRR.MEMBER-N @ ;
: LIBRARY-COLLECTION-REPLACE-REQUEST-INIT  ( request -- )
    LIBRARY-COLLECTION-REPLACE-REQUEST-SIZE 0 FILL ;

   0 CONSTANT _LIBCV-ID
  32 CONSTANT _LIBCV-REVISION
  40 CONSTANT _LIBCV-MUTATION-SEQUENCE
  48 CONSTANT _LIBCV-TITLE-U
  56 CONSTANT _LIBCV-MEMBER-N
  64 CONSTANT _LIBCV-FLAGS
  72 CONSTANT _LIBCV-TITLE
 136 CONSTANT _LIBCV-MEMBERS
4232 CONSTANT LIBRARY-COLLECTION-VIEW-SIZE

: LIBCV.ID                 ( view -- id ) _LIBCV-ID + ;
: LIBCV.REVISION           ( view -- a ) _LIBCV-REVISION + ;
: LIBCV.MUTATION-SEQUENCE  ( view -- a ) _LIBCV-MUTATION-SEQUENCE + ;
: LIBCV.TITLE-U            ( view -- a ) _LIBCV-TITLE-U + ;
: LIBCV.MEMBER-N           ( view -- a ) _LIBCV-MEMBER-N + ;
: LIBCV.FLAGS              ( view -- a ) _LIBCV-FLAGS + ;
: LIBCV.TITLE              ( view -- a ) _LIBCV-TITLE + ;
: LIBCV-MEMBER  ( index view -- rid )
    _LIBCV-MEMBERS + SWAP LIB-DIGEST-SIZE * + ;
: LIBCV-TITLE$  ( view -- a u ) DUP LIBCV.TITLE SWAP LIBCV.TITLE-U @ ;
: LIBRARY-COLLECTION-VIEW-INIT  ( view -- )
    LIBRARY-COLLECTION-VIEW-SIZE 0 FILL ;

\ =====================================================================
\  Caller-owned catalog-query summary
\ =====================================================================
\  A query does not disclose the entry's full receipt, origin, tags, or
\  lineage.  Its identity RREF has revision zero; DOMAIN-REVISION is the
\  exact durable Library revision used by an exact read.

32 CONSTANT LIBRARY-QUERY-PAGE-MAX

  0 CONSTANT _LIBQS-REF
 80 CONSTANT _LIBQS-DOMAIN-REVISION
 88 CONSTANT _LIBQS-KIND
 96 CONSTANT _LIBQS-LIFECYCLE
104 CONSTANT _LIBQS-MEDIA
112 CONSTANT _LIBQS-CONTENT-U
120 CONSTANT _LIBQS-MUTATION-SEQUENCE
128 CONSTANT _LIBQS-CONTENT-DIGEST
160 CONSTANT _LIBQS-TITLE-U
168 CONSTANT _LIBQS-TITLE
296 CONSTANT LIBRARY-QUERY-SUMMARY-SIZE

: LIBQS.REF               ( summary -- rref ) _LIBQS-REF + ;
: LIBQS.DOMAIN-REVISION   ( summary -- a ) _LIBQS-DOMAIN-REVISION + ;
: LIBQS.KIND              ( summary -- a ) _LIBQS-KIND + ;
: LIBQS.LIFECYCLE         ( summary -- a ) _LIBQS-LIFECYCLE + ;
: LIBQS.MEDIA             ( summary -- a ) _LIBQS-MEDIA + ;
: LIBQS.CONTENT-U         ( summary -- a ) _LIBQS-CONTENT-U + ;
: LIBQS.MUTATION-SEQUENCE ( summary -- a ) _LIBQS-MUTATION-SEQUENCE + ;
: LIBQS.CONTENT-DIGEST    ( summary -- digest ) _LIBQS-CONTENT-DIGEST + ;
: LIBQS.TITLE-U           ( summary -- a ) _LIBQS-TITLE-U + ;
: LIBQS.TITLE             ( summary -- a ) _LIBQS-TITLE + ;
: LIBQS-TITLE$  ( summary -- a u )
    DUP LIBQS.TITLE SWAP LIBQS.TITLE-U @ ;

: LIBRARY-QUERY-SUMMARY-INIT  ( summary -- )
    DUP LIBRARY-QUERY-SUMMARY-SIZE 0 FILL LIBQS.REF RREF-INIT ;

\ =====================================================================
\  Caller-owned bounded corpus-query request
\ =====================================================================
\  An empty term is an explicit bounded browse.  A nonempty term selects one
\  or more title/body/tag fields.  Collection is either an all-zero RID (no
\  collection filter) or one exact collection RID.  Continuations copy both
\  the returned generation and next raw catalog slot back into the request and
\  retain the same term and scope masks.

1 CONSTANT LIBRARY-CORPUS-LIFECYCLE-ACTIVE
2 CONSTANT LIBRARY-CORPUS-LIFECYCLE-ARCHIVED
3 CONSTANT LIBRARY-CORPUS-LIFECYCLE-ALL

1 CONSTANT LIBRARY-CORPUS-KIND-MANAGED
2 CONSTANT LIBRARY-CORPUS-KIND-CAPTURE
3 CONSTANT LIBRARY-CORPUS-KIND-ALL

1 CONSTANT LIBRARY-CORPUS-MEDIA-PLAIN
2 CONSTANT LIBRARY-CORPUS-MEDIA-MARKDOWN
4 CONSTANT LIBRARY-CORPUS-MEDIA-CSV
7 CONSTANT LIBRARY-CORPUS-MEDIA-ALL

1 CONSTANT LIBRARY-CORPUS-FIELD-TITLE
2 CONSTANT LIBRARY-CORPUS-FIELD-BODY
4 CONSTANT LIBRARY-CORPUS-FIELD-TAGS
7 CONSTANT LIBRARY-CORPUS-FIELD-ALL

128 CONSTANT LIBRARY-CORPUS-TERM-MAX

  0 CONSTANT _LIBCQR-EXPECTED-CATALOG-GENERATION
  8 CONSTANT _LIBCQR-START-SLOT
 16 CONSTANT _LIBCQR-LIFECYCLE-MASK
 24 CONSTANT _LIBCQR-KIND-MASK
 32 CONSTANT _LIBCQR-MEDIA-MASK
 40 CONSTANT _LIBCQR-FIELD-MASK
 48 CONSTANT _LIBCQR-FLAGS
 56 CONSTANT _LIBCQR-TERM-U
 64 CONSTANT _LIBCQR-COLLECTION
 96 CONSTANT _LIBCQR-TERM
224 CONSTANT LIBRARY-CORPUS-QUERY-REQUEST-SIZE

: LIBCQR.EXPECTED-CATALOG-GENERATION  ( request -- a )
    _LIBCQR-EXPECTED-CATALOG-GENERATION + ;
: LIBCQR.START-SLOT       ( request -- a ) _LIBCQR-START-SLOT + ;
: LIBCQR.LIFECYCLE-MASK   ( request -- a ) _LIBCQR-LIFECYCLE-MASK + ;
: LIBCQR.KIND-MASK        ( request -- a ) _LIBCQR-KIND-MASK + ;
: LIBCQR.MEDIA-MASK       ( request -- a ) _LIBCQR-MEDIA-MASK + ;
: LIBCQR.FIELD-MASK       ( request -- a ) _LIBCQR-FIELD-MASK + ;
: LIBCQR.FLAGS            ( request -- a ) _LIBCQR-FLAGS + ;
: LIBCQR.TERM-U           ( request -- a ) _LIBCQR-TERM-U + ;
: LIBCQR.COLLECTION       ( request -- rid ) _LIBCQR-COLLECTION + ;
: LIBCQR.TERM             ( request -- a ) _LIBCQR-TERM + ;
: LIBCQR-TERM$  ( request -- a u )
    DUP LIBCQR.TERM SWAP LIBCQR.TERM-U @ ;

: LIBRARY-CORPUS-QUERY-REQUEST-INIT  ( request -- )
    DUP LIBRARY-CORPUS-QUERY-REQUEST-SIZE 0 FILL
    DUP LIBRARY-CORPUS-LIFECYCLE-ACTIVE SWAP LIBCQR.LIFECYCLE-MASK !
    DUP LIBRARY-CORPUS-KIND-ALL SWAP LIBCQR.KIND-MASK !
    DUP LIBRARY-CORPUS-MEDIA-ALL SWAP LIBCQR.MEDIA-MASK !
    LIBRARY-CORPUS-FIELD-ALL SWAP LIBCQR.FIELD-MASK ! ;

\ =====================================================================
\  Public bounded collection-query summary
\ =====================================================================

  0 CONSTANT _LIBCS-REF
 80 CONSTANT _LIBCS-REVISION
 88 CONSTANT _LIBCS-MUTATION-SEQUENCE
 96 CONSTANT _LIBCS-MEMBER-N
104 CONSTANT _LIBCS-FLAGS
112 CONSTANT _LIBCS-TITLE-U
120 CONSTANT _LIBCS-TITLE
184 CONSTANT LIBRARY-COLLECTION-SUMMARY-SIZE

: LIBCS.REF               ( summary -- rref ) _LIBCS-REF + ;
: LIBCS.REVISION          ( summary -- a ) _LIBCS-REVISION + ;
: LIBCS.MUTATION-SEQUENCE ( summary -- a ) _LIBCS-MUTATION-SEQUENCE + ;
: LIBCS.MEMBER-N          ( summary -- a ) _LIBCS-MEMBER-N + ;
: LIBCS.FLAGS             ( summary -- a ) _LIBCS-FLAGS + ;
: LIBCS.TITLE-U           ( summary -- a ) _LIBCS-TITLE-U + ;
: LIBCS.TITLE             ( summary -- a ) _LIBCS-TITLE + ;
: LIBCS-TITLE$  ( summary -- a u )
    DUP LIBCS.TITLE SWAP LIBCS.TITLE-U @ ;

: LIBRARY-COLLECTION-SUMMARY-INIT  ( summary -- )
    DUP LIBRARY-COLLECTION-SUMMARY-SIZE 0 FILL LIBCS.REF RREF-INIT ;

\ =====================================================================
\  Sealed Library-private topology
\ =====================================================================
\  There is intentionally no caller-selected path and no public path
\  accessor.  These names are storage topology, never semantic identity.

: _LIBVFS-DIRECTORY$     ( -- a u ) S" /library" ;
: _LIBVFS-DIRECTORY-NAME$ ( -- a u ) S" library" ;
: _LIBVFS-HEAD-PATH$     ( -- a u ) S" /library/head.bin" ;
: _LIBVFS-BANK-A-PATH$   ( -- a u ) S" /library/catalog-a.bin" ;
: _LIBVFS-BANK-B-PATH$   ( -- a u ) S" /library/catalog-b.bin" ;
: _LIBVFS-CONTENT-PATH$  ( -- a u ) S" /library/content.bin" ;
: _LIBVFS-HEAD-STAGE-PATH$  ( -- a u )
    S" /library/.s-6rmqm5qfh6dxiytnh65y" ;
: _LIBVFS-HEAD-BACKUP-PATH$  ( -- a u )
    S" /library/.b-6rmqm5qfh6dxiytnh65y" ;
: _LIBVFS-HEAD-MARKER-PATH$  ( -- a u )
    S" /library/.m-6rmqm5qfh6dxiytnh65y" ;

\ =====================================================================
\  Static head specification and public store descriptor
\ =====================================================================

1 CONSTANT _LIBVFS-HEAD-ENVELOPE-FORMAT-V1

CREATE _LIBVFS-HEAD-RECORD-MAGIC
65 C, 75 C, 76 C, 72 C, 68 C, 48 C, 48 C, 49 C,  \ "AKLHD001"

CREATE _LIBVFS-HEAD-SPEC VFSNAP-SPEC-SIZE ALLOT

0x4C49425646535431 CONSTANT _LIBVFS-STORE-MAGIC  \ "LIBVFST1"
1 CONSTANT _LIBVFS-F-BLOCKED
2 CONSTANT _LIBVFS-F-PROVISIONED
4 CONSTANT _LIBVFS-F-CLEANUP-FAILED
8 CONSTANT _LIBVFS-F-LOADED
9 CONSTANT _LIBVFS-HEAD-NAME-BASE

 0 CONSTANT _LIBVS-MAGIC
 8 CONSTANT _LIBVS-VFS
16 CONSTANT _LIBVS-FLAGS
24 CONSTANT _LIBVS-LAST-STATUS
32 CONSTANT _LIBVS-LAST-VFSNAP
40 CONSTANT _LIBVS-LAST-VREPL
48 CONSTANT _LIBVS-CORE
_LIBVS-CORE VFSNAP-STORE-SIZE + CONSTANT _LIBVS-SNAPSHOT-SCRATCH
_LIBVS-SNAPSHOT-SCRATCH VFSNAP-HEADER-SIZE LIB-HEAD-PAYLOAD-SIZE + +
    CONSTANT _LIBVS-HEAD-PAYLOAD
_LIBVS-HEAD-PAYLOAD LIB-HEAD-PAYLOAD-SIZE +
    CONSTANT _LIBVS-CANDIDATE-GENERATION
_LIBVS-CANDIDATE-GENERATION 8 + CONSTANT _LIBVS-HEAD-GENERATION
_LIBVS-HEAD-GENERATION 8 + CONSTANT _LIBVS-HEAD-FACT
_LIBVS-HEAD-FACT LIB-HEAD-FACT-SIZE + CONSTANT _LIBVS-ARENA-FACT
_LIBVS-ARENA-FACT LIB-ARENA-FACT-SIZE + CONSTANT _LIBVS-BANK-FACT
_LIBVS-BANK-FACT LIB-BANK-FACT-SIZE + CONSTANT LIBRARY-VFS-STORE-SIZE

: LIBRARY-VFS-STORE.MAGIC        ( store -- a ) _LIBVS-MAGIC + ;
: LIBRARY-VFS-STORE.VFS          ( store -- a ) _LIBVS-VFS + ;
: LIBRARY-VFS-STORE.FLAGS        ( store -- a ) _LIBVS-FLAGS + ;
: LIBRARY-VFS-STORE.LAST-STATUS  ( store -- a ) _LIBVS-LAST-STATUS + ;
: LIBRARY-VFS-STORE.LAST-VFSNAP  ( store -- a ) _LIBVS-LAST-VFSNAP + ;
: LIBRARY-VFS-STORE.LAST-VREPL   ( store -- a ) _LIBVS-LAST-VREPL + ;
: _LIBRARY-VFS-STORE.CORE        ( store -- core ) _LIBVS-CORE + ;
: LIBRARY-VFS-STORE.HEAD         ( store -- head-fact ) _LIBVS-HEAD-FACT + ;
: LIBRARY-VFS-STORE.ARENA        ( store -- arena-fact ) _LIBVS-ARENA-FACT + ;
: LIBRARY-VFS-STORE.BANK         ( store -- bank-fact ) _LIBVS-BANK-FACT + ;
: LIBRARY-VFS-STORE.GENERATION   ( store -- a ) _LIBVS-HEAD-GENERATION + ;

: _LIBVFS-SNAPSHOT-SCRATCH  ( store -- a ) _LIBVS-SNAPSHOT-SCRATCH + ;
: _LIBVFS-HEAD-PAYLOAD      ( store -- a ) _LIBVS-HEAD-PAYLOAD + ;
: _LIBVFS-CANDIDATE-GENERATION  ( store -- a )
    _LIBVS-CANDIDATE-GENERATION + ;

: _LIBVFS-TOPOLOGY-ALIASES?  ( address length -- flag )
    2DUP _LIBVFS-DIRECTORY$ _VFSNAP-RANGES-OVERLAP? IF
        2DROP -1 EXIT
    THEN
    2DUP _LIBVFS-DIRECTORY-NAME$ _VFSNAP-RANGES-OVERLAP? IF
        2DROP -1 EXIT
    THEN
    2DUP _LIBVFS-HEAD-PATH$ _VFSNAP-RANGES-OVERLAP? IF
        2DROP -1 EXIT
    THEN
    2DUP _LIBVFS-BANK-A-PATH$ _VFSNAP-RANGES-OVERLAP? IF
        2DROP -1 EXIT
    THEN
    2DUP _LIBVFS-BANK-B-PATH$ _VFSNAP-RANGES-OVERLAP? IF
        2DROP -1 EXIT
    THEN
    2DUP _LIBVFS-CONTENT-PATH$ _VFSNAP-RANGES-OVERLAP? IF
        2DROP -1 EXIT
    THEN
    2DUP _LIBVFS-HEAD-STAGE-PATH$ _VFSNAP-RANGES-OVERLAP? IF
        2DROP -1 EXIT
    THEN
    2DUP _LIBVFS-HEAD-BACKUP-PATH$ _VFSNAP-RANGES-OVERLAP? IF
        2DROP -1 EXIT
    THEN
    2DUP _LIBVFS-HEAD-MARKER-PATH$ _VFSNAP-RANGES-OVERLAP? IF
        2DROP -1 EXIT
    THEN
    _LIBVFS-HEAD-RECORD-MAGIC 8 _VFSNAP-RANGES-OVERLAP? ;

: LIBRARY-VFS-STORE-BLOCKED?  ( store -- flag )
    LIBRARY-VFS-STORE.FLAGS @ _LIBVFS-F-BLOCKED AND 0<> ;
: LIBRARY-VFS-STORE-PROVISIONED?  ( store -- flag )
    LIBRARY-VFS-STORE.FLAGS @ _LIBVFS-F-PROVISIONED AND 0<> ;
: LIBRARY-VFS-STORE-CLEANUP-FAILED?  ( store -- flag )
    LIBRARY-VFS-STORE.FLAGS @ _LIBVFS-F-CLEANUP-FAILED AND 0<> ;
: LIBRARY-VFS-STORE-LOADED?  ( store -- flag )
    LIBRARY-VFS-STORE.FLAGS @ _LIBVFS-F-LOADED AND 0<> ;

: _LIBVFS-PRIVATE-ALIASES?  ( address length -- flag )
    2DUP _LIBVFS-TOPOLOGY-ALIASES? IF 2DROP -1 EXIT THEN
    2DUP _LIBVFS-HEAD-SPEC _VFSNAP-ALL-PRIVATE-ALIASES? IF
        2DROP -1 EXIT
    THEN
    _LIBVFS-HEAD-SPEC VFSNAP-SPEC-SIZE _VFSNAP-RANGES-OVERLAP? ;

: _LIBVFS-STORE-SPAN-SAFE?  ( store -- flag )
    DUP LIBRARY-VFS-STORE-SIZE _VFSNAP-SPAN-VALID? 0= IF DROP 0 EXIT THEN
    DUP LIBRARY-VFS-STORE-SIZE _LIBVFS-PRIVATE-ALIASES? 0= NIP ;

: LIBRARY-VFS-STORE-VALID?  ( store -- flag )
    DUP _LIBVFS-STORE-SPAN-SAFE? 0= IF DROP 0 EXIT THEN
    DUP LIBRARY-VFS-STORE.MAGIC @ _LIBVFS-STORE-MAGIC <> IF DROP 0 EXIT THEN
    DUP LIBRARY-VFS-STORE.VFS @ 0= IF DROP 0 EXIT THEN
    DUP _LIBRARY-VFS-STORE.CORE VFSNAP-VALID? 0= IF DROP 0 EXIT THEN
    DUP _LIBRARY-VFS-STORE.CORE VFSNAP.SPEC @
        _LIBVFS-HEAD-SPEC <> IF DROP 0 EXIT THEN
    DUP _LIBRARY-VFS-STORE.CORE VFSNAP.SCRATCH-A @
        OVER _LIBVFS-SNAPSHOT-SCRATCH <> IF DROP 0 EXIT THEN
    DUP _LIBRARY-VFS-STORE.CORE VFSNAP.SCRATCH-U @
        VFSNAP-HEADER-SIZE LIB-HEAD-PAYLOAD-SIZE + <> IF DROP 0 EXIT THEN
    DUP _LIBVFS-CANDIDATE-GENERATION @ 0<> IF DROP 0 EXIT THEN
    DUP _LIBRARY-VFS-STORE.CORE VFSNAP.CLOSE-XT @
        ['] VFS-CLOSE <> IF DROP 0 EXIT THEN
    DUP _LIBRARY-VFS-STORE.CORE VFSNAP.RESTORE-XT @
        ['] VFS-USE <> IF DROP 0 EXIT THEN
    DUP LIBRARY-VFS-STORE.VFS @
        OVER _LIBRARY-VFS-STORE.CORE VFSNAP.REPLACE VREPL.VFS @
        <> IF DROP 0 EXIT THEN
    DUP _LIBRARY-VFS-STORE.CORE VFSNAP.REPLACE VREPL.PRE-XT @
        0<> IF DROP 0 EXIT THEN
    DUP _LIBRARY-VFS-STORE.CORE VFSNAP.REPLACE VREPL.PRE-DATA @
        0<> IF DROP 0 EXIT THEN
    DUP _LIBRARY-VFS-STORE.CORE VFSNAP.REPLACE VREPL.TARGET-BASE @
        _LIBVFS-HEAD-NAME-BASE <> IF DROP 0 EXIT THEN
    DUP _LIBRARY-VFS-STORE.CORE VFSNAP.REPLACE VREPL.STAGE-BASE @
        _LIBVFS-HEAD-NAME-BASE <> IF DROP 0 EXIT THEN
    DUP _LIBRARY-VFS-STORE.CORE VFSNAP.REPLACE VREPL.BACKUP-BASE @
        _LIBVFS-HEAD-NAME-BASE <> IF DROP 0 EXIT THEN
    DUP _LIBRARY-VFS-STORE.CORE VFSNAP.REPLACE VREPL.MARKER-BASE @
        _LIBVFS-HEAD-NAME-BASE <> IF DROP 0 EXIT THEN
    DUP _LIBRARY-VFS-STORE.CORE VFSNAP-PATH$
        _LIBVFS-HEAD-PATH$ COMPARE IF DROP 0 EXIT THEN
    DUP _LIBRARY-VFS-STORE.CORE VFSNAP.REPLACE VREPL-STAGE$
        _LIBVFS-HEAD-STAGE-PATH$ COMPARE IF DROP 0 EXIT THEN
    DUP _LIBRARY-VFS-STORE.CORE VFSNAP.REPLACE VREPL-BACKUP$
        _LIBVFS-HEAD-BACKUP-PATH$ COMPARE IF DROP 0 EXIT THEN
    DUP _LIBRARY-VFS-STORE.CORE VFSNAP.REPLACE VREPL-MARKER$
        _LIBVFS-HEAD-MARKER-PATH$ COMPARE IF DROP 0 EXIT THEN
    DUP LIBRARY-VFS-STORE.VFS @ SWAP _LIBRARY-VFS-STORE.CORE
        VFSNAP.VFS @ = ;

\ =====================================================================
\  Serialized deterministic VFS hooks
\ =====================================================================
\  Production always installs the real public VFS words.  The private
\  hooks let the contract leaf fail each boundary deterministically.  A
\  single Library guard serializes their use, so they are intentionally
\  not caller-visible policy or per-instance descriptor state.

CREATE _LIBVFS-PRIVATE-BEGIN 0 ALLOT

GUARD _library-vfs-store-guard

VARIABLE _LIBVFS-RESOLVE-XT
VARIABLE _LIBVFS-OPEN-XT
VARIABLE _LIBVFS-CLOSE-XT
VARIABLE _LIBVFS-READ-EXACT-XT
VARIABLE _LIBVFS-WRITE-EXACT-XT
VARIABLE _LIBVFS-SEEK-XT
VARIABLE _LIBVFS-SIZE-XT
VARIABLE _LIBVFS-TRUNCATE-XT
VARIABLE _LIBVFS-CREATE-XT
VARIABLE _LIBVFS-MKDIR-XT
VARIABLE _LIBVFS-SYNC-XT
VARIABLE _LIBVFS-USE-XT
VARIABLE _LIBVFS-CD-XT

VARIABLE _LIBVN-EXPECTED-TYPE

\ Provisioning is one guarded transaction.  These cells and the one-sector
\ buffer are never persisted and are included in the callback-private span.
VARIABLE _LIBVP-STORE
VARIABLE _LIBVP-VFS
VARIABLE _LIBVP-FD
VARIABLE _LIBVP-OLD-VFS
VARIABLE _LIBVP-HAVE-OLD-VFS
VARIABLE _LIBVP-OLD-CWD
VARIABLE _LIBVP-HAVE-OLD-CWD
VARIABLE _LIBVP-STATUS
VARIABLE _LIBVP-THROW-STATUS
VARIABLE _LIBVP-CLEAN-FD
VARIABLE _LIBVP-CLEAN-FAILED
VARIABLE _LIBVP-CLEANUP-EVIDENCE
VARIABLE _LIBVP-PATH-A
VARIABLE _LIBVP-PATH-U
VARIABLE _LIBVP-FILE-U
VARIABLE _LIBVP-BODY-XT
VARIABLE _LIBVP-REMAINING
VARIABLE _LIBVP-CHUNK
VARIABLE _LIBVP-PRESENT-N
VARIABLE _LIBVP-SHA-ACTIVE
VARIABLE _LIBVP-CRC-ACTIVE
VARIABLE _LIBVP-BODY-CRC
VARIABLE _LIBVP-MAX-MUTATION
VARIABLE _LIBVP-INDEX
VARIABLE _LIBVP-OFFSET
VARIABLE _LIBVP-RECORD-U
VARIABLE _LIBVP-FRAME-U
VARIABLE _LIBVP-CONTENT-N
VARIABLE _LIBVP-ENTRY-INDEX
VARIABLE _LIBVP-HASH-DEST
VARIABLE _LIBVP-CANDIDATE-GENERATION
VARIABLE _LIBVP-FACT
VARIABLE _LIBVP-LOCATOR
VARIABLE _LIBVP-J
VARIABLE _LIBVP-SEEN-MASK
VARIABLE _LIBVP-ID
VARIABLE _LIBVP-SHA-END-DEST
VARIABLE _LIBVP-STREAM-STATUS

\ Maintenance operations reuse the guarded VFS transaction machinery but
\ never publish their probe candidate.  All caller output is staged here.
VARIABLE _LIBMA-STORE
VARIABLE _LIBMA-REPORT
VARIABLE _LIBMA-CALL-STATUS
VARIABLE _LIBMA-PART
VARIABLE _LIBMA-COMPONENT
VARIABLE _LIBMA-FILE-U
VARIABLE _LIBMA-RAW-TOTAL
VARIABLE _LIBMA-CANDIDATE-PART
VARIABLE _LIBMA-PROBE-STATUS
VARIABLE _LIBMA-RESIDUE
VARIABLE _LIBMA-REPAIRABLE
VARIABLE _LIBMA-MARKER-ORIGINAL
VARIABLE _LIBMA-EXPORT-A
VARIABLE _LIBMA-EXPORT-CAP
VARIABLE _LIBMA-EXPORT-REQUIRED
VARIABLE _LIBMA-EXPORT-STARTED
VARIABLE _LIBMA-EXPECTED-REPORT
VARIABLE _LIBMA-REOPEN-VFS
VARIABLE _LIBMA-REOPEN-FLAGS
VARIABLE _LIBMA-INDEX-READY-SAVE
VARIABLE _LIBMA-INDEX-STORE-SAVE
VARIABLE _LIBMA-INDEX-GENERATION-SAVE
VARIABLE _LIBMA-INDEX-CATALOG-N-SAVE
VARIABLE _LIBMA-INDEX-AUTH-CRC-SAVE
VARIABLE _LIBMA-INDEX-CRC-SAVE
CREATE _LIBMA-REPORT-A LIBRARY-INSPECTION-SIZE ALLOT
CREATE _LIBMA-REPORT-B LIBRARY-INSPECTION-SIZE ALLOT
CREATE _LIBMA-CELL 8 ALLOT
CREATE _LIBMA-TARGET-HASH LIB-DIGEST-SIZE ALLOT
CREATE _LIBMA-HEAD-CREC-SPEC CREC-SPEC-SIZE ALLOT
CREATE _LIBMA-HEAD-CREC-WORK CREC-WORK-SIZE ALLOT

\ Managed-create, query, and exact-read state.  All operations are serialized
\ by the one Library guard; none of these cells or buffers is persistent.
VARIABLE _LIBMU-REQUEST
VARIABLE _LIBMU-RESULT
VARIABLE _LIBMU-STORE
VARIABLE _LIBMU-STATUS
VARIABLE _LIBMU-ORIGINAL-STATUS
VARIABLE _LIBMU-ORIGINAL-VFSNAP
VARIABLE _LIBMU-ORIGINAL-VREPL
VARIABLE _LIBMU-REOPEN-VFS
VARIABLE _LIBMU-REOPEN-FLAGS
VARIABLE _LIBMU-INDEX
VARIABLE _LIBMU-COUNT
VARIABLE _LIBMU-NEXT
VARIABLE _LIBMU-CAPACITY
VARIABLE _LIBMU-ENTRIES
VARIABLE _LIBMU-START
VARIABLE _LIBMU-EXPECTED-CATALOG-GENERATION
VARIABLE _LIBMU-ACTUAL-CATALOG-GENERATION
VARIABLE _LIBMU-ID
VARIABLE _LIBMU-REVISION
VARIABLE _LIBMU-BYTES
VARIABLE _LIBMU-CONTENT-OUT
VARIABLE _LIBMU-ENTRY-OUT
VARIABLE _LIBMU-CONTENT-CAP
VARIABLE _LIBMU-REQUIRED-U
VARIABLE _LIBMU-FOUND
VARIABLE _LIBMU-NEW-GENERATION
VARIABLE _LIBMU-NEW-MUTATION
VARIABLE _LIBMU-NEW-TAIL
VARIABLE _LIBMU-NEW-RECORD-COUNT
VARIABLE _LIBMU-RECORD-U
VARIABLE _LIBMU-FRAME-U
VARIABLE _LIBMU-SOURCE-FD
VARIABLE _LIBMU-CLEAN-SOURCE-FD
VARIABLE _LIBMU-ATTEMPT
VARIABLE _LIBMU-SPAN-A
VARIABLE _LIBMU-SPAN-U
VARIABLE _LIBMU-CHECKPOINT-XT
VARIABLE _LIBMU-RANDOM-XT
VARIABLE _LIBMR-A
VARIABLE _LIBMR-U
VARIABLE _LIBMR-REQUEST
VARIABLE _LIBMR-I
VARIABLE _LIBMR-J
VARIABLE _LIBMU-OPERATION-KEY
VARIABLE _LIBMU-RID-DOMAIN-A
VARIABLE _LIBMU-RID-DOMAIN-U
VARIABLE _LIBMU-HAS-CONTENT
VARIABLE _LIBMU-HAS-CATALOG
VARIABLE _LIBMU-HAS-COLLECTION
VARIABLE _LIBMU-CATALOG-INDEX
VARIABLE _LIBMU-CATALOG-COUNT
VARIABLE _LIBMU-COLLECTION-INDEX
VARIABLE _LIBMU-COLLECTION-COUNT
VARIABLE _LIBMU-PLANNED-CONTENT-U
VARIABLE _LIBMU-COMMIT-MODE
VARIABLE _LIBMU-METADATA
VARIABLE _LIBMU-HISTORY
VARIABLE _LIBMU-HISTORY-CAP
VARIABLE _LIBMU-REQUIRED-N
VARIABLE _LIBMU-CONTENT-MODE
VARIABLE _LIBMU-LOCATOR
VARIABLE _LIBMU-LOCATOR-INDEX
VARIABLE _LIBMU-TARGET-DOMAIN
VARIABLE _LIBMU-TARGET-CONTENT
VARIABLE _LIBMU-COLLECTION-REQUEST
VARIABLE _LIBMU-COLLECTION-RESULT
VARIABLE _LIBMU-MEMBERS
VARIABLE _LIBMU-MEMBER-N
VARIABLE _LIBMU-EXPECTED-COLLECTION-REVISION
VARIABLE _LIBMU-RID-OUT
VARIABLE _LIBMU-RECEIPT-OUT
VARIABLE _LIBMU-TARGET-LIFECYCLE
VARIABLE _LIBMU-INPUT-A
VARIABLE _LIBMU-INPUT-U
VARIABLE _LIBMU-EQUAL
VARIABLE _LIBMU-REQUIRE-MANAGED
VARIABLE _LIBMU-MISSING-CONTENT-STATUS

\ The disposable corpus index is one activation-local candidate cache shared
\ by the serialized Library owner.  It is never part of a store descriptor or
\ durable format.  A binding and CRC are published only after a complete
\ authoritative bank/arena validation succeeds.
VARIABLE _LIBIX-READY
VARIABLE _LIBIX-STORE
VARIABLE _LIBIX-GENERATION
VARIABLE _LIBIX-CATALOG-N
VARIABLE _LIBIX-AUTH-CRC
VARIABLE _LIBIX-CRC
VARIABLE _LIBIX-ENTRY-A
VARIABLE _LIBIX-TEXT-A
VARIABLE _LIBIX-TEXT-U
VARIABLE _LIBIX-BLOOM
VARIABLE _LIBIX-BLOOM-U
VARIABLE _LIBIX-BIT
VARIABLE _LIBIX-SLOT

\ Corpus-query verifier scratch.  The derived index may only reject a slot
\ before these exact authoritative byte comparisons; it never supplies facts.
VARIABLE _LIBCQ-HAY-A
VARIABLE _LIBCQ-HAY-U
VARIABLE _LIBCQ-NEEDLE-A
VARIABLE _LIBCQ-NEEDLE-U
VARIABLE _LIBCQ-ENTRY
VARIABLE _LIBCQ-COLLECTION-FILTER
VARIABLE _LIBCQ-READ-CONTENT-XT

\ Private, activation-local qualification counters.  They expose cost shape
\ to the renderer-free contract fixtures without becoming a public owner ABI or a
\ durable fact.  The direct/warm counters begin at zero and are populated by
\ the ordered efficiency rework.
VARIABLE _LIBPQ-FULL-VALIDATION-N
VARIABLE _LIBPQ-WARM-ASSURANCE-N
VARIABLE _LIBPQ-INDEX-REBUILD-N
VARIABLE _LIBPQ-ENTRY-READ-N
VARIABLE _LIBPQ-COLLECTION-READ-N
VARIABLE _LIBPQ-DIRECT-FRAME-READ-N
VARIABLE _LIBPQ-DIRECT-FRAME-BYTES
VARIABLE _LIBPQ-ARENA-SCAN-N
VARIABLE _LIBPQ-ARENA-SCAN-FRAME-N
VARIABLE _LIBPQ-ARENA-SCAN-BYTES

: _LIBPQ-RESET  ( -- )
    0 _LIBPQ-FULL-VALIDATION-N !
    0 _LIBPQ-WARM-ASSURANCE-N !
    0 _LIBPQ-INDEX-REBUILD-N !
    0 _LIBPQ-ENTRY-READ-N !
    0 _LIBPQ-COLLECTION-READ-N !
    0 _LIBPQ-DIRECT-FRAME-READ-N !
    0 _LIBPQ-DIRECT-FRAME-BYTES !
    0 _LIBPQ-ARENA-SCAN-N !
    0 _LIBPQ-ARENA-SCAN-FRAME-N !
    0 _LIBPQ-ARENA-SCAN-BYTES ! ;

: _LIBPQ-FULL-VALIDATION@  ( -- n ) _LIBPQ-FULL-VALIDATION-N @ ;
: _LIBPQ-WARM-ASSURANCE@   ( -- n ) _LIBPQ-WARM-ASSURANCE-N @ ;
: _LIBPQ-INDEX-REBUILD@    ( -- n ) _LIBPQ-INDEX-REBUILD-N @ ;
: _LIBPQ-ENTRY-READ@       ( -- n ) _LIBPQ-ENTRY-READ-N @ ;
: _LIBPQ-COLLECTION-READ@  ( -- n ) _LIBPQ-COLLECTION-READ-N @ ;
: _LIBPQ-DIRECT-FRAME-READ@  ( -- n ) _LIBPQ-DIRECT-FRAME-READ-N @ ;
: _LIBPQ-DIRECT-FRAME-BYTES@  ( -- n ) _LIBPQ-DIRECT-FRAME-BYTES @ ;
: _LIBPQ-ARENA-SCAN@       ( -- n ) _LIBPQ-ARENA-SCAN-N @ ;
: _LIBPQ-ARENA-SCAN-FRAME@  ( -- n ) _LIBPQ-ARENA-SCAN-FRAME-N @ ;
: _LIBPQ-ARENA-SCAN-BYTES@  ( -- n ) _LIBPQ-ARENA-SCAN-BYTES @ ;

1 CONSTANT _LIBMU-COMMIT-ENTRY-KEY
2 CONSTANT _LIBMU-COMMIT-ENTRY-EXACT
3 CONSTANT _LIBMU-COMMIT-COLLECTION-EXACT

0 CONSTANT _LIBMU-CONTENT-CURRENT
1 CONSTANT _LIBMU-CONTENT-DOMAIN
2 CONSTANT _LIBMU-CONTENT-REVISION

1 CONSTANT _LIBMU-STAGE-BEFORE-CONTENT
2 CONSTANT _LIBMU-STAGE-AFTER-CONTENT
3 CONSTANT _LIBMU-STAGE-AFTER-BANK
4 CONSTANT _LIBMU-STAGE-BANK-READBACK
5 CONSTANT _LIBMU-STAGE-BEFORE-HEAD
6 CONSTANT _LIBMU-STAGE-AFTER-HEAD

VARIABLE _LIBVC-CONTEXT
VARIABLE _LIBVC-PAYLOAD
VARIABLE _LIBVC-PAYLOAD-U
VARIABLE _LIBVC-GENERATION

VARIABLE _LIBVI-VFS
VARIABLE _LIBVI-STORE
VARIABLE _LIBVR-STORE
VARIABLE _LIBVL-STORE
VARIABLE _LIBVL-SNAPSHOT-STATUS
VARIABLE _LIBVL-STATUS
VARIABLE _LIBVS-HEAD-FACT
VARIABLE _LIBVS-EXPECTED
VARIABLE _LIBVS-STORE

CREATE _LIBVP-ARENA-ID LIB-DIGEST-SIZE ALLOT
CREATE _LIBVP-SECTOR LIB-STORE-SECTOR-SIZE ALLOT
16384 CONSTANT _LIBVP-ZERO-BLOCK-SIZE
CREATE _LIBVP-ZERO-BLOCK _LIBVP-ZERO-BLOCK-SIZE ALLOT
CREATE _LIBVP-FRAME LIB-CONTENT-FRAME-MAX ALLOT
CREATE _LIBVP-ENTRY LIB-ENTRY-SIZE ALLOT
CREATE _LIBVP-COLLECTION LIB-COLLECTION-SIZE ALLOT
CREATE _LIBVP-CONTENT LIB-CONTENT-SIZE ALLOT
CREATE _LIBVP-BODY-SHA LIB-DIGEST-SIZE ALLOT
CREATE _LIBVP-BANK-SHA LIB-DIGEST-SIZE ALLOT
CREATE _LIBVP-FRAME-SHA LIB-DIGEST-SIZE ALLOT
CREATE _LIBVP-CHAIN LIB-DIGEST-SIZE ALLOT
CREATE _LIBVP-CHAIN-NEXT LIB-DIGEST-SIZE ALLOT
CREATE _LIBVP-SHA-DISCARD LIB-DIGEST-SIZE ALLOT
CREATE _LIBVP-ARENA-FACT LIB-ARENA-FACT-SIZE ALLOT
CREATE _LIBVP-BANK-FACT LIB-BANK-FACT-SIZE ALLOT
CREATE _LIBVP-HEAD-FACT LIB-HEAD-FACT-SIZE ALLOT
CREATE _LIBMU-ENTRY LIB-ENTRY-SIZE ALLOT
CREATE _LIBMU-FOUND-ENTRY LIB-ENTRY-SIZE ALLOT
CREATE _LIBMU-CONTENT LIB-CONTENT-SIZE ALLOT
CREATE _LIBMU-CONTENT-READBACK LIB-CONTENT-SIZE ALLOT
CREATE _LIBMU-COLLECTION LIB-COLLECTION-SIZE ALLOT
CREATE _LIBMU-FOUND-COLLECTION LIB-COLLECTION-SIZE ALLOT
CREATE _LIBMU-FIRST-SUMMARY LIBRARY-REVISION-SUMMARY-SIZE ALLOT
CREATE _LIBMU-RESTORE-BYTES LIB-CONTENT-MAX ALLOT
CREATE _LIBMU-BANK-FACT LIB-BANK-FACT-SIZE ALLOT
CREATE _LIBMU-HEAD-FACT LIB-HEAD-FACT-SIZE ALLOT
CREATE _LIBMU-BANK-SHA LIB-DIGEST-SIZE ALLOT
CREATE _LIBMU-FRAME-SHA LIB-DIGEST-SIZE ALLOT
CREATE _LIBMU-CHAIN LIB-DIGEST-SIZE ALLOT
CREATE _LIBMU-ENTROPY LIB-DIGEST-SIZE ALLOT
CREATE _LIBMU-RID LIB-DIGEST-SIZE ALLOT
CREATE _LIBMU-CELL 8 ALLOT

 64 CONSTANT _LIBIX-TITLE-BYTES
128 CONSTANT _LIBIX-TAG-BYTES
256 CONSTANT _LIBIX-BODY-BYTES
  0 CONSTANT _LIBIX-TITLE-OFFSET
_LIBIX-TITLE-OFFSET _LIBIX-TITLE-BYTES +
    CONSTANT _LIBIX-TAG-OFFSET
_LIBIX-TAG-OFFSET _LIBIX-TAG-BYTES +
    CONSTANT _LIBIX-BODY-OFFSET
_LIBIX-BODY-OFFSET _LIBIX-BODY-BYTES +
    CONSTANT _LIBIX-RECORD-SIZE
_LIBIX-RECORD-SIZE LIB-CATALOG-MAX * CONSTANT _LIBIX-BYTES
CREATE _LIBIX-CANDIDATE _LIBIX-BYTES ALLOT

\ A warm authority certificate binds one completely validated activation to
\ its exact descriptor/VFS attachment and complete decoded head.  The raw
\ fixed-record commitments let warm exact reads detect a self-consistent
\ record substitution without rehashing the complete selected bank.
VARIABLE _LIBAUTH-READY
VARIABLE _LIBAUTH-STORE
VARIABLE _LIBAUTH-VFS
VARIABLE _LIBAUTH-BINDING
VARIABLE _LIBAUTH-BCTX
VARIABLE _LIBAUTH-VOLUME
VARIABLE _LIBAUTH-VOL-COOKIE
VARIABLE _LIBAUTH-MEDIA-GEN
VARIABLE _LIBAUTH-CLEANUP-FAILED
VARIABLE _LIBAUTH-CRC
VARIABLE _LIBAUTH-CHECK-STORE
CREATE _LIBAUTH-HEAD LIB-HEAD-FACT-SIZE ALLOT
CREATE _LIBAUTH-CATALOG-RECORD-SHA
    LIB-CATALOG-MAX LIB-DIGEST-SIZE * ALLOT
CREATE _LIBAUTH-COLLECTION-RECORD-SHA
    LIB-COLLECTION-MAX LIB-DIGEST-SIZE * ALLOT

\ Each validated retained/current frame has one activation-local locator.
\ The padded-frame digest is required because the durable content-chain seal
\ was established by the complete scan and is not recomputed by a direct
\ target read.  Zero offset/span denotes an unpublished locator.
 0 CONSTANT _LIBLOC-OFFSET
 8 CONSTANT _LIBLOC-FRAME-U
16 CONSTANT _LIBLOC-FRAME-SHA
48 CONSTANT _LIBLOC-SIZE
LIB-CATALOG-MAX LIB-RETAINED-REVISION-MAX *
    CONSTANT _LIBLOC-N
_LIBLOC-N _LIBLOC-SIZE * CONSTANT _LIBLOC-BYTES
CREATE _LIBLOC-TABLE _LIBLOC-BYTES ALLOT
VARIABLE _LIBLOC-TEST-SOURCE-SLOT
VARIABLE _LIBLOC-TEST-SOURCE-INDEX
VARIABLE _LIBLOC-TEST-TARGET-SLOT
VARIABLE _LIBLOC-TEST-TARGET-INDEX

: _LIBLOC.OFFSET     ( locator -- a ) _LIBLOC-OFFSET + ;
: _LIBLOC.FRAME-U    ( locator -- a ) _LIBLOC-FRAME-U + ;
: _LIBLOC.FRAME-SHA  ( locator -- digest ) _LIBLOC-FRAME-SHA + ;

: _LIBLOC-AT  ( catalog-slot retained-index -- locator )
    SWAP LIB-RETAINED-REVISION-MAX * + _LIBLOC-SIZE *
        _LIBLOC-TABLE + ;

\ Compact recovery-only catalog facts.  These retain no titles, provenance,
\ payloads, or caller-visible records; they exist only for one guarded scan.
  0 CONSTANT _LIBVCF-ID
 32 CONSTANT _LIBVCF-OPERATION-KEY
 64 CONSTANT _LIBVCF-DOMAIN-REVISION
 72 CONSTANT _LIBVCF-KIND
 80 CONSTANT _LIBVCF-LIFECYCLE
 88 CONSTANT _LIBVCF-MEDIA
 96 CONSTANT _LIBVCF-CURRENT-REVISION
104 CONSTANT _LIBVCF-OLDEST-REVISION
112 CONSTANT _LIBVCF-CONTENT-U
120 CONSTANT _LIBVCF-CONTENT-DIGEST
152 CONSTANT _LIBVCF-SEEN
160 CONSTANT _LIBVCF-REVISION-DOMAINS
192 CONSTANT _LIBVCF-INITIAL-MEDIA
200 CONSTANT _LIBVCF-INITIAL-REVISION
208 CONSTANT _LIBVCF-INITIAL-U
216 CONSTANT _LIBVCF-INITIAL-DIGEST
248 CONSTANT _LIBVCF-LAST-CONTENT-REVISION
256 CONSTANT _LIBVCF-LAST-DOMAIN-REVISION
264 CONSTANT _LIBVCF-SIZE

: _LIBVCF.ID                 ( fact -- id ) _LIBVCF-ID + ;
: _LIBVCF.OPERATION-KEY      ( fact -- key ) _LIBVCF-OPERATION-KEY + ;
: _LIBVCF.DOMAIN-REVISION    ( fact -- a ) _LIBVCF-DOMAIN-REVISION + ;
: _LIBVCF.KIND               ( fact -- a ) _LIBVCF-KIND + ;
: _LIBVCF.LIFECYCLE          ( fact -- a ) _LIBVCF-LIFECYCLE + ;
: _LIBVCF.MEDIA              ( fact -- a ) _LIBVCF-MEDIA + ;
: _LIBVCF.CURRENT-REVISION   ( fact -- a ) _LIBVCF-CURRENT-REVISION + ;
: _LIBVCF.OLDEST-REVISION    ( fact -- a ) _LIBVCF-OLDEST-REVISION + ;
: _LIBVCF.CONTENT-U          ( fact -- a ) _LIBVCF-CONTENT-U + ;
: _LIBVCF.CONTENT-DIGEST     ( fact -- digest ) _LIBVCF-CONTENT-DIGEST + ;
: _LIBVCF.SEEN               ( fact -- a ) _LIBVCF-SEEN + ;
: _LIBVCF.INITIAL-MEDIA      ( fact -- a ) _LIBVCF-INITIAL-MEDIA + ;
: _LIBVCF.INITIAL-REVISION   ( fact -- a ) _LIBVCF-INITIAL-REVISION + ;
: _LIBVCF.INITIAL-U          ( fact -- a ) _LIBVCF-INITIAL-U + ;
: _LIBVCF.INITIAL-DIGEST     ( fact -- digest ) _LIBVCF-INITIAL-DIGEST + ;
: _LIBVCF.LAST-CONTENT-REVISION  ( fact -- a )
    _LIBVCF-LAST-CONTENT-REVISION + ;
: _LIBVCF.LAST-DOMAIN-REVISION  ( fact -- a )
    _LIBVCF-LAST-DOMAIN-REVISION + ;
: _LIBVCF.REVISION-DOMAIN  ( revision-index fact -- a )
    _LIBVCF-REVISION-DOMAINS + SWAP 8 * + ;

CREATE _LIBVP-CATALOG-FACTS LIB-CATALOG-MAX _LIBVCF-SIZE * ALLOT

 0 CONSTANT _LIBVCCF-ID
32 CONSTANT _LIBVCCF-OPERATION-KEY
64 CONSTANT _LIBVCCF-SIZE
: _LIBVCCF.ID             ( fact -- id ) _LIBVCCF-ID + ;
: _LIBVCCF.OPERATION-KEY  ( fact -- key ) _LIBVCCF-OPERATION-KEY + ;

CREATE _LIBVP-COLLECTION-FACTS
    LIB-COLLECTION-MAX _LIBVCCF-SIZE * ALLOT

\ A maintenance probe performs the ordinary complete V1 validation against
\ private staging, then restores the activation certificate and disposable
\ index byte-for-byte.  This keeps INSPECT observably read-only even when a
\ healthy owner is already serving warm operations.
CREATE _LIBMA-INDEX-BACKUP _LIBIX-BYTES ALLOT
CREATE _LIBMA-CATALOG-FACTS-BACKUP
    LIB-CATALOG-MAX _LIBVCF-SIZE * ALLOT
CREATE _LIBMA-COLLECTION-FACTS-BACKUP
    LIB-COLLECTION-MAX _LIBVCCF-SIZE * ALLOT
CREATE _LIBMA-CATALOG-SHA-BACKUP
    LIB-CATALOG-MAX LIB-DIGEST-SIZE * ALLOT
CREATE _LIBMA-COLLECTION-SHA-BACKUP
    LIB-COLLECTION-MAX LIB-DIGEST-SIZE * ALLOT
CREATE _LIBMA-LOCATOR-BACKUP _LIBLOC-BYTES ALLOT

: _LIBVP-CATALOG-FACT  ( index -- fact )
    _LIBVCF-SIZE * _LIBVP-CATALOG-FACTS + ;
: _LIBVP-COLLECTION-FACT  ( index -- fact )
    _LIBVCCF-SIZE * _LIBVP-COLLECTION-FACTS + ;

: _LIBAUTH-CATALOG-SHA  ( slot -- digest )
    LIB-DIGEST-SIZE * _LIBAUTH-CATALOG-RECORD-SHA + ;
: _LIBAUTH-COLLECTION-SHA  ( slot -- digest )
    LIB-DIGEST-SIZE * _LIBAUTH-COLLECTION-RECORD-SHA + ;

: _LIBAUTH-INVALIDATE  ( -- ) 0 _LIBAUTH-READY ! ;

: _LIBAUTH-CLEAR  ( -- )
    _LIBAUTH-INVALIDATE
    0 _LIBAUTH-STORE !
    0 _LIBAUTH-VFS !
    0 _LIBAUTH-BINDING !
    0 _LIBAUTH-BCTX !
    0 _LIBAUTH-VOLUME !
    0 _LIBAUTH-VOL-COOKIE !
    0 _LIBAUTH-MEDIA-GEN !
    0 _LIBAUTH-CLEANUP-FAILED !
    0 _LIBAUTH-CRC !
    0 _LIBAUTH-CHECK-STORE !
    _LIBAUTH-HEAD LIB-HEAD-FACT-SIZE 0 FILL
    _LIBVP-CATALOG-FACTS LIB-CATALOG-MAX _LIBVCF-SIZE * 0 FILL
    _LIBVP-COLLECTION-FACTS
        LIB-COLLECTION-MAX _LIBVCCF-SIZE * 0 FILL
    _LIBLOC-TABLE _LIBLOC-BYTES 0 FILL
    _LIBAUTH-CATALOG-RECORD-SHA
        LIB-CATALOG-MAX LIB-DIGEST-SIZE * 0 FILL
    _LIBAUTH-COLLECTION-RECORD-SHA
        LIB-COLLECTION-MAX LIB-DIGEST-SIZE * 0 FILL ;

: _LIBAUTH-COUNTS-BOUNDED?  ( store -- flag )
    DUP LIBRARY-VFS-STORE.BANK LIBBF.CATALOG-COUNT @
        DUP 0< SWAP LIB-CATALOG-MAX > OR IF DROP 0 EXIT THEN
    LIBRARY-VFS-STORE.BANK LIBBF.COLLECTION-COUNT @
        DUP 0< SWAP LIB-COLLECTION-MAX > OR IF 0 EXIT THEN
    -1 ;

: _LIBAUTH-COMPUTE-CRC  ( store -- crc )
    _LIBAUTH-CHECK-STORE !
    CRC32-BEGIN
    _LIBAUTH-STORE 8 CRC32-ADD
    _LIBAUTH-VFS 8 CRC32-ADD
    _LIBAUTH-BINDING 8 CRC32-ADD
    _LIBAUTH-BCTX 8 CRC32-ADD
    _LIBAUTH-VOLUME 8 CRC32-ADD
    _LIBAUTH-VOL-COOKIE 8 CRC32-ADD
    _LIBAUTH-MEDIA-GEN 8 CRC32-ADD
    _LIBAUTH-CLEANUP-FAILED 8 CRC32-ADD
    _LIBAUTH-HEAD LIB-HEAD-FACT-SIZE CRC32-ADD
    _LIBAUTH-CHECK-STORE @
        LIBRARY-VFS-STORE.GENERATION 8 CRC32-ADD
    _LIBAUTH-CHECK-STORE @
        LIBRARY-VFS-STORE.HEAD LIB-HEAD-FACT-SIZE CRC32-ADD
    _LIBAUTH-CHECK-STORE @
        LIBRARY-VFS-STORE.ARENA LIB-ARENA-FACT-SIZE CRC32-ADD
    _LIBAUTH-CHECK-STORE @
        LIBRARY-VFS-STORE.BANK LIB-BANK-FACT-SIZE CRC32-ADD
    _LIBVP-CATALOG-FACTS
        _LIBAUTH-CHECK-STORE @ LIBRARY-VFS-STORE.BANK
            LIBBF.CATALOG-COUNT @ _LIBVCF-SIZE * CRC32-ADD
    _LIBVP-COLLECTION-FACTS
        _LIBAUTH-CHECK-STORE @ LIBRARY-VFS-STORE.BANK
            LIBBF.COLLECTION-COUNT @ _LIBVCCF-SIZE * CRC32-ADD
    _LIBAUTH-CATALOG-RECORD-SHA
        _LIBAUTH-CHECK-STORE @ LIBRARY-VFS-STORE.BANK
            LIBBF.CATALOG-COUNT @ LIB-DIGEST-SIZE * CRC32-ADD
    _LIBAUTH-COLLECTION-RECORD-SHA
        _LIBAUTH-CHECK-STORE @ LIBRARY-VFS-STORE.BANK
            LIBBF.COLLECTION-COUNT @ LIB-DIGEST-SIZE * CRC32-ADD
    _LIBLOC-TABLE
        _LIBAUTH-CHECK-STORE @ LIBRARY-VFS-STORE.BANK
            LIBBF.CATALOG-COUNT @ LIB-RETAINED-REVISION-MAX *
            _LIBLOC-SIZE * CRC32-ADD
    CRC32-END ;

: _LIBAUTH-PUBLISH  ( store -- )
    _LIBAUTH-CHECK-STORE !
    _LIBAUTH-INVALIDATE
    _LIBAUTH-CHECK-STORE @ _LIBAUTH-STORE !
    _LIBAUTH-CHECK-STORE @ LIBRARY-VFS-STORE.VFS @
        DUP _LIBAUTH-VFS !
    DUP V.BINDING @ _LIBAUTH-BINDING !
    DUP V.BCTX @ _LIBAUTH-BCTX !
    DUP V.VOLUME @ _LIBAUTH-VOLUME !
    DUP V.VOL-COOKIE @ _LIBAUTH-VOL-COOKIE !
    V.MEDIA-GEN @ _LIBAUTH-MEDIA-GEN !
    _LIBAUTH-CHECK-STORE @ LIBRARY-VFS-STORE-CLEANUP-FAILED?
        _LIBAUTH-CLEANUP-FAILED !
    _LIBAUTH-CHECK-STORE @ LIBRARY-VFS-STORE.HEAD
        _LIBAUTH-HEAD LIB-HEAD-FACT-SIZE CMOVE
    _LIBAUTH-CHECK-STORE @ _LIBAUTH-COMPUTE-CRC _LIBAUTH-CRC !
    -1 _LIBAUTH-READY ! ;

: _LIBAUTH-BINDING-MATCH?  ( -- flag )
    _LIBAUTH-VFS @ DUP VFS-DESC-SIZE _VFSNAP-SPAN-VALID? 0= IF
        DROP 0 EXIT
    THEN
    DUP V.BINDING @ _LIBAUTH-BINDING @ =
    OVER V.BCTX @ _LIBAUTH-BCTX @ = AND
    OVER V.VOLUME @ _LIBAUTH-VOLUME @ = AND
    OVER V.VOL-COOKIE @ _LIBAUTH-VOL-COOKIE @ = AND
    SWAP V.MEDIA-GEN @ _LIBAUTH-MEDIA-GEN @ = AND ;

: _LIBAUTH-VALID?  ( store -- flag )
    _LIBAUTH-CHECK-STORE !
    _LIBAUTH-READY @ 0= IF 0 EXIT THEN
    _LIBAUTH-CHECK-STORE @ _LIBAUTH-STORE @ <> IF 0 EXIT THEN
    _LIBAUTH-CHECK-STORE @ LIBRARY-VFS-STORE-VALID? 0= IF 0 EXIT THEN
    _LIBAUTH-CHECK-STORE @ LIBRARY-VFS-STORE-LOADED? 0= IF 0 EXIT THEN
    _LIBAUTH-CHECK-STORE @ LIBRARY-VFS-STORE-BLOCKED? IF 0 EXIT THEN
    _LIBAUTH-CHECK-STORE @ _LIBAUTH-COUNTS-BOUNDED? 0= IF 0 EXIT THEN
    _LIBAUTH-CHECK-STORE @ LIBRARY-VFS-STORE-CLEANUP-FAILED?
        _LIBAUTH-CLEANUP-FAILED @ <> IF 0 EXIT THEN
    _LIBAUTH-CHECK-STORE @ LIBRARY-VFS-STORE.VFS @
        _LIBAUTH-VFS @ <> IF 0 EXIT THEN
    _LIBAUTH-BINDING-MATCH? 0= IF 0 EXIT THEN
    _LIBAUTH-CHECK-STORE @ _LIBAUTH-COMPUTE-CRC
        _LIBAUTH-CRC @ = ;

: _LIBAUTH-TEST-DAMAGE  ( -- status )
    _LIBAUTH-HEAD DUP C@ 1 XOR SWAP C! LIBSTORE-S-OK ;

\ L12-DELETION contract hook: retain the validated Library generation but
\ integrity-protect a different complete cached head identity.  Warm assurance
\ must compare the full decoded durable head rather than accept the integer.
\ It is deleted with the fixed backend, not carried into the successor API.
: _LIBAUTH-TEST-RESEAL-HEAD-MISMATCH  ( -- status )
    _LIBAUTH-STORE @ _LIBAUTH-VALID? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBAUTH-HEAD LIBHF.BANK-SELECTOR DUP @ 1 XOR SWAP !
    _LIBAUTH-STORE @ _LIBAUTH-COMPUTE-CRC _LIBAUTH-CRC !
    _LIBIX-READY @ IF _LIBAUTH-CRC @ _LIBIX-AUTH-CRC ! THEN
    LIBSTORE-S-OK ;

: _LIBAUTH-TEST-CATALOG-FACT-DAMAGE  ( -- status )
    _LIBAUTH-STORE @ _LIBAUTH-VALID? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBAUTH-STORE @ LIBRARY-VFS-STORE.BANK
        LIBBF.CATALOG-COUNT @ 0= IF LIBSTORE-S-INVALID EXIT THEN
    _LIBVP-CATALOG-FACTS DUP C@ 1 XOR SWAP C!
    LIBSTORE-S-OK ;

: _LIBAUTH-TEST-COLLECTION-FACT-DAMAGE  ( -- status )
    _LIBAUTH-STORE @ _LIBAUTH-VALID? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBAUTH-STORE @ LIBRARY-VFS-STORE.BANK
        LIBBF.COLLECTION-COUNT @ 0= IF LIBSTORE-S-INVALID EXIT THEN
    _LIBVP-COLLECTION-FACTS DUP C@ 1 XOR SWAP C!
    LIBSTORE-S-OK ;

: _LIBLOC-TEST-DAMAGE  ( -- status )
    _LIBLOC-TABLE DUP C@ 1 XOR SWAP C! LIBSTORE-S-OK ;

\ L12-DELETION contract hook: install a checksummed but stale/wrong hint so the
\ direct verifier, rather than the certificate CRC, must reject the frame. It
\ is deleted with the fixed locator table, not carried into the successor API.
: _LIBLOC-TEST-RETARGET-AND-RESEAL
  ( source-slot source-index target-slot target-index -- status )
    _LIBLOC-TEST-TARGET-INDEX ! _LIBLOC-TEST-TARGET-SLOT !
    _LIBLOC-TEST-SOURCE-INDEX ! _LIBLOC-TEST-SOURCE-SLOT !
    _LIBAUTH-STORE @ _LIBAUTH-VALID? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBLOC-TEST-SOURCE-SLOT @ DUP 0<
    SWAP _LIBAUTH-STORE @ LIBRARY-VFS-STORE.BANK
        LIBBF.CATALOG-COUNT @ >= OR IF LIBSTORE-S-INVALID EXIT THEN
    _LIBLOC-TEST-TARGET-SLOT @ DUP 0<
    SWAP _LIBAUTH-STORE @ LIBRARY-VFS-STORE.BANK
        LIBBF.CATALOG-COUNT @ >= OR IF LIBSTORE-S-INVALID EXIT THEN
    _LIBLOC-TEST-SOURCE-INDEX @ DUP 0<
    SWAP LIB-RETAINED-REVISION-MAX >= OR IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBLOC-TEST-TARGET-INDEX @ DUP 0<
    SWAP LIB-RETAINED-REVISION-MAX >= OR IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBLOC-TEST-SOURCE-SLOT @ _LIBLOC-TEST-SOURCE-INDEX @
        _LIBLOC-AT DUP _LIBLOC.OFFSET @ 0= IF
        DROP LIBSTORE-S-INVALID EXIT
    THEN
    _LIBLOC-TEST-TARGET-SLOT @ _LIBLOC-TEST-TARGET-INDEX @
        _LIBLOC-AT _LIBLOC-SIZE CMOVE
    _LIBAUTH-STORE @ _LIBAUTH-COMPUTE-CRC _LIBAUTH-CRC !
    _LIBIX-READY @ IF _LIBAUTH-CRC @ _LIBIX-AUTH-CRC ! THEN
    LIBSTORE-S-OK ;

: _LIBVFS-CD-REAL  ( inode vfs -- ) V.CWD ! ;

: _LIBVFS-RESOLVE-NOFOLLOW?  ( path-a path-u vfs -- inode ior )
    >R VFS-RP-NOFOLLOW-FINAL R> VFS-RESOLVE-POLICY? ;

: _LIBVFS-RESET-VFS-HOOKS  ( -- )
    ['] _LIBVFS-RESOLVE-NOFOLLOW? _LIBVFS-RESOLVE-XT !
    ['] VFS-OPEN        _LIBVFS-OPEN-XT !
    ['] VFS-CLOSE       _LIBVFS-CLOSE-XT !
    ['] VFS-READ-EXACT  _LIBVFS-READ-EXACT-XT !
    ['] VFS-WRITE-EXACT _LIBVFS-WRITE-EXACT-XT !
    ['] VFS-SEEK        _LIBVFS-SEEK-XT !
    ['] VFS-SIZE        _LIBVFS-SIZE-XT !
    ['] VFS-TRUNCATE    _LIBVFS-TRUNCATE-XT !
    ['] VFS-CREATE      _LIBVFS-CREATE-XT !
    ['] VFS-MKDIR       _LIBVFS-MKDIR-XT !
    ['] VFS-SYNC        _LIBVFS-SYNC-XT !
    ['] VFS-USE         _LIBVFS-USE-XT !
    ['] _LIBVFS-CD-REAL _LIBVFS-CD-XT ! ;

: _LIBVFS-RESOLVE?  ( path-a path-u vfs -- inode ior )
    _LIBVFS-RESOLVE-XT @ EXECUTE ;
: _LIBVFS-OPEN  ( path-a path-u -- fd | 0 )
    _LIBVFS-OPEN-XT @ EXECUTE ;
: _LIBVFS-CLOSE  ( fd -- )
    _LIBVFS-CLOSE-XT @ EXECUTE ;
: _LIBVFS-READ-EXACT  ( destination length fd -- ior )
    _LIBVFS-READ-EXACT-XT @ EXECUTE ;
: _LIBVFS-WRITE-EXACT  ( source length fd -- ior )
    _LIBVFS-WRITE-EXACT-XT @ EXECUTE ;
: _LIBVFS-SEEK  ( position fd -- )
    _LIBVFS-SEEK-XT @ EXECUTE ;
: _LIBVFS-SIZE  ( fd -- length )
    _LIBVFS-SIZE-XT @ EXECUTE ;
: _LIBVFS-TRUNCATE  ( length fd -- ior )
    _LIBVFS-TRUNCATE-XT @ EXECUTE ;
: _LIBVFS-CREATE  ( path-a path-u vfs -- inode | 0 )
    _LIBVFS-CREATE-XT @ EXECUTE ;
: _LIBVFS-MKDIR  ( name-a name-u vfs -- ior )
    _LIBVFS-MKDIR-XT @ EXECUTE ;
: _LIBVFS-SYNC  ( vfs -- ior )
    _LIBVFS-SYNC-XT @ EXECUTE ;
: _LIBVFS-USE  ( vfs -- )
    _LIBVFS-USE-XT @ EXECUTE ;
: _LIBVFS-CD  ( inode vfs -- )
    _LIBVFS-CD-XT @ EXECUTE ;

\ Resolve a sealed Library name as a namespace object.  Missing names remain
\ distinguishable from resolver failures, while a terminal symlink is the
\ object inspected here rather than an authority-bearing target elsewhere.
: _LIBVFS-NAMESPACE-TYPE  ( path-a path-u expected-type vfs -- status )
    >R _LIBVN-EXPECTED-TYPE !
    R> _LIBVFS-RESOLVE?
    ?DUP IF
        VFS-IOR-REASON VFS-R-NOENT = IF
            DROP LIBSTORE-S-ABSENT EXIT
        THEN
        DROP LIBSTORE-S-IO EXIT
    THEN
    ?DUP 0= IF LIBSTORE-S-ABSENT EXIT THEN
    IN.TYPE @ _LIBVN-EXPECTED-TYPE @ = IF
        LIBSTORE-S-OK
    ELSE
        LIBSTORE-S-CORRUPT
    THEN ;

: _LIBVFS-DIRECTORY-NAMESPACE  ( vfs -- status )
    >R _LIBVFS-DIRECTORY$ VFS-T-DIR R> _LIBVFS-NAMESPACE-TYPE ;

\ Library checks its fixed parent immediately before each public VFSNAP call.
\ The contract's trusted-writer convention applies to that parent-check gap;
\ wrapping VFSNAP here would invert the VFSNAP -> VREPL -> VFS lock order.
\ Terminal head and replacement-artifact checks remain atomic inside their
\ generic owners.  Library owns only /library policy and status adaptation.
: _LIBVFS-HEAD-NAMESPACE-PREFLIGHT  ( vfs -- status )
    _LIBVFS-DIRECTORY-NAMESPACE
    DUP LIBSTORE-S-CORRUPT = IF DROP LIBSTORE-S-RECOVERY THEN ;

_LIBVFS-RESET-VFS-HOOKS

: _LIBMU-NO-CHECKPOINT  ( stage -- status )
    DROP LIBSTORE-S-OK ;

: _LIBMU-CHECKPOINT  ( stage -- status )
    _LIBMU-CHECKPOINT-XT @ EXECUTE ;

: _LIBMU-RANDOM  ( -- value )
    _LIBMU-RANDOM-XT @ EXECUTE ;

: _LIBVFS-RESET-MUTATION-HOOKS  ( -- )
    ['] _LIBMU-NO-CHECKPOINT _LIBMU-CHECKPOINT-XT !
    ['] RANDOM _LIBMU-RANDOM-XT ! ;

_LIBVFS-RESET-MUTATION-HOOKS

\ =====================================================================
\  Activation-local disposable title/body/tag candidate index
\ =====================================================================
\  Each catalog slot owns three fixed Bloom bitsets.  Raw three-byte grams
\  make every term of length three or more a bounded candidate test; shorter
\  terms fall through to an authoritative scan.  Bloom collisions are benign
\  because every candidate is reread and byte-compared before publication.

: _LIBIX-RECORD  ( slot -- a )
    _LIBIX-RECORD-SIZE * _LIBIX-CANDIDATE + ;
: _LIBIX-TITLE  ( slot -- a )
    _LIBIX-RECORD _LIBIX-TITLE-OFFSET + ;
: _LIBIX-TAGS  ( slot -- a )
    _LIBIX-RECORD _LIBIX-TAG-OFFSET + ;
: _LIBIX-BODY  ( slot -- a )
    _LIBIX-RECORD _LIBIX-BODY-OFFSET + ;

: _LIBIX-INVALIDATE  ( -- )
    0 _LIBIX-READY !
    0 _LIBIX-STORE !
    0 _LIBIX-GENERATION !
    0 _LIBIX-CATALOG-N !
    0 _LIBIX-AUTH-CRC !
    0 _LIBIX-CRC ! ;

: _LIBIX-CANDIDATE-CLEAR  ( -- )
    _LIBIX-INVALIDATE
    _LIBIX-CANDIDATE _LIBIX-BYTES 0 FILL ;

: _LIBIX-GRAM-HASH  ( a -- u )
    DUP C@ 251 *
    OVER 1+ C@ + 251 *
    SWAP 2 + C@ + ;

: _LIBIX-SET-BIT  ( hash -- )
    _LIBIX-BLOOM-U @ 8 * MOD DUP _LIBIX-BIT !
    3 RSHIFT _LIBIX-BLOOM @ + DUP C@
    1 _LIBIX-BIT @ 7 AND LSHIFT OR SWAP C! ;

: _LIBIX-BIT-SET?  ( hash -- flag )
    _LIBIX-BLOOM-U @ 8 * MOD DUP _LIBIX-BIT !
    3 RSHIFT _LIBIX-BLOOM @ + C@
    1 _LIBIX-BIT @ 7 AND LSHIFT AND 0<> ;

: _LIBIX-ADD$  ( a u bloom bloom-u -- )
    _LIBIX-BLOOM-U ! _LIBIX-BLOOM !
    _LIBIX-TEXT-U ! _LIBIX-TEXT-A !
    _LIBIX-TEXT-U @ 3 < IF EXIT THEN
    _LIBIX-TEXT-U @ 2 - 0 ?DO
        _LIBIX-TEXT-A @ I + _LIBIX-GRAM-HASH _LIBIX-SET-BIT
    LOOP ;

: _LIBIX-INDEX-ENTRY-FROM  ( entry slot -- )
    _LIBIX-SLOT ! _LIBIX-ENTRY-A !
    _LIBIX-ENTRY-A @ LIBE.LIFECYCLE @
        LIB-LIFECYCLE-TOMBSTONED = IF EXIT THEN
    _LIBIX-ENTRY-A @ LIBE-TITLE$
        _LIBIX-SLOT @ _LIBIX-TITLE _LIBIX-TITLE-BYTES _LIBIX-ADD$
    _LIBIX-ENTRY-A @ LIBE.TAG-N @ 0 ?DO
        I _LIBIX-ENTRY-A @ LIBE-TAG LIB-TAG$
            _LIBIX-SLOT @ _LIBIX-TAGS _LIBIX-TAG-BYTES _LIBIX-ADD$
    LOOP ;

: _LIBIX-INDEX-ENTRY  ( slot -- )
    _LIBVP-ENTRY SWAP _LIBIX-INDEX-ENTRY-FROM ;

: _LIBIX-INDEX-CURRENT-BODY-FROM  ( content slot -- )
    _LIBIX-SLOT !
    LIBCT-DATA$
        _LIBIX-SLOT @ _LIBIX-BODY _LIBIX-BODY-BYTES _LIBIX-ADD$ ;

: _LIBIX-INDEX-CURRENT-BODY  ( catalog-fact -- )
    _LIBVP-CATALOG-FACTS - _LIBVCF-SIZE /
    DUP 0< OVER LIB-CATALOG-MAX >= OR IF DROP EXIT THEN
    _LIBVP-CONTENT SWAP _LIBIX-INDEX-CURRENT-BODY-FROM ;

: _LIBIX-COMPUTE-CRC  ( -- crc )
    CRC32-BEGIN
    _LIBIX-CATALOG-N 8 CRC32-ADD
    _LIBIX-CANDIDATE _LIBIX-CATALOG-N @ _LIBIX-RECORD-SIZE *
        CRC32-ADD
    CRC32-END ;

: _LIBIX-PUBLISH  ( store -- )
    0 _LIBIX-READY !
    DUP _LIBIX-STORE !
    DUP LIBRARY-VFS-STORE.GENERATION @ _LIBIX-GENERATION !
    LIBRARY-VFS-STORE.BANK LIBBF.CATALOG-COUNT @ _LIBIX-CATALOG-N !
    _LIBAUTH-CRC @ _LIBIX-AUTH-CRC !
    _LIBIX-COMPUTE-CRC _LIBIX-CRC !
    1 _LIBPQ-INDEX-REBUILD-N +!
    -1 _LIBIX-READY ! ;

: _LIBIX-VALID-UNDER-AUTH?  ( store -- flag )
    _LIBIX-READY @ 0= IF DROP 0 EXIT THEN
    DUP _LIBIX-STORE @ <> IF DROP 0 EXIT THEN
    _LIBAUTH-READY @ 0= IF DROP 0 EXIT THEN
    DUP _LIBAUTH-STORE @ <> IF DROP 0 EXIT THEN
    _LIBIX-AUTH-CRC @ _LIBAUTH-CRC @ <> IF DROP 0 EXIT THEN
    DUP LIBRARY-VFS-STORE.GENERATION @
        _LIBIX-GENERATION @ <> IF DROP 0 EXIT THEN
    LIBRARY-VFS-STORE.BANK LIBBF.CATALOG-COUNT @
        _LIBIX-CATALOG-N @ <> IF 0 EXIT THEN
    _LIBIX-CATALOG-N @ DUP 0<
        SWAP LIB-CATALOG-MAX > OR IF 0 EXIT
    THEN
    _LIBIX-COMPUTE-CRC _LIBIX-CRC @ = ;

\ L12-DELETION contract hooks: deterministic loss/damage injection used only
\ by the current fixed-index fixture; delete with that index implementation.
: _LIBIX-TEST-LOSE  ( -- status )
    _LIBIX-INVALIDATE LIBSTORE-S-OK ;
: _LIBIX-TEST-DAMAGE  ( -- status )
    _LIBIX-CANDIDATE DUP C@ 1 XOR SWAP C! LIBSTORE-S-OK ;

: _LIBMR-ZERO?  ( a u -- flag )
    0 ?DO DUP I + C@ IF DROP 0 UNLOOP EXIT THEN LOOP DROP -1 ;

\ =====================================================================
\  Checked public corpus-query request construction
\ =====================================================================

: _LIBCQR-REQUEST-SAFE?  ( request -- flag )
    DUP LIBRARY-CORPUS-QUERY-REQUEST-SIZE
        _VFSNAP-SPAN-VALID? 0= IF DROP 0 EXIT THEN
    DUP LIBRARY-CORPUS-QUERY-REQUEST-SIZE
        _LIBVFS-PRIVATE-ALIASES? 0= NIP ;

: _LIBRARY-CORPUS-QUERY-TERM!  ( a u request -- status )
    _LIBMR-REQUEST ! _LIBMR-U ! _LIBMR-A !
    _LIBMR-REQUEST @ _LIBCQR-REQUEST-SAFE? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-U @ 0< IF LIBSTORE-S-INVALID EXIT THEN
    _LIBMR-U @ LIBRARY-CORPUS-TERM-MAX > IF
        LIBSTORE-S-OUTPUT-CAPACITY EXIT
    THEN
    _LIBMR-U @ IF
        _LIBMR-A @ _LIBMR-U @ _VFSNAP-SPAN-VALID? 0= IF
            LIBSTORE-S-INVALID EXIT
        THEN
        _LIBMR-A @ _LIBMR-U @ UTF8-VALID? 0= IF
            LIBSTORE-S-INVALID EXIT
        THEN
    THEN
    _LIBMR-U @ IF
        _LIBMR-A @ _LIBMR-REQUEST @ LIBCQR.TERM _LIBMR-U @ MOVE
    THEN
    _LIBMR-REQUEST @ LIBCQR.TERM _LIBMR-U @ +
        LIBRARY-CORPUS-TERM-MAX _LIBMR-U @ - 0 FILL
    _LIBMR-U @ _LIBMR-REQUEST @ LIBCQR.TERM-U !
    LIBSTORE-S-OK ;

: _LIBRARY-CORPUS-QUERY-COLLECTION!  ( rid request -- status )
    _LIBMR-REQUEST ! _LIBMR-A !
    _LIBMR-REQUEST @ _LIBCQR-REQUEST-SAFE? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-A @ LIB-DIGEST-SIZE _VFSNAP-SPAN-VALID? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-A @ RID-PRESENT? 0= IF LIBSTORE-S-INVALID EXIT THEN
    \ MOVE keeps an in-request, partially overlapping RID source well-defined.
    _LIBMR-A @ _LIBMR-REQUEST @ LIBCQR.COLLECTION
        LIB-DIGEST-SIZE MOVE
    LIBSTORE-S-OK ;

: _LIBRARY-CORPUS-QUERY-REQUEST-VALID?  ( request -- flag )
    DUP _LIBCQR-REQUEST-SAFE? 0= IF DROP 0 EXIT THEN _LIBMR-REQUEST !
    _LIBMR-REQUEST @ LIBCQR.EXPECTED-CATALOG-GENERATION @ 0< IF
        0 EXIT
    THEN
    _LIBMR-REQUEST @ LIBCQR.START-SLOT @ DUP 0<
        SWAP LIB-CATALOG-MAX > OR IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCQR.EXPECTED-CATALOG-GENERATION @ 0=
    _LIBMR-REQUEST @ LIBCQR.START-SLOT @ 0<> AND IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCQR.LIFECYCLE-MASK @ DUP 1 <
        SWAP LIBRARY-CORPUS-LIFECYCLE-ALL > OR IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCQR.KIND-MASK @ DUP 1 <
        SWAP LIBRARY-CORPUS-KIND-ALL > OR IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCQR.MEDIA-MASK @ DUP 1 <
        SWAP LIBRARY-CORPUS-MEDIA-ALL > OR IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCQR.FIELD-MASK @ DUP 0<
        SWAP LIBRARY-CORPUS-FIELD-ALL > OR IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCQR.FLAGS @ IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCQR.TERM-U @ DUP 0<
        SWAP LIBRARY-CORPUS-TERM-MAX > OR IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCQR.TERM-U @ IF
        _LIBMR-REQUEST @ LIBCQR.FIELD-MASK @ 0= IF 0 EXIT THEN
        _LIBMR-REQUEST @ LIBCQR-TERM$ UTF8-VALID? 0= IF 0 EXIT THEN
    THEN
    _LIBMR-REQUEST @ LIBCQR.TERM
        _LIBMR-REQUEST @ LIBCQR.TERM-U @ +
        LIBRARY-CORPUS-TERM-MAX _LIBMR-REQUEST @ LIBCQR.TERM-U @ -
        _LIBMR-ZERO? 0= IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCQR.COLLECTION DUP LIB-DIGEST-SIZE
        _LIBMR-ZERO? IF
        DROP
    ELSE
        RID-PRESENT? 0= IF 0 EXIT THEN
    THEN
    -1 ;

' _LIBRARY-CORPUS-QUERY-TERM! CONSTANT _libcqr-term-set-xt
' _LIBRARY-CORPUS-QUERY-COLLECTION! CONSTANT _libcqr-collection-set-xt
' _LIBRARY-CORPUS-QUERY-REQUEST-VALID? CONSTANT _libcqr-valid-xt

: LIBRARY-CORPUS-QUERY-TERM!  ( a u request -- status )
    _libcqr-term-set-xt _library-vfs-store-guard WITH-GUARD ;
: LIBRARY-CORPUS-QUERY-COLLECTION!  ( rid request -- status )
    _libcqr-collection-set-xt _library-vfs-store-guard WITH-GUARD ;
: LIBRARY-CORPUS-QUERY-REQUEST-VALID?  ( request -- flag )
    _libcqr-valid-xt _library-vfs-store-guard WITH-GUARD ;

\ =====================================================================
\  Checked public managed-create request construction
\ =====================================================================

: _LIBMR-REQUEST-SAFE?  ( request -- flag )
    DUP LIBRARY-MANAGED-CREATE-REQUEST-SIZE _VFSNAP-SPAN-VALID? 0= IF
        DROP 0 EXIT
    THEN
    DUP LIBRARY-MANAGED-CREATE-REQUEST-SIZE _LIBVFS-PRIVATE-ALIASES? 0= NIP ;

: _LIBRARY-MANAGED-CREATE-OPERATION-KEY!
  ( key request -- status )
    _LIBMR-REQUEST ! _LIBMR-A !
    _LIBMR-REQUEST @ _LIBMR-REQUEST-SAFE? 0= IF LIBSTORE-S-INVALID EXIT THEN
    _LIBMR-A @ LIB-OPERATION-KEY-SIZE _VFSNAP-SPAN-VALID? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-A @ RID-PRESENT? 0= IF LIBSTORE-S-INVALID EXIT THEN
    _LIBMR-A @ _LIBMR-REQUEST @ LIBMCR.OPERATION-KEY RID-COPY
    LIBSTORE-S-OK ;

: _LIBRARY-MANAGED-CREATE-TITLE!  ( a u request -- status )
    _LIBMR-REQUEST ! _LIBMR-U ! _LIBMR-A !
    _LIBMR-REQUEST @ _LIBMR-REQUEST-SAFE? 0= IF LIBSTORE-S-INVALID EXIT THEN
    _LIBMR-U @ DUP 1 < SWAP LIB-TITLE-MAX > OR IF
        LIBSTORE-S-OUTPUT-CAPACITY EXIT
    THEN
    _LIBMR-A @ _LIBMR-U @ _VFSNAP-SPAN-VALID? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-A @ _LIBMR-U @ UTF8-VALID? 0= IF LIBSTORE-S-INVALID EXIT THEN
    _LIBMR-A @ _LIBMR-REQUEST @ LIBMCR.TITLE _LIBMR-U @ MOVE
    _LIBMR-REQUEST @ LIBMCR.TITLE _LIBMR-U @ +
        LIB-TITLE-MAX _LIBMR-U @ - 0 FILL
    _LIBMR-U @ _LIBMR-REQUEST @ LIBMCR.TITLE-U !
    LIBSTORE-S-OK ;

: _LIBRARY-MANAGED-CREATE-CONTENT!  ( a u request -- status )
    _LIBMR-REQUEST ! _LIBMR-U ! _LIBMR-A !
    _LIBMR-REQUEST @ _LIBMR-REQUEST-SAFE? 0= IF LIBSTORE-S-INVALID EXIT THEN
    _LIBMR-U @ DUP 0< SWAP LIB-CONTENT-MAX > OR IF
        LIBSTORE-S-CONTENT-FULL EXIT
    THEN
    _LIBMR-U @ IF
        _LIBMR-A @ _LIBMR-U @ _VFSNAP-SPAN-VALID? 0= IF
            LIBSTORE-S-INVALID EXIT
        THEN
        _LIBMR-A @ _LIBMR-U @ UTF8-VALID? 0= IF
            LIBSTORE-S-INVALID EXIT
        THEN
    THEN
    _LIBMR-A @ _LIBMR-REQUEST @ LIBMCR.CONTENT-A !
    _LIBMR-U @ _LIBMR-REQUEST @ LIBMCR.CONTENT-U !
    LIBSTORE-S-OK ;

: _LIBRARY-MANAGED-CREATE-REQUEST-VALID?  ( request -- flag )
    DUP _LIBMR-REQUEST-SAFE? 0= IF DROP 0 EXIT THEN _LIBMR-REQUEST !
    _LIBMR-REQUEST @ LIBMCR.OPERATION-KEY RID-PRESENT? 0= IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBMCR.EXPECTED-CATALOG-GENERATION @ 0< IF
        0 EXIT
    THEN
    _LIBMR-REQUEST @ LIBMCR.MEDIA @ DUP LIB-MEDIA-TEXT-PLAIN =
        SWAP LIB-MEDIA-TEXT-MARKDOWN = OR 0= IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBMCR.TITLE-U @ DUP 1 <
        SWAP LIB-TITLE-MAX > OR IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBMCR-TITLE$ UTF8-VALID? 0= IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBMCR.TITLE
        _LIBMR-REQUEST @ LIBMCR.TITLE-U @ +
        LIB-TITLE-MAX _LIBMR-REQUEST @ LIBMCR.TITLE-U @ -
        _LIBMR-ZERO? 0= IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBMCR.CONTENT-U @ DUP 0<
        SWAP LIB-CONTENT-MAX > OR IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBMCR.CONTENT-U @ IF
        _LIBMR-REQUEST @ LIBMCR-CONTENT$
            _VFSNAP-SPAN-VALID? 0= IF 0 EXIT THEN
        _LIBMR-REQUEST @ LIBMCR-CONTENT$ UTF8-VALID? 0= IF 0 EXIT THEN
    THEN
    _LIBMR-REQUEST @ LIBMCR.FLAGS @ 0= ;

' _LIBRARY-MANAGED-CREATE-OPERATION-KEY!
    CONSTANT _libmcr-operation-key-set-xt
' _LIBRARY-MANAGED-CREATE-TITLE! CONSTANT _libmcr-title-set-xt
' _LIBRARY-MANAGED-CREATE-CONTENT! CONSTANT _libmcr-content-set-xt
' _LIBRARY-MANAGED-CREATE-REQUEST-VALID? CONSTANT _libmcr-valid-xt

: LIBRARY-MANAGED-CREATE-OPERATION-KEY!  ( key request -- status )
    _libmcr-operation-key-set-xt _library-vfs-store-guard WITH-GUARD ;

: LIBRARY-MANAGED-CREATE-TITLE!  ( a u request -- status )
    _libmcr-title-set-xt _library-vfs-store-guard WITH-GUARD ;

: LIBRARY-MANAGED-CREATE-CONTENT!  ( a u request -- status )
    _libmcr-content-set-xt _library-vfs-store-guard WITH-GUARD ;

: LIBRARY-MANAGED-CREATE-REQUEST-VALID?  ( request -- flag )
    _libmcr-valid-xt _library-vfs-store-guard WITH-GUARD ;

\ ---------------------------------------------------------------------
\ Capture-import request construction
\ ---------------------------------------------------------------------

: _LIBMR-CAPTURE-REQUEST-SAFE?  ( request -- flag )
    DUP LIBRARY-CAPTURE-IMPORT-REQUEST-SIZE
        _VFSNAP-SPAN-VALID? 0= IF DROP 0 EXIT THEN
    DUP LIBRARY-CAPTURE-IMPORT-REQUEST-SIZE
        _LIBVFS-PRIVATE-ALIASES? 0= NIP ;

: _LIBRARY-CAPTURE-IMPORT-OPERATION-KEY!  ( key request -- status )
    _LIBMR-REQUEST ! _LIBMR-A !
    _LIBMR-REQUEST @ _LIBMR-CAPTURE-REQUEST-SAFE? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-A @ LIB-OPERATION-KEY-SIZE _VFSNAP-SPAN-VALID? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-A @ RID-PRESENT? 0= IF LIBSTORE-S-INVALID EXIT THEN
    _LIBMR-A @ _LIBMR-REQUEST @ LIBCIR.OPERATION-KEY RID-COPY
    LIBSTORE-S-OK ;

: _LIBRARY-CAPTURE-IMPORT-TITLE!  ( a u request -- status )
    _LIBMR-REQUEST ! _LIBMR-U ! _LIBMR-A !
    _LIBMR-REQUEST @ _LIBMR-CAPTURE-REQUEST-SAFE? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-U @ DUP 1 < SWAP LIB-TITLE-MAX > OR IF
        LIBSTORE-S-OUTPUT-CAPACITY EXIT
    THEN
    _LIBMR-A @ _LIBMR-U @ _VFSNAP-SPAN-VALID? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-A @ _LIBMR-U @ UTF8-VALID? 0= IF LIBSTORE-S-INVALID EXIT THEN
    _LIBMR-A @ _LIBMR-REQUEST @ LIBCIR.TITLE _LIBMR-U @ MOVE
    _LIBMR-REQUEST @ LIBCIR.TITLE _LIBMR-U @ +
        LIB-TITLE-MAX _LIBMR-U @ - 0 FILL
    _LIBMR-U @ _LIBMR-REQUEST @ LIBCIR.TITLE-U !
    LIBSTORE-S-OK ;

: _LIBRARY-CAPTURE-IMPORT-CONTENT!  ( a u request -- status )
    _LIBMR-REQUEST ! _LIBMR-U ! _LIBMR-A !
    _LIBMR-REQUEST @ _LIBMR-CAPTURE-REQUEST-SAFE? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-U @ DUP 0< SWAP LIB-CONTENT-MAX > OR IF
        LIBSTORE-S-CONTENT-FULL EXIT
    THEN
    _LIBMR-U @ IF
        _LIBMR-A @ _LIBMR-U @ _VFSNAP-SPAN-VALID? 0= IF
            LIBSTORE-S-INVALID EXIT
        THEN
        _LIBMR-A @ _LIBMR-U @ UTF8-VALID? 0= IF
            LIBSTORE-S-INVALID EXIT
        THEN
    THEN
    _LIBMR-A @ _LIBMR-REQUEST @ LIBCIR.CONTENT-A !
    _LIBMR-U @ _LIBMR-REQUEST @ LIBCIR.CONTENT-U !
    LIBSTORE-S-OK ;

: _LIBRARY-CAPTURE-IMPORT-ORIGIN!  ( origin request -- status )
    _LIBMR-REQUEST ! _LIBMR-A !
    _LIBMR-REQUEST @ _LIBMR-CAPTURE-REQUEST-SAFE? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-A @ LIB-ORIGIN-SIZE _VFSNAP-SPAN-VALID? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-A @ LIB-ORIGIN-VALID? 0= IF LIBSTORE-S-INVALID EXIT THEN
    _LIBMR-A @ LIBO.KIND @ LIB-ORIGIN-NONE = IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-A @ _LIBMR-REQUEST @ LIBCIR.ORIGIN LIB-ORIGIN-SIZE MOVE
    LIBSTORE-S-OK ;

: _LIBMR-CAPTURE-CONTENT-MATCHES-ORIGIN?  ( request -- flag )
    _LIBMR-REQUEST !
    _LIBMR-REQUEST @ LIBCIR-CONTENT$ _LIBMU-FRAME-SHA SHA3-256-HASH
    _LIBMR-REQUEST @ LIBCIR.ORIGIN LIBO.KIND @ CASE
        LIB-ORIGIN-VFS-SNAPSHOT OF
            _LIBMR-REQUEST @ LIBCIR.CONTENT-U @
                _LIBMR-REQUEST @ LIBCIR.ORIGIN LIBO.VFS LIBV.CONTENT-U @ =
            _LIBMU-FRAME-SHA
                _LIBMR-REQUEST @ LIBCIR.ORIGIN LIBO.VFS
                    LIBV.CONTENT-DIGEST
                SHA3-256-COMPARE AND
        ENDOF
        LIB-ORIGIN-SEMANTIC OF
            _LIBMR-REQUEST @ LIBCIR.ORIGIN LIBO.SEMANTIC
                QLOC.DIGEST-KIND @ QLOC-DK-PROJECTION-CONTENT = IF
                _LIBMU-FRAME-SHA
                    _LIBMR-REQUEST @ LIBCIR.ORIGIN LIBO.SEMANTIC
                        QLOC.STATE-DIGEST
                    SHA3-256-COMPARE
            ELSE
                -1
            THEN
        ENDOF
        0 SWAP
    ENDCASE ;

: _LIBRARY-CAPTURE-IMPORT-REQUEST-VALID?  ( request -- flag )
    DUP _LIBMR-CAPTURE-REQUEST-SAFE? 0= IF DROP 0 EXIT THEN
    _LIBMR-REQUEST !
    _LIBMR-REQUEST @ LIBCIR.OPERATION-KEY RID-PRESENT? 0= IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCIR.EXPECTED-CATALOG-GENERATION @ 0< IF
        0 EXIT
    THEN
    _LIBMR-REQUEST @ LIBCIR.MEDIA @ DUP LIB-MEDIA-TEXT-PLAIN =
    OVER LIB-MEDIA-TEXT-MARKDOWN = OR
    SWAP LIB-MEDIA-TEXT-CSV = OR 0= IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCIR.TITLE-U @ DUP 1 <
        SWAP LIB-TITLE-MAX > OR IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCIR-TITLE$ UTF8-VALID? 0= IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCIR.TITLE
        _LIBMR-REQUEST @ LIBCIR.TITLE-U @ +
        LIB-TITLE-MAX _LIBMR-REQUEST @ LIBCIR.TITLE-U @ -
        _LIBMR-ZERO? 0= IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCIR.CONTENT-U @ DUP 0<
        SWAP LIB-CONTENT-MAX > OR IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCIR.CONTENT-U @ IF
        _LIBMR-REQUEST @ LIBCIR-CONTENT$
            _VFSNAP-SPAN-VALID? 0= IF 0 EXIT THEN
        _LIBMR-REQUEST @ LIBCIR-CONTENT$ UTF8-VALID? 0= IF 0 EXIT THEN
    THEN
    _LIBMR-REQUEST @ LIBCIR.ORIGIN LIB-ORIGIN-VALID? 0= IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCIR.ORIGIN LIBO.KIND @
        LIB-ORIGIN-NONE = IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCIR.FLAGS @ IF 0 EXIT THEN
    _LIBMR-REQUEST @ _LIBMR-CAPTURE-CONTENT-MATCHES-ORIGIN? ;

' _LIBRARY-CAPTURE-IMPORT-OPERATION-KEY!
    CONSTANT _libcir-operation-key-set-xt
' _LIBRARY-CAPTURE-IMPORT-TITLE! CONSTANT _libcir-title-set-xt
' _LIBRARY-CAPTURE-IMPORT-CONTENT! CONSTANT _libcir-content-set-xt
' _LIBRARY-CAPTURE-IMPORT-ORIGIN! CONSTANT _libcir-origin-set-xt
' _LIBRARY-CAPTURE-IMPORT-REQUEST-VALID? CONSTANT _libcir-valid-xt

: LIBRARY-CAPTURE-IMPORT-OPERATION-KEY!  ( key request -- status )
    _libcir-operation-key-set-xt _library-vfs-store-guard WITH-GUARD ;
: LIBRARY-CAPTURE-IMPORT-TITLE!  ( a u request -- status )
    _libcir-title-set-xt _library-vfs-store-guard WITH-GUARD ;
: LIBRARY-CAPTURE-IMPORT-CONTENT!  ( a u request -- status )
    _libcir-content-set-xt _library-vfs-store-guard WITH-GUARD ;
: LIBRARY-CAPTURE-IMPORT-ORIGIN!  ( origin request -- status )
    _libcir-origin-set-xt _library-vfs-store-guard WITH-GUARD ;
: LIBRARY-CAPTURE-IMPORT-REQUEST-VALID?  ( request -- flag )
    _libcir-valid-xt _library-vfs-store-guard WITH-GUARD ;

\ ---------------------------------------------------------------------
\ Metadata construction and validation
\ ---------------------------------------------------------------------

: _LIBMR-METADATA-SAFE?  ( metadata -- flag )
    DUP LIBRARY-METADATA-SIZE _VFSNAP-SPAN-VALID? 0= IF DROP 0 EXIT THEN
    DUP LIBRARY-METADATA-SIZE _LIBVFS-PRIVATE-ALIASES? 0= NIP ;

: _LIBRARY-METADATA-TITLE!  ( a u metadata -- status )
    _LIBMR-REQUEST ! _LIBMR-U ! _LIBMR-A !
    _LIBMR-REQUEST @ _LIBMR-METADATA-SAFE? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-U @ DUP 1 < SWAP LIB-TITLE-MAX > OR IF
        LIBSTORE-S-OUTPUT-CAPACITY EXIT
    THEN
    _LIBMR-A @ _LIBMR-U @ _VFSNAP-SPAN-VALID? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-A @ _LIBMR-U @ UTF8-VALID? 0= IF LIBSTORE-S-INVALID EXIT THEN
    _LIBMR-A @ _LIBMR-REQUEST @ LIBMD.TITLE _LIBMR-U @ MOVE
    _LIBMR-REQUEST @ LIBMD.TITLE _LIBMR-U @ +
        LIB-TITLE-MAX _LIBMR-U @ - 0 FILL
    _LIBMR-U @ _LIBMR-REQUEST @ LIBMD.TITLE-U !
    LIBSTORE-S-OK ;

: _LIBRARY-METADATA-TAG!  ( a u index metadata -- status )
    _LIBMR-REQUEST ! _LIBMU-INDEX ! _LIBMR-U ! _LIBMR-A !
    _LIBMR-REQUEST @ _LIBMR-METADATA-SAFE? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMU-INDEX @ DUP 0< SWAP LIB-TAG-MAX >= OR IF
        LIBSTORE-S-OUTPUT-CAPACITY EXIT
    THEN
    _LIBMU-INDEX @ _LIBMR-REQUEST @ LIBMD.TAG-N @ > IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-U @ DUP 1 < SWAP LIB-TAG-TEXT-MAX > OR IF
        LIBSTORE-S-OUTPUT-CAPACITY EXIT
    THEN
    _LIBMR-A @ _LIBMR-U @ _VFSNAP-SPAN-VALID? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-A @ _LIBMR-U @ UTF8-VALID? 0= IF LIBSTORE-S-INVALID EXIT THEN
    _LIBMU-INDEX @ _LIBMR-REQUEST @ LIBMD-TAG DUP LIB-TAG-SIZE 0 FILL
    DUP LIB-TAG.TEXT _LIBMR-A @ SWAP _LIBMR-U @ MOVE
    _LIBMR-U @ SWAP LIB-TAG.LEN !
    _LIBMU-INDEX @ _LIBMR-REQUEST @ LIBMD.TAG-N @ = IF
        1 _LIBMR-REQUEST @ LIBMD.TAG-N +!
    THEN
    LIBSTORE-S-OK ;

: _LIBMR-SEMANTIC-EXACT?  ( qloc -- flag )
    DUP QLOC-SIZE _VFSNAP-SPAN-VALID? 0= IF DROP 0 EXIT THEN
    DUP QLOC-VALID? 0= IF DROP 0 EXIT THEN
    DUP QLOC.MODE @ QLOC-M-EXACT-DOMAIN =
    OVER QLOC.STATE-DIGEST RID-PRESENT? AND NIP ;

: _LIBRARY-METADATA-LINEAGE!  ( lineage index metadata -- status )
    _LIBMR-REQUEST ! _LIBMU-INDEX ! _LIBMR-A !
    _LIBMR-REQUEST @ _LIBMR-METADATA-SAFE? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMU-INDEX @ DUP 0< SWAP LIB-LINEAGE-MAX >= OR IF
        LIBSTORE-S-OUTPUT-CAPACITY EXIT
    THEN
    _LIBMU-INDEX @ _LIBMR-REQUEST @ LIBMD.LINEAGE-N @ > IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-A @ LIB-LINEAGE-SIZE _VFSNAP-SPAN-VALID? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-A @ LIBLN.RELATION @
        LIB-LINEAGE-RELATION-DERIVED-FROM <> IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-A @ LIBLN.LOCATOR _LIBMR-SEMANTIC-EXACT? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-A @ _LIBMU-INDEX @ _LIBMR-REQUEST @ LIBMD-LINEAGE
        LIB-LINEAGE-SIZE MOVE
    _LIBMU-INDEX @ _LIBMR-REQUEST @ LIBMD.LINEAGE-N @ = IF
        1 _LIBMR-REQUEST @ LIBMD.LINEAGE-N +!
    THEN
    LIBSTORE-S-OK ;

: _LIBMR-TAG-SLOT-VALID?  ( tag -- flag )
    DUP LIB-TAG.LEN @ DUP 1 < SWAP LIB-TAG-TEXT-MAX > OR IF
        DROP 0 EXIT
    THEN
    DUP LIB-TAG$ UTF8-VALID? 0= IF DROP 0 EXIT THEN
    DUP LIB-TAG.TEXT OVER LIB-TAG.LEN @ +
    SWAP LIB-TAG.LEN @ LIB-TAG-TEXT-MAX SWAP - _LIBMR-ZERO? ;

: _LIBRARY-METADATA-VALID?  ( metadata -- flag )
    DUP _LIBMR-METADATA-SAFE? 0= IF DROP 0 EXIT THEN _LIBMR-REQUEST !
    _LIBMR-REQUEST @ LIBMD.TITLE-U @ DUP 1 <
        SWAP LIB-TITLE-MAX > OR IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBMD-TITLE$ UTF8-VALID? 0= IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBMD.TITLE
        _LIBMR-REQUEST @ LIBMD.TITLE-U @ +
        LIB-TITLE-MAX _LIBMR-REQUEST @ LIBMD.TITLE-U @ -
        _LIBMR-ZERO? 0= IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBMD.TAG-N @ DUP 0<
        SWAP LIB-TAG-MAX > OR IF 0 EXIT THEN
    LIB-TAG-MAX 0 ?DO
        I _LIBMR-REQUEST @ LIBMD-TAG
        I _LIBMR-REQUEST @ LIBMD.TAG-N @ < IF
            DUP _LIBMR-TAG-SLOT-VALID? 0= IF DROP 0 UNLOOP EXIT THEN
            I IF
                I 1- _LIBMR-REQUEST @ LIBMD-TAG LIB-TAG$
                I _LIBMR-REQUEST @ LIBMD-TAG LIB-TAG$ COMPARE
                0< 0= IF DROP 0 UNLOOP EXIT THEN
            THEN
            DROP
        ELSE
            LIB-TAG-SIZE _LIBMR-ZERO? 0= IF 0 UNLOOP EXIT THEN
        THEN
    LOOP
    _LIBMR-REQUEST @ LIBMD.LINEAGE-N @ DUP 0<
        SWAP LIB-LINEAGE-MAX > OR IF 0 EXIT THEN
    LIB-LINEAGE-MAX 0 ?DO
        I _LIBMR-REQUEST @ LIBMD-LINEAGE
        I _LIBMR-REQUEST @ LIBMD.LINEAGE-N @ < IF
            DUP LIBLN.RELATION @
                LIB-LINEAGE-RELATION-DERIVED-FROM <> IF
                DROP 0 UNLOOP EXIT
            THEN
            DUP LIBLN.LOCATOR _LIBMR-SEMANTIC-EXACT? 0= IF
                DROP 0 UNLOOP EXIT
            THEN
            I IF
                I 1- _LIBMR-REQUEST @ LIBMD-LINEAGE LIBLN.LOCATOR QLOC-SIZE
                I _LIBMR-REQUEST @ LIBMD-LINEAGE LIBLN.LOCATOR QLOC-SIZE
                COMPARE 0< 0= IF DROP 0 UNLOOP EXIT THEN
            THEN
            DROP
        ELSE
            LIB-LINEAGE-SIZE _LIBMR-ZERO? 0= IF 0 UNLOOP EXIT THEN
        THEN
    LOOP
    _LIBMR-REQUEST @ LIBMD.FLAGS @ 0= ;

' _LIBRARY-METADATA-TITLE! CONSTANT _libmd-title-set-xt
' _LIBRARY-METADATA-TAG! CONSTANT _libmd-tag-set-xt
' _LIBRARY-METADATA-LINEAGE! CONSTANT _libmd-lineage-set-xt
' _LIBRARY-METADATA-VALID? CONSTANT _libmd-valid-xt

: LIBRARY-METADATA-TITLE!  ( a u metadata -- status )
    _libmd-title-set-xt _library-vfs-store-guard WITH-GUARD ;
: LIBRARY-METADATA-TAG!  ( a u index metadata -- status )
    _libmd-tag-set-xt _library-vfs-store-guard WITH-GUARD ;
: LIBRARY-METADATA-LINEAGE!  ( lineage index metadata -- status )
    _libmd-lineage-set-xt _library-vfs-store-guard WITH-GUARD ;
: LIBRARY-METADATA-VALID?  ( metadata -- flag )
    _libmd-valid-xt _library-vfs-store-guard WITH-GUARD ;

\ ---------------------------------------------------------------------
\ Collection request construction
\ ---------------------------------------------------------------------

: _LIBMR-MEMBER-ARRAY-VALID?  ( members count -- flag )
    _LIBMR-U ! _LIBMR-A !
    _LIBMR-U @ DUP 0< SWAP LIB-COLLECTION-MEMBER-MAX > OR IF 0 EXIT THEN
    _LIBMR-U @ 0= IF _LIBMR-A @ 0= EXIT THEN
    _LIBMR-A @ _LIBMR-U @ LIB-DIGEST-SIZE *
        _VFSNAP-SPAN-VALID? 0= IF 0 EXIT THEN
    0 _LIBMR-I !
    BEGIN _LIBMR-I @ _LIBMR-U @ < WHILE
        _LIBMR-A @ _LIBMR-I @ LIB-DIGEST-SIZE * +
            RID-PRESENT? 0= IF 0 EXIT THEN
        0 _LIBMR-J !
        BEGIN _LIBMR-J @ _LIBMR-I @ < WHILE
            _LIBMR-A @ _LIBMR-J @ LIB-DIGEST-SIZE * +
            _LIBMR-A @ _LIBMR-I @ LIB-DIGEST-SIZE * + RID= IF
                0 EXIT
            THEN
            1 _LIBMR-J +!
        REPEAT
        1 _LIBMR-I +!
    REPEAT
    -1 ;

: _LIBMR-COLLECTION-CREATE-SAFE?  ( request -- flag )
    DUP LIBRARY-COLLECTION-CREATE-REQUEST-SIZE
        _VFSNAP-SPAN-VALID? 0= IF DROP 0 EXIT THEN
    DUP LIBRARY-COLLECTION-CREATE-REQUEST-SIZE
        _LIBVFS-PRIVATE-ALIASES? 0= NIP ;

: _LIBMR-COLLECTION-REPLACE-SAFE?  ( request -- flag )
    DUP LIBRARY-COLLECTION-REPLACE-REQUEST-SIZE
        _VFSNAP-SPAN-VALID? 0= IF DROP 0 EXIT THEN
    DUP LIBRARY-COLLECTION-REPLACE-REQUEST-SIZE
        _LIBVFS-PRIVATE-ALIASES? 0= NIP ;

: _LIBRARY-COLLECTION-CREATE-OPERATION-KEY!  ( key request -- status )
    _LIBMR-REQUEST ! _LIBMR-A !
    _LIBMR-REQUEST @ _LIBMR-COLLECTION-CREATE-SAFE? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-A @ LIB-DIGEST-SIZE _VFSNAP-SPAN-VALID? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-A @ RID-PRESENT? 0= IF LIBSTORE-S-INVALID EXIT THEN
    _LIBMR-A @ _LIBMR-REQUEST @ LIBCCR.OPERATION-KEY RID-COPY
    LIBSTORE-S-OK ;

: _LIBRARY-COLLECTION-CREATE-TITLE!  ( a u request -- status )
    _LIBMR-REQUEST ! _LIBMR-U ! _LIBMR-A !
    _LIBMR-REQUEST @ _LIBMR-COLLECTION-CREATE-SAFE? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-U @ DUP 1 < SWAP LIB-COLLECTION-TITLE-MAX > OR IF
        LIBSTORE-S-OUTPUT-CAPACITY EXIT
    THEN
    _LIBMR-A @ _LIBMR-U @ _VFSNAP-SPAN-VALID? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-A @ _LIBMR-U @ UTF8-VALID? 0= IF LIBSTORE-S-INVALID EXIT THEN
    _LIBMR-A @ _LIBMR-REQUEST @ LIBCCR.TITLE _LIBMR-U @ MOVE
    _LIBMR-REQUEST @ LIBCCR.TITLE _LIBMR-U @ +
        LIB-COLLECTION-TITLE-MAX _LIBMR-U @ - 0 FILL
    _LIBMR-U @ _LIBMR-REQUEST @ LIBCCR.TITLE-U !
    LIBSTORE-S-OK ;

: _LIBRARY-COLLECTION-REPLACE-TITLE!  ( a u request -- status )
    _LIBMR-REQUEST ! _LIBMR-U ! _LIBMR-A !
    _LIBMR-REQUEST @ _LIBMR-COLLECTION-REPLACE-SAFE? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-U @ DUP 1 < SWAP LIB-COLLECTION-TITLE-MAX > OR IF
        LIBSTORE-S-OUTPUT-CAPACITY EXIT
    THEN
    _LIBMR-A @ _LIBMR-U @ _VFSNAP-SPAN-VALID? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-A @ _LIBMR-U @ UTF8-VALID? 0= IF LIBSTORE-S-INVALID EXIT THEN
    _LIBMR-A @ _LIBMR-REQUEST @ LIBCRR.TITLE _LIBMR-U @ MOVE
    _LIBMR-REQUEST @ LIBCRR.TITLE _LIBMR-U @ +
        LIB-COLLECTION-TITLE-MAX _LIBMR-U @ - 0 FILL
    _LIBMR-U @ _LIBMR-REQUEST @ LIBCRR.TITLE-U !
    LIBSTORE-S-OK ;

: _LIBRARY-COLLECTION-CREATE-MEMBERS!  ( members count request -- status )
    _LIBMR-REQUEST ! _LIBMR-U ! _LIBMR-A !
    _LIBMR-REQUEST @ _LIBMR-COLLECTION-CREATE-SAFE? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-A @ _LIBMR-U @ _LIBMR-MEMBER-ARRAY-VALID? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-A @ _LIBMR-REQUEST @ LIBCCR.MEMBERS-A !
    _LIBMR-U @ _LIBMR-REQUEST @ LIBCCR.MEMBER-N !
    LIBSTORE-S-OK ;

: _LIBRARY-COLLECTION-REPLACE-MEMBERS!  ( members count request -- status )
    _LIBMR-REQUEST ! _LIBMR-U ! _LIBMR-A !
    _LIBMR-REQUEST @ _LIBMR-COLLECTION-REPLACE-SAFE? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-A @ _LIBMR-U @ _LIBMR-MEMBER-ARRAY-VALID? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBMR-A @ _LIBMR-REQUEST @ LIBCRR.MEMBERS-A !
    _LIBMR-U @ _LIBMR-REQUEST @ LIBCRR.MEMBER-N !
    LIBSTORE-S-OK ;

: _LIBRARY-COLLECTION-CREATE-REQUEST-VALID?  ( request -- flag )
    DUP _LIBMR-COLLECTION-CREATE-SAFE? 0= IF DROP 0 EXIT THEN
    _LIBMR-REQUEST !
    _LIBMR-REQUEST @ LIBCCR.OPERATION-KEY RID-PRESENT? 0= IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCCR.EXPECTED-CATALOG-GENERATION @ 0< IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCCR.TITLE-U @ DUP 1 <
        SWAP LIB-COLLECTION-TITLE-MAX > OR IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCCR-TITLE$ UTF8-VALID? 0= IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCCR.TITLE
        _LIBMR-REQUEST @ LIBCCR.TITLE-U @ +
        LIB-COLLECTION-TITLE-MAX _LIBMR-REQUEST @ LIBCCR.TITLE-U @ -
        _LIBMR-ZERO? 0= IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCCR-MEMBERS$ _LIBMR-MEMBER-ARRAY-VALID? 0= IF
        0 EXIT
    THEN
    _LIBMR-REQUEST @ LIBCCR.FLAGS @ 0= ;

: _LIBRARY-COLLECTION-REPLACE-REQUEST-VALID?  ( request -- flag )
    DUP _LIBMR-COLLECTION-REPLACE-SAFE? 0= IF DROP 0 EXIT THEN
    _LIBMR-REQUEST !
    _LIBMR-REQUEST @ LIBCRR.ID RID-PRESENT? 0= IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCRR.EXPECTED-REVISION @ 0> 0= IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCRR.TITLE-U @ DUP 1 <
        SWAP LIB-COLLECTION-TITLE-MAX > OR IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCRR-TITLE$ UTF8-VALID? 0= IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCRR.TITLE
        _LIBMR-REQUEST @ LIBCRR.TITLE-U @ +
        LIB-COLLECTION-TITLE-MAX _LIBMR-REQUEST @ LIBCRR.TITLE-U @ -
        _LIBMR-ZERO? 0= IF 0 EXIT THEN
    _LIBMR-REQUEST @ LIBCRR-MEMBERS$ _LIBMR-MEMBER-ARRAY-VALID? 0= IF
        0 EXIT
    THEN
    _LIBMR-REQUEST @ LIBCRR.FLAGS @ 0= ;

' _LIBRARY-COLLECTION-CREATE-OPERATION-KEY!
    CONSTANT _libccr-operation-key-set-xt
' _LIBRARY-COLLECTION-CREATE-TITLE! CONSTANT _libccr-title-set-xt
' _LIBRARY-COLLECTION-CREATE-MEMBERS! CONSTANT _libccr-members-set-xt
' _LIBRARY-COLLECTION-CREATE-REQUEST-VALID? CONSTANT _libccr-valid-xt
' _LIBRARY-COLLECTION-REPLACE-TITLE! CONSTANT _libcrr-title-set-xt
' _LIBRARY-COLLECTION-REPLACE-MEMBERS! CONSTANT _libcrr-members-set-xt
' _LIBRARY-COLLECTION-REPLACE-REQUEST-VALID? CONSTANT _libcrr-valid-xt

: LIBRARY-COLLECTION-CREATE-OPERATION-KEY!  ( key request -- status )
    _libccr-operation-key-set-xt _library-vfs-store-guard WITH-GUARD ;
: LIBRARY-COLLECTION-CREATE-TITLE!  ( a u request -- status )
    _libccr-title-set-xt _library-vfs-store-guard WITH-GUARD ;
: LIBRARY-COLLECTION-CREATE-MEMBERS!  ( members count request -- status )
    _libccr-members-set-xt _library-vfs-store-guard WITH-GUARD ;
: LIBRARY-COLLECTION-CREATE-REQUEST-VALID?  ( request -- flag )
    _libccr-valid-xt _library-vfs-store-guard WITH-GUARD ;
: LIBRARY-COLLECTION-REPLACE-TITLE!  ( a u request -- status )
    _libcrr-title-set-xt _library-vfs-store-guard WITH-GUARD ;
: LIBRARY-COLLECTION-REPLACE-MEMBERS!  ( members count request -- status )
    _libcrr-members-set-xt _library-vfs-store-guard WITH-GUARD ;
: LIBRARY-COLLECTION-REPLACE-REQUEST-VALID?  ( request -- flag )
    _libcrr-valid-xt _library-vfs-store-guard WITH-GUARD ;

\ =====================================================================
\  VFSNAP adaptation and retained evidence
\ =====================================================================

: LIBRARY-VFS-STORE-LAST-STATUS@  ( store -- status )
    LIBRARY-VFS-STORE.LAST-STATUS @ ;
: LIBRARY-VFS-STORE-LAST-VFSNAP@  ( store -- status )
    LIBRARY-VFS-STORE.LAST-VFSNAP @ ;
: LIBRARY-VFS-STORE-LAST-VREPL@  ( store -- status )
    LIBRARY-VFS-STORE.LAST-VREPL @ ;

: _LIBVFS-VFSNAP>STATUS  ( snapshot-status -- library-status )
    CASE
        VFSNAP-S-OK OF LIBSTORE-S-OK ENDOF
        VFSNAP-S-ABSENT OF LIBSTORE-S-ABSENT ENDOF
        VFSNAP-S-CORRUPT OF LIBSTORE-S-CORRUPT ENDOF
        VFSNAP-S-UNSUPPORTED OF LIBSTORE-S-UNSUPPORTED ENDOF
        VFSNAP-S-INVALID OF LIBSTORE-S-INVALID ENDOF
        \ A fixed 448-byte payload cannot be caller-resized.  Capacity here
        \ means exhausted envelope generation or an impossible sealed spec.
        VFSNAP-S-CAPACITY OF LIBSTORE-S-RECOVERY ENDOF
        VFSNAP-S-IO OF LIBSTORE-S-IO ENDOF
        VFSNAP-S-RECOVERY OF LIBSTORE-S-RECOVERY ENDOF
        VFSNAP-S-BUSY OF LIBSTORE-S-BUSY ENDOF
        VFSNAP-S-CONFLICT OF LIBSTORE-S-CONFLICT ENDOF
        LIBSTORE-S-RECOVERY SWAP
    ENDCASE ;

VARIABLE _LIBVA-STORE
VARIABLE _LIBVA-SNAPSHOT-STATUS
VARIABLE _LIBVA-STATUS
VARIABLE _LIBVA-FLAGS

: _LIBVFS-ADAPT  ( snapshot-status store -- library-status )
    _LIBVA-STORE ! _LIBVA-SNAPSHOT-STATUS !
    _LIBVA-SNAPSHOT-STATUS @
        _LIBVA-STORE @ LIBRARY-VFS-STORE.LAST-VFSNAP !
    _LIBVA-STORE @ _LIBRARY-VFS-STORE.CORE VFSNAP-LAST-VREPL@
        DUP _LIBVA-STORE @ LIBRARY-VFS-STORE.LAST-VREPL !
    DUP VREPL-S-COMMITTED-CLEANUP = IF
        _LIBVA-STORE @ LIBRARY-VFS-STORE.FLAGS DUP @
            _LIBVFS-F-CLEANUP-FAILED OR SWAP !
    THEN
    _LIBVA-SNAPSHOT-STATUS @ VFSNAP-S-RECOVERY =
        SWAP VREPL-S-UNCERTAIN = AND IF
        LIBSTORE-S-UNCERTAIN
    ELSE
        _LIBVA-SNAPSHOT-STATUS @ _LIBVFS-VFSNAP>STATUS
    THEN
    _LIBVA-STATUS !
    \ VFSNAP may add a block, but a healthy head transaction must never
    \ erase corpus-level corruption/future/recovery evidence.
    _LIBVA-STORE @ LIBRARY-VFS-STORE.FLAGS @ _LIBVA-FLAGS !
    _LIBVA-STORE @ _LIBRARY-VFS-STORE.CORE VFSNAP-BLOCKED? IF
        _LIBVA-FLAGS @ _LIBVFS-F-BLOCKED OR _LIBVA-FLAGS !
    THEN
    _LIBVA-FLAGS @ _LIBVA-STORE @ LIBRARY-VFS-STORE.FLAGS !
    _LIBVA-STATUS @ _LIBVA-STORE @ LIBRARY-VFS-STORE.LAST-STATUS !
    _LIBVA-STATUS @ ;

: _LIBVFS-RESULT  ( status store -- status )
    _LIBVA-STORE ! _LIBVA-STATUS !
    _LIBVA-STATUS @ _LIBVA-STORE @ LIBRARY-VFS-STORE.LAST-STATUS !
    _LIBVA-STATUS @ ;

: _LIBVFS-CORPUS-BLOCKING?  ( status -- flag )
    DUP LIBSTORE-S-CORRUPT =
    OVER LIBSTORE-S-UNSUPPORTED = OR
    OVER LIBSTORE-S-RECOVERY = OR
    SWAP LIBSTORE-S-UNCERTAIN = OR ;

: _LIBVFS-CORPUS-RESULT  ( status store -- status )
    _LIBVA-STORE ! _LIBVA-STATUS !
    _LIBVA-STATUS @ _LIBVFS-CORPUS-BLOCKING? IF
        _LIBVA-STORE @ LIBRARY-VFS-STORE.FLAGS DUP @
            _LIBVFS-F-BLOCKED OR SWAP !
    THEN
    _LIBVA-STATUS @ _LIBVA-STORE @ _LIBVFS-RESULT ;

: _LIBVFS-CLEAR-CORPUS-BLOCK  ( store -- )
    LIBRARY-VFS-STORE.FLAGS DUP @
        _LIBVFS-F-BLOCKED INVERT AND SWAP ! ;

: _LIBVFS-CLEAR-PUBLISHED  ( store -- )
    _LIBAUTH-INVALIDATE
    DUP LIBRARY-VFS-STORE.FLAGS DUP @ _LIBVFS-F-LOADED INVERT AND SWAP !
    DUP LIBRARY-VFS-STORE.GENERATION 8 0 FILL
    DUP LIBRARY-VFS-STORE.HEAD LIB-HEAD-FACT-SIZE 0 FILL
    DUP LIBRARY-VFS-STORE.ARENA LIB-ARENA-FACT-SIZE 0 FILL
    LIBRARY-VFS-STORE.BANK LIB-BANK-FACT-SIZE 0 FILL ;

: _LIBVFS-PUBLISH-CANDIDATES  ( store -- )
    >R
    _LIBVP-CANDIDATE-GENERATION @
        R@ LIBRARY-VFS-STORE.GENERATION !
    _LIBVP-HEAD-FACT R@ LIBRARY-VFS-STORE.HEAD
        LIB-HEAD-FACT-SIZE CMOVE
    _LIBVP-ARENA-FACT R@ LIBRARY-VFS-STORE.ARENA
        LIB-ARENA-FACT-SIZE CMOVE
    _LIBVP-BANK-FACT R@ LIBRARY-VFS-STORE.BANK
        LIB-BANK-FACT-SIZE CMOVE
    R> LIBRARY-VFS-STORE.FLAGS DUP @ _LIBVFS-F-LOADED OR SWAP ! ;

: _LIBVP-RESULT  ( status store -- status )
    _LIBVA-STORE ! _LIBVA-STATUS !
    _LIBVP-CLEANUP-EVIDENCE @ IF
        _LIBVA-STORE @ LIBRARY-VFS-STORE.FLAGS DUP @
            _LIBVFS-F-CLEANUP-FAILED OR SWAP !
    THEN
    _LIBVA-STATUS @ _LIBVA-STORE @ LIBRARY-VFS-STORE.LAST-STATUS !
    _LIBVA-STATUS @ ;

: _LIBVFS-FORMAT>STATUS  ( library-codec-status -- library-store-status )
    CASE
        LIB-S-OK OF LIBSTORE-S-OK ENDOF
        LIB-S-INVALID OF LIBSTORE-S-INVALID ENDOF
        LIB-S-CAPACITY OF LIBSTORE-S-INVALID ENDOF
        LIB-S-CHECKSUM OF LIBSTORE-S-CORRUPT ENDOF
        LIB-S-UNSUPPORTED OF LIBSTORE-S-UNSUPPORTED ENDOF
        LIB-S-INTEGRITY OF LIBSTORE-S-CORRUPT ENDOF
        LIBSTORE-S-RECOVERY SWAP
    ENDCASE ;

: _LIBVFS-FORMAT-READ>STATUS  ( library-codec-status -- store-status )
    CASE
        LIB-S-OK OF LIBSTORE-S-OK ENDOF
        LIB-S-UNSUPPORTED OF LIBSTORE-S-UNSUPPORTED ENDOF
        LIB-S-INVALID OF LIBSTORE-S-CORRUPT ENDOF
        LIB-S-CAPACITY OF LIBSTORE-S-CORRUPT ENDOF
        LIB-S-CHECKSUM OF LIBSTORE-S-CORRUPT ENDOF
        LIB-S-INTEGRITY OF LIBSTORE-S-CORRUPT ENDOF
        LIBSTORE-S-RECOVERY SWAP
    ENDCASE ;

: _LIBVFS-ENCODE-CODEC>VFSNAP  ( library-codec-status -- snapshot-status )
    CASE
        LIB-S-OK OF VFSNAP-S-OK ENDOF
        LIB-S-INVALID OF VFSNAP-S-INVALID ENDOF
        LIB-S-CAPACITY OF VFSNAP-S-CAPACITY ENDOF
        LIB-S-UNSUPPORTED OF VFSNAP-S-UNSUPPORTED ENDOF
        LIB-S-CHECKSUM OF VFSNAP-S-INVALID ENDOF
        LIB-S-INTEGRITY OF VFSNAP-S-INVALID ENDOF
        VFSNAP-S-INVALID SWAP
    ENDCASE ;

: _LIBVFS-READ-CODEC>VFSNAP  ( library-codec-status -- snapshot-status )
    CASE
        LIB-S-OK OF VFSNAP-S-OK ENDOF
        LIB-S-UNSUPPORTED OF VFSNAP-S-UNSUPPORTED ENDOF
        LIB-S-INVALID OF VFSNAP-S-CORRUPT ENDOF
        LIB-S-CAPACITY OF VFSNAP-S-CORRUPT ENDOF
        LIB-S-CHECKSUM OF VFSNAP-S-CORRUPT ENDOF
        LIB-S-INTEGRITY OF VFSNAP-S-CORRUPT ENDOF
        VFSNAP-S-CORRUPT SWAP
    ENDCASE ;

: _LIBVFS-HEAD-ENCODE-CALLBACK
  ( head-fact payload-a payload-u next-generation -- snapshot-status )
    _LIBVC-GENERATION ! _LIBVC-PAYLOAD-U !
    _LIBVC-PAYLOAD ! _LIBVC-CONTEXT !
    _LIBVC-CONTEXT @ _LIBVC-PAYLOAD @ _LIBVC-PAYLOAD-U @
        _LIBVC-GENERATION @ LIB-HEAD-PAYLOAD-ENCODE
    DUP IF NIP _LIBVFS-ENCODE-CODEC>VFSNAP EXIT THEN DROP
    LIB-HEAD-PAYLOAD-SIZE = IF VFSNAP-S-OK ELSE VFSNAP-S-INVALID THEN ;

: _LIBVFS-HEAD-VALIDATE-CALLBACK
  ( payload-a payload-u envelope-generation -- snapshot-status )
    LIB-HEAD-PAYLOAD-VALIDATE _LIBVFS-READ-CODEC>VFSNAP ;

\ Maintenance consumes the same bytes through the neutral checked-record
\ boundary.  This spec is validation-only; ordinary head writes continue
\ through the Library owner's VFSNAP path.
: _LIBMA-HEAD-CREC-ENCODE-UNUSED
  ( context-a context-u payload-a payload-u tag -- checked-status )
    2DROP 2DROP DROP CREC-S-INVALID ;

: _LIBMA-HEAD-CREC-VALIDATE
  ( context-a context-u payload-a payload-u tag -- checked-status )
    >R 2SWAP 2DROP R> LIB-HEAD-PAYLOAD-VALIDATE
    CASE
        LIB-S-OK OF CREC-S-OK ENDOF
        LIB-S-CHECKSUM OF CREC-S-CHECKSUM ENDOF
        LIB-S-UNSUPPORTED OF CREC-S-UNSUPPORTED ENDOF
        CREC-S-SEMANTIC SWAP
    ENDCASE ;

\ =====================================================================
\  Exact terminal cleanup
\ =====================================================================

: _LIBVP-SHA-END-CALL  ( -- )
    _LIBVP-SHA-END-DEST @ SHA3-256-END ;
: _LIBVP-CRC-END-CALL  ( -- )
    CRC32-END _LIBVP-BODY-CRC ! ;

: _LIBVP-SHA-BEGIN  ( -- )
    SHA3-256-BEGIN -1 _LIBVP-SHA-ACTIVE ! ;
: _LIBVP-CRC-BEGIN  ( -- )
    CRC32-BEGIN -1 _LIBVP-CRC-ACTIVE ! ;

: _LIBVP-SHA-END-NOW  ( destination -- status )
    _LIBVP-SHA-END-DEST !
    _LIBVP-SHA-ACTIVE @ 0= IF LIBSTORE-S-OK EXIT THEN
    0 _LIBVP-SHA-ACTIVE !
    ['] _LIBVP-SHA-END-CALL CATCH IF
        -1 _LIBVP-CLEANUP-EVIDENCE ! LIBSTORE-S-IO
    ELSE
        LIBSTORE-S-OK
    THEN ;

: _LIBVP-CRC-END-NOW  ( -- status )
    _LIBVP-CRC-ACTIVE @ 0= IF LIBSTORE-S-OK EXIT THEN
    0 _LIBVP-CRC-ACTIVE !
    ['] _LIBVP-CRC-END-CALL CATCH IF
        -1 _LIBVP-CLEANUP-EVIDENCE ! LIBSTORE-S-IO
    ELSE
        LIBSTORE-S-OK
    THEN ;

: _LIBVP-CLOSE-CALL  ( -- )
    _LIBVP-CLEAN-FD @ _LIBVFS-CLOSE ;
: _LIBVP-RESTORE-CWD-CALL  ( -- )
    _LIBVP-OLD-CWD @ _LIBVP-VFS @ _LIBVFS-CD ;
: _LIBVP-RESTORE-VFS-CALL  ( -- )
    _LIBVP-OLD-VFS @ _LIBVFS-USE ;

: _LIBVP-CLOSE-NOW  ( -- status )
    _LIBVP-FD @ ?DUP 0= IF LIBSTORE-S-OK EXIT THEN
    _LIBVP-CLEAN-FD !
    0 _LIBVP-FD !
    ['] _LIBVP-CLOSE-CALL CATCH IF
        -1 _LIBVP-CLEANUP-EVIDENCE ! LIBSTORE-S-IO
    ELSE
        LIBSTORE-S-OK
    THEN ;

: _LIBMU-CLOSE-SOURCE-CALL  ( -- )
    _LIBMU-CLEAN-SOURCE-FD @ _LIBVFS-CLOSE ;

: _LIBMU-CLOSE-SOURCE-NOW  ( -- status )
    _LIBMU-SOURCE-FD @ ?DUP 0= IF LIBSTORE-S-OK EXIT THEN
    _LIBMU-CLEAN-SOURCE-FD !
    0 _LIBMU-SOURCE-FD !
    ['] _LIBMU-CLOSE-SOURCE-CALL CATCH IF
        -1 _LIBVP-CLEANUP-EVIDENCE ! LIBSTORE-S-IO
    ELSE
        LIBSTORE-S-OK
    THEN ;

: _LIBVP-RESTORE-CWD-NOW  ( -- status )
    _LIBVP-HAVE-OLD-CWD @ 0= IF LIBSTORE-S-OK EXIT THEN
    \ Clear before the call: even a throwing callback is attempted once.
    0 _LIBVP-HAVE-OLD-CWD !
    ['] _LIBVP-RESTORE-CWD-CALL CATCH IF
        -1 _LIBVP-CLEANUP-EVIDENCE ! LIBSTORE-S-IO
    ELSE
        LIBSTORE-S-OK
    THEN ;

: _LIBVP-CLEANUP  ( -- failed? )
    0 _LIBVP-CLEAN-FAILED !
    _LIBVP-CRC-END-NOW IF -1 _LIBVP-CLEAN-FAILED ! THEN
    _LIBVP-SHA-DISCARD _LIBVP-SHA-END-NOW IF
        -1 _LIBVP-CLEAN-FAILED !
    THEN
    _LIBMU-CLOSE-SOURCE-NOW IF -1 _LIBVP-CLEAN-FAILED ! THEN
    _LIBVP-CLOSE-NOW IF -1 _LIBVP-CLEAN-FAILED ! THEN
    _LIBVP-RESTORE-CWD-NOW IF -1 _LIBVP-CLEAN-FAILED ! THEN
    _LIBVP-HAVE-OLD-VFS @ IF
        \ The selector restore is likewise exact-once under THROW.
        0 _LIBVP-HAVE-OLD-VFS !
        ['] _LIBVP-RESTORE-VFS-CALL CATCH IF
            -1 _LIBVP-CLEANUP-EVIDENCE !
            -1 _LIBVP-CLEAN-FAILED !
        THEN
    THEN
    _LIBVP-CLEAN-FAILED @ ;

\ =====================================================================
\  Format-independent first-use file mechanics
\ =====================================================================

: _LIBVP-SELECT  ( -- )
    VFS-CUR _LIBVP-OLD-VFS !
    -1 _LIBVP-HAVE-OLD-VFS !
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    _LIBVP-VFS @ _LIBVFS-USE ;

: _LIBVP-SYNC  ( -- status )
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    _LIBVP-VFS @ _LIBVFS-SYNC IF LIBSTORE-S-IO ELSE LIBSTORE-S-OK THEN ;

\ Direct child preflights run inside _LIBVP-RUN's outer VFS transaction.
\ This revalidates the sealed parent in the same exclusion region as OPEN,
\ closing the gap between head assurance and subsequent bank/content I/O.
: _LIBVP-DIRECTORY-PREFLIGHT  ( missing-status -- status )
    >R _LIBVP-VFS @ _LIBVFS-DIRECTORY-NAMESPACE
    DUP LIBSTORE-S-ABSENT = IF DROP R> EXIT THEN
    R> DROP
    DUP LIBSTORE-S-CORRUPT = IF DROP LIBSTORE-S-RECOVERY THEN ;

: _LIBVP-ENSURE-DIRECTORY  ( -- status )
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    _LIBVP-VFS @ _LIBVFS-DIRECTORY-NAMESPACE
    DUP LIBSTORE-S-OK = IF EXIT THEN
    DUP LIBSTORE-S-ABSENT <> IF EXIT THEN DROP
    _LIBVP-VFS @ V.CWD @ _LIBVP-OLD-CWD !
    -1 _LIBVP-HAVE-OLD-CWD !
    _LIBVP-VFS @ V.ROOT @ _LIBVP-VFS @ _LIBVFS-CD
    LIBSTORE-S-ALLOCATION _LIBVP-THROW-STATUS !
    _LIBVFS-DIRECTORY-NAME$ _LIBVP-VFS @ _LIBVFS-MKDIR IF
        _LIBVP-RESTORE-CWD-NOW DROP
        LIBSTORE-S-ALLOCATION EXIT
    THEN
    _LIBVP-RESTORE-CWD-NOW DUP IF EXIT THEN DROP
    \ Directory durability precedes every child create.
    _LIBVP-SYNC DUP IF EXIT THEN DROP
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    _LIBVP-VFS @ _LIBVFS-DIRECTORY-NAMESPACE
    DUP LIBSTORE-S-ABSENT = IF DROP LIBSTORE-S-IO THEN ;

: _LIBVP-OPEN-OR-CREATE  ( -- status )
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    _LIBVP-PATH-A @ _LIBVP-PATH-U @ VFS-T-FILE _LIBVP-VFS @
        _LIBVFS-NAMESPACE-TYPE
    DUP LIBSTORE-S-ABSENT = IF
        DROP
        LIBSTORE-S-ALLOCATION _LIBVP-THROW-STATUS !
        _LIBVP-PATH-A @ _LIBVP-PATH-U @ _LIBVP-VFS @ _LIBVFS-CREATE
            0= IF LIBSTORE-S-ALLOCATION EXIT THEN
    ELSE
        DUP IF EXIT THEN DROP
    THEN
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    _LIBVP-PATH-A @ _LIBVP-PATH-U @ _LIBVFS-OPEN DUP 0= IF
        DROP LIBSTORE-S-IO EXIT
    THEN
    _LIBVP-FD !
    LIBSTORE-S-OK ;

: _LIBVP-ZERO-CURRENT-FILE  ( -- status )
    _LIBVP-FILE-U @ 1 <
    _LIBVP-FILE-U @ LIB-STORE-SECTOR-SIZE 1- AND 0<> OR IF
        LIBSTORE-S-INVALID EXIT
    THEN
    LIBSTORE-S-ALLOCATION _LIBVP-THROW-STATUS !
    _LIBVP-FILE-U @ _LIBVP-FD @ _LIBVFS-TRUNCATE IF
        LIBSTORE-S-ALLOCATION EXIT
    THEN
    _LIBVP-FD @ _LIBVFS-SIZE _LIBVP-FILE-U @ <> IF
        LIBSTORE-S-ALLOCATION EXIT
    THEN
    \ Force the backing binding to reserve the full logical extent before
    \ chunked initialization.  RAM VFS allocates on first write, while
    \ persistent bindings treat this as an ordinary in-range write.
    0 _LIBVP-SECTOR C!
    _LIBVP-FILE-U @ 1- _LIBVP-FD @ _LIBVFS-SEEK
    _LIBVP-SECTOR 1 _LIBVP-FD @ _LIBVFS-WRITE-EXACT IF
        LIBSTORE-S-ALLOCATION EXIT
    THEN
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    0 _LIBVP-FD @ _LIBVFS-SEEK
    _LIBVP-ZERO-BLOCK _LIBVP-ZERO-BLOCK-SIZE 0 FILL
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    _LIBVP-FILE-U @ _LIBVP-REMAINING !
    BEGIN _LIBVP-REMAINING @ 0> WHILE
        _LIBVP-REMAINING @ _LIBVP-ZERO-BLOCK-SIZE MIN _LIBVP-CHUNK !
        _LIBVP-ZERO-BLOCK _LIBVP-CHUNK @
            _LIBVP-FD @ _LIBVFS-WRITE-EXACT IF
            LIBSTORE-S-IO EXIT
        THEN
        _LIBVP-CHUNK @ NEGATE _LIBVP-REMAINING +!
    REPEAT
    LIBSTORE-S-OK ;

: _LIBVP-ZERO-FILE  ( path-a path-u exact-length -- status )
    _LIBVP-FILE-U ! _LIBVP-PATH-U ! _LIBVP-PATH-A !
    _LIBVP-OPEN-OR-CREATE DUP IF EXIT THEN DROP
    _LIBVP-ZERO-CURRENT-FILE DUP IF EXIT THEN DROP
    _LIBVP-CLOSE-NOW DUP IF EXIT THEN DROP
    _LIBVP-SYNC ;

: _LIBVP-OPEN-EXACT  ( path-a path-u exact-length -- status )
    _LIBVP-FILE-U ! _LIBVP-PATH-U ! _LIBVP-PATH-A !
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    LIBSTORE-S-CORRUPT _LIBVP-DIRECTORY-PREFLIGHT
        DUP IF EXIT THEN DROP
    _LIBVP-PATH-A @ _LIBVP-PATH-U @ VFS-T-FILE _LIBVP-VFS @
        _LIBVFS-NAMESPACE-TYPE
    DUP LIBSTORE-S-ABSENT = IF DROP LIBSTORE-S-CORRUPT EXIT THEN
    DUP IF EXIT THEN DROP
    _LIBVP-PATH-A @ _LIBVP-PATH-U @ _LIBVFS-OPEN DUP 0= IF
        DROP LIBSTORE-S-IO EXIT
    THEN
    _LIBVP-FD !
    _LIBVP-FD @ _LIBVFS-SIZE _LIBVP-FILE-U @ <> IF
        LIBSTORE-S-CORRUPT EXIT
    THEN
    LIBSTORE-S-OK ;

\ A committed head names evidence that must exist.  Absence is recovery;
\ malformed type/size is corruption, and transfer failures remain I/O.
: _LIBVP-OPEN-COMMITTED  ( path-a path-u exact-length -- status )
    _LIBVP-FILE-U ! _LIBVP-PATH-U ! _LIBVP-PATH-A !
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    LIBSTORE-S-RECOVERY _LIBVP-DIRECTORY-PREFLIGHT
        DUP IF EXIT THEN DROP
    _LIBVP-PATH-A @ _LIBVP-PATH-U @ VFS-T-FILE _LIBVP-VFS @
        _LIBVFS-NAMESPACE-TYPE
    DUP LIBSTORE-S-ABSENT = IF DROP LIBSTORE-S-RECOVERY EXIT THEN
    DUP IF EXIT THEN DROP
    _LIBVP-PATH-A @ _LIBVP-PATH-U @ _LIBVFS-OPEN DUP 0= IF
        DROP LIBSTORE-S-IO EXIT
    THEN
    _LIBVP-FD !
    _LIBVP-FD @ _LIBVFS-SIZE _LIBVP-FILE-U @ <> IF
        LIBSTORE-S-CORRUPT EXIT
    THEN
    LIBSTORE-S-OK ;

: _LIBVP-HASH-RANGE  ( offset length destination -- status )
    _LIBVP-HASH-DEST ! _LIBVP-REMAINING !
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    _LIBVP-FD @ _LIBVFS-SEEK
    _LIBVP-SHA-BEGIN
    BEGIN _LIBVP-REMAINING @ 0> WHILE
        _LIBVP-REMAINING @ _LIBVP-ZERO-BLOCK-SIZE MIN _LIBVP-CHUNK !
        _LIBVP-ZERO-BLOCK _LIBVP-CHUNK @
            _LIBVP-FD @ _LIBVFS-READ-EXACT IF
            _LIBVP-SHA-DISCARD _LIBVP-SHA-END-NOW DROP
            LIBSTORE-S-IO EXIT
        THEN
        _LIBVP-ZERO-BLOCK _LIBVP-CHUNK @ SHA3-256-ADD
        _LIBVP-CHUNK @ NEGATE _LIBVP-REMAINING +!
    REPEAT
    _LIBVP-HASH-DEST @ _LIBVP-SHA-END-NOW ;

: _LIBVP-CRC-RANGE  ( offset length -- status )
    _LIBVP-REMAINING !
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    _LIBVP-FD @ _LIBVFS-SEEK
    _LIBVP-CRC-BEGIN
    BEGIN _LIBVP-REMAINING @ 0> WHILE
        _LIBVP-REMAINING @ _LIBVP-ZERO-BLOCK-SIZE MIN _LIBVP-CHUNK !
        _LIBVP-ZERO-BLOCK _LIBVP-CHUNK @
            _LIBVP-FD @ _LIBVFS-READ-EXACT IF
            _LIBVP-CRC-END-NOW DROP
            LIBSTORE-S-IO EXIT
        THEN
        _LIBVP-ZERO-BLOCK _LIBVP-CHUNK @ CRC32-ADD
        _LIBVP-CHUNK @ NEGATE _LIBVP-REMAINING +!
    REPEAT
    _LIBVP-CRC-END-NOW ;

: _LIBVP-BANK-BODY-INTEGRITY  ( -- status )
    LIB-BANK-HEADER-SIZE LIB-BANK-BODY-SIZE _LIBVP-CRC-RANGE
        DUP IF EXIT THEN DROP
    _LIBVP-BODY-CRC @ 0xFFFFFFFF AND
        _LIBVP-BANK-FACT LIBBF.BODY-CRC @ <> IF
        LIBSTORE-S-CORRUPT EXIT
    THEN
    LIB-BANK-HEADER-SIZE LIB-BANK-BODY-SIZE _LIBVP-BODY-SHA
        _LIBVP-HASH-RANGE DUP IF EXIT THEN DROP
    _LIBVP-BODY-SHA _LIBVP-BANK-FACT LIBBF.BODY-SHA
        SHA3-256-COMPARE 0= IF LIBSTORE-S-CORRUPT EXIT THEN
    LIBSTORE-S-OK ;

: _LIBVP-COMPLETE-BANK-INTEGRITY  ( -- status )
    0 LIB-BANK-SIZE _LIBVP-BANK-SHA _LIBVP-HASH-RANGE
        DUP IF EXIT THEN DROP
    _LIBVP-BANK-SHA _LIBVP-HEAD-FACT LIBHF.BANK-SHA
        SHA3-256-COMPARE 0= IF LIBSTORE-S-CORRUPT EXIT THEN
    LIBSTORE-S-OK ;

: _LIBVP-SELECTED-BANK$  ( -- path-a path-u )
    _LIBVP-HEAD-FACT LIBHF.BANK-SELECTOR @ IF
        _LIBVFS-BANK-B-PATH$
    ELSE
        _LIBVFS-BANK-A-PATH$
    THEN ;

: _LIBVP-ZERO?  ( address length -- flag )
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _LIBVP-NOTE-MUTATION  ( sequence -- )
    _LIBVP-MAX-MUTATION @ MAX _LIBVP-MAX-MUTATION ! ;

: _LIBVP-COPY-ENTRY-FACT  ( index -- )
    _LIBVP-INDEX !
    _LIBVP-INDEX @ _LIBVP-CATALOG-FACT DUP _LIBVP-FACT !
        _LIBVCF-SIZE 0 FILL
    _LIBVP-ENTRY LIBE.ID _LIBVP-FACT @ _LIBVCF.ID RID-COPY
    _LIBVP-ENTRY LIBE.RECEIPT LIBR.OPERATION-KEY
        _LIBVP-FACT @ _LIBVCF.OPERATION-KEY RID-COPY
    _LIBVP-ENTRY LIBE.DOMAIN-REVISION @
        _LIBVP-FACT @ _LIBVCF.DOMAIN-REVISION !
    _LIBVP-ENTRY LIBE.KIND @ _LIBVP-FACT @ _LIBVCF.KIND !
    _LIBVP-ENTRY LIBE.LIFECYCLE @ _LIBVP-FACT @ _LIBVCF.LIFECYCLE !
    _LIBVP-ENTRY LIBE.MEDIA @ _LIBVP-FACT @ _LIBVCF.MEDIA !
    _LIBVP-ENTRY LIBE.CURRENT-CONTENT-REVISION @
        _LIBVP-FACT @ _LIBVCF.CURRENT-REVISION !
    _LIBVP-ENTRY LIBE.OLDEST-CONTENT-REVISION @
        _LIBVP-FACT @ _LIBVCF.OLDEST-REVISION !
    _LIBVP-ENTRY LIBE.CONTENT-U @ _LIBVP-FACT @ _LIBVCF.CONTENT-U !
    _LIBVP-ENTRY LIBE.CONTENT-DIGEST
        _LIBVP-FACT @ _LIBVCF.CONTENT-DIGEST LIB-DIGEST-SIZE CMOVE
    _LIBVP-ENTRY LIBE.RECEIPT LIBR.INITIAL-MEDIA @
        _LIBVP-FACT @ _LIBVCF.INITIAL-MEDIA !
    _LIBVP-ENTRY LIBE.RECEIPT LIBR.INITIAL-CONTENT-REVISION @
        _LIBVP-FACT @ _LIBVCF.INITIAL-REVISION !
    _LIBVP-ENTRY LIBE.RECEIPT LIBR.INITIAL-CONTENT-U @
        _LIBVP-FACT @ _LIBVCF.INITIAL-U !
    _LIBVP-ENTRY LIBE.RECEIPT LIBR.INITIAL-CONTENT-DIGEST
        _LIBVP-FACT @ _LIBVCF.INITIAL-DIGEST LIB-DIGEST-SIZE CMOVE
    _LIBVP-ENTRY LIBE.MUTATION-SEQUENCE @ _LIBVP-NOTE-MUTATION ;

: _LIBVP-CATALOG-UNIQUE?  ( index -- flag )
    DUP _LIBVP-CATALOG-FACT _LIBVP-FACT !
    0 ?DO
        _LIBVP-FACT @ _LIBVCF.ID
            I _LIBVP-CATALOG-FACT _LIBVCF.ID RID= IF
            0 UNLOOP EXIT
        THEN
        _LIBVP-FACT @ _LIBVCF.ID
            I _LIBVP-CATALOG-FACT _LIBVCF.OPERATION-KEY RID= IF
            0 UNLOOP EXIT
        THEN
        _LIBVP-FACT @ _LIBVCF.OPERATION-KEY
            I _LIBVP-CATALOG-FACT _LIBVCF.OPERATION-KEY RID= IF
            0 UNLOOP EXIT
        THEN
        _LIBVP-FACT @ _LIBVCF.OPERATION-KEY
            I _LIBVP-CATALOG-FACT _LIBVCF.ID RID= IF
            0 UNLOOP EXIT
        THEN
    LOOP
    -1 ;

: _LIBVP-COPY-COLLECTION-FACT  ( index -- )
    _LIBVP-INDEX !
    _LIBVP-INDEX @ _LIBVP-COLLECTION-FACT DUP _LIBVP-FACT !
        _LIBVCCF-SIZE 0 FILL
    _LIBVP-COLLECTION LIBC.ID _LIBVP-FACT @ _LIBVCCF.ID RID-COPY
    _LIBVP-COLLECTION LIBC.OPERATION-KEY
        _LIBVP-FACT @ _LIBVCCF.OPERATION-KEY RID-COPY
    _LIBVP-COLLECTION LIBC.MUTATION-SEQUENCE @ _LIBVP-NOTE-MUTATION ;

: _LIBVP-COLLECTION-UNIQUE?  ( index -- flag )
    _LIBVP-INDEX !
    _LIBVP-INDEX @ _LIBVP-COLLECTION-FACT _LIBVP-FACT !
    _LIBVP-BANK-FACT LIBBF.CATALOG-COUNT @ 0 ?DO
        _LIBVP-FACT @ _LIBVCCF.ID
            I _LIBVP-CATALOG-FACT _LIBVCF.ID RID= IF
            0 UNLOOP EXIT
        THEN
        _LIBVP-FACT @ _LIBVCCF.ID
            I _LIBVP-CATALOG-FACT _LIBVCF.OPERATION-KEY RID= IF
            0 UNLOOP EXIT
        THEN
        _LIBVP-FACT @ _LIBVCCF.OPERATION-KEY
            I _LIBVP-CATALOG-FACT _LIBVCF.OPERATION-KEY RID= IF
            0 UNLOOP EXIT
        THEN
        _LIBVP-FACT @ _LIBVCCF.OPERATION-KEY
            I _LIBVP-CATALOG-FACT _LIBVCF.ID RID= IF
            0 UNLOOP EXIT
        THEN
    LOOP
    _LIBVP-INDEX @ 0 ?DO
        _LIBVP-FACT @ _LIBVCCF.ID
            I _LIBVP-COLLECTION-FACT _LIBVCCF.ID RID= IF
            0 UNLOOP EXIT
        THEN
        _LIBVP-FACT @ _LIBVCCF.ID
            I _LIBVP-COLLECTION-FACT _LIBVCCF.OPERATION-KEY RID= IF
            0 UNLOOP EXIT
        THEN
        _LIBVP-FACT @ _LIBVCCF.OPERATION-KEY
            I _LIBVP-COLLECTION-FACT _LIBVCCF.OPERATION-KEY RID= IF
            0 UNLOOP EXIT
        THEN
        _LIBVP-FACT @ _LIBVCCF.OPERATION-KEY
            I _LIBVP-COLLECTION-FACT _LIBVCCF.ID RID= IF
            0 UNLOOP EXIT
        THEN
    LOOP
    -1 ;

: _LIBVP-COLLECTION-BITS?  ( -- flag )
    LIB-CATALOG-MAX _LIBVP-BANK-FACT LIBBF.CATALOG-COUNT @ ?DO
        I _LIBVP-COLLECTION LIBC-MEMBER? IF 0 UNLOOP EXIT THEN
    LOOP
    -1 ;

: _LIBVP-SCAN-BANK-RECORDS  ( -- status )
    _LIBIX-CANDIDATE-CLEAR
    _LIBVP-CATALOG-FACTS LIB-CATALOG-MAX _LIBVCF-SIZE * 0 FILL
    _LIBVP-COLLECTION-FACTS LIB-COLLECTION-MAX _LIBVCCF-SIZE * 0 FILL
    _LIBAUTH-CATALOG-RECORD-SHA
        LIB-CATALOG-MAX LIB-DIGEST-SIZE * 0 FILL
    _LIBAUTH-COLLECTION-RECORD-SHA
        LIB-COLLECTION-MAX LIB-DIGEST-SIZE * 0 FILL
    0 _LIBVP-MAX-MUTATION !
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    LIB-BANK-CATALOG-OFFSET _LIBVP-FD @ _LIBVFS-SEEK
    LIB-CATALOG-MAX 0 ?DO
        _LIBVP-FRAME LIB-CATALOG-RECORD-SIZE
            _LIBVP-FD @ _LIBVFS-READ-EXACT IF
            LIBSTORE-S-IO UNLOOP EXIT
        THEN
        I _LIBVP-BANK-FACT LIBBF.CATALOG-COUNT @ < IF
            _LIBVP-FRAME LIB-CATALOG-RECORD-SIZE _LIBVP-ENTRY
                LIB-CATALOG-RECORD-DECODE
                _LIBVFS-FORMAT-READ>STATUS DUP IF UNLOOP EXIT THEN DROP
            _LIBVP-FRAME LIB-CATALOG-RECORD-SIZE
                I _LIBAUTH-CATALOG-SHA SHA3-256-HASH
            I _LIBVP-COPY-ENTRY-FACT
            I _LIBVP-CATALOG-UNIQUE? 0= IF
                LIBSTORE-S-CORRUPT UNLOOP EXIT
            THEN
            I _LIBIX-INDEX-ENTRY
        ELSE
            _LIBVP-FRAME LIB-CATALOG-RECORD-SIZE _LIBVP-ZERO? 0= IF
                LIBSTORE-S-CORRUPT UNLOOP EXIT
            THEN
        THEN
    LOOP
    LIB-COLLECTION-MAX 0 ?DO
        _LIBVP-FRAME LIB-COLLECTION-RECORD-SIZE
            _LIBVP-FD @ _LIBVFS-READ-EXACT IF
            LIBSTORE-S-IO UNLOOP EXIT
        THEN
        I _LIBVP-BANK-FACT LIBBF.COLLECTION-COUNT @ < IF
            _LIBVP-FRAME LIB-COLLECTION-RECORD-SIZE _LIBVP-COLLECTION
                LIB-COLLECTION-RECORD-DECODE
                _LIBVFS-FORMAT-READ>STATUS DUP IF UNLOOP EXIT THEN DROP
            _LIBVP-FRAME LIB-COLLECTION-RECORD-SIZE
                I _LIBAUTH-COLLECTION-SHA SHA3-256-HASH
            _LIBVP-COLLECTION-BITS? 0= IF
                LIBSTORE-S-CORRUPT UNLOOP EXIT
            THEN
            I _LIBVP-COPY-COLLECTION-FACT
            I _LIBVP-COLLECTION-UNIQUE? 0= IF
                LIBSTORE-S-CORRUPT UNLOOP EXIT
            THEN
        ELSE
            _LIBVP-FRAME LIB-COLLECTION-RECORD-SIZE _LIBVP-ZERO? 0= IF
                LIBSTORE-S-CORRUPT UNLOOP EXIT
            THEN
        THEN
    LOOP
    _LIBVP-MAX-MUTATION @
        _LIBVP-BANK-FACT LIBBF.MUTATION-SEQUENCE @ <> IF
        LIBSTORE-S-CORRUPT EXIT
    THEN
    _LIBVP-CLOSE-NOW ;

: _LIBVP-LOAD-SELECTED-BANK  ( -- status )
    _LIBVP-BANK-FACT LIB-BANK-FACT-INIT
    _LIBVP-SELECTED-BANK$ LIB-BANK-SIZE _LIBVP-OPEN-COMMITTED
        DUP IF EXIT THEN DROP
    \ The selected whole-bank seal is format-independent commit evidence.
    \ Check it before dispatching a future checksummed bank header.
    _LIBVP-COMPLETE-BANK-INTEGRITY DUP IF EXIT THEN DROP
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    0 _LIBVP-FD @ _LIBVFS-SEEK
    _LIBVP-SECTOR LIB-BANK-HEADER-SIZE
        _LIBVP-FD @ _LIBVFS-READ-EXACT IF LIBSTORE-S-IO EXIT THEN
    _LIBVP-SECTOR LIB-BANK-HEADER-SIZE _LIBVP-BANK-FACT
        LIB-BANK-HEADER-DECODE _LIBVFS-FORMAT-READ>STATUS
        DUP IF EXIT THEN DROP
    _LIBVP-HEAD-FACT _LIBVP-BANK-FACT LIB-HEAD-BANK-MATCH? 0= IF
        LIBSTORE-S-CORRUPT EXIT
    THEN
    _LIBVP-BANK-BODY-INTEGRITY DUP IF EXIT THEN DROP
    _LIBVP-SCAN-BANK-RECORDS ;

: _LIBVP-OPEN-VALIDATED-ARENA  ( -- status )
    _LIBVP-ARENA-FACT LIB-ARENA-FACT-INIT
    _LIBVFS-CONTENT-PATH$ LIB-ARENA-SIZE _LIBVP-OPEN-COMMITTED
        DUP IF EXIT THEN DROP
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    0 _LIBVP-FD @ _LIBVFS-SEEK
    _LIBVP-SECTOR LIB-ARENA-HEADER-SIZE
        _LIBVP-FD @ _LIBVFS-READ-EXACT IF LIBSTORE-S-IO EXIT THEN
    _LIBVP-SECTOR LIB-ARENA-HEADER-SIZE
        _LIBVP-HEAD-FACT LIBHF.ARENA-ID _LIBVP-ARENA-FACT
        LIB-ARENA-HEADER-DECODE _LIBVFS-FORMAT-READ>STATUS
        DUP IF EXIT THEN DROP
    _LIBVP-HEAD-FACT _LIBVP-ARENA-FACT LIB-HEAD-ARENA-MATCH? 0= IF
        LIBSTORE-S-CORRUPT EXIT
    THEN
    LIBSTORE-S-OK ;

: _LIBVP-FIND-CATALOG-FACT  ( id -- fact|0 )
    _LIBVP-ID !
    _LIBVP-BANK-FACT LIBBF.CATALOG-COUNT @ 0 ?DO
        _LIBVP-ID @ I _LIBVP-CATALOG-FACT _LIBVCF.ID RID= IF
            I _LIBVP-CATALOG-FACT UNLOOP EXIT
        THEN
    LOOP
    0 ;

: _LIBLOC-STAGE  ( -- status )
    _LIBVP-INDEX @ DUP 0<
    SWAP LIB-RETAINED-REVISION-MAX >= OR IF
        LIBSTORE-S-CORRUPT EXIT
    THEN
    _LIBVP-FACT @ _LIBVP-CATALOG-FACTS -
    DUP 0< IF DROP LIBSTORE-S-CORRUPT EXIT THEN
    DUP _LIBVCF-SIZE MOD IF DROP LIBSTORE-S-CORRUPT EXIT THEN
    _LIBVCF-SIZE / DUP _LIBVP-ENTRY-INDEX !
    DUP 0<
    SWAP _LIBVP-BANK-FACT LIBBF.CATALOG-COUNT @ >= OR IF
        LIBSTORE-S-CORRUPT EXIT
    THEN
    _LIBVP-FACT @ _LIBVP-ENTRY-INDEX @ _LIBVP-CATALOG-FACT <> IF
        LIBSTORE-S-CORRUPT EXIT
    THEN
    _LIBVP-ENTRY-INDEX @ _LIBVP-INDEX @ _LIBLOC-AT
        DUP _LIBVP-LOCATOR !
    DUP _LIBLOC.OFFSET @
    OVER _LIBLOC.FRAME-U @ OR IF DROP LIBSTORE-S-CORRUPT EXIT THEN
    DROP
    _LIBVP-OFFSET @ _LIBVP-LOCATOR @ _LIBLOC.OFFSET !
    _LIBVP-FRAME-U @ _LIBVP-LOCATOR @ _LIBLOC.FRAME-U !
    _LIBVP-FRAME-SHA _LIBVP-LOCATOR @ _LIBLOC.FRAME-SHA
        LIB-DIGEST-SIZE CMOVE
    LIBSTORE-S-OK ;

: _LIBVP-CONTENT-RELATION  ( -- status )
    _LIBVP-CONTENT LIBCT.ID _LIBVP-FIND-CATALOG-FACT
        DUP 0= IF DROP LIBSTORE-S-CORRUPT EXIT THEN
    _LIBVP-FACT !
    _LIBVP-CONTENT LIBCT.KIND @
        _LIBVP-FACT @ _LIBVCF.KIND @ <> IF
        LIBSTORE-S-CORRUPT EXIT
    THEN
    _LIBVP-CONTENT LIBCT.DOMAIN-REVISION @
        _LIBVP-FACT @ _LIBVCF.DOMAIN-REVISION @ > IF
        LIBSTORE-S-CORRUPT EXIT
    THEN
    \ Every RID's immutable frames are stored in strictly increasing
    \ content/domain revision order, including pruned and tombstoned
    \ history outside the retained window.
    _LIBVP-CONTENT LIBCT.CONTENT-REVISION @
        _LIBVP-FACT @ _LIBVCF.LAST-CONTENT-REVISION @ <= IF
        LIBSTORE-S-CORRUPT EXIT
    THEN
    _LIBVP-CONTENT LIBCT.DOMAIN-REVISION @
        _LIBVP-FACT @ _LIBVCF.LAST-DOMAIN-REVISION @ <= IF
        LIBSTORE-S-CORRUPT EXIT
    THEN
    _LIBVP-CONTENT LIBCT.CONTENT-REVISION @
        _LIBVP-FACT @ _LIBVCF.LAST-CONTENT-REVISION !
    _LIBVP-CONTENT LIBCT.DOMAIN-REVISION @
        _LIBVP-FACT @ _LIBVCF.LAST-DOMAIN-REVISION !
    \ The immutable import receipt remains authoritative even after its
    \ initial revision falls below the retained window or the entry is
    \ tombstoned.  Its frame is optional after pruning, but if present it
    \ must occur once and match the sealed initial length and digest.
    _LIBVP-CONTENT LIBCT.CONTENT-REVISION @
        _LIBVP-FACT @ _LIBVCF.INITIAL-REVISION @ = IF
        _LIBVP-CONTENT LIBCT.DATA-U @
            _LIBVP-FACT @ _LIBVCF.INITIAL-U @ <> IF
            LIBSTORE-S-CORRUPT EXIT
        THEN
        _LIBVP-CONTENT LIBCT.DIGEST
            _LIBVP-FACT @ _LIBVCF.INITIAL-DIGEST
            SHA3-256-COMPARE 0= IF LIBSTORE-S-CORRUPT EXIT THEN
    THEN
    _LIBVP-FACT @ _LIBVCF.LIFECYCLE @
        LIB-LIFECYCLE-TOMBSTONED = IF
        _LIBVP-CONTENT LIBCT.MEDIA @
            _LIBVP-FACT @ _LIBVCF.INITIAL-MEDIA @ =
        IF LIBSTORE-S-OK ELSE LIBSTORE-S-CORRUPT THEN
        EXIT
    THEN
    _LIBVP-CONTENT LIBCT.MEDIA @
        _LIBVP-FACT @ _LIBVCF.MEDIA @ <> IF
        LIBSTORE-S-CORRUPT EXIT
    THEN
    _LIBVP-CONTENT LIBCT.CONTENT-REVISION @
        _LIBVP-FACT @ _LIBVCF.CURRENT-REVISION @ > IF
        LIBSTORE-S-CORRUPT EXIT
    THEN
    _LIBVP-CONTENT LIBCT.CONTENT-REVISION @
        _LIBVP-FACT @ _LIBVCF.OLDEST-REVISION @ < IF
        LIBSTORE-S-OK EXIT
    THEN
    _LIBVP-CONTENT LIBCT.CONTENT-REVISION @
        _LIBVP-FACT @ _LIBVCF.OLDEST-REVISION @ - _LIBVP-INDEX !
    1 _LIBVP-INDEX @ LSHIFT _LIBVP-SEEN-MASK !
    _LIBVP-FACT @ _LIBVCF.SEEN @ _LIBVP-SEEN-MASK @ AND IF
        LIBSTORE-S-CORRUPT EXIT
    THEN
    _LIBVP-SEEN-MASK @ _LIBVP-FACT @ _LIBVCF.SEEN +!
    _LIBVP-CONTENT LIBCT.DOMAIN-REVISION @
        _LIBVP-INDEX @ _LIBVP-FACT @ _LIBVCF.REVISION-DOMAIN !
    _LIBLOC-STAGE DUP IF EXIT THEN DROP
    _LIBVP-CONTENT LIBCT.CONTENT-REVISION @
        _LIBVP-FACT @ _LIBVCF.CURRENT-REVISION @ = IF
        _LIBVP-CONTENT LIBCT.DATA-U @
            _LIBVP-FACT @ _LIBVCF.CONTENT-U @ <> IF
            LIBSTORE-S-CORRUPT EXIT
        THEN
        _LIBVP-CONTENT LIBCT.DIGEST
            _LIBVP-FACT @ _LIBVCF.CONTENT-DIGEST
            SHA3-256-COMPARE 0= IF LIBSTORE-S-CORRUPT EXIT THEN
        _LIBVP-FACT @ _LIBIX-INDEX-CURRENT-BODY
    THEN
    LIBSTORE-S-OK ;

: _LIBVP-RETAINED-WINDOWS?  ( -- flag )
    _LIBVP-BANK-FACT LIBBF.CATALOG-COUNT @
    DUP 0= IF DROP -1 EXIT THEN
    0 ?DO
        I _LIBVP-CATALOG-FACT _LIBVP-FACT !
        _LIBVP-FACT @ _LIBVCF.LIFECYCLE @
            LIB-LIFECYCLE-TOMBSTONED <> IF
            _LIBVP-FACT @ _LIBVCF.KIND @ LIB-KIND-CAPTURE = IF
                _LIBVP-FACT @ _LIBVCF.CURRENT-REVISION @ 1 <>
                _LIBVP-FACT @ _LIBVCF.OLDEST-REVISION @ 1 <> OR IF
                    0 UNLOOP EXIT
                THEN
            THEN
            _LIBVP-FACT @ _LIBVCF.CURRENT-REVISION @
                _LIBVP-FACT @ _LIBVCF.OLDEST-REVISION @ - 1+
                _LIBVP-J !
            1 _LIBVP-J @ LSHIFT 1- _LIBVP-SEEN-MASK !
            _LIBVP-FACT @ _LIBVCF.SEEN @ _LIBVP-SEEN-MASK @ <> IF
                0 UNLOOP EXIT
            THEN
            _LIBVP-J @ 1 > IF
                _LIBVP-J @ 1 DO
                    I _LIBVP-FACT @ _LIBVCF.REVISION-DOMAIN @
                    I 1- _LIBVP-FACT @ _LIBVCF.REVISION-DOMAIN @ <= IF
                        0 UNLOOP UNLOOP EXIT
                    THEN
                LOOP
            THEN
        THEN
    LOOP
    -1 ;

: _LIBVP-SCAN-CONTENT  ( -- status )
    _LIBLOC-TABLE _LIBLOC-BYTES 0 FILL
    _LIBVP-OPEN-VALIDATED-ARENA DUP IF EXIT THEN DROP
    _LIBVP-CHAIN LIB-CONTENT-CHAIN-GENESIS
        _LIBVFS-FORMAT>STATUS DUP IF EXIT THEN DROP
    LIB-ARENA-HEADER-SIZE _LIBVP-OFFSET !
    0 _LIBVP-CONTENT-N !
    BEGIN
        _LIBVP-OFFSET @
            _LIBVP-BANK-FACT LIBBF.CONTENT-TAIL @ <
    WHILE
        LIBSTORE-S-IO _LIBVP-THROW-STATUS !
        _LIBVP-OFFSET @ _LIBVP-FD @ _LIBVFS-SEEK
        _LIBVP-FRAME LIB-CONTENT-HEADER-SIZE
            _LIBVP-FD @ _LIBVFS-READ-EXACT IF LIBSTORE-S-IO EXIT THEN
        _LIBVP-FRAME LIB-CONTENT-HEADER-SIZE
            LIB-CONTENT-RECORD-MEASURE
        DUP LIB-S-OK <> IF
            _LIBVFS-FORMAT-READ>STATUS >R DROP R> EXIT
        THEN
        DROP _LIBVP-RECORD-U !
        _LIBVP-RECORD-U @ LIB-CONTENT-FRAME-SIZE
            DUP -1 = IF DROP LIBSTORE-S-CORRUPT EXIT THEN
            _LIBVP-FRAME-U !
        _LIBVP-OFFSET @
            _LIBVP-BANK-FACT LIBBF.CONTENT-TAIL @
            _LIBVP-FRAME-U @ - > IF
            LIBSTORE-S-CORRUPT EXIT
        THEN
        _LIBVP-FRAME LIB-CONTENT-HEADER-SIZE +
            _LIBVP-FRAME-U @ LIB-CONTENT-HEADER-SIZE -
            _LIBVP-FD @ _LIBVFS-READ-EXACT IF LIBSTORE-S-IO EXIT THEN
        _LIBVP-FRAME _LIBVP-RECORD-U @ +
            _LIBVP-FRAME-U @ _LIBVP-RECORD-U @ -
            _LIBVP-ZERO? 0= IF LIBSTORE-S-CORRUPT EXIT THEN
        _LIBVP-FRAME _LIBVP-RECORD-U @ _LIBVP-CONTENT
            LIB-CONTENT-RECORD-DECODE _LIBVFS-FORMAT-READ>STATUS
            DUP IF EXIT THEN DROP
        _LIBVP-FRAME _LIBVP-FRAME-U @ _LIBVP-FRAME-SHA
            LIB-CONTENT-FRAME-DIGEST _LIBVFS-FORMAT>STATUS
            DUP IF EXIT THEN DROP
        _LIBVP-CHAIN _LIBVP-OFFSET @ _LIBVP-FRAME-U @
            _LIBVP-FRAME-SHA _LIBVP-CHAIN-NEXT
            LIB-CONTENT-CHAIN-STEP _LIBVFS-FORMAT>STATUS
            DUP IF EXIT THEN DROP
        _LIBVP-CHAIN-NEXT _LIBVP-CHAIN LIB-DIGEST-SIZE CMOVE
        _LIBVP-CONTENT-RELATION DUP IF EXIT THEN DROP
        _LIBVP-FRAME-U @ _LIBVP-OFFSET +!
        1 _LIBVP-CONTENT-N +!
    REPEAT
    _LIBVP-OFFSET @ _LIBVP-BANK-FACT LIBBF.CONTENT-TAIL @ <> IF
        LIBSTORE-S-CORRUPT EXIT
    THEN
    _LIBVP-CONTENT-N @
        _LIBVP-BANK-FACT LIBBF.CONTENT-RECORD-COUNT @ <> IF
        LIBSTORE-S-CORRUPT EXIT
    THEN
    _LIBVP-CHAIN _LIBVP-BANK-FACT LIBBF.CONTENT-CHAIN
        SHA3-256-COMPARE 0= IF LIBSTORE-S-CORRUPT EXIT THEN
    _LIBVP-RETAINED-WINDOWS? 0= IF LIBSTORE-S-CORRUPT EXIT THEN
    _LIBVP-CLOSE-NOW ;

: _LIBVP-FULL-LOAD-BODY  ( -- status )
    1 _LIBPQ-FULL-VALIDATION-N +!
    _LIBVP-LOAD-SELECTED-BANK DUP IF EXIT THEN DROP
    _LIBVP-SCAN-CONTENT ;

: _LIBVP-NOTE-TARGET  ( path-a path-u -- status )
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    VFS-T-FILE _LIBVP-VFS @ _LIBVFS-NAMESPACE-TYPE
    DUP LIBSTORE-S-ABSENT = IF DROP LIBSTORE-S-OK EXIT THEN
    DUP LIBSTORE-S-CORRUPT = IF DROP LIBSTORE-S-RECOVERY EXIT THEN
    DUP IF EXIT THEN DROP
    1 _LIBVP-PRESENT-N +!
    LIBSTORE-S-OK ;

: _LIBVP-HEADLESS-LOAD-BODY  ( -- status )
    0 _LIBVP-PRESENT-N !
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    _LIBVP-VFS @ _LIBVFS-DIRECTORY-NAMESPACE
    DUP LIBSTORE-S-ABSENT = IF DROP ELSE
        DUP LIBSTORE-S-CORRUPT = IF DROP LIBSTORE-S-RECOVERY EXIT THEN
        DUP IF EXIT THEN DROP
    THEN
    _LIBVFS-BANK-A-PATH$ _LIBVP-NOTE-TARGET DUP IF EXIT THEN DROP
    _LIBVFS-BANK-B-PATH$ _LIBVP-NOTE-TARGET DUP IF EXIT THEN DROP
    _LIBVFS-CONTENT-PATH$ _LIBVP-NOTE-TARGET DUP IF EXIT THEN DROP
    _LIBVP-PRESENT-N @ IF LIBSTORE-S-RECOVERY ELSE LIBSTORE-S-ABSENT THEN ;

: _LIBVP-READ-ZERO-REMAINDER  ( exact-length -- status )
    _LIBVP-REMAINING !
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    BEGIN _LIBVP-REMAINING @ 0> WHILE
        _LIBVP-REMAINING @ _LIBVP-ZERO-BLOCK-SIZE MIN _LIBVP-CHUNK !
        _LIBVP-ZERO-BLOCK _LIBVP-CHUNK @
            _LIBVP-FD @ _LIBVFS-READ-EXACT IF
            LIBSTORE-S-IO EXIT
        THEN
        _LIBVP-ZERO-BLOCK _LIBVP-CHUNK @ _LIBVP-ZERO? 0= IF
            LIBSTORE-S-RECOVERY EXIT
        THEN
        _LIBVP-CHUNK @ NEGATE _LIBVP-REMAINING +!
    REPEAT
    LIBSTORE-S-OK ;

: _LIBVP-OPEN-PRISTINE  ( path-a path-u exact-length -- status )
    _LIBVP-OPEN-EXACT
    DUP LIBSTORE-S-OK = IF EXIT THEN
    DUP LIBSTORE-S-IO = IF EXIT THEN
    DROP LIBSTORE-S-RECOVERY ;

: _LIBVP-VERIFY-ZERO-BANK  ( path-a path-u -- status )
    LIB-BANK-SIZE _LIBVP-OPEN-PRISTINE DUP IF EXIT THEN DROP
    LIB-BANK-SIZE _LIBVP-READ-ZERO-REMAINDER DUP IF EXIT THEN DROP
    _LIBVP-CLOSE-NOW ;

: _LIBVP-VERIFY-PRISTINE-ARENA  ( -- status )
    _LIBVFS-CONTENT-PATH$ LIB-ARENA-SIZE _LIBVP-OPEN-PRISTINE
        DUP IF EXIT THEN DROP
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    _LIBVP-SECTOR LIB-ARENA-HEADER-SIZE
        _LIBVP-FD @ _LIBVFS-READ-EXACT IF LIBSTORE-S-IO EXIT THEN
    LIBSTORE-S-RECOVERY _LIBVP-THROW-STATUS !
    _LIBVP-SECTOR LIB-ARENA-HEADER-SIZE _LIBVP-ARENA-ID
        LIB-ARENA-HEADER-VALIDATE
    DUP LIB-S-INTEGRITY = IF DROP LIBSTORE-S-CONFLICT EXIT THEN
    DUP LIB-S-UNSUPPORTED = IF DROP LIBSTORE-S-UNSUPPORTED EXIT THEN
    LIB-S-OK <> IF LIBSTORE-S-RECOVERY EXIT THEN
    _LIBVP-SECTOR LIB-ARENA-HEADER-SIZE _LIBVP-ARENA-ID
        _LIBVP-ARENA-FACT
        LIB-ARENA-HEADER-DECODE LIB-S-OK <> IF
        LIBSTORE-S-RECOVERY EXIT
    THEN
    LIB-ARENA-SIZE LIB-ARENA-HEADER-SIZE -
        _LIBVP-READ-ZERO-REMAINDER DUP IF EXIT THEN DROP
    _LIBVP-CLOSE-NOW ;

: _LIBVP-CLASSIFY-HEADLESS  ( -- status )
    0 _LIBVP-PRESENT-N !
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    _LIBVP-VFS @ _LIBVFS-DIRECTORY-NAMESPACE
    DUP LIBSTORE-S-ABSENT = IF DROP ELSE
        DUP LIBSTORE-S-CORRUPT = IF DROP LIBSTORE-S-RECOVERY EXIT THEN
        DUP IF EXIT THEN DROP
    THEN
    _LIBVFS-BANK-A-PATH$ _LIBVP-NOTE-TARGET DUP IF EXIT THEN DROP
    _LIBVFS-BANK-B-PATH$ _LIBVP-NOTE-TARGET DUP IF EXIT THEN DROP
    _LIBVFS-CONTENT-PATH$ _LIBVP-NOTE-TARGET DUP IF EXIT THEN DROP
    _LIBVP-PRESENT-N @ DUP 0= IF DROP LIBSTORE-S-OK EXIT THEN
    3 <> IF LIBSTORE-S-RECOVERY EXIT THEN
    \ A successful barrier plus cold-style readback makes a prior exact
    \ preparation safely resumable without rewriting any evidence.
    _LIBVP-SYNC DUP IF EXIT THEN DROP
    _LIBVFS-BANK-A-PATH$ _LIBVP-VERIFY-ZERO-BANK DUP IF EXIT THEN DROP
    _LIBVFS-BANK-B-PATH$ _LIBVP-VERIFY-ZERO-BANK DUP IF EXIT THEN DROP
    _LIBVP-VERIFY-PRISTINE-ARENA ;

: _LIBVP-WRITE-SECTOR-AT-ZERO  ( -- status )
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    0 _LIBVP-FD @ _LIBVFS-SEEK
    _LIBVP-SECTOR LIB-STORE-SECTOR-SIZE
        _LIBVP-FD @ _LIBVFS-WRITE-EXACT IF
        LIBSTORE-S-IO EXIT
    THEN
    _LIBVP-CLOSE-NOW DUP IF EXIT THEN DROP
    _LIBVP-SYNC ;

: _LIBVP-READ-SECTOR-AT-ZERO  ( -- status )
    _LIBVP-SECTOR LIB-STORE-SECTOR-SIZE 0 FILL
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    0 _LIBVP-FD @ _LIBVFS-SEEK
    _LIBVP-SECTOR LIB-STORE-SECTOR-SIZE
        _LIBVP-FD @ _LIBVFS-READ-EXACT IF
        LIBSTORE-S-IO EXIT
    THEN
    _LIBVP-CLOSE-NOW ;

: _LIBVP-BUILD-ARENA-HEADER  ( -- status )
    _LIBVP-ARENA-FACT LIB-ARENA-FACT-INIT
    _LIBVP-ARENA-ID
        _LIBVP-ARENA-FACT LIBAF.ARENA-ID
        LIB-DIGEST-SIZE CMOVE
    _LIBVP-ARENA-FACT
        _LIBVP-SECTOR LIB-STORE-SECTOR-SIZE LIB-ARENA-HEADER-ENCODE
    DUP IF NIP _LIBVFS-FORMAT>STATUS EXIT THEN DROP
    LIB-ARENA-HEADER-SIZE = IF LIBSTORE-S-OK ELSE LIBSTORE-S-RECOVERY THEN ;

: _LIBVP-VALIDATE-ARENA-READBACK  ( -- status )
    _LIBVP-SECTOR LIB-ARENA-HEADER-SIZE _LIBVP-ARENA-ID
        LIB-ARENA-HEADER-VALIDATE _LIBVFS-FORMAT-READ>STATUS ;

: _LIBVP-COMPUTE-ZERO-BODY  ( -- status )
    _LIBVP-ZERO-BLOCK _LIBVP-ZERO-BLOCK-SIZE 0 FILL
    LIB-BANK-BODY-SIZE _LIBVP-REMAINING !
    _LIBVP-CRC-BEGIN
    BEGIN _LIBVP-REMAINING @ 0> WHILE
        _LIBVP-REMAINING @ _LIBVP-ZERO-BLOCK-SIZE MIN _LIBVP-CHUNK !
        _LIBVP-ZERO-BLOCK _LIBVP-CHUNK @ CRC32-ADD
        _LIBVP-CHUNK @ NEGATE _LIBVP-REMAINING +!
    REPEAT
    _LIBVP-CRC-END-NOW DUP IF EXIT THEN DROP
    _LIBVP-BODY-CRC @ 0xFFFFFFFF AND _LIBVP-BODY-CRC !
    LIB-BANK-BODY-SIZE _LIBVP-REMAINING !
    _LIBVP-SHA-BEGIN
    BEGIN _LIBVP-REMAINING @ 0> WHILE
        _LIBVP-REMAINING @ _LIBVP-ZERO-BLOCK-SIZE MIN _LIBVP-CHUNK !
        _LIBVP-ZERO-BLOCK _LIBVP-CHUNK @ SHA3-256-ADD
        _LIBVP-CHUNK @ NEGATE _LIBVP-REMAINING +!
    REPEAT
    _LIBVP-BODY-SHA _LIBVP-SHA-END-NOW ;

: _LIBVP-BUILD-EMPTY-BANK-HEADER  ( -- status )
    _LIBVP-BANK-FACT LIB-BANK-FACT-INIT
    1 _LIBVP-BANK-FACT LIBBF.GENERATION !
    _LIBVP-ARENA-ID _LIBVP-BANK-FACT LIBBF.ARENA-ID
        LIB-DIGEST-SIZE CMOVE
    LIB-ARENA-HEADER-SIZE _LIBVP-BANK-FACT LIBBF.CONTENT-TAIL !
    _LIBVP-BANK-FACT LIBBF.CONTENT-CHAIN
        LIB-CONTENT-CHAIN-GENESIS _LIBVFS-FORMAT>STATUS
        DUP IF EXIT THEN DROP
    _LIBVP-COMPUTE-ZERO-BODY DUP IF EXIT THEN DROP
    _LIBVP-BODY-CRC @ _LIBVP-BANK-FACT LIBBF.BODY-CRC !
    _LIBVP-BODY-SHA _LIBVP-BANK-FACT LIBBF.BODY-SHA
        LIB-DIGEST-SIZE CMOVE
    _LIBVP-BANK-FACT _LIBVP-SECTOR LIB-BANK-HEADER-SIZE
        LIB-BANK-HEADER-ENCODE
    DUP IF NIP _LIBVFS-FORMAT>STATUS EXIT THEN
    DROP LIB-BANK-HEADER-SIZE = IF
        LIBSTORE-S-OK
    ELSE
        LIBSTORE-S-RECOVERY
    THEN ;

: _LIBVP-VERIFY-BOOTSTRAP-BANK  ( -- status )
    _LIBVFS-BANK-A-PATH$ LIB-BANK-SIZE _LIBVP-OPEN-COMMITTED
        DUP IF EXIT THEN DROP
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    0 _LIBVP-FD @ _LIBVFS-SEEK
    _LIBVP-SECTOR LIB-BANK-HEADER-SIZE
        _LIBVP-FD @ _LIBVFS-READ-EXACT IF LIBSTORE-S-IO EXIT THEN
    _LIBVP-SECTOR LIB-BANK-HEADER-SIZE _LIBVP-BANK-FACT
        LIB-BANK-HEADER-DECODE _LIBVFS-FORMAT-READ>STATUS
        DUP IF EXIT THEN DROP
    _LIBVP-BANK-FACT LIBBF.GENERATION @ 1 <>
    _LIBVP-BANK-FACT LIBBF.CATALOG-COUNT @ 0<> OR
    _LIBVP-BANK-FACT LIBBF.COLLECTION-COUNT @ 0<> OR
    _LIBVP-BANK-FACT LIBBF.MUTATION-SEQUENCE @ 0<> OR
    _LIBVP-BANK-FACT LIBBF.CONTENT-TAIL @ LIB-ARENA-HEADER-SIZE <> OR
    _LIBVP-BANK-FACT LIBBF.CONTENT-RECORD-COUNT @ 0<> OR IF
        LIBSTORE-S-CORRUPT EXIT
    THEN
    _LIBVP-BANK-FACT LIBBF.ARENA-ID _LIBVP-ARENA-ID
        SHA3-256-COMPARE 0= IF LIBSTORE-S-CORRUPT EXIT THEN
    _LIBVP-CHAIN LIB-CONTENT-CHAIN-GENESIS
        _LIBVFS-FORMAT>STATUS DUP IF EXIT THEN DROP
    _LIBVP-BANK-FACT LIBBF.CONTENT-CHAIN _LIBVP-CHAIN
        SHA3-256-COMPARE 0= IF LIBSTORE-S-CORRUPT EXIT THEN
    _LIBVP-COMPUTE-ZERO-BODY DUP IF EXIT THEN DROP
    _LIBVP-BANK-FACT LIBBF.BODY-CRC @
        _LIBVP-BODY-CRC @ <> IF LIBSTORE-S-CORRUPT EXIT THEN
    _LIBVP-BANK-FACT LIBBF.BODY-SHA _LIBVP-BODY-SHA
        SHA3-256-COMPARE 0= IF LIBSTORE-S-CORRUPT EXIT THEN
    _LIBVP-BANK-BODY-INTEGRITY DUP IF EXIT THEN DROP
    0 LIB-BANK-SIZE _LIBVP-BANK-SHA _LIBVP-HASH-RANGE
        DUP IF EXIT THEN DROP
    _LIBVP-SCAN-BANK-RECORDS ;

: _LIBVP-BUILD-EMPTY-HEAD  ( -- status )
    _LIBVP-HEAD-FACT LIB-HEAD-FACT-INIT
    1 _LIBVP-HEAD-FACT LIBHF.GENERATION !
    0 _LIBVP-HEAD-FACT LIBHF.BANK-SELECTOR !
    1 _LIBVP-HEAD-FACT LIBHF.BANK-GENERATION !
    _LIBVP-BANK-SHA _LIBVP-HEAD-FACT LIBHF.BANK-SHA
        LIB-DIGEST-SIZE CMOVE
    _LIBVP-ARENA-ID _LIBVP-HEAD-FACT LIBHF.ARENA-ID
        LIB-DIGEST-SIZE CMOVE
    LIB-ARENA-HEADER-SIZE _LIBVP-HEAD-FACT LIBHF.CONTENT-TAIL !
    _LIBVP-CHAIN _LIBVP-HEAD-FACT LIBHF.CONTENT-CHAIN
        LIB-DIGEST-SIZE CMOVE
    _LIBVP-HEAD-FACT LIB-HEAD-FACT-VALID? IF
        1 _LIBVP-CANDIDATE-GENERATION !
        LIBSTORE-S-OK
    ELSE
        LIBSTORE-S-RECOVERY
    THEN ;

: _LIBVP-BOOTSTRAP-EMPTY-BANK  ( -- status )
    _LIBVP-BUILD-EMPTY-BANK-HEADER DUP IF EXIT THEN DROP
    _LIBVFS-BANK-A-PATH$ LIB-BANK-SIZE _LIBVP-OPEN-EXACT
        DUP IF EXIT THEN DROP
    _LIBVP-WRITE-SECTOR-AT-ZERO DUP IF EXIT THEN DROP
    _LIBVP-VERIFY-BOOTSTRAP-BANK DUP IF EXIT THEN DROP
    _LIBVP-BUILD-EMPTY-HEAD ;

: _LIBVP-PROVISION-BODY  ( -- status )
    _LIBVP-CLASSIFY-HEADLESS DUP IF EXIT THEN DROP
    _LIBVP-PRESENT-N @ 0= IF
        _LIBVP-ENSURE-DIRECTORY DUP IF EXIT THEN DROP
        _LIBVFS-BANK-A-PATH$ LIB-BANK-SIZE _LIBVP-ZERO-FILE
            DUP IF EXIT THEN DROP
        _LIBVFS-BANK-B-PATH$ LIB-BANK-SIZE _LIBVP-ZERO-FILE
            DUP IF EXIT THEN DROP
        _LIBVFS-CONTENT-PATH$ LIB-ARENA-SIZE _LIBVP-ZERO-FILE
            DUP IF EXIT THEN DROP
        _LIBVP-BUILD-ARENA-HEADER DUP IF EXIT THEN DROP
        _LIBVFS-CONTENT-PATH$ LIB-ARENA-SIZE _LIBVP-OPEN-EXACT
            DUP IF EXIT THEN DROP
        _LIBVP-WRITE-SECTOR-AT-ZERO DUP IF EXIT THEN DROP
        \ Fresh creation must pass the same full cold readback as resume.
        _LIBVP-CLASSIFY-HEADLESS DUP IF EXIT THEN DROP
        _LIBVP-PRESENT-N @ 3 <> IF LIBSTORE-S-RECOVERY EXIT THEN
    THEN
    _LIBVP-BOOTSTRAP-EMPTY-BANK ;

: _LIBVP-TRANSACTION-BODY  ( -- status )
    0 _LIBVP-FD !
    0 _LIBMU-SOURCE-FD !
    0 _LIBVP-SHA-ACTIVE !
    0 _LIBVP-CRC-ACTIVE !
    0 _LIBVP-HAVE-OLD-VFS !
    0 _LIBVP-HAVE-OLD-CWD !
    0 _LIBVP-CLEANUP-EVIDENCE !
    LIBSTORE-S-IO _LIBVP-STATUS !
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    ['] _LIBVP-SELECT CATCH IF
        _LIBVP-THROW-STATUS @ _LIBVP-STATUS !
    ELSE
        _LIBVP-BODY-XT @ CATCH IF
            _LIBVP-THROW-STATUS @ _LIBVP-STATUS !
        ELSE
            _LIBVP-STATUS !
        THEN
    THEN
    _LIBVP-CLEANUP IF
        _LIBVP-STATUS @ LIBSTORE-S-OK = IF
            LIBSTORE-S-IO _LIBVP-STATUS !
        THEN
    THEN
    _LIBVP-STATUS @ ;

: _LIBVP-TRANSACTION-CALL  ( -- status )
    ['] _LIBVP-TRANSACTION-BODY VFS-TRANSACTION ;

: _LIBVP-RUN  ( body-xt -- status )
    _LIBVP-BODY-XT !
    0 _LIBVP-FD !
    0 _LIBMU-SOURCE-FD !
    0 _LIBVP-SHA-ACTIVE !
    0 _LIBVP-CRC-ACTIVE !
    0 _LIBVP-HAVE-OLD-VFS !
    0 _LIBVP-HAVE-OLD-CWD !
    0 _LIBVP-CLEANUP-EVIDENCE !
    ['] _LIBVP-TRANSACTION-CALL CATCH ?DUP IF
        DROP _LIBVP-CLEANUP DROP LIBSTORE-S-IO
    THEN ;

\ =====================================================================
\  Read-only maintenance inspection and coherent opaque export
\ =====================================================================

: _LIBMA-PART$  ( object-id -- path-a path-u )
    CASE
        LIBRARY-EVIDENCE-HEAD OF _LIBVFS-HEAD-PATH$ ENDOF
        LIBRARY-EVIDENCE-HEAD-STAGE OF _LIBVFS-HEAD-STAGE-PATH$ ENDOF
        LIBRARY-EVIDENCE-HEAD-BACKUP OF _LIBVFS-HEAD-BACKUP-PATH$ ENDOF
        LIBRARY-EVIDENCE-HEAD-MARKER OF _LIBVFS-HEAD-MARKER-PATH$ ENDOF
        LIBRARY-EVIDENCE-BANK-A OF _LIBVFS-BANK-A-PATH$ ENDOF
        LIBRARY-EVIDENCE-BANK-B OF _LIBVFS-BANK-B-PATH$ ENDOF
        LIBRARY-EVIDENCE-CONTENT OF _LIBVFS-CONTENT-PATH$ ENDOF
    ENDCASE ;

: _LIBMA-OBJECT  ( object-id -- object )
    _LIBMA-REPORT @ LIBINS-OBJECT ;

: _LIBMA-STATE!  ( state -- )
    _LIBMA-COMPONENT @ LIBEO.STATE ! ;

: _LIBMA-FLAG+  ( flag -- )
    _LIBMA-COMPONENT @ LIBEO.FLAGS DUP @ ROT OR SWAP ! ;

: _LIBMA-OPEN-PART  ( object-id -- status )
    _LIBMA-PART !
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    LIBSTORE-S-ABSENT _LIBVP-DIRECTORY-PREFLIGHT
    DUP IF EXIT THEN DROP
    _LIBMA-PART @ _LIBMA-PART$ VFS-T-FILE _LIBVP-VFS @
        _LIBVFS-NAMESPACE-TYPE
    DUP LIBSTORE-S-ABSENT = IF EXIT THEN
    DUP LIBSTORE-S-CORRUPT = IF DROP LIBSTORE-S-RECOVERY EXIT THEN
    DUP IF EXIT THEN DROP
    _LIBMA-PART @ _LIBMA-PART$ _LIBVFS-OPEN DUP 0= IF
        DROP LIBSTORE-S-IO EXIT
    THEN
    DUP _LIBVP-FD ! _LIBVFS-SIZE DUP 0< IF
        DROP LIBSTORE-S-IO EXIT
    THEN
    _LIBMA-FILE-U !
    LIBSTORE-S-OK ;

: _LIBMA-READ-AT  ( destination length offset -- status )
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    _LIBVP-FD @ _LIBVFS-SEEK
    _LIBVP-FD @ _LIBVFS-READ-EXACT IF
        LIBSTORE-S-IO
    ELSE
        LIBSTORE-S-OK
    THEN ;

: _LIBMA-CORRUPT  ( -- status )
    LIBRARY-EVIDENCE-S-CORRUPT _LIBMA-STATE!
    LIBRARY-EVIDENCE-F-OPAQUE _LIBMA-FLAG+
    LIBSTORE-S-OK ;

: _LIBMA-FUTURE  ( -- status )
    LIBRARY-EVIDENCE-S-FUTURE _LIBMA-STATE!
    LIBRARY-EVIDENCE-F-OPAQUE _LIBMA-FLAG+
    LIBSTORE-S-OK ;

: _LIBMA-RECOGNIZED  ( -- status )
    LIBRARY-EVIDENCE-S-RECOGNIZED _LIBMA-STATE!
    LIBSTORE-S-OK ;

: _LIBMA-CLASSIFY-HEAD  ( -- status )
    _LIBMA-FILE-U @ CREC-HEADER-SIZE < IF _LIBMA-CORRUPT EXIT THEN
    _LIBVP-SECTOR CREC-HEADER-SIZE 0 _LIBMA-READ-AT
        DUP IF EXIT THEN DROP
    _LIBVP-SECTOR CREC-HEADER-SIZE _LIBMA-HEAD-CREC-SPEC
        _LIBMA-HEAD-CREC-WORK CREC-INSPECT-HEADER
    DUP CREC-S-UNSUPPORTED = IF
        DROP _LIBVP-SECTOR CREC-H-FORMAT + @
        _LIBMA-COMPONENT @ LIBEO.ENVELOPE-FORMAT !
        _LIBMA-FUTURE EXIT
    THEN
    DUP CREC-S-OK <> IF DROP _LIBMA-CORRUPT EXIT THEN DROP
    _LIBVP-SECTOR CREC-H-FORMAT + @
        _LIBMA-COMPONENT @ LIBEO.ENVELOPE-FORMAT !
    _LIBMA-HEAD-CREC-WORK CREC-TAG@
        _LIBMA-COMPONENT @ LIBEO.GENERATION !
    _LIBMA-FILE-U @ _LIBMA-HEAD-CREC-WORK CREC-RECORD-U@ <> IF
        _LIBMA-CORRUPT EXIT
    THEN
    _LIBVP-FRAME _LIBMA-FILE-U @ 0 _LIBMA-READ-AT
        DUP IF EXIT THEN DROP
    0 0 _LIBVP-FRAME _LIBMA-FILE-U @ _LIBMA-HEAD-CREC-SPEC
        _LIBMA-HEAD-CREC-WORK CREC-VALIDATE
    DUP CREC-S-UNSUPPORTED = IF
        DROP _LIBVP-FRAME CREC-HEADER-SIZE + _LIBSH-FORMAT + @
        _LIBMA-COMPONENT @ LIBEO.STORE-FORMAT !
        _LIBMA-FUTURE EXIT
    THEN
    DUP CREC-S-OK <> IF DROP _LIBMA-CORRUPT EXIT THEN DROP
    LIB-STORE-FORMAT-V1 _LIBMA-COMPONENT @ LIBEO.STORE-FORMAT !
    _LIBMA-RECOGNIZED ;

: _LIBMA-CLASSIFY-BANK  ( -- status )
    _LIBMA-FILE-U @ LIB-BANK-HEADER-SIZE < IF _LIBMA-CORRUPT EXIT THEN
    _LIBVP-SECTOR LIB-BANK-HEADER-SIZE 0 _LIBMA-READ-AT
        DUP IF EXIT THEN DROP
    _LIBVP-SECTOR LIB-BANK-HEADER-SIZE LIB-BANK-HEADER-VALIDATE
    DUP LIB-S-UNSUPPORTED = IF
        DROP _LIBVP-SECTOR _LIBSB-FORMAT + @
        _LIBMA-COMPONENT @ LIBEO.STORE-FORMAT !
        _LIBMA-FUTURE EXIT
    THEN
    DUP LIB-S-OK <> IF DROP _LIBMA-CORRUPT EXIT THEN DROP
    _LIBMA-FILE-U @ LIB-BANK-SIZE <> IF _LIBMA-CORRUPT EXIT THEN
    LIB-STORE-FORMAT-V1 _LIBMA-COMPONENT @ LIBEO.STORE-FORMAT !
    _LIBVP-SECTOR _LIBSB-GENERATION + @
        _LIBMA-COMPONENT @ LIBEO.GENERATION !
    _LIBMA-RECOGNIZED ;

: _LIBMA-CLASSIFY-CONTENT  ( -- status )
    _LIBMA-FILE-U @ LIB-ARENA-HEADER-SIZE < IF _LIBMA-CORRUPT EXIT THEN
    _LIBVP-SECTOR LIB-ARENA-HEADER-SIZE 0 _LIBMA-READ-AT
        DUP IF EXIT THEN DROP
    _LIBVP-SECTOR _LIBSA-ARENA-ID + _LIBVP-ARENA-ID
        LIB-DIGEST-SIZE CMOVE
    _LIBVP-ARENA-ID LIB-DIGEST-SIZE _LIBVP-ZERO? IF
        1 _LIBVP-ARENA-ID C!
    THEN
    _LIBVP-SECTOR LIB-ARENA-HEADER-SIZE _LIBVP-ARENA-ID
        LIB-ARENA-HEADER-VALIDATE
    DUP LIB-S-UNSUPPORTED = IF
        DROP _LIBVP-SECTOR _LIBSA-FORMAT + @
        _LIBMA-COMPONENT @ LIBEO.STORE-FORMAT !
        _LIBMA-FUTURE EXIT
    THEN
    DUP LIB-S-OK <> IF DROP _LIBMA-CORRUPT EXIT THEN DROP
    _LIBMA-FILE-U @ LIB-ARENA-SIZE <> IF _LIBMA-CORRUPT EXIT THEN
    LIB-STORE-FORMAT-V1 _LIBMA-COMPONENT @ LIBEO.STORE-FORMAT !
    _LIBMA-RECOGNIZED ;

: _LIBMA-CLASSIFY-MARKER  ( -- status )
    _LIBMA-FILE-U @ _VREPL-MARKER-SIZE <> IF _LIBMA-CORRUPT EXIT THEN
    _LIBVP-SECTOR _VREPL-MARKER-SIZE 0 _LIBMA-READ-AT
        DUP IF EXIT THEN DROP
    _LIBVP-SECTOR _VR-M-MAGIC + 8
        _VREPL-MARKER-MAGIC 8 COMPARE IF _LIBMA-CORRUPT EXIT THEN
    _LIBVP-SECTOR _VR-M-RECORD-CRC CRC32
        _LIBVP-SECTOR _VR-M-RECORD-CRC + @ <> IF
        _LIBMA-CORRUPT EXIT
    THEN
    _LIBVP-SECTOR _VR-M-FORMAT + @ DUP
        _LIBMA-COMPONENT @ LIBEO.ENVELOPE-FORMAT !
    DUP _VREPL-MARKER-FORMAT <> IF
        DUP _VREPL-MARKER-FORMAT > IF
            DROP _LIBMA-FUTURE
        ELSE
            DROP _LIBMA-CORRUPT
        THEN
        EXIT
    THEN DROP
    _LIBVP-SECTOR _VR-M-FLAGS + @
        _VREPL-MF-ORIGINAL INVERT AND IF _LIBMA-CORRUPT EXIT THEN
    _LIBVP-SECTOR _VR-M-DATA-LEN + @ 0< IF _LIBMA-CORRUPT EXIT THEN
    _LIBVFS-HEAD-PATH$ _LIBMA-TARGET-HASH SHA3-256-HASH
    _LIBMA-TARGET-HASH _VREPL-MARKER-TARGET-HASH-SIZE
        _LIBVP-SECTOR _VR-M-TARGET-HASH +
        _VREPL-MARKER-TARGET-HASH-SIZE COMPARE IF
        _LIBMA-CORRUPT EXIT
    THEN
    _LIBVP-SECTOR _VR-M-FLAGS + @ _VREPL-MF-ORIGINAL AND 0<>
        _LIBMA-MARKER-ORIGINAL !
    _LIBMA-RECOGNIZED ;

: _LIBMA-CLASSIFY-CURRENT  ( -- status )
    _LIBMA-PART @ CASE
        LIBRARY-EVIDENCE-HEAD OF _LIBMA-CLASSIFY-HEAD ENDOF
        LIBRARY-EVIDENCE-HEAD-STAGE OF _LIBMA-CLASSIFY-HEAD ENDOF
        LIBRARY-EVIDENCE-HEAD-BACKUP OF _LIBMA-CLASSIFY-HEAD ENDOF
        LIBRARY-EVIDENCE-HEAD-MARKER OF _LIBMA-CLASSIFY-MARKER ENDOF
        LIBRARY-EVIDENCE-BANK-A OF _LIBMA-CLASSIFY-BANK ENDOF
        LIBRARY-EVIDENCE-BANK-B OF _LIBMA-CLASSIFY-BANK ENDOF
        LIBRARY-EVIDENCE-CONTENT OF _LIBMA-CLASSIFY-CONTENT ENDOF
    ENDCASE ;

: _LIBMA-INSPECT-PART  ( object-id -- status )
    DUP _LIBMA-PART ! _LIBMA-OBJECT DUP _LIBMA-COMPONENT !
        LIBRARY-EVIDENCE-OBJECT-SIZE 0 FILL
    LIBRARY-EVIDENCE-S-ABSENT _LIBMA-COMPONENT @ LIBEO.STATE !
    _LIBMA-RAW-TOTAL @ _LIBMA-COMPONENT @ LIBEO.RAW-OFFSET !
    _LIBMA-PART @ _LIBMA-OPEN-PART
    DUP LIBSTORE-S-ABSENT = IF DROP LIBSTORE-S-OK EXIT THEN
    DUP LIBSTORE-S-RECOVERY = IF
        DROP LIBRARY-EVIDENCE-F-PRESENT _LIBMA-FLAG+
        LIBRARY-EVIDENCE-F-OPAQUE _LIBMA-FLAG+
        LIBRARY-EVIDENCE-S-RECOVERY _LIBMA-STATE!
        LIBSTORE-S-OK EXIT
    THEN
    DUP IF EXIT THEN DROP
    LIBRARY-EVIDENCE-F-PRESENT _LIBMA-FLAG+
    _LIBMA-FILE-U @ _LIBMA-COMPONENT @ LIBEO.RAW-U !
    _LIBMA-FILE-U @
        LIBRARY-RAW-EXPORT-MAX _LIBMA-RAW-TOTAL @ - > IF
        _LIBVP-CLOSE-NOW DROP LIBSTORE-S-OUTPUT-CAPACITY EXIT
    THEN
    _LIBMA-FILE-U @ _LIBMA-RAW-TOTAL +!
    0 _LIBMA-FILE-U @ _LIBMA-COMPONENT @ LIBEO.SHA
        _LIBVP-HASH-RANGE DUP IF
        _LIBVP-CLOSE-NOW DROP EXIT
    THEN DROP
    _LIBMA-CLASSIFY-CURRENT DUP _LIBMA-CALL-STATUS ! DROP
    _LIBVP-CLOSE-NOW DUP IF
        DROP LIBSTORE-S-IO EXIT
    THEN DROP
    _LIBMA-CALL-STATUS @ ;

: _LIBMA-SAVE-ACTIVATION  ( -- )
    _LIBIX-READY @ _LIBMA-INDEX-READY-SAVE !
    _LIBIX-STORE @ _LIBMA-INDEX-STORE-SAVE !
    _LIBIX-GENERATION @ _LIBMA-INDEX-GENERATION-SAVE !
    _LIBIX-CATALOG-N @ _LIBMA-INDEX-CATALOG-N-SAVE !
    _LIBIX-AUTH-CRC @ _LIBMA-INDEX-AUTH-CRC-SAVE !
    _LIBIX-CRC @ _LIBMA-INDEX-CRC-SAVE !
    _LIBIX-CANDIDATE _LIBMA-INDEX-BACKUP _LIBIX-BYTES CMOVE
    _LIBVP-CATALOG-FACTS _LIBMA-CATALOG-FACTS-BACKUP
        LIB-CATALOG-MAX _LIBVCF-SIZE * CMOVE
    _LIBVP-COLLECTION-FACTS _LIBMA-COLLECTION-FACTS-BACKUP
        LIB-COLLECTION-MAX _LIBVCCF-SIZE * CMOVE
    _LIBAUTH-CATALOG-RECORD-SHA _LIBMA-CATALOG-SHA-BACKUP
        LIB-CATALOG-MAX LIB-DIGEST-SIZE * CMOVE
    _LIBAUTH-COLLECTION-RECORD-SHA _LIBMA-COLLECTION-SHA-BACKUP
        LIB-COLLECTION-MAX LIB-DIGEST-SIZE * CMOVE
    _LIBLOC-TABLE _LIBMA-LOCATOR-BACKUP _LIBLOC-BYTES CMOVE ;

: _LIBMA-RESTORE-ACTIVATION  ( -- )
    _LIBMA-INDEX-BACKUP _LIBIX-CANDIDATE _LIBIX-BYTES CMOVE
    _LIBMA-CATALOG-FACTS-BACKUP _LIBVP-CATALOG-FACTS
        LIB-CATALOG-MAX _LIBVCF-SIZE * CMOVE
    _LIBMA-COLLECTION-FACTS-BACKUP _LIBVP-COLLECTION-FACTS
        LIB-COLLECTION-MAX _LIBVCCF-SIZE * CMOVE
    _LIBMA-CATALOG-SHA-BACKUP _LIBAUTH-CATALOG-RECORD-SHA
        LIB-CATALOG-MAX LIB-DIGEST-SIZE * CMOVE
    _LIBMA-COLLECTION-SHA-BACKUP _LIBAUTH-COLLECTION-RECORD-SHA
        LIB-COLLECTION-MAX LIB-DIGEST-SIZE * CMOVE
    _LIBMA-LOCATOR-BACKUP _LIBLOC-TABLE _LIBLOC-BYTES CMOVE
    _LIBMA-INDEX-READY-SAVE @ _LIBIX-READY !
    _LIBMA-INDEX-STORE-SAVE @ _LIBIX-STORE !
    _LIBMA-INDEX-GENERATION-SAVE @ _LIBIX-GENERATION !
    _LIBMA-INDEX-CATALOG-N-SAVE @ _LIBIX-CATALOG-N !
    _LIBMA-INDEX-AUTH-CRC-SAVE @ _LIBIX-AUTH-CRC !
    _LIBMA-INDEX-CRC-SAVE @ _LIBIX-CRC ! ;

: _LIBMA-LOAD-CANDIDATE-HEAD  ( object-id -- status )
    DUP _LIBMA-PART ! _LIBMA-OPEN-PART DUP IF EXIT THEN DROP
    _LIBMA-FILE-U @ CREC-HEADER-SIZE LIB-HEAD-PAYLOAD-SIZE + <> IF
        LIBSTORE-S-CORRUPT EXIT
    THEN
    _LIBVP-FRAME CREC-HEADER-SIZE LIB-HEAD-PAYLOAD-SIZE + 0
        _LIBMA-READ-AT DUP IF EXIT THEN DROP
    _LIBVP-CLOSE-NOW DUP IF EXIT THEN DROP
    0 0 _LIBVP-FRAME _LIBMA-FILE-U @ _LIBMA-HEAD-CREC-SPEC
        _LIBMA-HEAD-CREC-WORK CREC-VALIDATE
    DUP CREC-S-UNSUPPORTED = IF DROP LIBSTORE-S-UNSUPPORTED EXIT THEN
    DUP CREC-S-OK <> IF DROP LIBSTORE-S-CORRUPT EXIT THEN DROP
    _LIBVP-HEAD-FACT LIB-HEAD-FACT-INIT
    _LIBMA-HEAD-CREC-WORK CREC-PAYLOAD$
    _LIBMA-HEAD-CREC-WORK CREC-TAG@ _LIBVP-HEAD-FACT
        LIB-HEAD-PAYLOAD-DECODE _LIBVFS-FORMAT-READ>STATUS ;

: _LIBMA-PUBLISH-SEMANTICS  ( -- )
    LIBRARY-INSPECTION-F-RECOGNIZED-V1
        _LIBMA-REPORT @ LIBINS.FLAGS !
    _LIBVP-HEAD-FACT LIBHF.GENERATION @
        _LIBMA-REPORT @ LIBINS.HEAD-GENERATION !
    _LIBVP-HEAD-FACT LIBHF.BANK-SELECTOR @
        DUP _LIBMA-REPORT @ LIBINS.SELECTED-BANK !
    IF LIBRARY-EVIDENCE-BANK-B ELSE LIBRARY-EVIDENCE-BANK-A THEN
        _LIBMA-OBJECT
        LIBRARY-EVIDENCE-F-SELECTED LIBRARY-EVIDENCE-F-COMMITTED OR
        SWAP LIBEO.FLAGS DUP @ ROT OR SWAP !
    _LIBVP-BANK-FACT LIBBF.CATALOG-COUNT @
        _LIBMA-REPORT @ LIBINS.CATALOG-COUNT !
    _LIBVP-BANK-FACT LIBBF.COLLECTION-COUNT @
        _LIBMA-REPORT @ LIBINS.COLLECTION-COUNT !
    _LIBVP-BANK-FACT LIBBF.MUTATION-SEQUENCE @
        _LIBMA-REPORT @ LIBINS.MUTATION-SEQUENCE !
    _LIBVP-BANK-FACT LIBBF.CONTENT-TAIL @
        _LIBMA-REPORT @ LIBINS.CONTENT-TAIL !
    _LIBVP-BANK-FACT LIBBF.CONTENT-RECORD-COUNT @
        _LIBMA-REPORT @ LIBINS.CONTENT-RECORD-COUNT !
    LIBRARY-EVIDENCE-F-COMMITTED
        LIBRARY-EVIDENCE-CONTENT _LIBMA-OBJECT
        LIBEO.FLAGS DUP @ ROT OR SWAP !
    LIBRARY-EVIDENCE-F-COMMITTED
        _LIBMA-CANDIDATE-PART @ _LIBMA-OBJECT
        LIBEO.FLAGS DUP @ ROT OR SWAP ! ;

: _LIBMA-PROBE-CANDIDATE-BODY  ( -- status )
    _LIBMA-CANDIDATE-PART @ _LIBMA-LOAD-CANDIDATE-HEAD
        _LIBMA-PROBE-STATUS !
    _LIBMA-PROBE-STATUS @ IF
        _LIBVP-CLOSE-NOW DROP
        _LIBMA-PROBE-STATUS @ EXIT
    THEN
    _LIBVP-FULL-LOAD-BODY DUP _LIBMA-PROBE-STATUS ! DROP
    _LIBVP-CLOSE-NOW DUP IF
        DROP
        _LIBMA-PROBE-STATUS @ LIBSTORE-S-OK = IF
            LIBSTORE-S-IO _LIBMA-PROBE-STATUS !
        THEN
    ELSE
        DROP
    THEN
    _LIBMA-PROBE-STATUS @ LIBSTORE-S-OK = IF
        _LIBMA-PUBLISH-SEMANTICS
    THEN
    _LIBMA-PROBE-STATUS @ ;

: _LIBMA-PROBE-CANDIDATE  ( -- status )
    _LIBMA-SAVE-ACTIVATION
    ['] _LIBMA-PROBE-CANDIDATE-BODY CATCH
    _LIBMA-RESTORE-ACTIVATION
    DUP IF THROW THEN DROP ;

: _LIBMA-PRESENT?  ( object-id -- flag )
    _LIBMA-OBJECT LIBEO.FLAGS @ LIBRARY-EVIDENCE-F-PRESENT AND 0<> ;

: _LIBMA-RECOGNIZED?  ( object-id -- flag )
    _LIBMA-OBJECT LIBEO.STATE @ LIBRARY-EVIDENCE-S-RECOGNIZED = ;

: _LIBMA-HEAD-ARTIFACTS-RECOGNIZED?  ( -- flag )
    LIBRARY-EVIDENCE-HEAD DUP _LIBMA-PRESENT? IF
        _LIBMA-RECOGNIZED? 0= IF 0 EXIT THEN
    ELSE DROP THEN
    LIBRARY-EVIDENCE-HEAD-STAGE DUP _LIBMA-PRESENT? IF
        _LIBMA-RECOGNIZED? 0= IF 0 EXIT THEN
    ELSE DROP THEN
    LIBRARY-EVIDENCE-HEAD-BACKUP DUP _LIBMA-PRESENT? IF
        _LIBMA-RECOGNIZED? 0= IF 0 EXIT THEN
    ELSE DROP THEN
    LIBRARY-EVIDENCE-HEAD-MARKER DUP _LIBMA-PRESENT? IF
        _LIBMA-RECOGNIZED? 0= IF 0 EXIT THEN
    ELSE DROP THEN
    -1 ;

: _LIBMA-ANY-PRESENT?  ( -- flag )
    LIBRARY-EVIDENCE-OBJECT-N 0 DO
        I _LIBMA-PRESENT? IF -1 UNLOOP EXIT THEN
    LOOP
    0 ;

: _LIBMA-PLAN  ( -- )
    -1 _LIBMA-CANDIDATE-PART !
    0 _LIBMA-REPAIRABLE !
    LIBRARY-EVIDENCE-HEAD-STAGE _LIBMA-PRESENT?
    LIBRARY-EVIDENCE-HEAD-BACKUP _LIBMA-PRESENT? OR
    LIBRARY-EVIDENCE-HEAD-MARKER _LIBMA-PRESENT? OR
        _LIBMA-RESIDUE !
    LIBRARY-EVIDENCE-HEAD-MARKER _LIBMA-PRESENT? IF
        LIBRARY-EVIDENCE-HEAD-MARKER _LIBMA-RECOGNIZED?
        _LIBMA-MARKER-ORIGINAL @ AND IF
            LIBRARY-EVIDENCE-HEAD-BACKUP _LIBMA-RECOGNIZED? IF
                LIBRARY-EVIDENCE-HEAD-BACKUP _LIBMA-CANDIDATE-PART !
            ELSE
                LIBRARY-EVIDENCE-HEAD _LIBMA-RECOGNIZED?
                LIBRARY-EVIDENCE-HEAD-STAGE _LIBMA-RECOGNIZED? AND IF
                    LIBRARY-EVIDENCE-HEAD _LIBMA-CANDIDATE-PART !
                THEN
            THEN
        THEN
    ELSE
        LIBRARY-EVIDENCE-HEAD _LIBMA-RECOGNIZED? IF
            LIBRARY-EVIDENCE-HEAD _LIBMA-CANDIDATE-PART !
        ELSE
            LIBRARY-EVIDENCE-HEAD _LIBMA-PRESENT? 0=
            LIBRARY-EVIDENCE-HEAD-BACKUP _LIBMA-RECOGNIZED? AND IF
                LIBRARY-EVIDENCE-HEAD-BACKUP _LIBMA-CANDIDATE-PART !
            THEN
        THEN
    THEN
    _LIBMA-RESIDUE @
    _LIBMA-CANDIDATE-PART @ 0>= AND
    _LIBMA-HEAD-ARTIFACTS-RECOGNIZED? AND IF
        \ A marker can roll back only an original target.  Without a marker,
        \ target-wins cleanup or exact backup restoration is deterministic.
        LIBRARY-EVIDENCE-HEAD-MARKER _LIBMA-PRESENT? IF
            _LIBMA-MARKER-ORIGINAL @ IF -1 _LIBMA-REPAIRABLE ! THEN
        ELSE
            -1 _LIBMA-REPAIRABLE !
        THEN
    THEN ;

: _LIBMA-SEAL  ( inspection destination -- )
    >R SHA3-256-BEGIN
    S" org.akashic.library.raw-evidence.v1" SHA3-256-ADD
    LIBRARY-EVIDENCE-OBJECT-N 0 DO
        I _LIBMA-CELL ! _LIBMA-CELL 8 SHA3-256-ADD
        I OVER LIBINS-OBJECT DUP LIBEO.STATE 8 SHA3-256-ADD
        DUP LIBEO.RAW-U 8 SHA3-256-ADD
        LIBEO.SHA LIB-DIGEST-SIZE SHA3-256-ADD
    LOOP
    DROP R> SHA3-256-END ;

: _LIBMA-BUILD-REPAIRED-SEAL  ( -- )
    _LIBMA-REPAIRABLE @ _LIBMA-PROBE-STATUS @ LIBSTORE-S-OK = AND IF
        _LIBMA-REPORT @ _LIBMA-REPORT-B LIBRARY-INSPECTION-SIZE CMOVE
        _LIBMA-CANDIDATE-PART @ _LIBMA-REPORT @ LIBINS-OBJECT
        LIBRARY-EVIDENCE-HEAD _LIBMA-REPORT-B LIBINS-OBJECT
        LIBRARY-EVIDENCE-OBJECT-SIZE CMOVE
        LIBRARY-EVIDENCE-HEAD-STAGE _LIBMA-REPORT-B LIBINS-OBJECT
            LIBRARY-EVIDENCE-OBJECT-SIZE 0 FILL
        LIBRARY-EVIDENCE-HEAD-BACKUP _LIBMA-REPORT-B LIBINS-OBJECT
            LIBRARY-EVIDENCE-OBJECT-SIZE 0 FILL
        LIBRARY-EVIDENCE-HEAD-MARKER _LIBMA-REPORT-B LIBINS-OBJECT
            LIBRARY-EVIDENCE-OBJECT-SIZE 0 FILL
        _LIBMA-REPORT-B _LIBMA-REPORT @ LIBINS.REPAIRED-SEAL _LIBMA-SEAL
    THEN
    ;

: _LIBMA-HEALTH-WITHOUT-CANDIDATE  ( -- health )
    LIBRARY-EVIDENCE-HEAD _LIBMA-OBJECT LIBEO.STATE @ CASE
        LIBRARY-EVIDENCE-S-ABSENT OF
            _LIBMA-ANY-PRESENT? IF
                LIBSTORE-S-RECOVERY
            ELSE
                LIBSTORE-S-ABSENT
            THEN
        ENDOF
        LIBRARY-EVIDENCE-S-FUTURE OF LIBSTORE-S-UNSUPPORTED ENDOF
        LIBRARY-EVIDENCE-S-CORRUPT OF LIBSTORE-S-CORRUPT ENDOF
        LIBRARY-EVIDENCE-S-RECOVERY OF LIBSTORE-S-RECOVERY ENDOF
        LIBSTORE-S-RECOVERY SWAP
    ENDCASE ;

: _LIBMA-INSPECT-BODY  ( -- status )
    _LIBMA-REPORT @ LIBRARY-INSPECTION-SIZE 0 FILL
    0 _LIBMA-RAW-TOTAL !
    0 _LIBMA-MARKER-ORIGINAL !
    LIBSTORE-S-OK _LIBMA-PROBE-STATUS !
    LIBRARY-EVIDENCE-OBJECT-N 0 DO
        I _LIBMA-INSPECT-PART DUP IF UNLOOP EXIT THEN DROP
    LOOP
    _LIBMA-RAW-TOTAL @ _LIBMA-REPORT @ LIBINS.RAW-REQUIRED !
    _LIBMA-PLAN
    _LIBMA-CANDIDATE-PART @ 0>= IF
        _LIBMA-PROBE-CANDIDATE DUP _LIBMA-PROBE-STATUS !
        DUP LIBSTORE-S-IO = IF EXIT THEN
        DUP LIBSTORE-S-OK = IF
            DROP
            _LIBMA-RESIDUE @ IF
                LIBSTORE-S-RECOVERY
                _LIBMA-REPAIRABLE @ IF
                    LIBRARY-REPAIR-F-HEAD-TRANSACTION
                        _LIBMA-REPORT @ LIBINS.REPAIR-MASK !
                THEN
            ELSE
                LIBSTORE-S-OK
            THEN
        THEN
        _LIBMA-REPORT @ LIBINS.HEALTH !
    ELSE
        _LIBMA-HEALTH-WITHOUT-CANDIDATE
            _LIBMA-REPORT @ LIBINS.HEALTH !
    THEN
    _LIBMA-REPORT @ _LIBMA-REPORT @ LIBINS.EVIDENCE-SEAL _LIBMA-SEAL
    _LIBMA-BUILD-REPAIRED-SEAL
    LIBSTORE-S-OK ;

: _LIBMA-INSPECT-INTO  ( inspection store -- call-status )
    _LIBMA-STORE ! _LIBMA-REPORT !
    _LIBMA-STORE @ _LIBVP-STORE !
    _LIBMA-STORE @ LIBRARY-VFS-STORE.VFS @ _LIBVP-VFS !
    ['] _LIBMA-INSPECT-BODY _LIBVP-RUN
    DUP IF _LIBMA-REPORT @ LIBRARY-INSPECTION-SIZE 0 FILL THEN ;

: _LIBMA-COPY-OBJECT  ( object-id -- status )
    DUP _LIBMA-PART ! _LIBMA-REPORT @ LIBINS-OBJECT _LIBMA-COMPONENT !
    _LIBMA-COMPONENT @ LIBEO.RAW-U @ 0= IF
        LIBSTORE-S-OK EXIT
    THEN
    _LIBMA-PART @ _LIBMA-OPEN-PART DUP IF EXIT THEN DROP
    _LIBMA-FILE-U @ _LIBMA-COMPONENT @ LIBEO.RAW-U @ <> IF
        LIBSTORE-S-CONFLICT EXIT
    THEN
    _LIBMA-EXPORT-A @ _LIBMA-COMPONENT @ LIBEO.RAW-OFFSET @ +
    _LIBMA-COMPONENT @ LIBEO.RAW-U @ 0 _LIBMA-READ-AT
    DUP _LIBMA-CALL-STATUS ! DROP
    _LIBVP-CLOSE-NOW DUP IF DROP LIBSTORE-S-IO EXIT THEN DROP
    _LIBMA-CALL-STATUS @ DUP IF EXIT THEN DROP
    _LIBMA-EXPORT-A @ _LIBMA-COMPONENT @ LIBEO.RAW-OFFSET @ +
        _LIBMA-COMPONENT @ LIBEO.RAW-U @ _LIBMA-TARGET-HASH
        SHA3-256-HASH
    _LIBMA-TARGET-HASH _LIBMA-COMPONENT @ LIBEO.SHA
        SHA3-256-COMPARE 0= IF LIBSTORE-S-CONFLICT EXIT THEN
    LIBSTORE-S-OK ;

: _LIBMA-EXPORT-BODY  ( -- status )
    _LIBMA-REPORT-A _LIBMA-REPORT !
    _LIBMA-INSPECT-BODY DUP IF EXIT THEN DROP
    _LIBMA-REPORT-A LIBINS.RAW-REQUIRED @
        DUP _LIBMA-EXPORT-REQUIRED ! DROP
    _LIBMA-EXPECTED-REPORT @ LIBINS.EVIDENCE-SEAL
        _LIBMA-REPORT-A LIBINS.EVIDENCE-SEAL
        SHA3-256-COMPARE 0= IF LIBSTORE-S-CONFLICT EXIT THEN
    _LIBMA-REPORT-A LIBINS.RAW-REQUIRED @
        _LIBMA-EXPORT-CAP @ > IF LIBSTORE-S-OUTPUT-CAPACITY EXIT THEN
    -1 _LIBMA-EXPORT-STARTED !
    LIBRARY-EVIDENCE-OBJECT-N 0 DO
        I _LIBMA-COPY-OBJECT DUP IF UNLOOP EXIT THEN DROP
    LOOP
    LIBSTORE-S-OK ;

\ =====================================================================
\  Typed lifecycle and absent-store provisioning
\ =====================================================================

: _LIBVFS-ARENA-ID-SAFE?  ( arena-id store -- flag )
    >R
    DUP LIB-DIGEST-SIZE _VFSNAP-SPAN-VALID? 0= IF
        DROP R> DROP 0 EXIT
    THEN
    DUP RID-PRESENT? 0= IF DROP R> DROP 0 EXIT THEN
    DUP LIB-DIGEST-SIZE R@ LIBRARY-VFS-STORE-SIZE
        _VFSNAP-RANGES-OVERLAP? IF DROP R> DROP 0 EXIT THEN
    DUP LIB-DIGEST-SIZE _LIBVFS-PRIVATE-ALIASES? IF
        DROP R> DROP 0 EXIT
    THEN
    DROP R> DROP -1 ;

: _LIBRARY-VFS-STORE-INIT  ( vfs store -- status )
    _LIBVI-STORE ! _LIBVI-VFS !
    _LIBAUTH-CLEAR
    _LIBIX-CANDIDATE-CLEAR
    _LIBVI-STORE @ LIBRARY-VFS-STORE-SIZE 0 FILL
    _LIBVFS-STORE-MAGIC _LIBVI-STORE @ LIBRARY-VFS-STORE.MAGIC !
    _LIBVI-VFS @ _LIBVI-STORE @ LIBRARY-VFS-STORE.VFS !
    LIBSTORE-S-ABSENT _LIBVI-STORE @ LIBRARY-VFS-STORE.LAST-STATUS !
    VFSNAP-S-ABSENT _LIBVI-STORE @ LIBRARY-VFS-STORE.LAST-VFSNAP !
    VREPL-S-OK _LIBVI-STORE @ LIBRARY-VFS-STORE.LAST-VREPL !
    _LIBVFS-HEAD-PATH$
        _LIBVI-STORE @ _LIBVFS-SNAPSHOT-SCRATCH
        VFSNAP-HEADER-SIZE LIB-HEAD-PAYLOAD-SIZE +
        _LIBVI-VFS @ _LIBVFS-HEAD-SPEC
        _LIBVI-STORE @ _LIBRARY-VFS-STORE.CORE
        VFSNAP-INIT-AT
        _LIBVI-STORE @ _LIBVFS-ADAPT ;

' _LIBRARY-VFS-STORE-INIT CONSTANT _libvfs-init-xt
: LIBRARY-VFS-STORE-INIT  ( vfs store -- status )
    DUP _LIBVFS-STORE-SPAN-SAFE? 0= IF
        2DROP LIBSTORE-S-INVALID EXIT
    THEN
    OVER VFS-DESC-SIZE _VFSNAP-SPAN-VALID? 0= IF
        2DROP LIBSTORE-S-INVALID EXIT
    THEN
    OVER VFS-DESC-SIZE _LIBVFS-PRIVATE-ALIASES? IF
        2DROP LIBSTORE-S-INVALID EXIT
    THEN
    OVER VFS-DESC-SIZE 2 PICK LIBRARY-VFS-STORE-SIZE
        _VFSNAP-RANGES-OVERLAP? IF
        2DROP LIBSTORE-S-INVALID EXIT
    THEN
    _libvfs-init-xt _library-vfs-store-guard WITH-GUARD ;

: _LIBVR-RECOVER-CALL  ( -- status )
    _LIBVR-STORE @ _LIBRARY-VFS-STORE.CORE VFSNAP-BLOCKED? 0= IF
        _LIBVR-STORE @ LIBRARY-VFS-STORE.VFS @
            _LIBVFS-HEAD-NAMESPACE-PREFLIGHT
        DUP LIBSTORE-S-ABSENT = IF
            DROP VFSNAP-S-OK _LIBVR-STORE @ _LIBVFS-ADAPT EXIT
        THEN
        DUP IF _LIBVR-STORE @ _LIBVFS-RESULT EXIT THEN DROP
    THEN
    _LIBVR-STORE @ DUP >R
        _LIBRARY-VFS-STORE.CORE VFSNAP-RECOVER R> _LIBVFS-ADAPT ;

: _LIBRARY-VFS-STORE-RECOVER  ( store -- status )
    DUP LIBRARY-VFS-STORE-VALID? 0= IF DROP LIBSTORE-S-INVALID EXIT THEN
    _LIBVR-STORE !
    _LIBVR-RECOVER-CALL ;

: _LIBVL-LOAD-HEAD-CALL  ( -- status )
    _LIBVL-STORE @ _LIBRARY-VFS-STORE.CORE VFSNAP-BLOCKED? 0= IF
        _LIBVL-STORE @ LIBRARY-VFS-STORE.VFS @
            _LIBVFS-HEAD-NAMESPACE-PREFLIGHT
        DUP LIBSTORE-S-ABSENT = IF
            DROP VFSNAP-S-ABSENT _LIBVL-STORE @ _LIBVFS-ADAPT EXIT
        THEN
        DUP IF _LIBVL-STORE @ _LIBVFS-RESULT EXIT THEN DROP
    THEN
    _LIBVL-STORE @ _LIBVFS-HEAD-PAYLOAD LIB-HEAD-PAYLOAD-SIZE
        _LIBVL-STORE @ _LIBVFS-CANDIDATE-GENERATION
        _LIBVL-STORE @ _LIBRARY-VFS-STORE.CORE VFSNAP-LOAD
        DUP _LIBVL-SNAPSHOT-STATUS !
        _LIBVL-STORE @ _LIBVFS-CANDIDATE-GENERATION @
            _LIBVP-CANDIDATE-GENERATION !
        0 _LIBVL-STORE @ _LIBVFS-CANDIDATE-GENERATION !
        _LIBVL-STORE @ _LIBVFS-ADAPT ;

: _LIBRARY-VFS-STORE-LOAD-HEAD  ( store -- status )
    DUP LIBRARY-VFS-STORE-VALID? 0= IF DROP LIBSTORE-S-INVALID EXIT THEN
    _LIBVL-STORE !
    _LIBVL-STORE @ _LIBVFS-HEAD-PAYLOAD LIB-HEAD-PAYLOAD-SIZE 0 FILL
    0 _LIBVP-CANDIDATE-GENERATION !
    0 _LIBVL-STORE @ _LIBVFS-CANDIDATE-GENERATION !
    _LIBVP-HEAD-FACT LIB-HEAD-FACT-INIT
    _LIBVL-LOAD-HEAD-CALL DUP _LIBVL-STATUS ! DROP
    _LIBVL-STATUS @ LIBSTORE-S-OK <> IF _LIBVL-STATUS @ EXIT THEN
    _LIBVL-STORE @ _LIBVFS-HEAD-PAYLOAD LIB-HEAD-PAYLOAD-SIZE
        _LIBVP-CANDIDATE-GENERATION @
        _LIBVP-HEAD-FACT LIB-HEAD-PAYLOAD-DECODE
        _LIBVFS-FORMAT-READ>STATUS
        _LIBVL-STORE @ _LIBVFS-RESULT ;

: _LIBVP-FINISH-CORPUS-RUN  ( status -- status )
    DUP LIBSTORE-S-OK = IF
        _LIBVP-STORE @ _LIBVFS-PUBLISH-CANDIDATES
        _LIBVP-STORE @ _LIBAUTH-PUBLISH
        _LIBVP-STORE @ _LIBIX-PUBLISH
        _LIBVP-STORE @ _LIBVFS-CLEAR-CORPUS-BLOCK
    ELSE
        DUP _LIBVFS-CORPUS-BLOCKING? IF
            _LIBVP-STORE @ LIBRARY-VFS-STORE.FLAGS DUP @
                _LIBVFS-F-BLOCKED OR SWAP !
        THEN
    THEN
    _LIBVP-STORE @ _LIBVP-RESULT ;

: _LIBRARY-VFS-STORE-LOAD  ( store -- status )
    DUP LIBRARY-VFS-STORE-VALID? 0= IF DROP LIBSTORE-S-INVALID EXIT THEN
    DUP _LIBVP-STORE !
    _LIBAUTH-INVALIDATE
    _LIBIX-INVALIDATE
    DUP _LIBVFS-CLEAR-PUBLISHED
    DUP _LIBRARY-VFS-STORE-RECOVER DUP IF
        SWAP _LIBVFS-CORPUS-RESULT EXIT
    THEN
    DROP
    DUP _LIBRARY-VFS-STORE-LOAD-HEAD
    DUP LIBSTORE-S-ABSENT = IF
        DROP
        DUP LIBRARY-VFS-STORE.VFS @ _LIBVP-VFS !
        DROP ['] _LIBVP-HEADLESS-LOAD-BODY _LIBVP-RUN
            _LIBVP-FINISH-CORPUS-RUN EXIT
    THEN
    DUP IF SWAP _LIBVFS-CORPUS-RESULT EXIT THEN
    DROP
    DUP LIBRARY-VFS-STORE.VFS @ _LIBVP-VFS !
    DROP ['] _LIBVP-FULL-LOAD-BODY _LIBVP-RUN
        _LIBVP-FINISH-CORPUS-RUN ;

' _LIBRARY-VFS-STORE-LOAD CONSTANT _libvfs-load-xt
: LIBRARY-VFS-STORE-LOAD  ( store -- status )
    DUP _LIBVFS-STORE-SPAN-SAFE? 0= IF DROP LIBSTORE-S-INVALID EXIT THEN
    _libvfs-load-xt _library-vfs-store-guard WITH-GUARD ;

\ Private commit-point primitive.  The later publication slice calls this
\ only after content and the complete inactive bank have passed readback.
: _LIBVS-SAVE-HEAD-CALL  ( -- status )
    _LIBVS-STORE @ LIBRARY-VFS-STORE.VFS @
        _LIBVFS-HEAD-NAMESPACE-PREFLIGHT
    DUP LIBSTORE-S-ABSENT = IF DROP ELSE
        DUP IF _LIBVS-STORE @ _LIBVFS-CORPUS-RESULT EXIT THEN DROP
    THEN
    _LIBVS-HEAD-FACT @ _LIBVS-EXPECTED @
        _LIBVS-STORE @ _LIBRARY-VFS-STORE.CORE VFSNAP-SAVE
        _LIBVS-STORE @ _LIBVFS-ADAPT ;

: _LIBRARY-VFS-STORE-SAVE-HEAD
  ( head-fact expected-generation store -- status )
    _LIBVS-STORE ! _LIBVS-EXPECTED ! _LIBVS-HEAD-FACT !
    _LIBVS-STORE @ LIBRARY-VFS-STORE-VALID? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBVS-HEAD-FACT @ LIB-HEAD-FACT-SIZE _VFSNAP-SPAN-VALID? 0= IF
        LIBSTORE-S-INVALID EXIT
    THEN
    _LIBVS-STORE @ LIBRARY-VFS-STORE-BLOCKED? IF
        _LIBVS-STORE @ LIBRARY-VFS-STORE-LAST-STATUS@ EXIT
    THEN
    _LIBVS-SAVE-HEAD-CALL ;

: _LIBRARY-VFS-STORE-PROVISION  ( arena-id store -- status )
    _LIBVP-STORE !
    _LIBVP-STORE @ LIBRARY-VFS-STORE-VALID? 0= IF
        DROP LIBSTORE-S-INVALID EXIT
    THEN
    _LIBVP-STORE @ LIBRARY-VFS-STORE-BLOCKED? IF
        DROP _LIBVP-STORE @ LIBRARY-VFS-STORE-LAST-STATUS@ EXIT
    THEN
    _LIBAUTH-INVALIDATE
    _LIBIX-INVALIDATE
    _LIBVP-STORE @ _LIBVFS-CLEAR-PUBLISHED
    0 _LIBVP-CLEANUP-EVIDENCE !
    _LIBVP-ARENA-ID LIB-DIGEST-SIZE 0 FILL
    _LIBVP-ARENA-ID LIB-DIGEST-SIZE CMOVE
    _LIBVP-STORE @ _LIBRARY-VFS-STORE-RECOVER DUP IF
        _LIBVP-STORE @ _LIBVFS-CORPUS-RESULT EXIT
    THEN
    DROP
    _LIBVP-STORE @ _LIBRARY-VFS-STORE-LOAD-HEAD
    DUP LIBSTORE-S-ABSENT = IF
        DROP
    ELSE
        DUP LIBSTORE-S-OK = IF
            DROP
            _LIBVP-STORE @ LIBRARY-VFS-STORE.VFS @ _LIBVP-VFS !
            ['] _LIBVP-FULL-LOAD-BODY _LIBVP-RUN
                DUP IF _LIBVP-FINISH-CORPUS-RUN EXIT THEN
            DROP
            _LIBVP-ARENA-ID
                _LIBVP-HEAD-FACT LIBHF.ARENA-ID
                SHA3-256-COMPARE IF
                LIBSTORE-S-OK _LIBVP-FINISH-CORPUS-RUN DROP
                _LIBVP-STORE @ LIBRARY-VFS-STORE.FLAGS DUP @
                    _LIBVFS-F-PROVISIONED OR SWAP !
                LIBSTORE-S-OK EXIT
            THEN
            LIBSTORE-S-CONFLICT _LIBVP-STORE @ _LIBVP-RESULT EXIT
        THEN
        _LIBVP-STORE @ _LIBVFS-CORPUS-RESULT EXIT
    THEN
    _LIBVP-STORE @ LIBRARY-VFS-STORE.VFS @ _LIBVP-VFS !
    ['] _LIBVP-PROVISION-BODY _LIBVP-RUN
    DUP LIBSTORE-S-OK <> IF
        DUP _LIBVFS-CORPUS-BLOCKING? IF
            _LIBVP-STORE @ LIBRARY-VFS-STORE.FLAGS DUP @
                _LIBVFS-F-BLOCKED OR SWAP !
        THEN
        _LIBVP-STORE @ _LIBVP-RESULT EXIT
    THEN
    _LIBVP-STORE @ _LIBVP-RESULT DROP
    _LIBVP-HEAD-FACT 0 _LIBVP-STORE @
        _LIBRARY-VFS-STORE-SAVE-HEAD DUP IF EXIT THEN DROP
    _LIBVP-STORE @ _LIBRARY-VFS-STORE-LOAD DUP IF EXIT THEN DROP
    _LIBVP-ARENA-ID
        _LIBVP-STORE @ LIBRARY-VFS-STORE.HEAD LIBHF.ARENA-ID
        SHA3-256-COMPARE 0= IF
        _LIBVP-STORE @ _LIBVFS-CLEAR-PUBLISHED
        LIBSTORE-S-CORRUPT _LIBVP-STORE @ _LIBVFS-CORPUS-RESULT EXIT
    THEN
    _LIBVP-STORE @ LIBRARY-VFS-STORE.FLAGS DUP @
        _LIBVFS-F-PROVISIONED OR SWAP !
    LIBSTORE-S-OK _LIBVP-STORE @ _LIBVFS-RESULT ;

' _LIBRARY-VFS-STORE-PROVISION CONSTANT _libvfs-provision-xt
: LIBRARY-VFS-STORE-PROVISION  ( arena-id store -- status )
    DUP _LIBVFS-STORE-SPAN-SAFE? 0= IF
        2DROP LIBSTORE-S-INVALID EXIT
    THEN
    2DUP _LIBVFS-ARENA-ID-SAFE? 0= IF
        2DROP LIBSTORE-S-INVALID EXIT
    THEN
    _libvfs-provision-xt _library-vfs-store-guard WITH-GUARD ;

\ =====================================================================
\  Public managed-document vertical slice
\ =====================================================================
\  The old head remains authoritative through content and inactive-bank
\  preparation.  A failed preparation may leave only an ignored arena suffix
\  or an ignored complete inactive bank; retry overwrites both from the old
\  committed facts.  Only the fixed-snapshot head save publishes the result.

: _LIBMU-SPAN-ALIASES-STORE?  ( a u store -- flag )
    >R R@ LIBRARY-VFS-STORE-SIZE _VFSNAP-RANGES-OVERLAP? R> DROP ;

: _LIBMU-SPAN-ALIASES-VFS?  ( a u -- flag )
    _LIBMU-SPAN-U ! _LIBMU-SPAN-A !
    _LIBMU-STORE @ LIBRARY-VFS-STORE.VFS @ DUP
        VFS-DESC-SIZE _VFSNAP-SPAN-VALID? 0= IF DROP -1 EXIT THEN
    >R
    _LIBMU-SPAN-A @ _LIBMU-SPAN-U @ R@ VFS-DESC-SIZE
        _VFSNAP-RANGES-OVERLAP? IF R> DROP -1 EXIT THEN
    R> V.ARENA @ DUP 32 _VFSNAP-SPAN-VALID? 0= IF DROP -1 EXIT THEN
    >R
    _LIBMU-SPAN-A @ _LIBMU-SPAN-U @ R@ 32
        _VFSNAP-RANGES-OVERLAP? IF R> DROP -1 EXIT THEN
    R>
    DUP A.BASE @ SWAP A.SIZE @
    2DUP _VFSNAP-SPAN-VALID? 0= IF 2DROP -1 EXIT THEN
    _LIBMU-SPAN-A @ _LIBMU-SPAN-U @ 2SWAP
        _VFSNAP-RANGES-OVERLAP? ;

: _LIBMU-OWNER-SPAN-SAFE?  ( a u -- flag )
    2DUP _VFSNAP-SPAN-VALID? 0= IF 2DROP 0 EXIT THEN
    2DUP _LIBVFS-PRIVATE-ALIASES? IF 2DROP 0 EXIT THEN
    2DUP _LIBMU-STORE @ _LIBMU-SPAN-ALIASES-STORE? IF
        2DROP 0 EXIT
    THEN
    _LIBMU-SPAN-ALIASES-VFS? 0= ;

: _LIBMU-CREATE-ARGS?  ( request result store -- flag )
    _LIBMU-STORE ! _LIBMU-RESULT ! _LIBMU-REQUEST !
    _LIBMU-STORE @ LIBRARY-VFS-STORE-VALID? 0= IF 0 EXIT THEN
    _LIBMU-REQUEST @ LIBRARY-MANAGED-CREATE-REQUEST-SIZE
        _LIBMU-OWNER-SPAN-SAFE? 0= IF 0 EXIT THEN
    _LIBMU-REQUEST @ _LIBRARY-MANAGED-CREATE-REQUEST-VALID? 0= IF
        0 EXIT
    THEN
    _LIBMU-RESULT @ LIB-ENTRY-SIZE _LIBMU-OWNER-SPAN-SAFE? 0= IF
        0 EXIT
    THEN
    _LIBMU-RESULT @ LIB-ENTRY-SIZE _LIBMU-REQUEST @
        LIBRARY-MANAGED-CREATE-REQUEST-SIZE
        _VFSNAP-RANGES-OVERLAP? IF 0 EXIT THEN
    _LIBMU-REQUEST @ LIBMCR.CONTENT-U @ IF
        _LIBMU-REQUEST @ LIBMCR-CONTENT$
            _LIBMU-OWNER-SPAN-SAFE? 0= IF 0 EXIT THEN
        _LIBMU-REQUEST @ LIBMCR-CONTENT$
            _LIBMU-REQUEST @ LIBRARY-MANAGED-CREATE-REQUEST-SIZE
            _VFSNAP-RANGES-OVERLAP? IF 0 EXIT THEN
        _LIBMU-REQUEST @ LIBMCR-CONTENT$
            _LIBMU-RESULT @ LIB-ENTRY-SIZE
            _VFSNAP-RANGES-OVERLAP? IF 0 EXIT THEN
    THEN
    -1 ;

: _LIBMU-FIND-OPERATION-KEY  ( key -- slot|-1 )
    _LIBMU-ID !
    _LIBVP-BANK-FACT LIBBF.CATALOG-COUNT @ 0 ?DO
        _LIBMU-ID @ I _LIBVP-CATALOG-FACT _LIBVCF.OPERATION-KEY RID= IF
            I UNLOOP EXIT
        THEN
    LOOP
    -1 ;

: _LIBMU-COLLECTION-KEY-CONFLICT?  ( key -- flag )
    _LIBMU-ID !
    _LIBVP-BANK-FACT LIBBF.COLLECTION-COUNT @ 0 ?DO
        _LIBMU-ID @ I _LIBVP-COLLECTION-FACT _LIBVCCF.ID RID= IF
            -1 UNLOOP EXIT
        THEN
        _LIBMU-ID @ I _LIBVP-COLLECTION-FACT _LIBVCCF.OPERATION-KEY RID= IF
            -1 UNLOOP EXIT
        THEN
    LOOP
    0 ;

: _LIBMU-FIND-RID  ( rid -- slot|-1 )
    _LIBMU-ID !
    _LIBVP-BANK-FACT LIBBF.CATALOG-COUNT @ 0 ?DO
        _LIBMU-ID @ I _LIBVP-CATALOG-FACT _LIBVCF.ID RID= IF
            I UNLOOP EXIT
        THEN
    LOOP
    -1 ;

: _LIBMU-FIND-COLLECTION-KEY  ( key -- slot|-1 )
    _LIBMU-ID !
    _LIBVP-BANK-FACT LIBBF.COLLECTION-COUNT @ 0 ?DO
        _LIBMU-ID @ I _LIBVP-COLLECTION-FACT
            _LIBVCCF.OPERATION-KEY RID= IF I UNLOOP EXIT THEN
    LOOP
    -1 ;

: _LIBMU-FIND-COLLECTION-RID  ( rid -- slot|-1 )
    _LIBMU-ID !
    _LIBVP-BANK-FACT LIBBF.COLLECTION-COUNT @ 0 ?DO
        _LIBMU-ID @ I _LIBVP-COLLECTION-FACT _LIBVCCF.ID RID= IF
            I UNLOOP EXIT
        THEN
    LOOP
    -1 ;

: _LIBMU-RID-IN-USE?  ( rid -- flag )
    _LIBMU-ID !
    _LIBMU-OPERATION-KEY @ DUP IF
        _LIBMU-ID @ SWAP RID= IF -1 EXIT THEN
    ELSE
        DROP
    THEN
    _LIBVP-BANK-FACT LIBBF.CATALOG-COUNT @ 0 ?DO
        _LIBMU-ID @ I _LIBVP-CATALOG-FACT _LIBVCF.ID RID= IF
            -1 UNLOOP EXIT
        THEN
        _LIBMU-ID @ I _LIBVP-CATALOG-FACT _LIBVCF.OPERATION-KEY RID= IF
            -1 UNLOOP EXIT
        THEN
    LOOP
    _LIBVP-BANK-FACT LIBBF.COLLECTION-COUNT @ 0 ?DO
        _LIBMU-ID @ I _LIBVP-COLLECTION-FACT _LIBVCCF.ID RID= IF
            -1 UNLOOP EXIT
        THEN
        _LIBMU-ID @ I _LIBVP-COLLECTION-FACT _LIBVCCF.OPERATION-KEY RID= IF
            -1 UNLOOP EXIT
        THEN
    LOOP
    0 ;

: _LIBMU-ACTIVE-BANK$  ( -- a u )
    _LIBMU-STORE @ LIBRARY-VFS-STORE.HEAD LIBHF.BANK-SELECTOR @ IF
        _LIBVFS-BANK-B-PATH$
    ELSE
        _LIBVFS-BANK-A-PATH$
    THEN ;

: _LIBMU-INACTIVE-BANK$  ( -- a u )
    _LIBMU-STORE @ LIBRARY-VFS-STORE.HEAD LIBHF.BANK-SELECTOR @ IF
        _LIBVFS-BANK-A-PATH$
    ELSE
        _LIBVFS-BANK-B-PATH$
    THEN ;

: _LIBMU-TOUCHED-AUTHORITY-RESULT  ( status -- status )
    _LIBMU-STORE @ _LIBVP-RESULT
    DUP _LIBVFS-CORPUS-BLOCKING? IF
        _LIBAUTH-INVALIDATE
        _LIBMU-STORE @ _LIBVFS-CORPUS-RESULT
    THEN ;

: _LIBMU-READ-ENTRY-BODY  ( -- status )
    _LIBMU-FOUND-ENTRY LIB-ENTRY-INIT
    1 _LIBPQ-ENTRY-READ-N +!
    _LIBMU-ACTIVE-BANK$ LIB-BANK-SIZE _LIBVP-OPEN-COMMITTED
        DUP IF EXIT THEN DROP
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    _LIBMU-INDEX @ LIB-CATALOG-RECORD-SIZE *
        LIB-BANK-CATALOG-OFFSET + _LIBVP-FD @ _LIBVFS-SEEK
    _LIBVP-FRAME LIB-CATALOG-RECORD-SIZE
        _LIBVP-FD @ _LIBVFS-READ-EXACT IF LIBSTORE-S-IO EXIT THEN
    _LIBVP-CLOSE-NOW DUP IF EXIT THEN DROP
    _LIBVP-FRAME LIB-CATALOG-RECORD-SIZE
        _LIBMU-FRAME-SHA SHA3-256-HASH
    _LIBMU-FRAME-SHA _LIBMU-INDEX @ _LIBAUTH-CATALOG-SHA
        SHA3-256-COMPARE 0= IF
        _LIBAUTH-INVALIDATE LIBSTORE-S-CORRUPT EXIT
    THEN
    _LIBVP-FRAME LIB-CATALOG-RECORD-SIZE _LIBMU-FOUND-ENTRY
        LIB-CATALOG-RECORD-DECODE _LIBVFS-FORMAT-READ>STATUS ;

: _LIBMU-READ-ENTRY  ( slot -- status )
    _LIBMU-INDEX !
    _LIBMU-STORE @ LIBRARY-VFS-STORE.VFS @ _LIBVP-VFS !
    ['] _LIBMU-READ-ENTRY-BODY _LIBVP-RUN
        _LIBMU-TOUCHED-AUTHORITY-RESULT ;

: _LIBMU-READ-COLLECTION-BODY  ( -- status )
    _LIBMU-FOUND-COLLECTION LIB-COLLECTION-INIT
    1 _LIBPQ-COLLECTION-READ-N +!
    _LIBMU-ACTIVE-BANK$ LIB-BANK-SIZE _LIBVP-OPEN-COMMITTED
        DUP IF EXIT THEN DROP
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    _LIBMU-INDEX @ LIB-COLLECTION-RECORD-SIZE *
        LIB-BANK-COLLECTION-OFFSET + _LIBVP-FD @ _LIBVFS-SEEK
    _LIBVP-FRAME LIB-COLLECTION-RECORD-SIZE
        _LIBVP-FD @ _LIBVFS-READ-EXACT IF LIBSTORE-S-IO EXIT THEN
    _LIBVP-CLOSE-NOW DUP IF EXIT THEN DROP
    _LIBVP-FRAME LIB-COLLECTION-RECORD-SIZE
        _LIBMU-FRAME-SHA SHA3-256-HASH
    _LIBMU-FRAME-SHA _LIBMU-INDEX @ _LIBAUTH-COLLECTION-SHA
        SHA3-256-COMPARE 0= IF
        _LIBAUTH-INVALIDATE LIBSTORE-S-CORRUPT EXIT
    THEN
    _LIBVP-FRAME LIB-COLLECTION-RECORD-SIZE _LIBMU-FOUND-COLLECTION
        LIB-COLLECTION-RECORD-DECODE _LIBVFS-FORMAT-READ>STATUS ;

: _LIBMU-READ-COLLECTION  ( slot -- status )
    _LIBMU-INDEX !
    _LIBMU-STORE @ LIBRARY-VFS-STORE.VFS @ _LIBVP-VFS !
    ['] _LIBMU-READ-COLLECTION-BODY _LIBVP-RUN
        _LIBMU-TOUCHED-AUTHORITY-RESULT ;

: _LIBMU-BUILD-CONTENT  ( rid -- status )
    _LIBMU-ID !
    _LIBMU-CONTENT LIB-CONTENT-INIT
    _LIBMU-ID @ _LIBMU-CONTENT LIBCT.ID RID-COPY
    1 _LIBMU-CONTENT LIBCT.DOMAIN-REVISION !
    1 _LIBMU-CONTENT LIBCT.CONTENT-REVISION !
    LIB-KIND-MANAGED-DOCUMENT _LIBMU-CONTENT LIBCT.KIND !
    _LIBMU-REQUEST @ LIBMCR.MEDIA @ _LIBMU-CONTENT LIBCT.MEDIA !
    _LIBMU-REQUEST @ LIBMCR.CONTENT-A @ _LIBMU-CONTENT LIBCT.DATA-A !
    _LIBMU-REQUEST @ LIBMCR.CONTENT-U @ _LIBMU-CONTENT LIBCT.DATA-U !
    _LIBMU-CONTENT LIB-CONTENT-DIGEST! _LIBVFS-FORMAT>STATUS ;

: _LIBMU-BUILD-ENTRY  ( rid mutation-sequence -- status )
    _LIBMU-NEW-MUTATION ! _LIBMU-ID !
    _LIBMU-ENTRY LIB-ENTRY-INIT
    _LIBMU-ID @ _LIBMU-ENTRY LIBE.ID RID-COPY
    1 _LIBMU-ENTRY LIBE.DOMAIN-REVISION !
    LIB-KIND-MANAGED-DOCUMENT _LIBMU-ENTRY LIBE.KIND !
    LIB-LIFECYCLE-ACTIVE _LIBMU-ENTRY LIBE.LIFECYCLE !
    _LIBMU-REQUEST @ LIBMCR.MEDIA @ _LIBMU-ENTRY LIBE.MEDIA !
    1 _LIBMU-ENTRY LIBE.CURRENT-CONTENT-REVISION !
    1 _LIBMU-ENTRY LIBE.OLDEST-CONTENT-REVISION !
    _LIBMU-REQUEST @ LIBMCR.CONTENT-U @ _LIBMU-ENTRY LIBE.CONTENT-U !
    _LIBMU-CONTENT LIBCT.DIGEST _LIBMU-ENTRY LIBE.CONTENT-DIGEST
        LIB-DIGEST-SIZE CMOVE
    _LIBMU-NEW-MUTATION @ _LIBMU-ENTRY LIBE.MUTATION-SEQUENCE !
    LIB-CLOCK-MUTATION-SEQUENCE _LIBMU-ENTRY LIBE.CREATED-CLOCK !
    _LIBMU-NEW-MUTATION @ _LIBMU-ENTRY LIBE.CREATED-VALUE !
    LIB-CLOCK-MUTATION-SEQUENCE _LIBMU-ENTRY LIBE.MODIFIED-CLOCK !
    _LIBMU-NEW-MUTATION @ _LIBMU-ENTRY LIBE.MODIFIED-VALUE !
    _LIBMU-REQUEST @ LIBMCR.TITLE-U @ _LIBMU-ENTRY LIBE.TITLE-U !
    _LIBMU-REQUEST @ LIBMCR.TITLE _LIBMU-ENTRY LIBE.TITLE
        _LIBMU-REQUEST @ LIBMCR.TITLE-U @ CMOVE
    _LIBMU-REQUEST @ LIBMCR.OPERATION-KEY
        _LIBMU-ENTRY LIBE.RECEIPT LIBR.OPERATION-KEY RID-COPY
    LIB-IMPORT-CREATED _LIBMU-ENTRY LIBE.RECEIPT LIBR.METHOD !
    1 _LIBMU-ENTRY LIBE.RECEIPT LIBR.INITIAL-CONTENT-REVISION !
    _LIBMU-REQUEST @ LIBMCR.CONTENT-U @
        _LIBMU-ENTRY LIBE.RECEIPT LIBR.INITIAL-CONTENT-U !
    _LIBMU-REQUEST @ LIBMCR.MEDIA @
        _LIBMU-ENTRY LIBE.RECEIPT LIBR.INITIAL-MEDIA !
    _LIBMU-CONTENT LIBCT.DIGEST
        _LIBMU-ENTRY LIBE.RECEIPT LIBR.INITIAL-CONTENT-DIGEST
        LIB-DIGEST-SIZE CMOVE
    _LIBMU-REQUEST @ LIBMCR.EXPECTED-CATALOG-GENERATION @
        _LIBMU-ENTRY LIBE.RECEIPT LIBR.EXPECTED-CATALOG-GENERATION !
    _LIBMU-ENTRY LIB-ENTRY-REQUEST-SEAL! _LIBVFS-FORMAT>STATUS ;

: _LIBMU-GENERATE-RID  ( -- status )
    0 _LIBMU-ATTEMPT !
    BEGIN _LIBMU-ATTEMPT @ 16 < WHILE
        4 0 DO _LIBMU-RANDOM _LIBMU-ENTROPY I 8 * + ! LOOP
        _LIBMU-ATTEMPT @ _LIBMU-CELL !
        SHA3-256-BEGIN
        _LIBMU-RID-DOMAIN-A @ _LIBMU-RID-DOMAIN-U @ SHA3-256-ADD
        _LIBMU-STORE @ LIBRARY-VFS-STORE.ARENA LIBAF.ARENA-ID
            LIB-DIGEST-SIZE SHA3-256-ADD
        _LIBMU-ENTROPY LIB-DIGEST-SIZE SHA3-256-ADD
        _LIBMU-CELL 8 SHA3-256-ADD
        _LIBMU-RID SHA3-256-END
        _LIBMU-RID RID-PRESENT?
        _LIBMU-RID _LIBMU-RID-IN-USE? 0= AND IF LIBSTORE-S-OK EXIT THEN
        1 _LIBMU-ATTEMPT +!
    REPEAT
    LIBSTORE-S-ALLOCATION ;

: _LIBMU-PREFLIGHT-CAPACITY  ( -- status )
    _LIBMU-CATALOG-COUNT @ DUP 0< SWAP LIB-CATALOG-MAX > OR IF
        LIBSTORE-S-CATALOG-FULL EXIT
    THEN
    _LIBMU-COLLECTION-COUNT @ DUP 0< SWAP LIB-COLLECTION-MAX > OR IF
        LIBSTORE-S-COLLECTION-FULL EXIT
    THEN
    _LIBMU-STORE @ LIBRARY-VFS-STORE.GENERATION @ 1+
        DUP 0> 0= IF DROP LIBSTORE-S-CONTENT-FULL EXIT THEN
        _LIBMU-NEW-GENERATION !
    _LIBMU-STORE @ LIBRARY-VFS-STORE.BANK LIBBF.MUTATION-SEQUENCE @ 1+
        DUP 0> 0= IF DROP LIBSTORE-S-CATALOG-FULL EXIT THEN
        _LIBMU-NEW-MUTATION !
    _LIBMU-STORE @ LIBRARY-VFS-STORE.BANK LIBBF.CONTENT-TAIL @
        _LIBMU-NEW-TAIL !
    _LIBMU-STORE @ LIBRARY-VFS-STORE.BANK LIBBF.CONTENT-RECORD-COUNT @
        _LIBMU-NEW-RECORD-COUNT !
    _LIBMU-STORE @ LIBRARY-VFS-STORE.BANK LIBBF.CONTENT-CHAIN
        _LIBMU-CHAIN LIB-DIGEST-SIZE CMOVE
    _LIBMU-HAS-CONTENT @ IF
        _LIBMU-PLANNED-CONTENT-U @ LIB-CONTENT-RECORD-SIZE
            DUP -1 = IF DROP LIBSTORE-S-INVALID EXIT THEN _LIBMU-RECORD-U !
        _LIBMU-RECORD-U @ LIB-CONTENT-FRAME-SIZE
            DUP -1 = IF DROP LIBSTORE-S-INVALID EXIT THEN _LIBMU-FRAME-U !
        _LIBMU-STORE @ LIBRARY-VFS-STORE.BANK LIBBF.CONTENT-TAIL @
            LIB-ARENA-SIZE _LIBMU-FRAME-U @ - > IF
            LIBSTORE-S-CONTENT-FULL EXIT
        THEN
        _LIBMU-STORE @ LIBRARY-VFS-STORE.BANK LIBBF.CONTENT-TAIL @
            _LIBMU-FRAME-U @ + _LIBMU-NEW-TAIL !
        _LIBMU-STORE @ LIBRARY-VFS-STORE.BANK
            LIBBF.CONTENT-RECORD-COUNT @ 1+
            DUP 0> 0= IF DROP LIBSTORE-S-CONTENT-FULL EXIT THEN
            _LIBMU-NEW-RECORD-COUNT !
    THEN
    LIBSTORE-S-OK ;

: _LIBMU-CONTENT-MATCH?  ( decoded -- flag )
    DUP LIBCT.ID _LIBMU-CONTENT LIBCT.ID RID=
    OVER LIBCT.DOMAIN-REVISION @
        _LIBMU-CONTENT LIBCT.DOMAIN-REVISION @ = AND
    OVER LIBCT.CONTENT-REVISION @
        _LIBMU-CONTENT LIBCT.CONTENT-REVISION @ = AND
    OVER LIBCT.KIND @ _LIBMU-CONTENT LIBCT.KIND @ = AND
    OVER LIBCT.MEDIA @ _LIBMU-CONTENT LIBCT.MEDIA @ = AND
    OVER LIBCT.DATA-U @ _LIBMU-CONTENT LIBCT.DATA-U @ = AND
    OVER LIBCT.DIGEST _LIBMU-CONTENT LIBCT.DIGEST SHA3-256-COMPARE AND
    SWAP LIBCT-DATA$ _LIBMU-CONTENT LIBCT-DATA$ COMPARE 0= AND ;

: _LIBMU-WRITE-CONTENT-BODY  ( -- status )
    _LIBMU-STAGE-BEFORE-CONTENT _LIBMU-CHECKPOINT DUP IF EXIT THEN DROP
    _LIBVP-FRAME _LIBMU-FRAME-U @ 0 FILL
    _LIBMU-CONTENT _LIBVP-FRAME _LIBMU-RECORD-U @
        LIB-CONTENT-RECORD-ENCODE
    DUP IF NIP _LIBVFS-FORMAT>STATUS EXIT THEN
    DROP _LIBMU-RECORD-U @ <> IF LIBSTORE-S-RECOVERY EXIT THEN
    _LIBVFS-CONTENT-PATH$ LIB-ARENA-SIZE _LIBVP-OPEN-COMMITTED
        DUP IF EXIT THEN DROP
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    _LIBMU-STORE @ LIBRARY-VFS-STORE.BANK LIBBF.CONTENT-TAIL @
        _LIBVP-FD @ _LIBVFS-SEEK
    _LIBVP-FRAME _LIBMU-FRAME-U @ _LIBVP-FD @ _LIBVFS-WRITE-EXACT IF
        LIBSTORE-S-IO EXIT
    THEN
    _LIBVP-CLOSE-NOW DUP IF EXIT THEN DROP
    _LIBVP-SYNC DUP IF EXIT THEN DROP
    _LIBMU-STAGE-AFTER-CONTENT _LIBMU-CHECKPOINT DUP IF EXIT THEN DROP
    _LIBVFS-CONTENT-PATH$ LIB-ARENA-SIZE _LIBVP-OPEN-COMMITTED
        DUP IF EXIT THEN DROP
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    _LIBMU-STORE @ LIBRARY-VFS-STORE.BANK LIBBF.CONTENT-TAIL @
        _LIBVP-FD @ _LIBVFS-SEEK
    _LIBVP-FRAME _LIBMU-FRAME-U @ _LIBVP-FD @ _LIBVFS-READ-EXACT IF
        LIBSTORE-S-IO EXIT
    THEN
    _LIBVP-CLOSE-NOW DUP IF EXIT THEN DROP
    _LIBVP-FRAME _LIBMU-RECORD-U @ +
        _LIBMU-FRAME-U @ _LIBMU-RECORD-U @ - _LIBVP-ZERO? 0= IF
        LIBSTORE-S-CORRUPT EXIT
    THEN
    _LIBVP-FRAME _LIBMU-RECORD-U @ _LIBMU-CONTENT-READBACK
        LIB-CONTENT-RECORD-DECODE _LIBVFS-FORMAT-READ>STATUS
        DUP IF EXIT THEN DROP
    _LIBMU-CONTENT-READBACK _LIBMU-CONTENT-MATCH? 0= IF
        LIBSTORE-S-CORRUPT EXIT
    THEN
    _LIBVP-FRAME _LIBMU-FRAME-U @ _LIBMU-FRAME-SHA
        LIB-CONTENT-FRAME-DIGEST _LIBVFS-FORMAT>STATUS DUP IF EXIT THEN DROP
    _LIBMU-STORE @ LIBRARY-VFS-STORE.BANK LIBBF.CONTENT-CHAIN
        _LIBMU-STORE @ LIBRARY-VFS-STORE.BANK LIBBF.CONTENT-TAIL @
        _LIBMU-FRAME-U @ _LIBMU-FRAME-SHA _LIBMU-CHAIN
        LIB-CONTENT-CHAIN-STEP _LIBVFS-FORMAT>STATUS ;

: _LIBMU-OPEN-ACTIVE-SOURCE  ( -- status )
    _LIBMU-ACTIVE-BANK$ LIB-BANK-SIZE _LIBVP-OPEN-COMMITTED
        DUP IF EXIT THEN DROP
    _LIBVP-FD @ _LIBMU-SOURCE-FD !
    0 _LIBVP-FD !
    LIBSTORE-S-OK ;

: _LIBMU-COPY-BANK-BODY  ( -- status )
    _LIBMU-OPEN-ACTIVE-SOURCE DUP IF EXIT THEN DROP
    _LIBMU-INACTIVE-BANK$ LIB-BANK-SIZE _LIBVP-OPEN-EXACT
        DUP IF EXIT THEN DROP
    LIBSTORE-S-IO _LIBVP-THROW-STATUS !
    LIB-BANK-HEADER-SIZE _LIBMU-SOURCE-FD @ _LIBVFS-SEEK
    LIB-BANK-HEADER-SIZE _LIBVP-FD @ _LIBVFS-SEEK
    LIB-BANK-BODY-SIZE _LIBVP-REMAINING !
    BEGIN _LIBVP-REMAINING @ 0> WHILE
        _LIBVP-REMAINING @ _LIBVP-ZERO-BLOCK-SIZE MIN _LIBVP-CHUNK !
        _LIBVP-ZERO-BLOCK _LIBVP-CHUNK @ _LIBMU-SOURCE-FD @
            _LIBVFS-READ-EXACT IF LIBSTORE-S-IO EXIT THEN
        _LIBVP-ZERO-BLOCK _LIBVP-CHUNK @ _LIBVP-FD @
            _LIBVFS-WRITE-EXACT IF LIBSTORE-S-IO EXIT THEN
        _LIBVP-CHUNK @ NEGATE _LIBVP-REMAINING +!
    REPEAT
    _LIBMU-CLOSE-SOURCE-NOW DUP IF EXIT THEN DROP
    _LIBMU-HAS-CATALOG @ IF
        _LIBMU-ENTRY _LIBVP-FRAME LIB-CATALOG-RECORD-SIZE
            LIB-CATALOG-RECORD-ENCODE
        DUP IF NIP _LIBVFS-FORMAT>STATUS EXIT THEN
        DROP LIB-CATALOG-RECORD-SIZE <> IF LIBSTORE-S-RECOVERY EXIT THEN
        _LIBMU-CATALOG-INDEX @ LIB-CATALOG-RECORD-SIZE *
            LIB-BANK-CATALOG-OFFSET + _LIBVP-FD @ _LIBVFS-SEEK
        _LIBVP-FRAME LIB-CATALOG-RECORD-SIZE _LIBVP-FD @
            _LIBVFS-WRITE-EXACT IF LIBSTORE-S-IO EXIT THEN
    THEN
    _LIBMU-HAS-COLLECTION @ IF
        _LIBMU-COLLECTION _LIBVP-FRAME LIB-COLLECTION-RECORD-SIZE
            LIB-COLLECTION-RECORD-ENCODE
        DUP IF NIP _LIBVFS-FORMAT>STATUS EXIT THEN
        DROP LIB-COLLECTION-RECORD-SIZE <> IF
            LIBSTORE-S-RECOVERY EXIT
        THEN
        _LIBMU-COLLECTION-INDEX @ LIB-COLLECTION-RECORD-SIZE *
            LIB-BANK-COLLECTION-OFFSET + _LIBVP-FD @ _LIBVFS-SEEK
        _LIBVP-FRAME LIB-COLLECTION-RECORD-SIZE _LIBVP-FD @
            _LIBVFS-WRITE-EXACT IF LIBSTORE-S-IO EXIT THEN
    THEN
    _LIBVP-CLOSE-NOW DUP IF EXIT THEN DROP
    _LIBVP-SYNC ;

: _LIBMU-BUILD-BANK-FACT  ( -- status )
    _LIBMU-BANK-FACT LIB-BANK-FACT-INIT
    _LIBMU-NEW-GENERATION @ _LIBMU-BANK-FACT LIBBF.GENERATION !
    _LIBMU-CATALOG-COUNT @ _LIBMU-BANK-FACT LIBBF.CATALOG-COUNT !
    _LIBMU-COLLECTION-COUNT @ _LIBMU-BANK-FACT LIBBF.COLLECTION-COUNT !
    _LIBMU-NEW-MUTATION @ _LIBMU-BANK-FACT LIBBF.MUTATION-SEQUENCE !
    _LIBMU-STORE @ LIBRARY-VFS-STORE.BANK LIBBF.ARENA-ID
        _LIBMU-BANK-FACT LIBBF.ARENA-ID LIB-DIGEST-SIZE CMOVE
    _LIBMU-NEW-TAIL @ _LIBMU-BANK-FACT LIBBF.CONTENT-TAIL !
    _LIBMU-NEW-RECORD-COUNT @
        _LIBMU-BANK-FACT LIBBF.CONTENT-RECORD-COUNT !
    _LIBMU-CHAIN _LIBMU-BANK-FACT LIBBF.CONTENT-CHAIN
        LIB-DIGEST-SIZE CMOVE
    _LIBVP-BODY-CRC @ 0xFFFFFFFF AND
        _LIBMU-BANK-FACT LIBBF.BODY-CRC !
    _LIBVP-BODY-SHA _LIBMU-BANK-FACT LIBBF.BODY-SHA
        LIB-DIGEST-SIZE CMOVE
    _LIBMU-BANK-FACT LIB-BANK-FACT-VALID? IF
        LIBSTORE-S-OK
    ELSE
        LIBSTORE-S-RECOVERY
    THEN ;

: _LIBMU-WRITE-BANK-HEADER  ( -- status )
    _LIBMU-BANK-FACT _LIBVP-SECTOR LIB-BANK-HEADER-SIZE
        LIB-BANK-HEADER-ENCODE
    DUP IF NIP _LIBVFS-FORMAT>STATUS EXIT THEN
    DROP LIB-BANK-HEADER-SIZE <> IF LIBSTORE-S-RECOVERY EXIT THEN
    _LIBMU-INACTIVE-BANK$ LIB-BANK-SIZE _LIBVP-OPEN-EXACT
        DUP IF EXIT THEN DROP
    _LIBVP-WRITE-SECTOR-AT-ZERO ;

: _LIBMU-BUILD-HEAD-FACT  ( -- status )
    _LIBMU-HEAD-FACT LIB-HEAD-FACT-INIT
    _LIBMU-NEW-GENERATION @ _LIBMU-HEAD-FACT LIBHF.GENERATION !
    1 _LIBMU-STORE @ LIBRARY-VFS-STORE.HEAD LIBHF.BANK-SELECTOR @ -
        _LIBMU-HEAD-FACT LIBHF.BANK-SELECTOR !
    _LIBMU-NEW-GENERATION @ _LIBMU-HEAD-FACT LIBHF.BANK-GENERATION !
    _LIBMU-BANK-FACT LIBBF.CATALOG-COUNT @
        _LIBMU-HEAD-FACT LIBHF.CATALOG-COUNT !
    _LIBMU-BANK-FACT LIBBF.COLLECTION-COUNT @
        _LIBMU-HEAD-FACT LIBHF.COLLECTION-COUNT !
    _LIBMU-NEW-MUTATION @ _LIBMU-HEAD-FACT LIBHF.MUTATION-SEQUENCE !
    _LIBMU-BANK-SHA _LIBMU-HEAD-FACT LIBHF.BANK-SHA LIB-DIGEST-SIZE CMOVE
    _LIBMU-BANK-FACT LIBBF.ARENA-ID _LIBMU-HEAD-FACT LIBHF.ARENA-ID
        LIB-DIGEST-SIZE CMOVE
    _LIBMU-NEW-TAIL @ _LIBMU-HEAD-FACT LIBHF.CONTENT-TAIL !
    _LIBMU-NEW-RECORD-COUNT @
        _LIBMU-HEAD-FACT LIBHF.CONTENT-RECORD-COUNT !
    _LIBMU-CHAIN _LIBMU-HEAD-FACT LIBHF.CONTENT-CHAIN
        LIB-DIGEST-SIZE CMOVE
    _LIBMU-HEAD-FACT LIB-HEAD-FACT-VALID? IF
        LIBSTORE-S-OK
    ELSE
        LIBSTORE-S-RECOVERY
    THEN ;

: _LIBMU-FULL-CANDIDATE-READBACK  ( -- status )
    _LIBVP-LOAD-SELECTED-BANK DUP IF EXIT THEN DROP
    _LIBVP-SCAN-CONTENT ;

: _LIBMU-WRITE-BANK-BODY  ( -- status )
    _LIBMU-COPY-BANK-BODY DUP IF EXIT THEN DROP
    _LIBMU-INACTIVE-BANK$ LIB-BANK-SIZE _LIBVP-OPEN-COMMITTED
        DUP IF EXIT THEN DROP
    LIB-BANK-HEADER-SIZE LIB-BANK-BODY-SIZE _LIBVP-CRC-RANGE
        DUP IF EXIT THEN DROP
    LIB-BANK-HEADER-SIZE LIB-BANK-BODY-SIZE _LIBVP-BODY-SHA
        _LIBVP-HASH-RANGE DUP IF EXIT THEN DROP
    _LIBVP-CLOSE-NOW DUP IF EXIT THEN DROP
    _LIBMU-BUILD-BANK-FACT DUP IF EXIT THEN DROP
    _LIBMU-WRITE-BANK-HEADER DUP IF EXIT THEN DROP
    _LIBMU-INACTIVE-BANK$ LIB-BANK-SIZE _LIBVP-OPEN-COMMITTED
        DUP IF EXIT THEN DROP
    0 LIB-BANK-SIZE _LIBMU-BANK-SHA _LIBVP-HASH-RANGE
        DUP IF EXIT THEN DROP
    _LIBVP-CLOSE-NOW DUP IF EXIT THEN DROP
    _LIBMU-BUILD-HEAD-FACT DUP IF EXIT THEN DROP
    _LIBMU-STAGE-AFTER-BANK _LIBMU-CHECKPOINT DUP IF EXIT THEN DROP
    _LIBMU-STAGE-BANK-READBACK _LIBMU-CHECKPOINT DUP IF EXIT THEN DROP
    _LIBMU-HEAD-FACT _LIBVP-HEAD-FACT LIB-HEAD-FACT-SIZE CMOVE
    _LIBMU-NEW-GENERATION @ _LIBVP-CANDIDATE-GENERATION !
    _LIBMU-FULL-CANDIDATE-READBACK ;

: _LIBMU-PREPARE-PUBLICATION-BODY  ( -- status )
    _LIBMU-HAS-CONTENT @ IF
        _LIBMU-WRITE-CONTENT-BODY DUP IF EXIT THEN DROP
    THEN
    _LIBMU-WRITE-BANK-BODY ;

: _LIBMU-PREPARE-PUBLICATION  ( -- status )
    _LIBAUTH-INVALIDATE
    _LIBMU-STORE @ LIBRARY-VFS-STORE.VFS @ _LIBVP-VFS !
    ['] _LIBMU-PREPARE-PUBLICATION-BODY _LIBVP-RUN
        _LIBMU-STORE @ _LIBVP-RESULT ;

: _LIBMU-REFRESH  ( -- status )
    _LIBMU-STORE @ _LIBRARY-VFS-STORE-LOAD ;

\ A warm assurance never treats the generation integer as authority.  It
\ first verifies the protected activation snapshot and exact VFS binding,
\ then performs the bounded replacement-aware VFSNAP head load and compares
\ every decoded committed-head byte.  Any missing/damaged snapshot or a
\ different valid head falls back to complete authoritative reconstruction.
: _LIBMU-ASSURE-WARM  ( -- status )
    _LIBMU-STORE @ _LIBAUTH-VALID? 0= IF
        _LIBAUTH-INVALIDATE
        _LIBMU-STORE @ _LIBRARY-VFS-STORE-LOAD EXIT
    THEN
    1 _LIBPQ-WARM-ASSURANCE-N +!
    _LIBMU-STORE @ _LIBRARY-VFS-STORE-LOAD-HEAD
    DUP LIBSTORE-S-ABSENT = IF
        DROP _LIBAUTH-INVALIDATE
        _LIBMU-STORE @ _LIBRARY-VFS-STORE-LOAD EXIT
    THEN
    DUP IF
        _LIBAUTH-INVALIDATE
        _LIBMU-STORE @ _LIBVFS-CORPUS-RESULT EXIT
    THEN
    DROP
    _LIBMU-STORE @ LIBRARY-VFS-STORE-BLOCKED?
    _LIBMU-STORE @ LIBRARY-VFS-STORE-CLEANUP-FAILED?
        _LIBAUTH-CLEANUP-FAILED @ <> OR
    _LIBAUTH-BINDING-MATCH? 0= OR IF
        _LIBAUTH-INVALIDATE
        _LIBMU-STORE @ _LIBRARY-VFS-STORE-LOAD EXIT
    THEN
    _LIBVP-HEAD-FACT LIB-HEAD-FACT-SIZE
        _LIBAUTH-HEAD LIB-HEAD-FACT-SIZE COMPARE IF
        _LIBAUTH-INVALIDATE
        _LIBMU-STORE @ _LIBRARY-VFS-STORE-LOAD EXIT
    THEN
    LIBSTORE-S-OK ;

\ A blocking VFSNAP result deliberately makes that core descriptor inert.
\ Reinitialize only its owner descriptor, then let durable replacement
\ recovery decide whether the requested head committed before inspecting the
\ operation key.  No in-memory candidate fact survives this boundary.
: _LIBMU-REOPEN-BLOCKED-STORE  ( -- status )
    _LIBMU-STORE @ LIBRARY-VFS-STORE.VFS @ _LIBMU-REOPEN-VFS !
    _LIBMU-STORE @ LIBRARY-VFS-STORE.FLAGS @
        _LIBVFS-F-PROVISIONED _LIBVFS-F-CLEANUP-FAILED OR AND
        _LIBMU-REOPEN-FLAGS !
    _LIBMU-STORE @ _LIBRARY-VFS-STORE.CORE VFSNAP-FINI
        DUP VFSNAP-S-OK <> IF
        DROP LIBSTORE-S-RECOVERY EXIT
    THEN
    DROP
    _LIBMU-REOPEN-VFS @ _LIBMU-STORE @ _LIBRARY-VFS-STORE-INIT
        >R
    _LIBMU-REOPEN-FLAGS @
        _LIBMU-STORE @ LIBRARY-VFS-STORE.FLAGS DUP @ ROT OR SWAP !
    R> DUP IF EXIT THEN DROP
    _LIBMU-STORE @ _LIBRARY-VFS-STORE-LOAD ;

: _LIBMU-RELOAD-AND-FIND-KEY  ( -- status )
    _LIBMU-STORE @ LIBRARY-VFS-STORE-BLOCKED? IF
        _LIBMU-REOPEN-BLOCKED-STORE
    ELSE
        _LIBMU-REFRESH
    THEN
    DUP IF EXIT THEN DROP
    _LIBMU-OPERATION-KEY @ _LIBMU-FIND-OPERATION-KEY
        DUP -1 = IF DROP LIBSTORE-S-NOT-FOUND EXIT THEN
    _LIBMU-READ-ENTRY DUP IF EXIT THEN DROP
    _LIBMU-FOUND-ENTRY LIBE.RECEIPT _LIBMU-ENTRY LIBE.RECEIPT
        LIB-RECEIPT-RETRY= 0= IF
        LIBSTORE-S-IDEMPOTENCY-MISMATCH EXIT
    THEN
    _LIBMU-FOUND-ENTRY LIBE.LIFECYCLE @
        LIB-LIFECYCLE-TOMBSTONED = IF LIBSTORE-S-TOMBSTONED EXIT THEN
    LIBSTORE-S-OK ;

: _LIBMU-RELOAD-AND-MATCH-ENTRY  ( -- status )
    _LIBMU-STORE @ LIBRARY-VFS-STORE-BLOCKED? IF
        _LIBMU-REOPEN-BLOCKED-STORE
    ELSE
        _LIBMU-REFRESH
    THEN
    DUP IF EXIT THEN DROP
    _LIBMU-ENTRY LIBE.ID _LIBMU-FIND-RID
        DUP -1 = IF DROP LIBSTORE-S-NOT-FOUND EXIT THEN
    _LIBMU-READ-ENTRY DUP IF EXIT THEN DROP
    _LIBMU-FOUND-ENTRY LIB-ENTRY-SIZE
        _LIBMU-ENTRY LIB-ENTRY-SIZE COMPARE IF
        LIBSTORE-S-NOT-FOUND EXIT
    THEN
    LIBSTORE-S-OK ;

: _LIBMU-RELOAD-AND-MATCH-COLLECTION  ( -- status )
    _LIBMU-STORE @ LIBRARY-VFS-STORE-BLOCKED? IF
        _LIBMU-REOPEN-BLOCKED-STORE
    ELSE
        _LIBMU-REFRESH
    THEN
    DUP IF EXIT THEN DROP
    _LIBMU-COLLECTION LIBC.ID _LIBMU-FIND-COLLECTION-RID
        DUP -1 = IF DROP LIBSTORE-S-NOT-FOUND EXIT THEN
    _LIBMU-READ-COLLECTION DUP IF EXIT THEN DROP
    _LIBMU-FOUND-COLLECTION LIB-COLLECTION-SIZE
        _LIBMU-COLLECTION LIB-COLLECTION-SIZE COMPARE IF
        LIBSTORE-S-NOT-FOUND EXIT
    THEN
    LIBSTORE-S-OK ;

: _LIBMU-RECONCILE-CANDIDATE  ( -- status )
    _LIBMU-COMMIT-MODE @ CASE
        _LIBMU-COMMIT-ENTRY-KEY OF _LIBMU-RELOAD-AND-FIND-KEY ENDOF
        _LIBMU-COMMIT-ENTRY-EXACT OF _LIBMU-RELOAD-AND-MATCH-ENTRY ENDOF
        _LIBMU-COMMIT-COLLECTION-EXACT OF
            _LIBMU-RELOAD-AND-MATCH-COLLECTION
        ENDOF
        LIBSTORE-S-RECOVERY SWAP
    ENDCASE ;

: _LIBMU-COMMIT-PREPARED  ( -- status )
    _LIBMU-STAGE-BEFORE-HEAD _LIBMU-CHECKPOINT DUP IF EXIT THEN DROP
    _LIBMU-HEAD-FACT _LIBMU-STORE @ LIBRARY-VFS-STORE.GENERATION @
        _LIBMU-STORE @ _LIBRARY-VFS-STORE-SAVE-HEAD
    DUP LIBSTORE-S-OK <> IF
        _LIBMU-ORIGINAL-STATUS !
        _LIBMU-STORE @ LIBRARY-VFS-STORE-LAST-VFSNAP@
            _LIBMU-ORIGINAL-VFSNAP !
        _LIBMU-STORE @ LIBRARY-VFS-STORE-LAST-VREPL@
            _LIBMU-ORIGINAL-VREPL !
        _LIBMU-RECONCILE-CANDIDATE DUP LIBSTORE-S-OK = IF
            DROP LIBSTORE-S-OK EXIT
        THEN
        DUP LIBSTORE-S-NOT-FOUND = IF
            DROP
            _LIBMU-ORIGINAL-VFSNAP @
                _LIBMU-STORE @ LIBRARY-VFS-STORE.LAST-VFSNAP !
            _LIBMU-ORIGINAL-VREPL @
                _LIBMU-STORE @ LIBRARY-VFS-STORE.LAST-VREPL !
            _LIBMU-ORIGINAL-STATUS @ EXIT
        THEN
        EXIT
    THEN
    DROP
    _LIBMU-RECONCILE-CANDIDATE DUP IF EXIT THEN DROP
    _LIBMU-STAGE-AFTER-HEAD _LIBMU-CHECKPOINT ;
