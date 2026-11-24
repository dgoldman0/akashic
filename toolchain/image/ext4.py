"""The ext4 profile the image tool builds volumes to, and its checks.

The profile (ext4-profile/manifest.json, with its mke2fs.conf) fixes what
Akashic's ext4 driver is qualified against: the feature set, the mke2fs
arguments, the environment that makes a build repeatable, and the facts the
driver's admission reads from a superblock.  The image tool builds the
system and user volumes with it, and the ext4 fixture generator
(local_testing/generate_ext4_profile_fixtures.py) builds its reference
images with it.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import struct
import uuid
import subprocess
from pathlib import Path
from typing import Any, Iterable

from .megapad import AKASHIC_ROOT

REPO_ROOT = AKASHIC_ROOT
PROFILE_DIR = Path(__file__).resolve().with_name("ext4-profile")
DEFAULT_MANIFEST = PROFILE_DIR / "manifest.json"


class ProfileError(RuntimeError):
    """The pinned tool or generated image violated the profile contract."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def load_manifest(path: Path = DEFAULT_MANIFEST) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as source:
        manifest = json.load(source)
    if manifest.get("schema") != "akashic.ext4-compatibility-profile.v1":
        raise ProfileError(f"unsupported ext4 profile schema in {path}")
    return manifest


def _run(
    argv: list[str],
    *,
    env: dict[str, str],
    expected_status: int | tuple[int, ...] = 0,
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        argv,
        check=False,
        capture_output=True,
        text=True,
        env=env,
    )
    expected_statuses = (
        (expected_status,) if isinstance(expected_status, int) else expected_status
    )
    if result.returncode not in expected_statuses:
        command = " ".join(argv)
        raise ProfileError(
            f"command exited {result.returncode}, expected one of "
            f"{expected_statuses}: "
            f"{command}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result


def pinned_environment(
    manifest: dict[str, Any], tool_dir: Path, manifest_path: Path
) -> dict[str, str]:
    values: dict[str, str] = {}
    for name, value in manifest["generator"]["environment"].items():
        values[name] = value.format(repo=REPO_ROOT)
    values["MKE2FS_CONFIG"] = str(manifest_path.parent / "mke2fs.conf")
    values["LANG"] = "C"
    values["PATH"] = f"{tool_dir}:/usr/bin:/bin"
    return values


_VERSION = r"(\d+)\.(\d+)\.(\d+)"


def verify_toolchain(
    manifest: dict[str, Any],
    tool_dir: Path,
    env: dict[str, str],
    *,
    minimum: tuple[int, int, int] | None = None,
) -> dict[str, dict[str, str]]:
    """The profile's e2fsprogs tools in TOOL_DIR, each checked: at the
    pinned version, or with MINIMUM at any version from MINIMUM on, linked to
    the library of its own version."""

    tool_dir = tool_dir.resolve()
    expected_banner = manifest["authorities"]["e2fsprogs"]["version_banner"]
    expected_library = "Using EXT2FS Library version 1.47.4"
    evidence: dict[str, dict[str, str]] = {}

    for name in manifest["authorities"]["e2fsprogs"]["required_tools"]:
        executable = tool_dir / name
        if not executable.is_file() or not os.access(executable, os.X_OK):
            raise ProfileError(f"missing executable e2fsprogs tool: {executable}")
        result = _run([str(executable), "-V"], env=env)
        banner = (result.stdout + result.stderr).strip()
        if minimum is not None:
            tool = re.search(re.escape(name) + " " + _VERSION, banner)
            library = re.search("Using EXT2FS Library version " + _VERSION, banner)
            version = tuple(map(int, tool.groups())) if tool else None
            if version is None or version < minimum:
                raise ProfileError(
                    f"{executable} is not e2fsprogs {'.'.join(map(str, minimum))} "
                    f"or later:\n{banner}"
                )
            if library is None or tuple(map(int, library.groups())) != version:
                raise ProfileError(
                    f"{executable} is not linked to its own libext2fs:\n{banner}"
                )
        elif f"{name} {expected_banner}" not in banner:
            raise ProfileError(
                f"{executable} is not pinned {name} {expected_banner}:\n{banner}"
            )
        elif expected_library not in banner:
            raise ProfileError(
                f"{executable} is not linked to pinned libext2fs 1.47.4:\n{banner}"
            )
        evidence[name] = {
            "path": str(executable.resolve()),
            "sha256": sha256_file(executable.resolve()),
            "version": banner,
        }
    return evidence


def _u16(data: bytes, offset: int) -> int:
    return struct.unpack_from("<H", data, offset)[0]


def _u32(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def _has_backup(group: int, sparse_super: bool) -> bool:
    """Whether GROUP holds a superblock backup: every group without
    sparse_super, else groups 0 and 1 and the powers of 3, 5 and 7."""

    if not sparse_super or group < 2:
        return True
    for base in (3, 5, 7):
        power = base
        while power < group:
            power *= base
        if power == group:
            return True
    return False


def uninitialized_backup_groups(image: Path) -> list[int]:
    """The block groups of IMAGE that hold a superblock backup yet carry
    BLOCK_UNINIT.  e2fsprogs 1.47.0 marks them so; the pinned 1.47.4 does
    not."""

    superblock = read_superblock(image)
    block_size = superblock["block_size"]
    descriptor = (
        superblock["group_descriptor_size"]
        if superblock["feature_incompat"] & 0x80
        else 32
    )
    sparse_super = bool(superblock["feature_ro_compat"] & 0x1)
    table = (superblock["first_data_block"] + 1) * block_size
    with image.open("rb") as source:
        source.seek(table)
        descriptors = source.read(superblock["group_count"] * descriptor)
    block_uninit = 0x2
    return [
        group
        for group in range(superblock["group_count"])
        if _has_backup(group, sparse_super)
        and _u16(descriptors, group * descriptor + 0x12) & block_uninit
    ]


def read_superblock(image: Path) -> dict[str, Any]:
    with image.open("rb") as source:
        source.seek(1024)
        sb = source.read(1024)
    if len(sb) != 1024:
        raise ProfileError(f"short ext4 superblock in {image}")

    incompat = _u32(sb, 0x60)
    blocks = _u32(sb, 0x04)
    if incompat & 0x80:
        blocks |= _u32(sb, 0x150) << 32
    block_size = 1024 << _u32(sb, 0x18)
    first_data_block = _u32(sb, 0x14)
    blocks_per_group = _u32(sb, 0x20)
    group_count = (
        blocks - first_data_block + blocks_per_group - 1
    ) // blocks_per_group
    journal_extent_count = _u16(sb, 0x10C + 2)
    journal_extents = []
    for index in range(min(journal_extent_count, 4)):
        extent = 0x10C + 12 + index * 12
        journal_extents.append(
            {
                "logical": _u32(sb, extent),
                "raw_length": _u16(sb, extent + 4),
                "physical_hi": _u16(sb, extent + 6),
                "physical": (
                    (_u16(sb, extent + 6) << 32) | _u32(sb, extent + 8)
                ),
            }
        )

    return {
        "magic": _u16(sb, 0x38),
        "revision": _u32(sb, 0x4C),
        "creator_os": _u32(sb, 0x48),
        "state": _u16(sb, 0x3A),
        "errors": _u16(sb, 0x3C),
        "block_size": block_size,
        "block_count": blocks,
        "first_data_block": first_data_block,
        "blocks_per_group": blocks_per_group,
        "group_count": group_count,
        "inode_count": _u32(sb, 0x00),
        "inodes_per_group": _u32(sb, 0x28),
        "inode_size": _u16(sb, 0x58),
        "minimum_extra_isize": _u16(sb, 0x15C),
        "wanted_extra_isize": _u16(sb, 0x15E),
        "group_descriptor_size": _u16(sb, 0xFE),
        "log_groups_per_flex": sb[0x174],
        "checksum_type": sb[0x175],
        "feature_compat": _u32(sb, 0x5C),
        "feature_incompat": incompat,
        "feature_ro_compat": _u32(sb, 0x64),
        "uuid": str(uuid.UUID(bytes=bytes(sb[0x68:0x78]))),
        "label": bytes(sb[0x78:0x88]).split(b"\0", 1)[0].decode("ascii"),
        "journal_inode": _u32(sb, 0xE0),
        "journal_backup_type": sb[0xFD],
        "journal_backup_extent_magic": _u16(sb, 0x10C),
        "journal_backup_extent_count": journal_extent_count,
        "journal_backup_extent_max": _u16(sb, 0x10C + 4),
        "journal_backup_extent_depth": _u16(sb, 0x10C + 6),
        "journal_backup_size": (
            (_u32(sb, 0x10C + 60) << 32) | _u32(sb, 0x10C + 64)
        ),
        "journal_backup_extents": journal_extents,
        "checksum_seed": _u32(sb, 0x270),
        "orphan_file_inode": _u32(sb, 0x280),
        "superblock_checksum": _u32(sb, 0x3FC),
    }


def profile_feature_names(
    manifest: dict[str, Any], image_spec: dict[str, Any]
) -> list[str]:
    names = list(manifest["profiles"]["primary"]["feature_names"])
    profile = manifest["profiles"][image_spec["profile"]]
    for name in profile.get("feature_names_remove", []):
        names.remove(name)
    return names


def render_argv(template: Iterable[str], context: dict[str, Any]) -> list[str]:
    return [word.format(**context) for word in template]


def validate_observed_superblock(
    manifest: dict[str, Any],
    image_spec: dict[str, Any],
    observed: dict[str, Any],
) -> None:
    profile = manifest["profiles"][image_spec["profile"]]
    masks = profile["feature_masks"]
    journal_authority = manifest["journal_feature_policy"]["recovery_authority"]
    expected = {
        "magic": 0xEF53,
        "revision": 1,
        "creator_os": 0,
        "state": 1,
        "errors": 2,
        "block_size": image_spec["block_size"],
        "block_count": image_spec["block_count"],
        "first_data_block": 1 if image_spec["block_size"] == 1024 else 0,
        "blocks_per_group": image_spec["blocks_per_group"],
        "group_count": image_spec["expected_groups"],
        "inode_count": image_spec["expected_inodes"],
        "inode_size": image_spec["inode_size"],
        "group_descriptor_size": 64,
        "log_groups_per_flex": 4,
        "checksum_type": 1,
        "feature_compat": masks["compat"],
        "feature_incompat": masks["incompat"],
        "feature_ro_compat": masks["ro_compat"],
        "uuid": image_spec["uuid"],
        "label": image_spec["label"],
        "journal_inode": 8,
        "journal_backup_type": journal_authority["journal_backup_type"],
        "journal_backup_extent_magic": journal_authority["extent_magic"],
        "journal_backup_extent_max": journal_authority["extent_max"],
        "journal_backup_extent_depth": journal_authority["extent_depth"],
    }
    if image_spec["inode_size"] == 256:
        expected["minimum_extra_isize"] = 32
        expected["wanted_extra_isize"] = 32
    else:
        expected["minimum_extra_isize"] = 0
        expected["wanted_extra_isize"] = 0

    differences = {
        name: {"expected": value, "observed": observed.get(name)}
        for name, value in expected.items()
        if observed.get(name) != value
    }
    if differences:
        raise ProfileError(
            f"{image_spec['id']} violates pinned superblock facts: "
            f"{json.dumps(differences, sort_keys=True)}"
        )
    extent_count = observed["journal_backup_extent_count"]
    if not (
        journal_authority["minimum_extents"]
        <= extent_count
        <= journal_authority["maximum_extents"]
    ):
        raise ProfileError(
            f"{image_spec['id']} has {extent_count} journal backup extents"
        )
    journal_size = observed["journal_backup_size"]
    if journal_size == 0 or journal_size % observed["block_size"]:
        raise ProfileError(
            f"{image_spec['id']} has invalid journal backup size {journal_size}"
        )
    logical = 0
    physical_ranges: list[tuple[int, int]] = []
    for extent in observed["journal_backup_extents"]:
        raw_length = extent["raw_length"]
        physical = extent["physical"]
        if extent["logical"] != logical or not 1 <= raw_length <= 32768:
            raise ProfileError(
                f"{image_spec['id']} has a sparse or unwritten journal extent"
            )
        if extent["physical_hi"] != 0 or physical == 0:
            raise ProfileError(
                f"{image_spec['id']} has an unsupported journal extent address"
            )
        physical_end = physical + raw_length
        if physical_end > observed["block_count"]:
            raise ProfileError(
                f"{image_spec['id']} has an out-of-bounds journal extent"
            )
        if any(
            other_end > physical and physical_end > other_start
            for other_start, other_end in physical_ranges
        ):
            raise ProfileError(
                f"{image_spec['id']} has overlapping journal extents"
            )
        physical_ranges.append((physical, physical_end))
        logical += raw_length
    if logical != journal_size // observed["block_size"]:
        raise ProfileError(
            f"{image_spec['id']} journal backup does not exactly cover its size"
        )
    if observed["orphan_file_inode"] == 0:
        raise ProfileError(f"{image_spec['id']} lacks its required orphan file inode")
