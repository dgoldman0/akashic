#!/usr/bin/env python3
"""Generate ext4 profile-v1 images using only a pinned e2fsprogs suite."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import tempfile
from pathlib import Path
from typing import Any


import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from toolchain.image.ext4 import (  # noqa: E402
    DEFAULT_MANIFEST,
    ProfileError,
    _run,
    load_manifest,
    pinned_environment,
    profile_feature_names,
    read_superblock,
    render_argv,
    sha256_file,
    sha256_text,
    validate_observed_superblock,
    verify_toolchain,
)

LOCAL_TESTING = Path(__file__).resolve().parent
DEFAULT_OUTPUT = LOCAL_TESTING / "out" / "ext4-profile"



def populate_image(
    manifest: dict[str, Any],
    image_spec: dict[str, Any],
    tools: dict[str, dict[str, str]],
    env: dict[str, str],
    image: Path,
    block_size: int,
    temporary: Path,
) -> tuple[list[list[str]], dict[str, Any]]:
    population = manifest["generator"]["population"]
    payload = temporary / "payload.txt"
    payload.write_bytes(population["payload_utf8"].encode("utf-8"))
    sparse_payload = temporary / "sparse.bin"
    sparse_payload.write_bytes(
        b"A" * block_size + b"B" * block_size + b"C" * block_size
    )
    context = {
        "payload": payload,
        "sparse_payload": sparse_payload,
        "slow_symlink_target": population["slow_symlink_target"],
        "large_xattr_value": population["large_xattr_value"],
    }
    commands: list[list[str]] = []
    for template in population["debugfs_commands"]:
        command = template.format(**context)
        argv = [tools["debugfs"]["path"], "-w", "-R", command, str(image)]
        _run(argv, env=env)
        commands.append(argv)

    if image_spec.get("fixture_role") != "read_side":
        return commands, {}

    read_side = manifest["generator"]["read_side_population"]
    extent_payload = temporary / "extent-tree.bin"
    extent_patterns = read_side["extent_tree_patterns"]
    extent_payload.write_bytes(
        b"".join(bytes((pattern,)) * block_size for pattern in extent_patterns)
    )
    acl_access_value = temporary / "acl-access-value.bin"
    acl_access_value.write_bytes(
        bytes.fromhex(read_side["acl_access_value_hex"])
    )
    acl_default_value = temporary / "acl-default-value.bin"
    acl_default_value.write_bytes(
        bytes.fromhex(read_side["acl_default_value_hex"])
    )
    context.update(
        {
            "extent_payload": extent_payload,
            "acl_access_value": acl_access_value,
            "acl_default_value": acl_default_value,
            "second_large_xattr_value": read_side["second_large_xattr_value"],
            "trusted_xattr_value": read_side["trusted_xattr_value"],
            "security_xattr_value": read_side["security_xattr_value"],
            "live_slow_symlink_target": read_side["live_slow_symlink_target"],
        }
    )
    for template in read_side["debugfs_commands"]:
        command = template.format(**context)
        argv = [tools["debugfs"]["path"], "-w", "-R", command, str(image)]
        _run(argv, env=env)
        commands.append(argv)

    candidates = [f"candidate-{index:06d}" for index in range(256)]
    collision_names = read_side["htree_collision_names"]
    hash_path = temporary / "debugfs-hashes.cmd"
    hash_path.write_text(
        "\n".join(f"dx_hash {name}" for name in (*candidates, *collision_names))
        + "\n",
        encoding="ascii",
    )
    hash_argv = [
        tools["debugfs"]["path"],
        "-f",
        str(hash_path),
        str(image),
    ]
    hash_result = _run(hash_argv, env=env)
    commands.append(hash_argv)
    hashes = {
        name: int(value, 16)
        for name, value in re.findall(
            r"(?m)^Hash of (\S+) is 0x([0-9a-fA-F]+)", hash_result.stdout
        )
    }
    if len(hashes) != len(candidates) + len(collision_names):
        raise ProfileError("debugfs did not return every requested HTree hash")
    collision_hash = read_side["htree_collision_hash"]
    if any(hashes[name] != collision_hash for name in collision_names):
        raise ProfileError("the pinned HTree collision pair no longer collides")
    lower = [name for name in candidates if hashes[name] < collision_hash][
        : read_side["htree_lower_entries"]
    ]
    higher = [name for name in candidates if hashes[name] > collision_hash][
        : read_side["htree_higher_entries"]
    ]
    if (
        len(lower) != read_side["htree_lower_entries"]
        or len(higher) != read_side["htree_higher_entries"]
    ):
        raise ProfileError("candidate set cannot bracket the pinned HTree collision")
    indexed_names = [*lower, *collision_names, *higher]
    batch_commands = [
        "cd /fixture",
        "mknod char-old c 5 1",
        "mknod block-new b 259 513",
        "mknod fifo p",
        "cd /fixture/indexed",
        "expand /fixture/indexed",
        "expand /fixture/indexed",
        "expand /fixture/indexed",
        "expand /fixture/indexed",
    ]
    for name in indexed_names:
        batch_commands.append(f"ln /fixture/indexed-target {name}")
    batch_commands.append(
        f"sif /fixture/indexed-target links_count {len(indexed_names) + 1}"
    )
    batch_commands.extend(
        [
            "sif /fixture/legacy-map.bin flags 0",
            *(
                f"sif /fixture/legacy-map.bin block[{index}] 0"
                for index in range(12)
            ),
            "sif /fixture/legacy-map.bin block[IND] 0",
            "sif /fixture/legacy-map.bin block[DIND] 0",
            "sif /fixture/legacy-map.bin block[TIND] 0",
        ]
    )
    batch_path = temporary / "debugfs-read-side.cmd"
    batch_path.write_text("\n".join(batch_commands) + "\n", encoding="ascii")
    batch_argv = [
        tools["debugfs"]["path"],
        "-w",
        "-f",
        str(batch_path),
        str(image),
    ]
    batch_result = _run(batch_argv, env=env)
    batch_text = _command_text(batch_result)
    if any(
        marker in batch_text
        for marker in (
            "File not found",
            "Usage:",
            "Could not",
            "No space",
            "while setting block map",
        )
    ):
        raise ProfileError(f"debugfs read-side batch failed:\n{batch_text}")
    commands.append(batch_argv)

    pointers_per_block = block_size // 4
    legacy_logical = [
        0,
        12,
        12 + pointers_per_block,
        12 + pointers_per_block + pointers_per_block**2,
        13 + pointers_per_block + pointers_per_block**2,
    ]
    legacy_physical = []
    for logical, pattern in zip(
        legacy_logical, read_side["legacy_map_patterns"], strict=True
    ):
        bmap_argv = [
            tools["debugfs"]["path"],
            "-w",
            "-R",
            f"bmap -a /fixture/legacy-map.bin {logical}",
            str(image),
        ]
        bmap = _run(bmap_argv, env=env)
        commands.append(bmap_argv)
        matches = re.findall(r"(?m)^(\d+)\s*$", bmap.stdout)
        if len(matches) != 1 or int(matches[0]) == 0:
            raise ProfileError(
                f"debugfs did not allocate legacy logical block {logical}: "
                f"{_command_text(bmap)}"
            )
        physical = int(matches[0])
        legacy_physical.append(physical)
        zap_argv = [
            tools["debugfs"]["path"],
            "-w",
            "-R",
            f"zap_block -p 0x{pattern:02x} {physical}",
            str(image),
        ]
        _run(zap_argv, env=env)
        commands.append(zap_argv)

    legacy_size = (legacy_logical[-1] + 1) * block_size
    for field, value in (
        ("size_lo", legacy_size & 0xFFFF_FFFF),
        ("size_hi", legacy_size >> 32),
    ):
        argv = [
            tools["debugfs"]["path"],
            "-w",
            "-R",
            f"sif /fixture/legacy-map.bin {field} {value}",
            str(image),
        ]
        _run(argv, env=env)
        commands.append(argv)

    return commands, {
        "indexed_names": indexed_names,
        "legacy_logical": legacy_logical,
        "legacy_physical": legacy_physical,
        "legacy_size": legacy_size,
        "htree_collision_names": collision_names,
        "htree_collision_hash": collision_hash,
    }


def _command_text(result: subprocess.CompletedProcess[str]) -> str:
    return result.stdout + result.stderr


def _filesystem_field(text: str, label: str, source: str) -> str:
    matches = re.findall(
        rf"(?m)^{re.escape(label)}:\s*(.*?)\s*$",
        text,
    )
    if len(matches) != 1:
        raise ProfileError(
            f"{source} expected one {label!r} field, observed {len(matches)}"
        )
    return matches[0]


def _validate_filesystem_header(
    manifest: dict[str, Any],
    image_spec: dict[str, Any],
    text: str,
    source: str,
    *,
    require_journal_features: bool,
) -> None:
    expected_fields = {
        "Filesystem volume name": image_spec["label"],
        "Filesystem UUID": image_spec["uuid"],
        "Filesystem magic number": "0xEF53",
        "Filesystem revision #": "1 (dynamic)",
        "Filesystem state": "clean",
        "Errors behavior": "Remount read-only",
        "Filesystem OS type": "Linux",
        "Inode count": str(image_spec["expected_inodes"]),
        "Block count": str(image_spec["block_count"]),
        "First block": "1" if image_spec["block_size"] == 1024 else "0",
        "Block size": str(image_spec["block_size"]),
        "Group descriptor size": "64",
        "Blocks per group": str(image_spec["blocks_per_group"]),
        "Inodes per group": str(
            image_spec["expected_inodes"] // image_spec["expected_groups"]
        ),
        "Flex block group size": "16",
        "Inode size": str(image_spec["inode_size"]),
        "Journal inode": "8",
        "Default directory hash": "half_md4",
        "Directory Hash Seed": image_spec["hash_seed"],
        "Checksum type": "crc32c",
    }
    differences = {}
    for label, expected in expected_fields.items():
        observed = _filesystem_field(text, label, source)
        if observed != expected:
            differences[label] = {"expected": expected, "observed": observed}

    expected_features = set(profile_feature_names(manifest, image_spec))
    observed_features = set(
        _filesystem_field(text, "Filesystem features", source).split()
    )
    if observed_features != expected_features:
        differences["Filesystem features"] = {
            "expected": sorted(expected_features),
            "observed": sorted(observed_features),
        }

    orphan_inode = _filesystem_field(text, "Orphan file inode", source)
    if not orphan_inode.isdecimal() or int(orphan_inode) == 0:
        differences["Orphan file inode"] = {
            "expected": "nonzero decimal inode",
            "observed": orphan_inode,
        }

    if require_journal_features:
        journal = _filesystem_field(text, "Journal features", source)
        if journal != "(none)":
            differences["Journal features"] = {
                "expected": "(none)",
                "observed": journal,
            }

    if differences:
        raise ProfileError(
            f"{image_spec['id']} {source} header mismatch: "
            f"{json.dumps(differences, sort_keys=True)}"
        )


def _stat_integer(text: str, label: str, source: str) -> int:
    match = re.search(rf"\b{re.escape(label)}:\s*(\d+)", text)
    if match is None:
        raise ProfileError(f"{source} lacks integer stat field {label!r}")
    return int(match.group(1))


def _listing_entry(text: str, name: str, source: str) -> tuple[int, int]:
    matches: list[tuple[int, int]] = []
    for line in text.splitlines():
        fields = line.split()
        if len(fields) >= 7 and fields[-1] == name:
            try:
                matches.append((int(fields[0]), int(fields[5])))
            except ValueError:
                continue
    if len(matches) != 1:
        raise ProfileError(
            f"{source} expected one listing entry for {name!r}, "
            f"observed {len(matches)}"
        )
    return matches[0]


def _validate_debugfs_oracles(
    manifest: dict[str, Any],
    image_spec: dict[str, Any],
    results: dict[str, subprocess.CompletedProcess[str]],
    sparse_bytes: bytes,
    image: Path,
    population_facts: dict[str, Any],
) -> None:
    image_id = image_spec["id"]
    population = manifest["generator"]["population"]
    payload_size = len(population["payload_utf8"].encode("utf-8"))
    fast_target = "payload.txt"
    slow_target = population["slow_symlink_target"]
    block_size = image_spec["block_size"]
    is_read_side = image_spec.get("fixture_role") == "read_side"

    listing = _command_text(results["listing"])
    payload_listing = _listing_entry(listing, "payload.txt", image_id)
    hardlink_listing = _listing_entry(listing, "hardlink.txt", image_id)
    fast_listing = _listing_entry(listing, "fast-link", image_id)
    slow_listing = _listing_entry(listing, "slow-link", image_id)
    sparse_listing = _listing_entry(listing, "sparse.bin", image_id)
    if payload_listing != hardlink_listing:
        raise ProfileError(
            f"{image_id} hard link listing differs from payload: "
            f"{payload_listing} != {hardlink_listing}"
        )
    expected_sizes = {
        "payload.txt": (payload_listing[1], payload_size),
        "fast-link": (fast_listing[1], len(fast_target)),
        "slow-link": (slow_listing[1], len(slow_target)),
        "sparse.bin": (sparse_listing[1], block_size * 3),
    }
    if is_read_side:
        read_side = manifest["generator"]["read_side_population"]
        live_slow_target = read_side["live_slow_symlink_target"]
        live_slow_listing = _listing_entry(
            listing, "live-slow-link", image_id
        )
        extent_listing = _listing_entry(listing, "extent-tree.bin", image_id)
        legacy_listing = _listing_entry(listing, "legacy-map.bin", image_id)
        expected_sizes.update(
            {
                "extent-tree.bin": (
                    extent_listing[1],
                    block_size * len(read_side["extent_tree_patterns"]),
                ),
                "legacy-map.bin": (
                    legacy_listing[1],
                    population_facts["legacy_size"],
                ),
                "live-slow-link": (
                    live_slow_listing[1],
                    len(live_slow_target),
                ),
            }
        )
    wrong_sizes = {
        name: {"expected": expected, "observed": observed}
        for name, (observed, expected) in expected_sizes.items()
        if observed != expected
    }
    if wrong_sizes:
        raise ProfileError(
            f"{image_id} debugfs listing size mismatch: "
            f"{json.dumps(wrong_sizes, sort_keys=True)}"
        )

    payload_stat = _command_text(results["payload_stat"])
    hardlink_stat = _command_text(results["hardlink_stat"])
    payload_inode = _stat_integer(payload_stat, "Inode", image_id)
    hardlink_inode = _stat_integer(hardlink_stat, "Inode", image_id)
    if (
        payload_inode != hardlink_inode
        or payload_inode != payload_listing[0]
        or _stat_integer(payload_stat, "Links", image_id) != 2
        or _stat_integer(hardlink_stat, "Links", image_id) != 2
        or re.search(r"\bType:\s+regular\b", payload_stat) is None
        or re.search(r"\bType:\s+regular\b", hardlink_stat) is None
    ):
        raise ProfileError(f"{image_id} hard-link inode/link-count oracle failed")

    fast_stat = _command_text(results["fast_stat"])
    if (
        re.search(r"\bType:\s+symlink\b", fast_stat) is None
        or _stat_integer(fast_stat, "Inode", image_id) != fast_listing[0]
        or _stat_integer(fast_stat, "Size", image_id) != len(fast_target)
        or _stat_integer(fast_stat, "Links", image_id) != 1
        or _stat_integer(fast_stat, "Blockcount", image_id) != 0
        or f'Fast link dest: "{fast_target}"' not in fast_stat
    ):
        raise ProfileError(f"{image_id} fast-symlink oracle failed")

    slow_stat = _command_text(results["slow_stat"])
    if (
        re.search(r"\bType:\s+symlink\b", slow_stat) is None
        or _stat_integer(slow_stat, "Inode", image_id) != slow_listing[0]
        or _stat_integer(slow_stat, "Size", image_id) != len(slow_target)
        or _stat_integer(slow_stat, "Links", image_id) != 1
        or _stat_integer(slow_stat, "Blockcount", image_id) == 0
        or "EXTENTS:" not in slow_stat
        or results["slow_target"].stdout != slow_target
    ):
        raise ProfileError(f"{image_id} block-backed symlink oracle failed")

    if is_read_side:
        live_slow_stat = _command_text(results["live_slow_stat"])
        live_slow_target = read_side["live_slow_symlink_target"]
        if (
            re.search(r"\bType:\s+symlink\b", live_slow_stat) is None
            or _stat_integer(live_slow_stat, "Inode", image_id)
            != live_slow_listing[0]
            or _stat_integer(live_slow_stat, "Size", image_id)
            != len(live_slow_target)
            or _stat_integer(live_slow_stat, "Links", image_id) != 1
            or _stat_integer(live_slow_stat, "Blockcount", image_id) == 0
            or "EXTENTS:" not in live_slow_stat
            or results["live_slow_target"].stdout != live_slow_target
        ):
            raise ProfileError(
                f"{image_id} live block-backed symlink oracle failed"
            )

    extent_text = _command_text(results["sparse_extents"])
    logical_ranges = [
        (int(start), int(end))
        for start, end in re.findall(
            r"(?m)^\s*\d+/\s*\d+\s+\d+/\s*\d+\s+"
            r"(\d+)\s*-\s*(\d+)\s+\d+\s*-\s*\d+\s+\d+",
            extent_text,
        )
    ]
    if logical_ranges != [(0, 0), (2, 2)]:
        raise ProfileError(
            f"{image_id} sparse extent map is not blocks 0,hole,2: "
            f"{logical_ranges}"
        )
    expected_sparse = b"A" * block_size + b"\0" * block_size + b"C" * block_size
    if sparse_bytes != expected_sparse:
        raise ProfileError(f"{image_id} sparse file readback differs")

    xattr_text = _command_text(results["xattrs"])
    observed_xattrs = {
        line.strip()
        for line in xattr_text.splitlines()
        if line.strip().startswith(
            ("user.", "trusted.", "security.", "system.")
        )
    }
    expected_xattrs = {
        'user.akashic (10) = "profile-v1"',
        "user.akashic.large (300)",
    }
    if is_read_side:
        read_side = manifest["generator"]["read_side_population"]
        expected_xattrs.update(
            {
                "user.akashic.large2 (260)",
                'trusted.akashic (10) = "trusted-v1"',
                'security.akashic (11) = "security-v1"',
                    "system.posix_acl_access (28) = "
                    + " ".join(
                        f"{byte:02x}"
                        for byte in bytes.fromhex(
                            read_side["acl_access_value_hex"]
                        )
                    ),
            }
        )
    if observed_xattrs != expected_xattrs:
        raise ProfileError(
            f"{image_id} xattr oracle mismatch: "
            f"{sorted(observed_xattrs)}"
        )

    if not is_read_side:
        return

    fixture_xattrs = {
        line.strip()
        for line in _command_text(results["fixture_xattrs"]).splitlines()
        if line.strip().startswith("system.")
    }
    expected_default_acl = (
        "system.posix_acl_default (28) = "
        + " ".join(
            f"{byte:02x}"
            for byte in bytes.fromhex(read_side["acl_default_value_hex"])
        )
    )
    if fixture_xattrs != {expected_default_acl}:
        raise ProfileError(
            f"{image_id} default ACL oracle mismatch: {sorted(fixture_xattrs)}"
        )

    extent_text = _command_text(results["extent_extents"])
    extent_ranges = [
        (int(start), int(end))
        for start, end in re.findall(
            r"(?m)^\s*\d+/\s*\d+\s+\d+/\s*\d+\s+"
            r"(\d+)\s*-\s*(\d+)\s+\d+\s*-\s*\d+\s+\d+",
            extent_text,
        )
    ]
    if extent_ranges != [
        (0, 0),
        (2, 2),
        (4, 4),
        (6, 6),
        (8, 8),
        (10, 11),
    ]:
        raise ProfileError(
            f"{image_id} external extent-tree oracle mismatch: {extent_ranges}"
        )
    extent_stat = _command_text(results["extent_stat"])
    if "(ETB0):" not in extent_stat:
        raise ProfileError(f"{image_id} extent tree did not acquire an external node")

    legacy_stat = _command_text(results["legacy_stat"])
    # Five data blocks plus the single-, double-, and triple-indirect metadata
    # path (one + two + three blocks).  The adjacent triple-indirect data
    # blocks deliberately share metadata while exercising a nonzero leaf slot.
    expected_blockcount = 11 * (block_size // 512)
    if (
        "Flags: 0x0" not in legacy_stat
        or _stat_integer(legacy_stat, "Size", image_id)
        != population_facts["legacy_size"]
        or _stat_integer(legacy_stat, "Blockcount", image_id)
        != expected_blockcount
        or "(IND):" not in legacy_stat
        or "(DIND):" not in legacy_stat
        or "(TIND):" not in legacy_stat
    ):
        raise ProfileError(f"{image_id} legacy map oracle failed")
    for index, (physical, pattern) in enumerate(
        zip(
            population_facts["legacy_physical"],
            read_side["legacy_map_patterns"],
            strict=True,
        )
    ):
        text = results[f"legacy_bmap_{index}"].stdout
        matches = re.findall(r"(?m)^(\d+)\s*$", text)
        if matches != [str(physical)]:
            raise ProfileError(
                f"{image_id} legacy bmap oracle {index} differs: {matches}"
            )
        with image.open("rb") as source:
            source.seek(physical * block_size)
            observed = source.read(block_size)
        if observed != bytes((pattern,)) * block_size:
            raise ProfileError(
                f"{image_id} legacy data pattern {index} differs at {physical}"
            )

    indexed_stat = _command_text(results["indexed_stat"])
    htree = _command_text(results["indexed_htree"])
    flags = re.search(r"\bFlags:\s+0x([0-9a-fA-F]+)", indexed_stat)
    continuation = f"Hash 0x{population_facts['htree_collision_hash'] | 1:08x} (**)"
    if (
        flags is None
        or int(flags.group(1), 16) & 0x1000 == 0
        or "Root node dump" not in htree
        or continuation not in htree
    ):
        raise ProfileError(f"{image_id} HTree index oracle failed")
    indexed_listing = _command_text(results["indexed_listing"])
    for name in (
        population_facts["indexed_names"][0],
        population_facts["indexed_names"][len(population_facts["indexed_names"]) // 2],
        population_facts["indexed_names"][-1],
    ):
        inode, size = _listing_entry(indexed_listing, name, image_id)
        if inode == 0 or size != 0:
            raise ProfileError(f"{image_id} HTree entry oracle failed for {name}")

    special_expectations = {
        "char_stat": ("Type: character special", "05:01"),
        "block_stat": ("Type: block special", "259:513"),
        "fifo_stat": ("Type: FIFO", ""),
    }
    for key, (kind, device) in special_expectations.items():
        text = _command_text(results[key])
        if kind not in text or (device and device not in text):
            raise ProfileError(f"{image_id} special inode oracle failed: {key}")

    symlink_targets = {
        "absolute_target": "/fixture/payload.txt",
        "chain_a_target": "chain-b",
        "chain_b_target": "payload.txt",
        "dangling_target": "missing-target",
        "loop_a_target": "loop-b",
        "loop_b_target": "loop-a",
        "fixture_dir_target": "fixture",
    }
    for key, expected in symlink_targets.items():
        text = _command_text(results[key])
        if f'Fast link dest: "{expected}"' not in text:
            raise ProfileError(
                f"{image_id} symlink target {key} differs: {text!r}"
            )


def generate_one(
    manifest: dict[str, Any],
    image_spec: dict[str, Any],
    output_dir: Path,
    tools: dict[str, dict[str, str]],
    env: dict[str, str],
) -> dict[str, Any]:
    image = output_dir / image_spec["filename"]
    image.parent.mkdir(parents=True, exist_ok=True)
    with image.open("wb") as destination:
        destination.truncate(image_spec["image_bytes"])

    names = profile_feature_names(manifest, image_spec)
    context = dict(image_spec)
    context.update(
        {
            "tool_dir": Path(tools["mke2fs"]["path"]).parent,
            "image": image,
            "feature_names": ",".join(names),
        }
    )
    mkfs_argv = render_argv(manifest["generator"]["mkfs_argv"], context)
    mkfs = _run(mkfs_argv, env=env)

    with tempfile.TemporaryDirectory(
        prefix=f".{image_spec['id']}.", dir=output_dir
    ) as directory:
        debugfs_write_argv, population_facts = populate_image(
            manifest,
            image_spec,
            tools,
            env,
            image,
            image_spec["block_size"],
            Path(directory),
        )

    directory_index_argv: list[str] = []
    directory_index: subprocess.CompletedProcess[str] | None = None
    timestamp_normalization_argv: list[list[str]] = []
    if image_spec.get("fixture_role") == "read_side":
        directory_index_argv = render_argv(
            manifest["generator"]["directory_index_argv"], context
        )
        directory_index = _run(
            directory_index_argv, env=env, expected_status=(0, 1)
        )
        fake_time = manifest["generator"]["environment"]["E2FSPROGS_FAKE_TIME"]
        for field in ("wtime_lo", "lastcheck_lo"):
            argv = [
                tools["debugfs"]["path"],
                "-w",
                "-R",
                f"set_super_value {field} {fake_time}",
                str(image),
            ]
            _run(argv, env=env)
            timestamp_normalization_argv.append(argv)

    fsck_context = dict(context)
    e2fsck_argv = render_argv(manifest["generator"]["e2fsck_argv"], fsck_context)
    fsck = _run(e2fsck_argv, env=env)
    dumpe2fs_argv = [tools["dumpe2fs"]["path"], "-h", str(image)]
    dumpe2fs = _run(dumpe2fs_argv, env=env)
    with tempfile.TemporaryDirectory(
        prefix=f".{image_spec['id']}.readback.", dir=output_dir
    ) as directory:
        sparse_dump = Path(directory) / "sparse.bin"
        debugfs_commands = {
            "stats": "stats",
            "listing": "ls -l /fixture",
            "payload_stat": "stat /fixture/payload.txt",
            "hardlink_stat": "stat /fixture/hardlink.txt",
            "fast_stat": "stat /fixture/fast-link",
            "slow_stat": "stat /fixture/slow-link",
            "slow_target": "cat /fixture/slow-link",
            "sparse_extents": "dump_extents /fixture/sparse.bin",
            "sparse_dump": f"dump /fixture/sparse.bin {sparse_dump}",
            "xattrs": "ea_list /fixture/payload.txt",
        }
        if image_spec.get("fixture_role") == "read_side":
            debugfs_commands.update(
                {
                    "fixture_xattrs": "ea_list /fixture",
                    "extent_stat": "stat /fixture/extent-tree.bin",
                    "extent_extents": "dump_extents /fixture/extent-tree.bin",
                    "legacy_stat": "stat /fixture/legacy-map.bin",
                    "indexed_stat": "stat /fixture/indexed",
                    "indexed_listing": "ls -l /fixture/indexed",
                    "indexed_htree": "htree_dump /fixture/indexed",
                    "char_stat": "stat /fixture/char-old",
                    "block_stat": "stat /fixture/block-new",
                    "fifo_stat": "stat /fixture/fifo",
                    "absolute_target": "stat /fixture/absolute-link",
                    "live_slow_stat": "stat /fixture/live-slow-link",
                    "live_slow_target": "cat /fixture/live-slow-link",
                    "chain_a_target": "stat /fixture/chain-a",
                    "chain_b_target": "stat /fixture/chain-b",
                    "dangling_target": "stat /fixture/dangling-link",
                    "loop_a_target": "stat /fixture/loop-a",
                    "loop_b_target": "stat /fixture/loop-b",
                    "fixture_dir_target": "stat /fixture-dir",
                }
            )
            for index, logical in enumerate(population_facts["legacy_logical"]):
                debugfs_commands[f"legacy_bmap_{index}"] = (
                    f"bmap /fixture/legacy-map.bin {logical}"
                )
        debugfs_read_argv = {
            name: [
                tools["debugfs"]["path"],
                "-R",
                command,
                str(image),
            ]
            for name, command in debugfs_commands.items()
        }
        debugfs_read = {
            name: _run(argv, env=env)
            for name, argv in debugfs_read_argv.items()
        }
        sparse_bytes = sparse_dump.read_bytes()
        _validate_debugfs_oracles(
            manifest,
            image_spec,
            debugfs_read,
            sparse_bytes,
            image,
            population_facts,
        )
        read_text = "\n".join(
            _command_text(result) for result in debugfs_read.values()
        )

    _validate_filesystem_header(
        manifest,
        image_spec,
        _command_text(dumpe2fs),
        "dumpe2fs",
        require_journal_features=True,
    )
    _validate_filesystem_header(
        manifest,
        image_spec,
        _command_text(debugfs_read["stats"]),
        "debugfs stats",
        require_journal_features=False,
    )

    observed = read_superblock(image)
    validate_observed_superblock(manifest, image_spec, observed)
    if image.stat().st_size != image_spec["image_bytes"]:
        raise ProfileError(f"{image_spec['id']} changed its pinned byte length")

    image_sha256 = sha256_file(image)
    expected_sha256 = image_spec.get("expected_sha256")
    if expected_sha256 is not None and image_sha256 != expected_sha256:
        raise ProfileError(
            f"{image_spec['id']} is not byte-reproducible: expected "
            f"{expected_sha256}, observed {image_sha256}"
        )

    return {
        "id": image_spec["id"],
        "path": str(image),
        "bytes": image.stat().st_size,
        "sha256": image_sha256,
        "observed_superblock": observed,
        "commands": {
            "mke2fs": mkfs_argv,
            "debugfs_write": debugfs_write_argv,
            "directory_index": directory_index_argv,
            "timestamp_normalization": timestamp_normalization_argv,
            "e2fsck": e2fsck_argv,
            "dumpe2fs": dumpe2fs_argv,
            "debugfs_read": debugfs_read_argv,
        },
        "evidence": {
            "mke2fs_output_sha256": sha256_text(mkfs.stdout + mkfs.stderr),
            "directory_index_exit": (
                directory_index.returncode if directory_index is not None else None
            ),
            "directory_index_output_sha256": (
                sha256_text(directory_index.stdout + directory_index.stderr)
                if directory_index is not None
                else None
            ),
            "e2fsck_exit": fsck.returncode,
            "e2fsck_output_sha256": sha256_text(fsck.stdout + fsck.stderr),
            "dumpe2fs_output_sha256": sha256_text(
                dumpe2fs.stdout + dumpe2fs.stderr
            ),
            "debugfs_output_sha256": sha256_text(read_text),
        },
    }


def generate(
    manifest_path: Path,
    tool_dir: Path,
    output_dir: Path,
    selected_images: set[str] | None = None,
) -> dict[str, Any]:
    manifest_path = manifest_path.resolve()
    output_dir = output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    evidence_path = output_dir / "qualification.json"
    temporary_evidence_path = output_dir / ".qualification.json.tmp"
    evidence_path.unlink(missing_ok=True)
    temporary_evidence_path.unlink(missing_ok=True)

    manifest = load_manifest(manifest_path)
    config = manifest_path.parent / "mke2fs.conf"
    expected_config_hash = manifest["generator"]["mke2fs_config_sha256"]
    if sha256_file(config) != expected_config_hash:
        raise ProfileError(f"pinned mke2fs.conf hash mismatch: {config}")

    tool_dir = tool_dir.resolve()
    env = pinned_environment(manifest, tool_dir, manifest_path)
    tools = verify_toolchain(manifest, tool_dir, env)
    specs = [
        image
        for image in manifest["images"]
        if selected_images is None or image["id"] in selected_images
    ]
    if selected_images is not None:
        found = {image["id"] for image in specs}
        unknown = selected_images - found
        if unknown:
            raise ProfileError(f"unknown requested image ids: {sorted(unknown)}")

    images = [generate_one(manifest, spec, output_dir, tools, env) for spec in specs]
    qualification = {
        "schema": "akashic.ext4-profile-qualification.v1",
        "profile_id": manifest["profile_id"],
        "manifest": str(manifest_path),
        "manifest_sha256": sha256_file(manifest_path),
        "mke2fs_config_sha256": expected_config_hash,
        "environment": env,
        "tools": tools,
        "images": images,
    }
    temporary_evidence_path.write_text(
        json.dumps(qualification, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    temporary_evidence_path.replace(evidence_path)
    return qualification


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--manifest", type=Path, default=DEFAULT_MANIFEST, help="profile manifest"
    )
    parser.add_argument(
        "--tool-dir",
        type=Path,
        required=True,
        help="directory containing the complete pinned e2fsprogs suite",
    )
    parser.add_argument(
        "--output-dir", type=Path, default=DEFAULT_OUTPUT, help="generated output"
    )
    parser.add_argument(
        "--image",
        action="append",
        dest="images",
        help="generate only this manifest image id (repeatable)",
    )
    return parser


def main() -> int:
    args = _parser().parse_args()
    try:
        result = generate(
            args.manifest,
            args.tool_dir,
            args.output_dir,
            set(args.images) if args.images else None,
        )
    except ProfileError as error:
        print(f"EXT4 PROFILE FAIL: {error}")
        return 1
    print(
        f"EXT4 PROFILE PASS: {len(result['images'])} image(s); "
        f"evidence {args.output_dir / 'qualification.json'}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
