"""Build a configuration's volumes.

    python3 -m toolchain.image check CONFIGURATION
    python3 -m toolchain.image build CONFIGURATION IMAGE
        [--fresh-user-volume] [--built-from FILE]
    python3 -m toolchain.image host

check reads a configuration and prints what it says as JSON, or says what
is wrong and exits with 1.  build writes the boot image at IMAGE, the
settings, system and user volumes beside it, and the session manifest
(IMAGE's name with -session.json).  A user volume that is already there is
kept, documents and all, unless --fresh-user-volume asks for a new one.
--built-from names a JSON file of what the caller built from, such as its
components' commits, which the manifest records with the configuration's
own digests.  host prints, as JSON, the e2fsprogs tools a build would make
the ext4 volumes with, or says what this computer lacks and exits with 1.
Run it from Akashic's root.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .configuration import ConfigurationError, build, host, read, summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="python3 -m toolchain.image",
        description="Build a configuration's volumes.",
    )
    commands = parser.add_subparsers(dest="command", required=True)
    check = commands.add_parser("check", help="read a configuration and print what it says")
    check.add_argument("configuration", type=Path)
    make = commands.add_parser("build", help="build a configuration's volumes")
    make.add_argument("configuration", type=Path)
    make.add_argument("image", type=Path, help="the boot image to write")
    make.add_argument(
        "--fresh-user-volume",
        action="store_true",
        help="replace a user volume that is already there",
    )
    make.add_argument(
        "--built-from",
        type=Path,
        metavar="FILE",
        help="a JSON object of what the caller built from, for the manifest",
    )
    commands.add_parser("host", help="check what a build needs from this computer")
    args = parser.parse_args(argv)
    try:
        if args.command == "host":
            print(json.dumps(host(), indent=2, sort_keys=True))
            return 0
        configuration = read(args.configuration)
        if args.command == "check":
            print(json.dumps(summary(configuration), indent=2, sort_keys=True))
            return 0
        built_from = None
        if args.built_from is not None:
            built_from = json.loads(args.built_from.read_text(encoding="utf-8"))
            if not isinstance(built_from, dict):
                parser.error("--built-from must name a file holding a JSON object")
        build(
            configuration,
            args.image,
            fresh_user_volume=args.fresh_user_volume,
            built_from=built_from,
        )
    except ConfigurationError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
