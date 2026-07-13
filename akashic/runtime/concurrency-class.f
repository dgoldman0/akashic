\ =====================================================================
\  concurrency-class.f - Execution ownership classes
\ =====================================================================
\  A concurrency class describes where an operation may execute.  It is
\  not authority, export status, scheduling policy, or an effect mask.
\  Those contracts remain independent.
\ =====================================================================

PROVIDED akashic-runtime-concurrency-class

0 CONSTANT CCLASS-UNSPECIFIED
1 CONSTANT CCLASS-PURE
2 CONSTANT CCLASS-SNAPSHOT-READ
3 CONSTANT CCLASS-CONTEXT-LOCAL
4 CONSTANT CCLASS-OWNER-COMMIT
5 CONSTANT CCLASS-EXCLUSIVE-BUFFER
6 CONSTANT CCLASS-SERIALIZED-SERVICE
7 CONSTANT CCLASS-CORE-AFFINE
8 CONSTANT CCLASS-EXTERNAL
9 CONSTANT CCLASS-UNSAFE-NATIVE

: CCLASS-VALID?  ( class -- flag )
    DUP CCLASS-PURE >= SWAP CCLASS-UNSAFE-NATIVE <= AND ;

: CCLASS-WORKER?  ( class -- flag )
    DUP CCLASS-PURE =
    OVER CCLASS-SNAPSHOT-READ = OR
    SWAP CCLASS-EXCLUSIVE-BUFFER = OR ;

: CCLASS-OWNER-ONLY?  ( class -- flag )
    DUP CCLASS-CONTEXT-LOCAL =
    OVER CCLASS-OWNER-COMMIT = OR
    OVER CCLASS-CORE-AFFINE = OR
    SWAP CCLASS-UNSAFE-NATIVE = OR ;
