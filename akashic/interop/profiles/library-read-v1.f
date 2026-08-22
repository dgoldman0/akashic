\ =====================================================================
\ library-read-v1.f - neutral Library read-profile wire contract
\ =====================================================================
\ This module contains only frozen public names and encoding bounds.  It is
\ deliberately below both Library and Streams: a transport profile can name
\ the public Library capabilities without importing Library's controller,
\ service, persistence, or product composition.
\ =====================================================================

PROVIDED akashic-profile-library-read-v1

\ One selector carries exactly one LIST/query and one FETCH/read route.
: LIBRARY-READ-V1-RABBIT-SELECTOR$  ( -- address length )
    S" /v1/library/documents" ;

: LIBRARY-READ-V1-QUERY-CAPABILITY$  ( -- address length )
    S" library.document.query" ;

: LIBRARY-READ-V1-READ-CAPABILITY$  ( -- address length )
    S" library.document.read" ;

2  CONSTANT LIBRARY-READ-V1-RABBIT-ROUTE-COUNT
51 CONSTANT LIBRARY-READ-V1-RABBIT-ROUTE-ARENA-MIN
2  CONSTANT LIBRARY-READ-V1-QUERY-WIRE-FIELD-COUNT
2  CONSTANT LIBRARY-READ-V1-READ-WIRE-FIELD-COUNT

\ The peer supplies only these reduced maps.  The server-side profile injects
\ collection, collection_domain_revision, and request_digest from the sealed
\ graph specification before dispatching the complete Library capability.
\ These maxima are derived from the borrowed canonical child schemas: query
\ `{after,limit}` and read `{resource,domain_revision}` respectively.
1917 CONSTANT LIBRARY-READ-V1-QUERY-WIRE-PLAIN-MAX
713  CONSTANT LIBRARY-READ-V1-READ-WIRE-PLAIN-MAX

\ Complete public capability maps, not the reduced Rabbit request bodies.
\ Semantic maxima use Library's canonical R0, lowercase H64, and managed
\ media invariants.  Schema-wide maxima include worst-case JSON escaping.
702  CONSTANT LIBRARY-DOCUMENT-QUERY-REQUEST-SEMANTIC-PLAIN-MAX
819  CONSTANT LIBRARY-DOCUMENT-QUERY-REQUEST-SEMANTIC-TYPED-MAX
3046 CONSTANT LIBRARY-DOCUMENT-QUERY-REQUEST-SCHEMA-PLAIN-MAX
3163 CONSTANT LIBRARY-DOCUMENT-QUERY-REQUEST-SCHEMA-TYPED-MAX

35072 CONSTANT LIBRARY-DOCUMENT-QUERY-RESULT-SEMANTIC-PLAIN-MAX
37430 CONSTANT LIBRARY-DOCUMENT-QUERY-RESULT-SEMANTIC-TYPED-MAX
67912 CONSTANT LIBRARY-DOCUMENT-QUERY-RESULT-SCHEMA-PLAIN-MAX
70270 CONSTANT LIBRARY-DOCUMENT-QUERY-RESULT-SCHEMA-TYPED-MAX

386  CONSTANT LIBRARY-DOCUMENT-READ-REQUEST-SEMANTIC-PLAIN-MAX
447  CONSTANT LIBRARY-DOCUMENT-READ-REQUEST-SEMANTIC-TYPED-MAX
1842 CONSTANT LIBRARY-DOCUMENT-READ-REQUEST-SCHEMA-PLAIN-MAX
1903 CONSTANT LIBRARY-DOCUMENT-READ-REQUEST-SCHEMA-TYPED-MAX

393750 CONSTANT LIBRARY-DOCUMENT-READ-RESULT-SEMANTIC-PLAIN-MAX
393852 CONSTANT LIBRARY-DOCUMENT-READ-RESULT-SEMANTIC-TYPED-MAX
395605 CONSTANT LIBRARY-DOCUMENT-READ-RESULT-SCHEMA-PLAIN-MAX
395707 CONSTANT LIBRARY-DOCUMENT-READ-RESULT-SCHEMA-TYPED-MAX
