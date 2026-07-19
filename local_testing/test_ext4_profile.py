"""Contract tests for the pinned pre-driver ext4 compatibility profile."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import pytest


LOCAL_TESTING = Path(__file__).resolve().parent
if str(LOCAL_TESTING) not in sys.path:
    sys.path.insert(0, str(LOCAL_TESTING))

from generate_ext4_profile_fixtures import (  # noqa: E402
    DEFAULT_MANIFEST,
    ProfileError,
    generate,
    load_manifest,
    pinned_environment,
    sha256_file,
)


EXPECTED_FEATURE_BITS = {
    "compat": {
        "dir_prealloc": 0x0001,
        "imagic_inodes": 0x0002,
        "has_journal": 0x0004,
        "ext_attr": 0x0008,
        "resize_inode": 0x0010,
        "dir_index": 0x0020,
        "lazy_bg": 0x0040,
        "exclude_inode": 0x0080,
        "exclude_bitmap": 0x0100,
        "sparse_super2": 0x0200,
        "fast_commit": 0x0400,
        "stable_inodes": 0x0800,
        "orphan_file": 0x1000,
    },
    "ro_compat": {
        "sparse_super": 0x0001,
        "large_file": 0x0002,
        "btree_dir": 0x0004,
        "huge_file": 0x0008,
        "gdt_csum": 0x0010,
        "dir_nlink": 0x0020,
        "extra_isize": 0x0040,
        "has_snapshot": 0x0080,
        "quota": 0x0100,
        "bigalloc": 0x0200,
        "metadata_csum": 0x0400,
        "replica": 0x0800,
        "readonly": 0x1000,
        "project": 0x2000,
        "shared_blocks": 0x4000,
        "verity": 0x8000,
        "orphan_present": 0x10000,
    },
    "incompat": {
        "compression": 0x0001,
        "filetype": 0x0002,
        "recover": 0x0004,
        "journal_dev": 0x0008,
        "meta_bg": 0x0010,
        "extent": 0x0040,
        "64bit": 0x0080,
        "mmp": 0x0100,
        "flex_bg": 0x0200,
        "ea_inode": 0x0400,
        "dirdata": 0x1000,
        "metadata_csum_seed": 0x2000,
        "largedir": 0x4000,
        "inline_data": 0x8000,
        "encrypt": 0x10000,
        "casefold": 0x20000,
    },
}

EXPECTED_JOURNAL_BITS = {
    "compat": {"checksum_v1": 0x01},
    "ro_compat": {},
    "incompat": {
        "revoke": 0x01,
        "64bit": 0x02,
        "async_commit": 0x04,
        "checksum_v2": 0x08,
        "checksum_v3": 0x10,
        "fast_commit": 0x20,
    },
}

EXPECTED_IMAGE_SHA256 = {
    "primary-1k-i256": "4f1408f2388b14935d4f749021c5c588faa582249ee780ce3f3e36051d7e10a0",
    "primary-2k-i256": "de3c1970f6a3fc5ee0a1f684130bcfd477b211106a85d745fe174bef12d3d016",
    "primary-4k-i256": "11ac071f3590ff06aa3a22928e0dbdb22affecb1d25203181c1d61d342732920",
    "legacy-1k-i128": "2aca099d7d024a47e0411a528adc55c75b6ad0ba5a28882dbfa24f906cd811b5",
}


@pytest.fixture(scope="module")
def manifest() -> dict:
    return load_manifest()


def _rows_by_name(rows: list[dict]) -> dict[str, dict]:
    return {row["name"]: row for row in rows}


def _bits(rows: list[dict]) -> dict[str, int]:
    return {row["name"]: row["bit"] for row in rows}


def test_authority_and_toolchain_are_immutable(manifest: dict) -> None:
    assert manifest["schema"] == "akashic.ext4-compatibility-profile.v1"
    assert manifest["profile_id"] == "akashic-ext4-rw-v1"

    linux = manifest["authorities"]["linux_ext4"]
    assert linux["tag"] == "v6.18"
    assert linux["annotated_tag_object"] == (
        "f7b88edb52c8dd01b7e576390d658ae6eef0e134"
    )
    assert linux["peeled_commit"] == (
        "7d0a66e4bb9081d75c82ec4957c50034cb0ea449"
    )

    tools = manifest["authorities"]["e2fsprogs"]
    assert tools["tag"] == "v1.47.4"
    assert tools["annotated_tag_object"] == (
        "ece89fac4603e400155b7bbf6326284f8511bca9"
    )
    assert tools["peeled_commit"] == (
        "7ee1d505ef3b37831215f490411f346fe57e9053"
    )
    assert tools["source_archive_sha256"] == (
        "fd5bf388cbdbe006a3d3b318d983b2948382440acc85a87f1e7d108653e8db0b"
    )
    assert tools["release_archive_published_on"] == "2026-03-06"
    assert tools["version_banner"] == "1.47.4 (6-Mar-2025)"
    assert tools["required_tools"] == [
        "mke2fs",
        "e2fsck",
        "debugfs",
        "dumpe2fs",
    ]


def test_private_mke2fs_config_and_environment_are_pinned(manifest: dict) -> None:
    config = DEFAULT_MANIFEST.parent / "mke2fs.conf"
    assert sha256_file(config) == manifest["generator"]["mke2fs_config_sha256"]
    environment = manifest["generator"]["environment"]
    assert environment == {
        "LC_ALL": "C",
        "TZ": "UTC",
        "E2FSPROGS_FAKE_TIME": "1704067200",
        "MKE2FS_CONFIG": (
            "{repo}/local_testing/fixtures/ext4-profile/mke2fs.conf"
        ),
    }
    mkfs = manifest["generator"]["mkfs_argv"]
    assert mkfs[0] == "{tool_dir}/mke2fs"
    assert "none,{feature_names}" in mkfs
    assert "lazy_itable_init=0,lazy_journal_init=0,nodiscard," in "".join(mkfs)
    assert manifest["generator"]["e2fsck_argv"] == [
        "{tool_dir}/e2fsck",
        "-f",
        "-n",
        "{image}",
    ]


def test_generator_environment_rejects_ambient_overrides(
    manifest: dict, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("SOURCE_DATE_EPOCH", "unexpected")
    monkeypatch.setenv("TEST_IO_FLAGS", "unexpected")
    monkeypatch.setenv("MKE2FS_DEVICE_SECTSIZE", "8192")
    tool_dir = Path("/pinned/e2fsprogs/sbin")
    environment = pinned_environment(manifest, tool_dir, DEFAULT_MANIFEST)
    assert environment == {
        "LC_ALL": "C",
        "LANG": "C",
        "TZ": "UTC",
        "E2FSPROGS_FAKE_TIME": "1704067200",
        "MKE2FS_CONFIG": str(DEFAULT_MANIFEST.parent / "mke2fs.conf"),
        "PATH": "/pinned/e2fsprogs/sbin:/usr/bin:/bin",
    }


def test_superblock_feature_ledger_is_complete(manifest: dict) -> None:
    policy = manifest["feature_policy"]
    for family, expected in EXPECTED_FEATURE_BITS.items():
        rows = policy[family]
        assert _bits(rows) == expected
        assert len({row["bit"] for row in rows}) == len(rows)
        assert all(row["hex"] == f"0x{row['bit']:08x}" for row in rows)
        assert all(
            row["disposition"]
            in {"read_write", "read_write_recovery", "read_only", "refuse"}
            for row in rows
        )

    assert policy["unknown"] == {
        "compat": "refuse",
        "ro_compat": "read_only_only_when_clean_and_recovery_free",
        "incompat": "refuse",
    }


def test_primary_feature_masks_are_derived_from_required_rows(manifest: dict) -> None:
    policy = manifest["feature_policy"]
    masks = manifest["profiles"]["primary"]["feature_masks"]
    for family in ("compat", "ro_compat", "incompat"):
        derived = sum(
            row["bit"] for row in policy[family] if row.get("required", False)
        )
        assert derived == masks[family]
        assert masks[f"{family}_hex"] == f"0x{derived:08x}"

    assert masks == {
        "compat": 0x103C,
        "compat_hex": "0x0000103c",
        "ro_compat": 0x046B,
        "ro_compat_hex": "0x0000046b",
        "incompat": 0x22C2,
        "incompat_hex": "0x000022c2",
    }

    compat = _rows_by_name(policy["compat"])
    incompat = _rows_by_name(policy["incompat"])
    ro_compat = _rows_by_name(policy["ro_compat"])
    assert compat["orphan_file"]["disposition"] == "read_write"
    assert incompat["metadata_csum_seed"]["disposition"] == "read_write"
    assert incompat["recover"]["disposition"] == "read_write_recovery"
    assert ro_compat["orphan_present"]["disposition"] == "read_write_recovery"
    assert ro_compat["readonly"]["disposition"] == "read_only"


def test_jbd2_feature_ledger_is_complete_and_strict(manifest: dict) -> None:
    journal = manifest["journal_feature_policy"]
    for family, expected in EXPECTED_JOURNAL_BITS.items():
        assert _bits(journal[family]) == expected
    assert journal["clean_mkfs_masks"] == {
        "compat": 0,
        "ro_compat": 0,
        "incompat": 0,
    }
    assert journal["writer_initial_incompat_mask"] == 0x12
    assert journal["writer_with_revoke_incompat_mask"] == 0x13
    assert journal["checksum_type"] == 4
    admitted = {
        row["name"]
        for row in journal["incompat"]
        if row["disposition"] == "read_write"
    }
    assert admitted == {"revoke", "64bit", "checksum_v3"}
    assert journal["unknown"] == "refuse"


def test_geometry_covers_all_required_blocks_and_inode_forms(manifest: dict) -> None:
    bounds = manifest["platform_bounds"]
    assert bounds["device_sector_bytes"] == 512
    assert bounds["volume_lba_bits"] == 32
    assert bounds["maximum_volume_sectors"] == 0xFFFFFFFF
    assert bounds["filesystem_block_bytes"] == [1024, 2048, 4096]
    assert bounds["maximum_name_bytes"] == 255
    assert bounds["maximum_vfs_offset"] == (1 << 63) - 1

    images = manifest["images"]
    primary = [image for image in images if image["profile"] == "primary"]
    assert {image["block_size"] for image in primary} == {1024, 2048, 4096}
    assert all(image["expected_groups"] > 1 for image in images)
    assert all(
        image["image_bytes"] == image["block_size"] * image["block_count"]
        for image in images
    )
    assert all(len(image["expected_sha256"]) == 64 for image in images)
    assert len({image["expected_sha256"] for image in images}) == len(images)
    assert {image["id"]: image["expected_sha256"] for image in images} == (
        EXPECTED_IMAGE_SHA256
    )
    assert {image["inode_size"] for image in images} == {128, 256}

    legacy = manifest["profiles"]["legacy_inode_128"]
    assert legacy["feature_names_remove"] == ["extra_isize"]
    assert legacy["feature_masks"]["ro_compat"] == 0x042B


def test_mount_policy_does_not_overclaim_current_vfs(manifest: dict) -> None:
    mount = manifest["mount_policy"]
    assert mount["writable_requires_internal_journal"] is True
    assert "replay writes" in mount["dirty_read_only_volume"]
    assert mount["case_sensitivity"] == "byte-sensitive"
    assert "resolver traversal remains implementation work" in mount["symlinks"]
    assert "enforcement is not claimed" in mount["acl"]


def _pinned_tool_dir() -> Path:
    value = os.environ.get("AKASHIC_E2FSPROGS_TOOL_DIR")
    if not value:
        pytest.skip("set AKASHIC_E2FSPROGS_TOOL_DIR for external-tool qualification")
    return Path(value)


def test_real_external_tool_fixture_and_oracles(tmp_path: Path) -> None:
    result = generate(
        DEFAULT_MANIFEST,
        _pinned_tool_dir(),
        tmp_path / "one",
        {"primary-1k-i256"},
    )
    assert len(result["images"]) == 1
    image = result["images"][0]
    assert image["evidence"]["e2fsck_exit"] == 0
    assert image["observed_superblock"]["feature_compat"] == 0x103C
    assert image["observed_superblock"]["feature_ro_compat"] == 0x046B
    assert image["observed_superblock"]["feature_incompat"] == 0x22C2
    assert image["observed_superblock"]["orphan_file_inode"] != 0
    assert (tmp_path / "one" / "qualification.json").is_file()


def test_canonical_generation_is_byte_reproducible(tmp_path: Path) -> None:
    tool_dir = _pinned_tool_dir()
    first = generate(
        DEFAULT_MANIFEST,
        tool_dir,
        tmp_path / "first",
        {"primary-1k-i256"},
    )
    second = generate(
        DEFAULT_MANIFEST,
        tool_dir,
        tmp_path / "second",
        {"primary-1k-i256"},
    )
    assert first["images"][0]["sha256"] == second["images"][0]["sha256"]


def test_generator_rejects_noncanonical_tool_version(tmp_path: Path) -> None:
    tool_dir = tmp_path / "tools"
    tool_dir.mkdir()
    for name in ("mke2fs", "e2fsck", "debugfs", "dumpe2fs"):
        executable = tool_dir / name
        executable.write_text(
            f"#!/bin/sh\necho '{name} 1.47.0 (5-Feb-2023)' >&2\n"
            "echo 'Using EXT2FS Library version 1.47.0' >&2\n",
            encoding="utf-8",
        )
        executable.chmod(0o755)

    output_dir = tmp_path / "out"
    output_dir.mkdir()
    stale_evidence = output_dir / "qualification.json"
    stale_evidence.write_text('{"stale": true}\n', encoding="utf-8")

    with pytest.raises(ProfileError, match="not pinned"):
        generate(DEFAULT_MANIFEST, tool_dir, output_dir, {"primary-1k-i256"})

    assert not stale_evidence.exists()
    assert not (output_dir / ".qualification.json.tmp").exists()


def test_config_failure_invalidates_stale_evidence(tmp_path: Path) -> None:
    profile_dir = tmp_path / "profile"
    profile_dir.mkdir()
    manifest_path = profile_dir / "manifest.json"
    manifest_path.write_text(
        DEFAULT_MANIFEST.read_text(encoding="utf-8"),
        encoding="utf-8",
    )
    (profile_dir / "mke2fs.conf").write_text(
        "[defaults]\nbase_features = deliberately-wrong\n",
        encoding="utf-8",
    )
    output_dir = tmp_path / "out"
    output_dir.mkdir()
    stale_evidence = output_dir / "qualification.json"
    stale_evidence.write_text('{"stale": true}\n', encoding="utf-8")

    with pytest.raises(ProfileError, match="mke2fs.conf hash mismatch"):
        generate(manifest_path, tmp_path / "unused-tools", output_dir)

    assert not stale_evidence.exists()
    assert not (output_dir / ".qualification.json.tmp").exists()


def test_manifest_json_is_canonical_utf8() -> None:
    parsed = json.loads(DEFAULT_MANIFEST.read_text(encoding="utf-8"))
    assert parsed["schema"] == "akashic.ext4-compatibility-profile.v1"
