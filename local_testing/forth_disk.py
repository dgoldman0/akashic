"""Load Akashic modules from an MP64FS disk the way KDOS's REQUIRE finds them.

Some suites write the modules they test to an MP64FS disk, boot KDOS from it
and let ``REQUIRE`` load the modules from their directories.  A disk listed
by hand goes stale as soon as a module comes to require another, and KDOS
then reports the missing module and carries on, so these suites build the
disk from the roots' REQUIRE closure and fail on any KDOS diagnostic in the
transcript, not only on their own PASS and FAIL lines.
"""

from __future__ import annotations

from pathlib import Path

from forth_dependencies import dependency_order
from forth_snapshot import KDOS_DIAGNOSTICS, SOURCE_ROOT


# What KDOS prints when a module it loads from disk names a file or a
# directory the disk lacks.
DISK_LOAD_DIAGNOSTICS = (
    "Module not found",
    "Path component not found",
)


def module_disk_files(roots: tuple[str, ...]) -> list[tuple[str, str, Path]]:
    """``(name, directory, host path)`` for ROOTS and their REQUIRE closure.

    ROOTS name modules under akashic/akashic.  Each file goes to its own
    directory on the disk, in dependency order.
    """

    files = []
    for module in dependency_order(SOURCE_ROOT, roots):
        directory, _, name = module.rpartition("/")
        files.append((name, "/" + directory, SOURCE_ROOT / module))
    return files


def kdos_diagnostics(text: str) -> list[str]:
    """The KDOS diagnostics a whole transcript holds."""

    return [item for item in KDOS_DIAGNOSTICS + DISK_LOAD_DIAGNOSTICS
            if item in text]
