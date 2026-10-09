\ =====================================================================
\  sandbox-schema.f - The schemas a sandbox module may declare
\ =====================================================================
\  A module's entry schemas are ordinary interoperability schemas in
\  their canonical bytes (schema-bytes.f).  They may use only the types a
\  sandbox value carries (sandbox-value.f), and a schema's identity is
\  the SHA3-256 digest of its bytes in the sandbox schema domain.
\ =====================================================================

PROVIDED akashic-sbcs

REQUIRE schema-bytes.f
REQUIRE ../../sandbox/digest.f

\ NULL, BOOL, INT, STRING, BYTES, LIST and MAP, which the value bridge
\ carries as NULL, BOOL, I64, UTF8, BYTES, LIST and MAP.
CV-T-NULL CS-TYPE-BIT CV-T-BOOL CS-TYPE-BIT OR CV-T-INT CS-TYPE-BIT OR
CV-T-STRING CS-TYPE-BIT OR CV-T-BYTES CS-TYPE-BIT OR
CV-T-LIST CS-TYPE-BIT OR CV-T-MAP CS-TYPE-BIT OR
CONSTANT SBCS-TYPE-MASK

: SBCS-MEASURE  ( document document-u -- storage-u ior )
    SBCS-TYPE-MASK CSB-MEASURE ;

: SBCS-DECODE  ( document document-u storage storage-u -- schema|0 ior )
    2>R SBCS-TYPE-MASK 2R> CSB-DECODE ;

\ Admits DOCUMENT as a sandbox schema and writes its 32-byte digest.
\ WORKSPACE is SBOX-DIGEST-WORKSPACE-SIZE bytes, cell-aligned.
: SBCS-DIGEST  ( document document-u digest workspace -- ior )
    2>R 2DUP SBCS-MEASURE NIP ?DUP IF
        >R 2DROP 2R> 2DROP R> EXIT
    THEN
    2R> SBOX-DIGEST-SCHEMA IF CSB-E-INVALID ELSE 0 THEN ;
