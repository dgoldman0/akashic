"""Where Akashic and the MegaPad checkout the image tool builds for sit.

MEGAPAD_ROOT names MegaPad's checkout, and the image tool reads its BIOS,
KDOS and system modules and imports its disk, token-form and simulator
modules from there.  Importing this module puts that checkout first on the
module path.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

AKASHIC_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = AKASHIC_ROOT / "akashic"
DEFAULT_MEGAPAD_ROOT = AKASHIC_ROOT.parent / "megapad"


def _megapad_root() -> Path:
    configured = os.environ.get("MEGAPAD_ROOT")
    root = Path(configured).expanduser() if configured else DEFAULT_MEGAPAD_ROOT
    root = root.resolve()
    required = (
        "bios.asm",
        "kdos.f",
        "networking.f",
        "diskutil.py",
        "emulator/session.py",
        "shared/session.py",
    )
    missing = [name for name in required if not (root / name).is_file()]
    if missing:
        detail = ", ".join(missing)
        raise RuntimeError(
            f"MegaPad checkout not found at {root} (missing: {detail}). "
            "Set MEGAPAD_ROOT to the emulator repository."
        )
    return root



MEGAPAD_ROOT = _megapad_root()
sys.path.insert(0, str(MEGAPAD_ROOT))
