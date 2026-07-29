#!/usr/bin/env python3
"""Static qualification for the generic RID-addressed credential vault."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
PROJECT = LOCAL_TESTING.parent
SOURCE = PROJECT / "akashic" / "security" / "credential-vault.f"
DOC = PROJECT / "docs" / "security" / "credential-vault.md"
IDENTITY = PROJECT / "akashic" / "runtime" / "identity.f"
SEALED_RECORD = PROJECT / "akashic" / "security" / "sealed-record.f"
MEMORY_SPAN = PROJECT / "akashic" / "utils" / "memory-span.f"
CHECKED_RECORD = PROJECT / "akashic" / "utils" / "checked-record.f"
VFS_REPLACE = PROJECT / "akashic" / "utils" / "fs" / "vfs-replace.f"
VFS_SNAPSHOT = (
    PROJECT / "akashic" / "utils" / "fs" / "vfs-fixed-snapshot.f"
)
LIFECYCLE_DEPS = LOCAL_TESTING / "cv-deps.f"
LIFECYCLE_FIXTURE = LOCAL_TESTING / "cv-life.f"


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing definition for {name}"
    return match.group("body")


def _flat(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def _decimal_constant(source: str, name: str) -> int:
    match = re.search(
        rf"(?m)^[ \t]*(\d+)[ \t]+CONSTANT[ \t]+{re.escape(name)}$",
        source,
    )
    assert match is not None, f"missing decimal constant {name}"
    return int(match.group(1))


def _ordered(body: str, *markers: str) -> None:
    position = -1
    for marker in markers:
        position = body.index(marker, position + 1)


def _assert_dependencies_and_boundary(source: str, doc: str) -> None:
    provided = re.search(r"(?m)^PROVIDED[ \t]+(\S+)$", source)
    assert provided is not None
    assert provided.group(1) == "akashic-cred-vault"
    assert len(provided.group(1)) <= 23

    requirements = re.findall(
        r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source
    )
    assert requirements == [
        "sealed-record.f",
        "../runtime/identity.f",
        "../math/entropy.f",
        "../utils/fs/vfs-fixed-snapshot.f",
        "../utils/memory-span.f",
        "../utils/caller-span.f",
        "../concurrency/guard.f",
    ]
    requirement_text = "\n".join(requirements).lower()
    for forbidden in (
        "oauth",
        "atproto",
        "streams",
        "tui",
        "prompt",
        "session",
        "xrpc",
    ):
        assert forbidden not in requirement_text
    forth_code = "\n".join(
        line.split("\\", 1)[0] for line in source.splitlines()
    ).lower()
    for forbidden_symbol in (
        "oauth",
        "atproto",
        "streams",
        "xrpc",
        "session.f",
    ):
        assert forbidden_symbol not in forth_code

    boundary = (
        "module owns no OAuth, AT Protocol, Streams, UI, prompt, or root key"
    )
    assert boundary in source
    flat_doc = _flat(doc)
    assert (
        "The library owns no OAuth, AT Protocol, PDS, Streams, account, "
        "prompt, UI, or credential interpretation."
    ) in flat_doc
    assert "kind is an application-defined positive cell" in doc.replace(
        "`", ""
    )

    creates = set(
        re.findall(r"(?mi)^[ \t]*CREATE[ \t]+(\S+)", source)
    )
    assert creates == {
        "_CV-PRIVATE-BEGIN",
        "_CV-PRIVATE-LIMIT",
        "_CV-FRAME",
        "_CV-FRAME-VAULT",
        "_CV-FRAME-ACTIVE",
        "_CV-CALLBACK-DEPTH",
        "_CV-VFS-OLD",
        "_CV-VFS-TARGET",
        "_CV-VFS-OLD-CWD",
        "_CV-VFS-SELECTED",
        "_CV-DIR-ROOT-INODE",
        "_CV-DIR-SHARD1-INODE",
        "_CV-DIR-SHARD2-INODE",
        "_CV-VFS-MAGIC",
    }
    assert not re.search(
        r"(?mi)^[ \t]*(?:VARIABLE|VALUE|DEFER)\b", source
    )


def _assert_statuses_and_public_api(source: str, doc: str) -> None:
    statuses = (
        "OK",
        "INVALID",
        "CAPACITY",
        "ABSENT",
        "REVOKED",
        "CONFLICT",
        "LOCKED",
        "CALLBACK",
        "ENTROPY",
        "CRYPTO",
        "AUTH",
        "CORRUPT",
        "UNSUPPORTED",
        "IO",
        "RECOVERY",
        "BUSY",
        "ROLLBACK",
        "RANGE",
        "PROTECTED",
        "PLATFORM",
        "INTERNAL",
    )
    for value, suffix in enumerate(statuses):
        name = f"CVAULT-S-{suffix}"
        assert re.search(
            rf"(?m)^{value}[ \t]+CONSTANT[ \t]+{name}$", source
        )
        assert name in doc

    status_valid = _word_body(source, "CVAULT-STATUS-VALID?")
    assert "CVAULT-S-OK >=" in status_valid
    assert "CVAULT-S-INTERNAL <=" in status_valid
    assert re.search(
        r"(?m)^1 CONSTANT CVAULT-STATE-PRESENT$", source
    )
    assert re.search(
        r"(?m)^2 CONSTANT CVAULT-STATE-TOMBSTONE$", source
    )

    config_accessors = {
        "CVAULT-C.ROOT": "_CVC-ROOT +",
        "CVAULT-C.ROOT-U": "_CVC-ROOT-U +",
        "CVAULT-C.SECRET-CAPACITY": "_CVC-SECRET-CAP +",
        "CVAULT-C.BACKING": "_CVC-BACKING +",
        "CVAULT-C.BACKING-U": "_CVC-BACKING-U +",
        "CVAULT-C.VFS": "_CVC-VFS +",
        "CVAULT-C.VAULT-ID": "_CVC-VAULT-ID +",
        "CVAULT-C.KEY-ID": "_CVC-KEY-ID +",
        "CVAULT-C.RESOLVER-XT": "_CVC-RESOLVER-XT +",
        "CVAULT-C.RESOLVER-CONTEXT": "_CVC-RESOLVER-CONTEXT +",
        "CVAULT-C.FLOOR-READ-XT": "_CVC-FLOOR-READ-XT +",
        "CVAULT-C.FLOOR-ADVANCE-XT": "_CVC-FLOOR-ADVANCE-XT +",
        "CVAULT-C.FLOOR-CONTEXT": "_CVC-FLOOR-CONTEXT +",
    }
    for accessor, expression in config_accessors.items():
        body = _word_body(source, accessor)
        assert "config -- a" in _flat(body)
        assert expression in _flat(body)
        assert accessor in doc

    public = {
        "CVAULT-CONFIG-CLEAR": (
            "_CVAULT-CONFIG-CLEAR",
            "_cvault-config-clear-xt",
            "config -- status",
        ),
        "CVAULT-INIT": (
            "_CVAULT-INIT",
            "_cvault-init-xt",
            "config vault -- status",
        ),
        "CVAULT-FINI": (
            "_CVAULT-FINI",
            "_cvault-fini-xt",
            "vault -- status",
        ),
        "CVAULT-RID-NEW": (
            "_CVAULT-RID-NEW",
            "_cvault-rid-new-xt",
            "destination vault -- status",
        ),
        "CVAULT-CREATE": (
            "_CVAULT-CREATE",
            "_cvault-create-xt",
            "rid kind secret-a secret-u vault -- generation status",
        ),
        "CVAULT-REPLACE": (
            "_CVAULT-REPLACE",
            "_cvault-replace-xt",
            (
                "rid expected-generation secret-a secret-u vault "
                "-- generation status"
            ),
        ),
        "CVAULT-REVOKE": (
            "_CVAULT-REVOKE",
            "_cvault-revoke-xt",
            "rid expected-generation vault -- generation status",
        ),
        "CVAULT-METADATA": (
            "_CVAULT-METADATA",
            "_cvault-metadata-xt",
            "rid vault -- generation state kind secret-u status",
        ),
        "CVAULT-WITH": (
            "_CVAULT-WITH",
            "_cvault-with-xt",
            (
                "rid consumer-xt consumer-context vault "
                "-- generation kind consumer-result status"
            ),
        ),
        "CVAULT-RECOVER": (
            "_CVAULT-RECOVER",
            "_cvault-recover-xt",
            "expected-rid vault -- generation state status",
        ),
        "CVAULT-PATH": (
            "_CVAULT-PATH",
            "_cvault-path-xt",
            "rid destination capacity vault -- written status",
        ),
        "CVAULT-VALID?": (
            "_CVAULT-VALID?",
            "_cvault-valid-xt",
            "vault -- flag",
        ),
        "CVAULT-BLOCKED?": (
            "_CVAULT-BLOCKED?",
            "_cvault-blocked-xt",
            "vault -- flag",
        ),
        "CVAULT-LAST-STATUS@": (
            "_CVAULT-LAST-STATUS@",
            "_cvault-last-status-xt",
            "vault -- status",
        ),
        "CVAULT-SECRET-CAPACITY@": (
            "_CVAULT-SECRET-CAPACITY@",
            "_cvault-secret-capacity-xt",
            "vault -- secret-capacity status",
        ),
        "CVAULT-EXTERNAL-SPAN-STATUS": (
            "_CVAULT-EXTERNAL-SPAN-STATUS",
            "_cvault-external-span-status-xt",
            "address length vault -- status",
        ),
    }
    for word, (internal, capture, stack) in public.items():
        assert re.search(
            rf"(?m)^'[ \t]+{re.escape(internal)}[ \t]+"
            rf"CONSTANT[ \t]+{re.escape(capture)}$",
            source,
        )
        body = _word_body(source, word)
        flat = _flat(body)
        assert stack in flat
        assert (
            f"{capture} _credential-vault-guard WITH-GUARD" in flat
        )
        assert flat.count("WITH-GUARD") == 1
        assert word in doc

    external_span = _word_body(
        source, "_CVAULT-EXTERNAL-SPAN-STATUS"
    )
    for required in (
        "_CV-ADMIT-SPAN",
        "_CVAULT-VALID?",
        "_CV-F-BUSY",
        "CVAULT-S-BUSY",
        "CVAULT-SIZE MSPAN-OVERLAP?",
        "_CV.BACKING @",
        "_CV.BACKING-U @",
        "_CV.VFS @ VFS-DESC-SIZE MSPAN-OVERLAP?",
        "_CV-ALL-PRIVATE-ALIASES?",
    ):
        assert required in external_span
    assert external_span.count("CVAULT-S-INVALID") >= 4
    assert external_span.count("MSPAN-OVERLAP?") == 3


def _assert_geometry(
    source: str,
    identity: str,
    sealed: str,
    memory_span: str,
    checked: str,
    replace: str,
    snapshot: str,
    doc: str,
) -> None:
    # Dependency geometry is read from its real defining source, while every
    # composite size below is calculated independently here.
    rid_size = _decimal_constant(identity, "RID-SIZE")
    sealed_descriptor_size = _decimal_constant(
        sealed, "SEALED-RECORD-DESCRIPTOR-SIZE"
    )
    sealed_header_size = _decimal_constant(
        sealed, "SEALED-RECORD-HEADER-SIZE"
    )
    sealed_tag_size = _decimal_constant(
        sealed, "SEALED-RECORD-TAG-SIZE"
    )
    sealed_overhead = _decimal_constant(
        sealed, "SEALED-RECORD-OVERHEAD"
    )
    sealed_data_max = _decimal_constant(
        sealed, "SEALED-RECORD-DATA-MAX"
    )
    sealed_size_max = _decimal_constant(
        sealed, "SEALED-RECORD-SIZE-MAX"
    )
    mspan_header_size = _decimal_constant(
        memory_span, "MSPAN-SET-HEADER-SIZE"
    )
    mspan_entry_size = _decimal_constant(
        memory_span, "MSPAN-SET-ENTRY-SIZE"
    )
    crec_header_size = _decimal_constant(checked, "CREC-HEADER-SIZE")
    crec_spec_size = _decimal_constant(checked, "CREC-SPEC-SIZE")
    crec_work_size = _decimal_constant(checked, "CREC-WORK-SIZE")
    vrepl_size = _decimal_constant(replace, "VREPL-SIZE")
    private_max = _decimal_constant(
        snapshot, "VFSNAP-SPEC-PRIVATE-MAX"
    )

    assert rid_size == 32
    assert sealed_descriptor_size == 80
    assert sealed_header_size == 160
    assert sealed_tag_size == 16
    assert sealed_overhead == sealed_header_size + sealed_tag_size == 176
    assert sealed_data_max == 65536
    assert sealed_size_max == sealed_data_max + sealed_overhead == 65712
    assert mspan_header_size == mspan_entry_size == 16
    assert crec_header_size == 64
    assert crec_spec_size == 112
    assert crec_work_size == 136
    assert vrepl_size == 1152
    assert private_max == 16

    private_set_size = mspan_header_size + private_max * mspan_entry_size
    vfs_spec_crec_offset = 56 + private_set_size
    vfs_spec_size = vfs_spec_crec_offset + crec_spec_size
    vfs_store_crec_offset = vrepl_size + 10 * 8
    vfs_context_size = 56
    vfs_store_size = (
        vfs_store_crec_offset + crec_work_size + vfs_context_size
    )
    assert private_set_size == 272
    assert vfs_spec_crec_offset == 328
    assert vfs_spec_size == 440
    assert vfs_store_crec_offset == 1232
    assert vfs_store_size == 1424

    spec_layout = _flat(snapshot)
    assert (
        "_VFSNS-PRIVATE-SET VFSNAP-SPEC-PRIVATE-MAX "
        "MSPAN-SET-BYTES + CONSTANT _VFSNS-CREC-SPEC"
    ) in spec_layout
    assert (
        "_VFSNS-CREC-SPEC CREC-SPEC-SIZE + "
        "CONSTANT VFSNAP-SPEC-SIZE"
    ) in spec_layout
    assert (
        "_VFSND-RESTORE-XT 8 + CONSTANT _VFSND-CREC-WORK"
    ) in spec_layout
    assert (
        "_VFSND-CREC-WORK CREC-WORK-SIZE + "
        "CONSTANT _VFSND-CREC-CONTEXT"
    ) in spec_layout
    assert (
        "_VFSND-CREC-CONTEXT _VFSNAP-CREC-CONTEXT-SIZE + "
        "CONSTANT VFSNAP-STORE-SIZE"
    ) in spec_layout

    plaintext_header_size = _decimal_constant(
        source, "CVAULT-PLAINTEXT-HEADER-SIZE"
    )
    root_max = _decimal_constant(source, "CVAULT-ROOT-MAX")
    path_capacity = _decimal_constant(source, "_CV-PATH-CAP")
    secret_capacity_max = sealed_data_max - plaintext_header_size
    assert plaintext_header_size == 128
    assert root_max == 187
    assert path_capacity == 256
    assert secret_capacity_max == 65408
    assert (
        "SEALED-RECORD-DATA-MAX CVAULT-PLAINTEXT-HEADER-SIZE - "
        "CONSTANT CVAULT-SECRET-CAPACITY-MAX"
    ) in _flat(source)

    # The sealed-record workspace is independently expanded from its checked
    # component geometry; this value is deliberately not imported from the
    # vault's own backing-size expression.
    sealed_workspace_size = 66568
    assert (
        "_SR-W-AES-WORKSPACE AES-GCM-WORKSPACE-SIZE + "
        "CONSTANT SEALED-RECORD-WORKSPACE-SIZE"
    ) in _flat(sealed)

    def plaintext_size(capacity: int) -> int:
        return capacity + plaintext_header_size

    def record_size(capacity: int) -> int:
        return plaintext_size(capacity) + sealed_overhead

    def backing_size(capacity: int) -> int:
        plain = plaintext_size(capacity)
        record = record_size(capacity)
        return plain + 2 * record + crec_header_size + sealed_workspace_size

    for capacity in (1, 32, 4096, secret_capacity_max):
        assert plaintext_size(capacity) == capacity + 128
        assert record_size(capacity) == capacity + 304
        assert backing_size(capacity) == (
            capacity + 128
            + 2 * (capacity + 304)
            + 64
            + 66568
        )
    assert plaintext_size(secret_capacity_max) == sealed_data_max
    assert record_size(secret_capacity_max) == sealed_size_max

    plaintext_body = _word_body(source, "CVAULT-PLAINTEXT-SIZE")
    record_body = _word_body(source, "CVAULT-RECORD-SIZE")
    backing_body = _word_body(source, "CVAULT-BACKING-SIZE")
    assert "secret-capacity -- plaintext-u|0" in _flat(plaintext_body)
    assert "secret-capacity -- record-u|0" in _flat(record_body)
    assert "secret-capacity -- backing-u|0" in _flat(backing_body)
    assert "CVAULT-SECRET-CAPACITY-MAX U>" in plaintext_body
    assert "CVAULT-PLAINTEXT-HEADER-SIZE +" in plaintext_body
    assert "CVAULT-PLAINTEXT-SIZE" in record_body
    assert "SEALED-RECORD-SIZE" in record_body
    assert "DUP SEALED-RECORD-SIZE 2* +" in _flat(backing_body)
    assert "VFSNAP-HEADER-SIZE +" in backing_body
    assert "SEALED-RECORD-WORKSPACE-SIZE +" in backing_body

    config_offsets = (
        ("_CVC-ROOT", 0),
        ("_CVC-ROOT-U", 8),
        ("_CVC-SECRET-CAP", 16),
        ("_CVC-BACKING", 24),
        ("_CVC-BACKING-U", 32),
        ("_CVC-VFS", 40),
        ("_CVC-VAULT-ID", 48),
        ("_CVC-KEY-ID", 56),
        ("_CVC-RESOLVER-XT", 64),
        ("_CVC-RESOLVER-CONTEXT", 72),
        ("_CVC-FLOOR-READ-XT", 80),
        ("_CVC-FLOOR-ADVANCE-XT", 88),
        ("_CVC-FLOOR-CONTEXT", 96),
        ("CVAULT-CONFIG-SIZE", 104),
    )
    for name, value in config_offsets:
        assert _decimal_constant(source, name) == value

    vault_id_offset = _decimal_constant(source, "_CV-VAULT-ID")
    key_id_offset = vault_id_offset + rid_size
    active_rid_offset = key_id_offset + rid_size
    binding_id_offset = active_rid_offset + rid_size
    seal_key_id_offset = binding_id_offset + rid_size
    seal_record_id_offset = seal_key_id_offset + rid_size
    root_offset = seal_record_id_offset + rid_size
    shard1_offset = (root_offset + root_max + 7) & -8
    shard2_offset = shard1_offset + path_capacity
    target_offset = shard2_offset + path_capacity
    sealed_descriptor_offset = target_offset + path_capacity
    vfs_spec_offset = sealed_descriptor_offset + sealed_descriptor_size
    vfs_store_offset = vfs_spec_offset + vfs_spec_size
    vault_size = vfs_store_offset + vfs_store_size

    assert vault_id_offset == 384
    assert (
        key_id_offset,
        active_rid_offset,
        binding_id_offset,
        seal_key_id_offset,
        seal_record_id_offset,
        root_offset,
    ) == (416, 448, 480, 512, 544, 576)
    assert (
        shard1_offset,
        shard2_offset,
        target_offset,
        sealed_descriptor_offset,
        vfs_spec_offset,
        vfs_store_offset,
        vault_size,
    ) == (768, 1024, 1280, 1536, 1616, 2056, 3480)

    layout = _flat(source)
    for expression in (
        "_CV-VAULT-ID RID-SIZE + CONSTANT _CV-KEY-ID",
        "_CV-KEY-ID RID-SIZE + CONSTANT _CV-ACTIVE-RID",
        "_CV-ACTIVE-RID RID-SIZE + CONSTANT _CV-BINDING-ID",
        "_CV-BINDING-ID RID-SIZE + CONSTANT _CV-SEAL-KEY-ID",
        "_CV-SEAL-KEY-ID RID-SIZE + CONSTANT _CV-SEAL-RECORD-ID",
        "_CV-SEAL-RECORD-ID RID-SIZE + CONSTANT _CV-ROOT",
        "_CV-ROOT CVAULT-ROOT-MAX + 7 + -8 AND CONSTANT _CV-SHARD1",
        "_CV-SHARD1 _CV-PATH-CAP + CONSTANT _CV-SHARD2",
        "_CV-SHARD2 _CV-PATH-CAP + CONSTANT _CV-TARGET",
        "_CV-TARGET _CV-PATH-CAP + CONSTANT _CV-SEALED-DESCRIPTOR",
        (
            "_CV-SEALED-DESCRIPTOR SEALED-RECORD-DESCRIPTOR-SIZE + "
            "CONSTANT _CV-VFS-SPEC"
        ),
        "_CV-VFS-SPEC VFSNAP-SPEC-SIZE + CONSTANT _CV-VFS-STORE",
        "_CV-VFS-STORE VFSNAP-STORE-SIZE + CONSTANT CVAULT-SIZE",
    ):
        assert expression in layout

    assert "CVAULT-CONFIG-SIZE             ( -- 104 )" in doc
    assert "CVAULT-PLAINTEXT-HEADER-SIZE   ( -- 128 )" in doc
    assert "CVAULT-SECRET-CAPACITY-MAX     ( -- 65408 )" in doc
    assert "CVAULT-ROOT-MAX                ( -- 187 )" in doc


def _assert_paths_and_private_state(source: str, doc: str) -> None:
    assert "ROOT/<20 lowercase hex>/<22 lowercase hex>/<22 lowercase hex>" in (
        source
    )
    expected_doc_path = (
        "ROOT/<first 10 RID bytes as 20 hex>/<next 11 as 22 hex>/"
        "<last 11 as 22 hex>"
    )
    assert expected_doc_path in doc

    build = _word_body(source, "_CV-BUILD-PATHS")
    _ordered(
        build,
        "_CV.ACTIVE-RID 10 ",
        "_CV.ACTIVE-RID 10 + 11 ",
        "_CV.ACTIVE-RID 21 + 11 ",
    )
    assert build.count("_CV-HEX!") == 3
    assert build.count("20 +") == 1
    assert build.count("22 +") == 2

    write = _word_body(source, "_CV-PATH-WRITE")
    _ordered(
        write,
        "2 PICK 10 ",
        "2 PICK 10 + 11 ",
        "2 PICK 21 + 11 ",
    )
    assert write.count("_CV-HEX!") == 3
    assert write.count("_CV-PATH-SLASH") == 3
    assert not re.search(r"(?m)(?:^|\s)0\s+\S+\s+C!", write)

    nibble = _word_body(source, "_CV-NIBBLE>LOWER")
    assert "15 AND" in nibble
    assert "10 < IF 48 + ELSE 87 +" in _flat(nibble)
    target_length = _word_body(source, "_CV-TARGET-LENGTH")
    assert "DUP 1 <> IF 1+ THEN" in _flat(target_length)
    assert "66 +" in target_length
    assert 187 + 67 == 254
    assert "CVAULT-ROOT-MAX 67 + 255 U> [IF]" in source
    assert "the longest path is 254 bytes" in doc
    assert "without appending a NUL byte" in doc

    public_path = _word_body(source, "_CVAULT-PATH")
    _ordered(
        public_path,
        "_CV-VAULT-SHAPE?",
        "_CV-F-BUSY",
        "_CV-RID-PREFLIGHT",
        "_CV-ADMIT-SPAN",
        "_CV-TARGET-LENGTH",
        "_CV-PATH-OUTPUT-ALIASES?",
        "_CV-PATH-WRITE",
    )

    assert re.search(
        r"(?m)^CREATE _CV-PRIVATE-BEGIN 0 ALLOT$", source
    )
    assert re.search(
        r"(?m)^CREATE _CV-PRIVATE-LIMIT 0 ,$", source
    )
    assert "_CV-PRIVATE-END" not in source
    assert source.rstrip().endswith("HERE _CV-PRIVATE-LIMIT !")

    private_length = _word_body(source, "_CV-PRIVATE-LENGTH")
    assert (
        "_CV-PRIVATE-LIMIT @ _CV-PRIVATE-BEGIN -" in _flat(private_length)
    )
    all_private = _word_body(source, "_CV-ALL-PRIVATE-ALIASES?")
    _ordered(
        all_private,
        "_VFSNAP-DEPENDENCY-ALIASES?",
        "_S256-LOCAL-RESERVED-OVERLAP?",
        "_aes-gcm-guard GUARD-SPIN-SIZE MSPAN-OVERLAP?",
        "_CV-PRIVATE-ALIASES?",
    )
    assert all_private.count("2DROP -1 EXIT") == 3

    spec_init = _word_body(source, "_CV-SPEC-INIT")
    _ordered(
        spec_init,
        "VFSNAP-SPEC-INIT",
        "_CV-PRIVATE-BEGIN _CV-PRIVATE-LENGTH",
        "VFSNAP-SPEC-PRIVATE-ADD",
        "VFSNAP-SPEC-SEAL",
    )
    private_exact = _word_body(source, "_CV-SPEC-PRIVATE-EXACT?")
    assert "MSPAN-SET-COUNT@ 1 <>" in private_exact
    assert "_CV-PRIVATE-BEGIN =" in private_exact
    assert "_CV-PRIVATE-LENGTH = AND" in private_exact

    private_admission_words = (
        "_CV-CONFIG-PRIVATE-ALIASES?",
        "_CV-VAULT-SHAPE?",
        "_CV-RID-ALIASES?",
        "_CV-PATH-OUTPUT-ALIASES?",
        "_CV-SECRET-PREFLIGHT",
        "_CVAULT-CONFIG-CLEAR",
    )
    for word in private_admission_words:
        assert "_CV-ALL-PRIVATE-ALIASES?" in _word_body(source, word)
    assert source.count("_CV-ALL-PRIVATE-ALIASES?") >= 14


def _assert_spec_store_identity(source: str) -> None:
    spec = _word_body(source, "_CV-SPEC-IDENTITY?")
    _ordered(
        spec,
        "VFSNAP-SPEC-SEALED?",
        "VFSNAP-SPEC.RECORD-MAGIC",
        "_CV-VFS-MAGIC 8 COMPARE",
        "VFSNAP-SPEC.FORMAT",
        "_CV-VFS-FORMAT <>",
        "VFSNAP-SPEC.PAYLOAD-U",
        "_CV.RECORD-U @ <>",
        "VFSNAP-SPEC.ENCODE-XT",
        "['] _CV-VFS-ENCODE <>",
        "VFSNAP-SPEC.VALIDATE-XT",
        "['] _CV-VFS-VALIDATE <>",
        "_CV-SPEC-PRIVATE-EXACT?",
    )

    store = _word_body(source, "_CV-STORE-IDENTITY?")
    for marker in (
        "VFSNAP.SPEC @",
        "_CV.VFS-SPEC <>",
        "VFSNAP.VFS @",
        "_CV.VFS @ <>",
        "VFSNAP.SCRATCH-A @",
        "_CV.VFS-SCRATCH",
        "VFSNAP.SCRATCH-U @",
        "_CV.VFS-SCRATCH-U",
        "VFSNAP.REPLACE VREPL.VFS @",
        "VFSNAP-VALID?",
        "VFSNAP-PATH$",
        "_CV.TARGET",
        "_CV.TARGET-U @",
        "COMPARE 0=",
    ):
        assert marker in store

    shape = _word_body(source, "_CV-VAULT-SHAPE?")
    assert shape.index("_CV-SPEC-IDENTITY?") < shape.index(
        "_CV.BACKING @"
    )
    store_active = shape.index("_CV-F-STORE-ACTIVE AND IF")
    assert store_active < shape.index("_CV-STORE-IDENTITY?", store_active)
    for marker in (
        "_CV-ALL-PRIVATE-ALIASES?",
        "CVAULT-BACKING-SIZE",
        "CVAULT-RECORD-SIZE",
        "CVAULT-PLAINTEXT-SIZE",
        "MSPAN-OVERLAP?",
        "CVAULT-STATUS-VALID?",
        "_CV-STATUS-BLOCKING?",
    ):
        assert marker in shape


def _assert_callback_containment(source: str, doc: str) -> None:
    begin = _word_body(source, "_CV-FRAME-BEGIN?")
    _ordered(
        begin,
        "_CV-FRAME-ACTIVE @",
        "_CV-FRAME-VAULT !",
        "_CV-FRAME CVAULT-SIZE MOVE",
        "_CV-FRAME-ACTIVE !",
    )
    intact = _word_body(source, "_CV-FRAME-INTACT?")
    assert "_CV-FRAME-ACTIVE @" in intact
    assert "_CV-FRAME-VAULT @ <>" in intact
    assert "CVAULT-SIZE _CV-FRAME CVAULT-SIZE COMPARE 0=" in _flat(
        intact
    )
    end = _word_body(source, "_CV-FRAME-END")
    _ordered(end, "_CV-FRAME-INTACT?", "_CV-FRAME-RESTORE", "_CV-FRAME-CLEAR")

    for word in (
        "_CV-ENCODE-SEAL",
        "_CV-OPEN-SEALED",
        "_CV-FLOOR-READ",
        "_CV-FLOOR-CATCH-UP",
        "_CV-CALL-CONSUMER",
        "_CV-TOPOLOGY",
    ):
        body = _word_body(source, word)
        assert body.count("_CV-FRAME-BEGIN?") == 1
        assert body.count("_CV-FRAME-END") == 1
        assert body.index("_CV-FRAME-BEGIN?") < body.index("_CV-FRAME-END")

    for word in (
        "_CV-OP-BEGIN",
        "_CV-RECOVER-BEGIN",
        "_CVAULT-INIT",
        "_CVAULT-FINI",
    ):
        body = _word_body(source, word)
        assert "_CV-FRAME-ACTIVE @" in body
        assert "CVAULT-S-BUSY EXIT" in _flat(body)
    assert "_CV-F-BUSY" in _word_body(source, "_CVAULT-PATH")

    assert re.search(
        r"(?m)^-3201 CONSTANT _CV-E-FLOOR-STACK$", source
    )
    assert re.search(
        r"(?m)^0x4356464C4F4F5231 CONSTANT _CV-FLOOR-CANARY", source
    )
    assert re.search(
        r"(?m)^-3202 CONSTANT _CV-E-CONSUMER-STACK$", source
    )
    assert re.search(
        r"(?m)^0x4356434F4E53554D CONSTANT _CV-CONSUMER-CANARY", source
    )

    floor_read = _word_body(source, "_CV-FLOOR-READ-INVOKE")
    for marker in (
        "DEPTH _CV-CALLBACK-DEPTH !",
        "_CV-FLOOR-CANARY",
        "DEPTH _CV-CALLBACK-DEPTH @ 4 + <>",
        "3 PICK _CV-FLOOR-CANARY <>",
        "2 PICK R@ <>",
        "_CV-E-FLOOR-STACK THROW",
    ):
        assert marker in floor_read

    floor_advance = _word_body(source, "_CV-FLOOR-ADVANCE-INVOKE")
    for marker in (
        "DEPTH _CV-CALLBACK-DEPTH !",
        "_CV-FLOOR-CANARY",
        "DEPTH _CV-CALLBACK-DEPTH @ 3 + <>",
        "2 PICK _CV-FLOOR-CANARY <>",
        "1 PICK R@ <>",
        "_CV-E-FLOOR-STACK THROW",
    ):
        assert marker in floor_advance

    consumer = _word_body(source, "_CV-CONSUMER-INVOKE")
    for marker in (
        "DEPTH _CV-CALLBACK-DEPTH !",
        "_CV-CONSUMER-CANARY",
        "DEPTH _CV-CALLBACK-DEPTH @ 3 + <>",
        "2 PICK _CV-CONSUMER-CANARY <>",
        "1 PICK R@ <>",
        "_CV-E-CONSUMER-STACK THROW",
    ):
        assert marker in consumer

    for word in (
        "_CV-SEALED-SEAL-SAFE",
        "_CV-SEALED-OPEN-SAFE",
        "_CV-FLOOR-READ-SAFE",
        "_CV-FLOOR-ADVANCE-SAFE",
        "_CV-CONSUMER-SAFE",
    ):
        assert "CATCH" in _word_body(source, word)
    call_consumer = _word_body(source, "_CV-CALL-CONSUMER")
    assert "DUP R@ _CV.CALLBACK-STATUS !" in call_consumer
    assert "stack-contract violation" in doc
    assert "module-wide recursive guard remains held" in doc


def _assert_entropy_floor_and_generations(source: str, doc: str) -> None:
    entropy_status = _word_body(source, "_CV-ENTROPY>STATUS")
    assert "CVAULT-S-PLATFORM SWAP" in _flat(entropy_status)
    entropy_call = _word_body(source, "_CV-RID-ENTROPY-CALL")
    assert (
        "RID-SIZE ENTROPY-FILL _CV-ENTROPY>STATUS"
        in _flat(entropy_call)
    )
    assert source.count("ENTROPY-FILL") == 1
    entropy_safe = _word_body(source, "_CV-RID-ENTROPY-SAFE")
    assert "['] _CV-RID-ENTROPY-CALL CATCH" in entropy_safe
    assert "RID-SIZE 0 FILL" in entropy_safe
    assert "CVAULT-S-ENTROPY" in entropy_safe
    assert "_CV-FINISH" in entropy_safe
    assert "THROW" in entropy_safe
    assert re.search(
        r"(?m)^8 CONSTANT _CV-RID-ENTROPY-ATTEMPTS$", source
    )

    rid_new = _word_body(source, "_CVAULT-RID-NEW")
    for marker in (
        "_CV-RID-ENTROPY-ATTEMPTS",
        "BEGIN",
        "_CV-RID-ENTROPY-SAFE",
        "RID-PRESENT?",
        "_CV.VAULT-ID RID= 0= AND",
        "_CV.EXPECTED +!",
        "UNTIL",
        "CVAULT-S-ENTROPY",
    ):
        assert marker in rid_new
    assert rid_new.count("RID-SIZE 0 FILL") >= 3
    for weak in (
        r"(?<![A-Za-z0-9_-])RANDOM(?![A-Za-z0-9_-])",
        r"(?<![A-Za-z0-9_-])RAND(?![A-Za-z0-9_-])",
        r"(?<![A-Za-z0-9_-])EPOCH@(?![A-Za-z0-9_-])",
        r"(?<![A-Za-z0-9_-])TICKS(?![A-Za-z0-9_-])",
        r"(?<![A-Za-z0-9_-])COREID(?![A-Za-z0-9_-])",
    ):
        assert not re.search(weak, rid_new, re.IGNORECASE)
    normalized_doc = _flat(doc.replace("`", ""))
    assert (
        "CVAULT-RID-NEW obtains all 32 RID bytes from ENTROPY-FILL"
        in normalized_doc
    )
    assert "There is no software random source" in doc
    assert "CVAULT-SECRET-CAPACITY@" in LIFECYCLE_FIXTURE.read_text(
        encoding="utf-8"
    )

    floor_status = _word_body(source, "_CV-FLOOR-STATUS-VALID?")
    assert "CVAULT-STATUS-VALID?" in floor_status
    assert "CVAULT-S-REVOKED <> AND" in _flat(floor_status)
    for word in ("_CV-FLOOR-READ-SAFE", "_CV-FLOOR-ADVANCE-SAFE"):
        assert "_CV-FLOOR-STATUS-VALID?" in _word_body(source, word)

    floor_read = _word_body(source, "_CV-FLOOR-READ")
    _ordered(
        floor_read,
        "_CV-FLOOR-STAGE-IDS",
        "_CV-FRAME-BEGIN?",
        "_CV-FLOOR-READ-SAFE",
        "_CV-FRAME-END",
        "_CV-FLOOR-STAGED-IDS-INTACT?",
        "_CV.FLOOR !",
        "_CV.GENERATION @ U>",
        "CVAULT-S-ROLLBACK",
    )
    catch_up = _word_body(source, "_CV-FLOOR-CATCH-UP")
    _ordered(
        catch_up,
        "_CV.GENERATION @ R@ _CV.FLOOR @ U<",
        "_CV.GENERATION @ R@ _CV.FLOOR @ =",
        "_CV-FLOOR-STAGE-IDS",
        "_CV-FRAME-BEGIN?",
        "_CV-FLOOR-ADVANCE-SAFE",
        "_CV-FRAME-END",
        "_CV-FLOOR-STAGED-IDS-INTACT?",
        "_CV.GENERATION @ R@ _CV.FLOOR !",
    )
    publish = _word_body(source, "_CV-FLOOR-PUBLISH")
    assert "_CV-FLOOR-CATCH-UP" in publish
    assert "CVAULT-S-ROLLBACK = IF NIP EXIT" in _flat(publish)
    assert "2DROP CVAULT-S-RECOVERY" in _flat(publish)

    advance_needed = _word_body(source, "_CV-FLOOR-ADVANCE-NEEDED?")
    assert "_CV-F-FLOOR AND 0=" in advance_needed
    assert "_CV.GENERATION @" in advance_needed
    assert "_CV.FLOOR @ U>" in advance_needed

    # Load order is security-sensitive: the outer generation is checked
    # against the floor, then the sealed record is authenticated before any
    # floor advance. If an advance is needed, parsed state is wiped before
    # the callback and the record is reopened afterward.
    load = _word_body(source, "_CV-LOAD-AUTHENTICATED")
    assert load.count("_CV-OPEN-SEALED") == 2
    first_open = load.index("_CV-OPEN-SEALED")
    second_open = load.rindex("_CV-OPEN-SEALED")
    _ordered(
        load,
        "_CV-LOAD-SEALED",
        "_CV-FLOOR-READ",
        "_CV-OPEN-SEALED",
        "_CV-FLOOR-ADVANCE-NEEDED? IF",
        "_CV-PARSED-WIPE",
        "_CV-FLOOR-PUBLISH",
    )
    assert first_open < load.index("_CV-FLOOR-PUBLISH") < second_open
    assert load.index("_CV-PARSED-WIPE") < load.index("_CV-FLOOR-PUBLISH")
    parsed_wipe = _word_body(source, "_CV-PARSED-WIPE")
    for marker in (
        "_CV.PLAIN R@ _CV.PLAIN-U @ 0 FILL",
        "0 R@ _CV.STATE !",
        "0 R@ _CV.KIND !",
        "0 R@ _CV.SECRET-U !",
    ):
        assert marker in parsed_wipe

    vfs_encode = _word_body(source, "_CV-VFS-ENCODE")
    _ordered(
        vfs_encode,
        "R@ 3 PICK _CV.RESULT-REVISION !",
        "_CV-BUILD-PLAINTEXT",
        "_CV-ENCODE-SEAL",
    )
    assert "R@ 2 PICK _CV.RESULT-REVISION !" not in vfs_encode
    save = _word_body(source, "_CV-SAVE")
    _ordered(
        save,
        "R@ SWAP R@ _CV.VFS-STORE VFSNAP-SAVE",
        "_CV.RESULT-REVISION @ R@ _CV.GENERATION !",
        "_CV-FLOOR-PUBLISH",
    )

    create = _word_body(source, "_CVAULT-CREATE")
    _ordered(
        create,
        "0 R@ _CV.GENERATION !",
        "_CV-FLOOR-READ",
        "0 R@ _CV-SAVE",
        "_CV-COMPLETE-GENERATION",
    )
    replace = _word_body(source, "_CVAULT-REPLACE")
    _ordered(
        replace,
        "2 PICK 0> 0=",
        "_CV.EXPECTED !",
        "_CV-LOAD-AUTHENTICATED",
        "_CV.GENERATION @ <>",
        "CVAULT-S-CONFLICT",
        "_CV.EXPECTED @ R@ _CV-SAVE",
    )
    revoke = _word_body(source, "_CVAULT-REVOKE")
    _ordered(
        revoke,
        "DUP 0> 0=",
        "_CV-LOAD-AUTHENTICATED",
        "_CV.GENERATION @ <>",
        "CVAULT-S-CONFLICT",
        "CVAULT-STATE-TOMBSTONE",
        "NIP",
        "_CV-SAVE",
    )
    complete = _word_body(source, "_CV-COMPLETE-GENERATION")
    assert "_CV-FINISH" in complete
    assert "DUP IF" in complete
    assert "R> DROP 0 SWAP" in complete

    for phrase in (
        "An unseen pair has floor zero",
        "before asking for the root key",
        "successful sealed-record authentication",
        "generation above the floor causes",
        "credential snapshot is made durable first",
        "A stale expected generation is CVAULT-S-CONFLICT",
        "Every returned failure has generation zero",
        "CVAULT-S-REVOKED, which is reserved exclusively for an authenticated",
    ):
        assert phrase in normalized_doc


def _assert_tombstone_recovery_and_wipes(source: str, doc: str) -> None:
    build = _word_body(source, "_CV-BUILD-PLAINTEXT")
    assert "CVAULT-STATE-PRESENT = IF" in build
    assert "ELSE 0 THEN" in _flat(build)
    assert build.count("CVAULT-STATE-PRESENT = IF") == 2
    assert "_CV.INPUT-U @ MOVE" in build

    validate = _word_body(source, "_CV-VALIDATE-PLAINTEXT")
    assert "CVAULT-STATE-PRESENT =" in validate
    assert "CVAULT-STATE-TOMBSTONE = OR" in validate
    assert "_CVP-SECRET-U + _CV-BE64@ 0= IF" in validate
    assert "_CVP-SECRET-U + _CV-BE64@ IF" in validate
    assert "_CV-ZERO? 0=" in validate
    assert (
        "DUP _CVP-VAULT-ID + RID-SIZE R@ _CV.VAULT-ID RID-SIZE COMPARE IF"
        in _flat(validate)
    )
    assert (
        "DUP _CVP-RID + RID-SIZE R@ _CV.ACTIVE-RID RID-SIZE COMPARE IF"
        in _flat(validate)
    )

    revoke = _word_body(source, "_CVAULT-REVOKE")
    _ordered(
        revoke,
        "CVAULT-STATE-TOMBSTONE R@ _CV.STATE !",
        "0 R@ _CV.INPUT !",
        "0 R@ _CV.INPUT-U !",
        "_CV-SAVE",
    )
    assert not re.search(
        r"(?mi)(?<![A-Za-z0-9_-])"
        r"(?:UNLINK|DELETE-FILE|VFS-(?:UNLINK|DELETE|REMOVE|RMDIR))"
        r"(?![A-Za-z0-9_-])",
        source,
    )
    load = _word_body(source, "_CV-LOAD-AUTHENTICATED")
    assert "CVAULT-STATE-TOMBSTONE =" in load
    assert "CVAULT-S-REVOKED" in load
    metadata = _word_body(source, "_CV-COMPLETE-METADATA")
    assert "CVAULT-S-REVOKED = OR" in metadata
    with_op = _word_body(source, "_CVAULT-WITH")
    assert with_op.index("_CV-LOAD-AUTHENTICATED") < with_op.index(
        "_CV-CALL-CONSUMER"
    )

    recovery = _word_body(source, "_CVAULT-RECOVER")
    _ordered(
        recovery,
        "_CV-RECOVER-BEGIN",
        "_CV-RID-PREFLIGHT",
        "_CV.ACTIVE-RID RID=",
        "_CV-STORE-FINI",
        "_CV-OP-RECOVER",
        "_CV-TOPOLOGY",
        "_CV-STORE-INIT",
        "VFSNAP-RECOVER",
        "_CV-LOAD-AUTHENTICATED",
        "CVAULT-S-OK =",
        "CVAULT-S-REVOKED = OR",
        "_CV-F-BLOCKED INVERT",
        "_CV-COMPLETE-RECOVERY",
        "_CV-FINISH-BLOCKED",
    )
    assert "_CV-ACTIVATE" not in recovery
    assert "_CVAULT-CREATE" not in recovery
    assert "CVAULT-S-CONFLICT R@ _CV-RECOVER-REJECT" in recovery
    recover_begin = _word_body(source, "_CV-RECOVER-BEGIN")
    assert "_CV-F-BLOCKED AND 0=" in recover_begin
    finish_blocked = _word_body(source, "_CV-FINISH-BLOCKED")
    assert "_CV-TRANSIENT-WIPE" in finish_blocked
    assert "_CV-ACTIVE-CLEAR" not in finish_blocked
    assert "_CV-BLOCK!" in finish_blocked

    blocking = _word_body(source, "_CV-STATUS-BLOCKING?")
    blocking_statuses = (
        "CVAULT-S-CORRUPT",
        "CVAULT-S-UNSUPPORTED",
        "CVAULT-S-IO",
        "CVAULT-S-RECOVERY",
        "CVAULT-S-ROLLBACK",
        "CVAULT-S-INTERNAL",
    )
    for status in blocking_statuses:
        assert blocking.count(status) == 1

    transient = _word_body(source, "_CV-TRANSIENT-WIPE")
    for marker in (
        "_CV.SEAL-KEY-ID RID-CLEAR",
        "_CV.SEAL-RECORD-ID RID-CLEAR",
        "_CV.SEALED R@ _CV.RECORD-U @ 0 FILL",
        "_CV.PLAIN R@ _CV.PLAIN-U @ 0 FILL",
        "_CV.SEALED-WORKSPACE SEALED-RECORD-WORKSPACE-SIZE 0 FILL",
        "0 R@ _CV.STATE !",
        "0 R@ _CV.KIND !",
        "0 R@ _CV.SECRET-U !",
        "0 R@ _CV.CALLBACK-XT !",
        "0 R@ _CV.CALLBACK-CONTEXT !",
        "0 R@ _CV.CALLBACK-STATUS !",
        "0 R@ _CV.INPUT !",
        "0 R@ _CV.INPUT-U !",
        "0 R@ _CV.EXPECTED !",
    ):
        assert marker in transient

    active = _word_body(source, "_CV-ACTIVE-CLEAR")
    for marker in (
        "_CV.ACTIVE-RID RID-CLEAR",
        "_CV.BINDING-ID RID-CLEAR",
        "_CV.SHARD1 _CV-PATH-CAP 0 FILL",
        "_CV.SHARD2 _CV-PATH-CAP 0 FILL",
        "_CV.TARGET _CV-PATH-CAP 0 FILL",
        "0 R@ _CV.SHARD1-U !",
        "0 R@ _CV.SHARD2-U !",
        "0 R@ _CV.TARGET-U !",
        "0 R@ _CV.GENERATION !",
        "0 R@ _CV.RESULT-REVISION !",
        "_CV-OP-NONE R@ _CV.OPERATION !",
    ):
        assert marker in active

    borrow = _word_body(source, "_CV-BORROW-PREPARE")
    _ordered(
        borrow,
        "_CV.SEALED R@ _CV.RECORD-U @ 0 FILL",
        "_CV.INPUT-U @ MOVE" if "_CV.INPUT-U @ MOVE" in borrow else (
            "_CV.SECRET-U @ MOVE"
        ),
        "_CV.PLAIN R@ _CV.PLAIN-U @ 0 FILL",
    )
    call_consumer = _word_body(source, "_CV-CALL-CONSUMER")
    assert call_consumer.count(
        "_CV.SEALED R@ _CV.RECORD-U @ 0 FILL"
    ) >= 3
    encode = _word_body(source, "_CV-ENCODE-SEAL")
    assert encode.count("_CV.PLAIN R@ _CV.PLAIN-U @ 0 FILL") >= 4
    opened = _word_body(source, "_CV-OPEN-SEALED")
    assert opened.count("_CV.PLAIN R@ _CV.PLAIN-U @ 0 FILL") >= 2
    assert (
        "_CV.SEALED-WORKSPACE SEALED-RECORD-WORKSPACE-SIZE 0 FILL"
        in opened
    )

    destroy = _word_body(source, "_CV-DESTROY")
    _ordered(
        destroy,
        "_CV.BACKING @ R@ _CV.BACKING-U @ 0 FILL",
        "CVAULT-SIZE 0 FILL",
    )
    populate = _word_body(source, "_CV-POPULATE")
    assert populate.count("CVAULT-SIZE 0 FILL") >= 2
    assert populate.count("CVAULT-C.BACKING-U @ 0 FILL") >= 2
    fini = _word_body(source, "_CVAULT-FINI")
    assert fini.index("_CV-STORE-FINI") < fini.index("_CV-DESTROY")

    normalized_doc = _flat(doc.replace("`", ""))
    for phrase in (
        "durable authenticated tombstone",
        "Revocation never unlinks the file",
        "a RID is never reusable",
        "There is no delete operation",
        "CVAULT-RECOVER is valid only for a blocked vault",
        "expected-rid to equal the RID retained by the failed operation",
        "finalizes the retained snapshot descriptor",
        "runs VFS replacement recovery",
        "Any other recovery result",
        "leaves the vault blocked",
        "wipes the complete borrow buffer immediately",
    ):
        assert phrase in normalized_doc


def _assert_source_hygiene(source: str) -> None:
    assert not re.search(
        r"(?mi)(?<![A-Za-z0-9_-])(?:\?DO|DO|\+LOOP|LOOP)"
        r"(?![A-Za-z0-9_-])",
        source,
    ), "credential-vault must not use KDOS DO-loop return-stack state"

    for line_number, line in enumerate(source.splitlines(), start=1):
        forth_code = line.split("\\", 1)[0]
        if "(" in forth_code:
            assert ")" in forth_code.split("(", 1)[1], (
                "KDOS parenthesized comments must close on their physical "
                f"line: {SOURCE}:{line_number}"
            )


def _assert_lifecycle_fixture_contracts() -> None:
    deps = LIFECYCLE_DEPS.read_text(encoding="utf-8")
    fixture = LIFECYCLE_FIXTURE.read_text(encoding="utf-8")
    provided = re.findall(r"(?m)^PROVIDED[ \t]+(\S+)$", deps)
    assert provided == [
        "cv-test-deps",
        "akashic-memory-span",
        "akashic-caller-span",
        "akashic-runtime-identity",
        "akashic-entropy",
        "akashic-guard",
        "akashic-vfs",
        "akashic-sealed-record",
        "akashic-vfs-fixed-snapshot",
    ]
    for text, path in (
        (deps, LIFECYCLE_DEPS),
        (fixture, LIFECYCLE_FIXTURE),
    ):
        assert not re.search(
            r"(?mi)(?<![A-Za-z0-9_-])(?:\?DO|DO|\+LOOP|LOOP)"
            r"(?![A-Za-z0-9_-])",
            text,
        )
        assert not re.search(
            r"(?mi)(?<![A-Za-z0-9_-])U>=(?![A-Za-z0-9_-])",
            text,
        )
        for line_number, line in enumerate(text.splitlines(), start=1):
            forth_code = line.split("\\", 1)[0]
            if "(" in forth_code:
                assert ")" in forth_code.split("(", 1)[1], (
                    "KDOS parenthesized comments must close on their "
                    f"physical line: {path}:{line_number}"
                )
    for marker in (
        "_CVTL-RUN",
        "CREDENTIAL VAULT LIFE PASS",
        "CVAULT-CREATE",
        "CVAULT-REPLACE",
        "CVAULT-REVOKE",
        "CVAULT-WITH",
        "CVAULT-RECOVER",
        "CVAULT-EXTERNAL-SPAN-STATUS",
        "_CVTL-EXTERNAL-SPAN-CASE",
        "_CVTL-EXTERNAL-BUSY-CASE",
        "CREDENTIAL VAULT LIFE EXTERNAL SPANS",
        "CREDENTIAL VAULT LIFE EXTERNAL BUSY",
        "CVAULT-S-REVOKED _CVTL-FLOOR-READ-STATUS !",
        "CVAULT-S-CALLBACK = _CVTL-ASSERT",
        "CVAULT-S-RECOVERY = _CVTL-ASSERT",
    ):
        assert marker in fixture


def _assert_source_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    doc = DOC.read_text(encoding="utf-8")
    identity = IDENTITY.read_text(encoding="utf-8")
    sealed = SEALED_RECORD.read_text(encoding="utf-8")
    memory_span = MEMORY_SPAN.read_text(encoding="utf-8")
    checked = CHECKED_RECORD.read_text(encoding="utf-8")
    replace = VFS_REPLACE.read_text(encoding="utf-8")
    snapshot = VFS_SNAPSHOT.read_text(encoding="utf-8")

    _assert_dependencies_and_boundary(source, doc)
    _assert_statuses_and_public_api(source, doc)
    _assert_geometry(
        source,
        identity,
        sealed,
        memory_span,
        checked,
        replace,
        snapshot,
        doc,
    )
    _assert_paths_and_private_state(source, doc)
    _assert_spec_store_identity(source)
    _assert_callback_containment(source, doc)
    _assert_entropy_floor_and_generations(source, doc)
    _assert_tombstone_recovery_and_wipes(source, doc)
    _assert_source_hygiene(source)
    _assert_lifecycle_fixture_contracts()


def _autoexec_lifecycle() -> str:
    return (
        "\\ autoexec.f - bounded credential-vault composition lifecycle\n"
        "ENTER-USERLAND\n"
        '." CREDENTIAL VAULT LOAD START" CR TX-FLUSH\n'
        "REQUIRE local_testing/cv-deps.f\n"
        '." CREDENTIAL VAULT DEPS READY" CR TX-FLUSH\n'
        "REQUIRE local_testing/cv-source.f\n"
        '." CREDENTIAL VAULT SOURCE READY" CR TX-FLUSH\n'
        "REQUIRE local_testing/cv-life.f\n"
        '." CREDENTIAL VAULT FIXTURE READY" CR TX-FLUSH\n'
        "_CVTL-RUN\n"
    )


def _lifecycle_source() -> bytes:
    source = SOURCE.read_text(encoding="utf-8")
    require_lines = [
        line
        for line in source.splitlines()
        if line.lstrip().startswith("REQUIRE ")
    ]
    assert require_lines == [
        "REQUIRE sealed-record.f",
        "REQUIRE ../runtime/identity.f",
        "REQUIRE ../math/entropy.f",
        "REQUIRE ../utils/fs/vfs-fixed-snapshot.f",
        "REQUIRE ../utils/memory-span.f",
        "REQUIRE ../utils/caller-span.f",
        "REQUIRE ../concurrency/guard.f",
    ]
    body = "".join(
        line
        for line in source.splitlines(keepends=True)
        if not line.lstrip().startswith("REQUIRE ")
    )
    return body.encode("utf-8")


def _run_lifecycle(timeout: float) -> int:
    import sys

    sys.path.insert(0, str(LOCAL_TESTING))
    import akashic_tui as harness

    profile = "credential-vault-life"
    image = Path("/tmp/akashic-credential-vault-life.img")
    marker = "CREDENTIAL VAULT LIFE PASS"
    harness.PROFILES[profile] = harness.Profile(
        roots=(),
        resources=(),
        autoexec=_autoexec_lifecycle(),
        ready_markers=(marker,),
        stable_markers=(marker,),
        failure_markers=(
            "CREDENTIAL VAULT LIFE FAIL",
            "CREDENTIAL VAULT LIFE ASSERT",
            "CREDENTIAL VAULT LIFE STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(
            ("local_testing/cv-deps.f", LIFECYCLE_DEPS.read_bytes()),
            ("local_testing/cv-source.f", _lifecycle_source()),
            (
                "local_testing/cv-life.f",
                LIFECYCLE_FIXTURE.read_bytes(),
            ),
        ),
        linked=False,
        include_large_sample=False,
        total_sectors=2048,
    )
    image_path = harness.build_image(profile, image)
    ok = harness.smoke(
        profile,
        image_path,
        cols=120,
        rows=40,
        max_steps=250_000_000,
        timeout=timeout,
        ext_mem_mib=128,
    )
    return 0 if ok else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--static-only",
        action="store_true",
        help="check the source, dependency geometry, and documentation",
    )
    mode.add_argument(
        "--lifecycle",
        action="store_true",
        help="run one bounded guest composition lifecycle with contract doubles",
    )
    parser.add_argument("--timeout", type=float, default=160.0)
    args = parser.parse_args()

    _assert_source_contracts()
    if args.static_only:
        print("CREDENTIAL VAULT STATIC PASS")
        return 0
    return _run_lifecycle(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
