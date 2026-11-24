"""Configurations: what a machine runs, in one TOML file.

A configuration names the applets Desk opens in tiles and offers on its
launcher, the Agent's provider, the machine's memory and full cores, the
user and system volumes, the viewer's size, the network, and values for
Desk's system settings.  read() checks a file and returns its
Configuration, image_spec() gives the build description, and build() builds
the volumes and the session manifest a server runs them from.  host() checks
what a build needs from the computer.  The format is described in
docs/image/configuration.md.  The harness never imports this module.
"""

from __future__ import annotations

import hashlib
import tomllib
from collections.abc import Mapping
from dataclasses import dataclass, replace
from pathlib import Path

from . import build as image_build
from .build import COLD_SOURCE_CODEC_STORED, USER_VOLUME_DEFAULT_MIB, ImageSpec
from .desk import (
    ADJACENT_DESK_APPLETS,
    DESK_APPLETS,
    DESK_SYSTEM_SETTINGS,
    desktop_autoexec,
    desktop_resources,
    desktop_roots,
)
from .megapad import AKASHIC_ROOT, MEGAPAD_ROOT, SOURCE_ROOT
from .rich import (
    DESKTOP_APT1_EXT_MEM_MIB,
    DESKTOP_APT1_RICH_TERMINAL,
    DESKTOP_APT1_XMEM_RESERVE_BYTES,
)

# The format this reader takes, which every file names.
FORMAT = 1


class ConfigurationError(ValueError):
    """A configuration that cannot be built, with what is wrong and where."""


# The name a configuration gives each applet Desk can open: its own, except
# File Explorer's, which is spelt out.
APPLETS = {
    ("file-explorer" if applet.name == "fexp" else applet.name): applet
    for applet in (*DESK_APPLETS, *ADJACENT_DESK_APPLETS)
}
# The Agent's providers.  Until real providers arrive, the scripted one,
# which the Desktop's journey relies on, is the only one.
PROVIDERS = ("scripted",)

# Components a documents path may name, and the folder each resolves in.
COMPONENT_ROOTS = {"akashic": AKASHIC_ROOT, "megapad": MEGAPAD_ROOT}

# Values a configuration may leave out.
DEFAULT_MEMORY_MIB = DESKTOP_APT1_EXT_MEM_MIB
DEFAULT_CORES = 1
DEFAULT_VIEWER = {"cols": 160, "rows": 48, "font-size": 16}

# The rich Desktop's boot volume: room for its linked modules and samples,
# with a mebibyte kept free for what Desk writes as it starts.
DESKTOP_TOTAL_SECTORS = 65536
DESKTOP_MINIMUM_FREE_BYTES = 1 << 20
DESKTOP_SESSION_ENTRY = "_boot-desktop-session-entry"

# Each table's keys and their types.  [desk.*] tables are Desk's system
# settings, checked against the file Akashic ships (_desk_settings).
_TABLES: dict[str, dict[str, type]] = {
    "configuration": {"format": int, "title": str, "description": str},
    "practice": {"entry": list, "offer": list},
    "agent": {"provider": str},
    "machine": {"memory-mib": int, "cores": int},
    "volumes": {"user": dict, "system": dict},
    "volumes.user": {"size-mib": int, "documents": str},
    "volumes.system": {"keep-source": bool},
    "viewer": {"cols": int, "rows": int, "font-size": int},
    "network": {"enabled": bool, "local-access": bool},
}
# The tables a file may hold.
_TOP_TABLES = ("configuration", "practice", "agent", "machine", "volumes",
               "viewer", "network", "desk")
_REQUIRED = {"configuration": ("format", "title")}
_TYPE_NAMES = {bool: "a boolean", int: "a whole number", str: "a string",
               list: "an array", dict: "a table"}


@dataclass(frozen=True)
class Configuration:
    """A checked configuration file."""

    path: Path
    sha256: str  # of the file's bytes
    title: str
    description: str
    entries: tuple[str, ...]  # the applets Desk opens in tiles, in order
    offers: tuple[str, ...]  # the applets Desk offers on its launcher
    provider: str | None  # the Agent's, when Desk opens or offers it
    memory_mib: int  # MegaPad's external memory
    cores: int  # full cores
    user_mib: int
    documents: Path | None  # copied into a new user volume's documents
    keep_source: bool  # module source beside the token forms
    viewer: Mapping[str, int]  # cols, rows and font-size
    network: bool
    local_access: bool
    desk: Mapping[str, Mapping[str, object]]  # {table: {key: value}}


def _typed(value: object, kind: type, where: str) -> object:
    # TOML's booleans are Python ints; a whole number must not be one.
    if kind is int and (isinstance(value, bool) or not isinstance(value, int)):
        raise ConfigurationError(f"{where} must be {_TYPE_NAMES[int]}")
    if not isinstance(value, kind):
        raise ConfigurationError(f"{where} must be {_TYPE_NAMES[kind]}")
    return value


def _table(data: Mapping[str, object], name: str) -> dict[str, object]:
    """The table NAME of DATA, each key known and typed, the required ones
    present; empty when absent."""

    keys = _TABLES[name]
    unknown = sorted(data.keys() - keys.keys())
    if unknown:
        raise ConfigurationError(
            "unknown key " + ", ".join(f"{name}.{key}" for key in unknown)
        )
    missing = [key for key in _REQUIRED.get(name, ()) if key not in data]
    if missing:
        raise ConfigurationError(
            "missing key " + ", ".join(f"{name}.{key}" for key in missing)
        )
    return {key: _typed(value, keys[key], f"{name}.{key}") for key, value in data.items()}


def _positive(value: int, where: str) -> int:
    if value <= 0:
        raise ConfigurationError(f"{where} must be above zero")
    return value


def _applet(name: object, where: str) -> str:
    if not isinstance(name, str):
        raise ConfigurationError(f"{where} must be {_TYPE_NAMES[str]}")
    if name not in APPLETS:
        raise ConfigurationError(
            f"{where} names no applet Desk can open: {name!r} "
            f"(the applets are {', '.join(sorted(APPLETS))})"
        )
    return name


def _documents(value: str, folder: Path) -> Path:
    """The documents folder VALUE names: COMPONENT:PATH inside that
    component, or a path relative to the configuration's FOLDER."""

    component, colon, rest = value.partition(":")
    if colon and component in COMPONENT_ROOTS:
        path = COMPONENT_ROOTS[component] / rest
    elif colon and "/" not in component:
        raise ConfigurationError(
            f"volumes.user.documents names no component: {component!r} "
            f"(the components are {', '.join(sorted(COMPONENT_ROOTS))})"
        )
    else:
        path = folder / value
    if not path.is_dir():
        raise ConfigurationError(f"volumes.user.documents is not a folder: {path}")
    return path


def _desk_settings() -> dict[str, dict[str, object]]:
    """Desk's system settings as Akashic ships them, {table: {key: value}}."""

    with (SOURCE_ROOT / DESK_SYSTEM_SETTINGS).open("rb") as source:
        return tomllib.load(source)["desk"]


def _desk(data: object) -> dict[str, dict[str, object]]:
    """The [desk.*] tables' values, each table and key one that Desk's
    system settings hold, of the same type.  Local access belongs to
    [network], which writes it for Desk too."""

    if not isinstance(data, dict):
        raise ConfigurationError("desk must be a table of tables")
    shipped = _desk_settings()
    values: dict[str, dict[str, object]] = {}
    for table, keys in data.items():
        where = f"desk.{table}"
        if table == "network":
            raise ConfigurationError(
                "desk.network is set through [network]: local-access there "
                "opens the network and tells Desk"
            )
        if table not in shipped or not isinstance(keys, dict):
            raise ConfigurationError(f"unknown table {where}")
        unknown = sorted(keys.keys() - shipped[table].keys())
        if unknown:
            raise ConfigurationError(
                "unknown key " + ", ".join(f"{where}.{key}" for key in unknown)
            )
        values[table] = {
            key: _typed(value, type(shipped[table][key]), f"{where}.{key}")
            for key, value in keys.items()
        }
    return values


def read(path: Path) -> Configuration:
    """The configuration in the TOML file at PATH, checked."""

    path = Path(path).resolve()
    try:
        raw = path.read_bytes()
        data = tomllib.loads(raw.decode("utf-8"))
    except (OSError, UnicodeDecodeError, tomllib.TOMLDecodeError) as error:
        raise ConfigurationError(f"{path}: {error}") from error
    try:
        return _check(path, raw, data)
    except ConfigurationError as error:
        raise ConfigurationError(f"{path}: {error}") from None


def _check(path: Path, raw: bytes, data: dict[str, object]) -> Configuration:
    unknown = sorted(data.keys() - set(_TOP_TABLES))
    if unknown:
        raise ConfigurationError("unknown table " + ", ".join(unknown))
    for name in ("configuration", "practice", "agent", "machine", "volumes",
                 "viewer", "network"):
        if name in data and not isinstance(data[name], dict):
            raise ConfigurationError(f"{name} must be {_TYPE_NAMES[dict]}")
    configuration = _table(data.get("configuration", {}), "configuration")
    if configuration["format"] != FORMAT:
        raise ConfigurationError(
            f"configuration.format is {configuration['format']}; this reader "
            f"takes format {FORMAT}"
        )

    practice = _table(data.get("practice", {}), "practice")
    entries = []
    for index, entry in enumerate(practice.get("entry", ())):
        where = f"practice.entry[{index}]"
        if not isinstance(entry, dict):
            raise ConfigurationError(f"{where} must be {_TYPE_NAMES[dict]}")
        unknown = sorted(entry.keys() - {"applet"})
        if unknown:
            raise ConfigurationError(
                "unknown key " + ", ".join(f"{where}.{key}" for key in unknown)
            )
        if "applet" not in entry:
            raise ConfigurationError(f"missing key {where}.applet")
        entries.append(_applet(entry["applet"], f"{where}.applet"))
    offers = [
        _applet(name, f"practice.offer[{index}]")
        for index, name in enumerate(practice.get("offer", ()))
    ]
    named = entries + offers
    twice = sorted({name for name in named if named.count(name) > 1})
    if twice:
        raise ConfigurationError("practice names twice: " + ", ".join(twice))
    if not entries:
        raise ConfigurationError("practice opens no applet: add a [[practice.entry]]")

    agent = _table(data.get("agent", {}), "agent")
    provider = agent.get("provider")
    if "agent" in named:
        if provider is None:
            raise ConfigurationError("the Agent needs [agent] provider")
        if provider not in PROVIDERS:
            raise ConfigurationError(
                f"agent.provider {provider!r} is not one of {', '.join(PROVIDERS)}"
            )
    elif "agent" in data:
        raise ConfigurationError("[agent] is for the Agent, which practice does not name")

    machine = _table(data.get("machine", {}), "machine")
    memory_mib = _positive(machine.get("memory-mib", DEFAULT_MEMORY_MIB), "machine.memory-mib")
    cores = machine.get("cores", DEFAULT_CORES)
    if not 1 <= cores <= 4:
        raise ConfigurationError("machine.cores must be 1 to 4")

    volumes = _table(data.get("volumes", {}), "volumes")
    user = _table(volumes.get("user", {}), "volumes.user")
    system = _table(volumes.get("system", {}), "volumes.system")
    user_mib = _positive(user.get("size-mib", USER_VOLUME_DEFAULT_MIB), "volumes.user.size-mib")
    documents = (
        _documents(user["documents"], path.parent) if "documents" in user else None
    )

    viewer = dict(DEFAULT_VIEWER)
    viewer.update(_table(data.get("viewer", {}), "viewer"))
    for key, value in viewer.items():
        _positive(value, f"viewer.{key}")

    network = _table(data.get("network", {}), "network")
    enabled = network.get("enabled", False)
    local_access = network.get("local-access", False)
    if local_access and not enabled:
        raise ConfigurationError("network.local-access needs network.enabled = true")

    return Configuration(
        path=path,
        sha256=hashlib.sha256(raw).hexdigest(),
        title=configuration["title"],
        description=configuration.get("description", ""),
        entries=tuple(entries),
        offers=tuple(offers),
        provider=provider,
        memory_mib=memory_mib,
        cores=cores,
        user_mib=user_mib,
        documents=documents,
        keep_source=system.get("keep-source", False),
        viewer=viewer,
        network=enabled,
        local_access=local_access,
        desk=_desk(data.get("desk", {})),
    )


def summary(configuration: Configuration) -> dict[str, object]:
    """What CONFIGURATION says, as JSON-ready values, with the digests a
    build records in its manifest's built_from, so a caller can tell whether
    a build is current."""

    return {
        "path": str(configuration.path),
        "sha256": configuration.sha256,
        "documents_sha256": _digest(documents(configuration)),
        "title": configuration.title,
        "description": configuration.description,
        "entries": list(configuration.entries),
        "offers": list(configuration.offers),
        "provider": configuration.provider,
        "memory_mib": configuration.memory_mib,
        "cores": configuration.cores,
        "user_mib": configuration.user_mib,
        "documents": None if configuration.documents is None else str(configuration.documents),
        "keep_source": configuration.keep_source,
        "viewer": dict(configuration.viewer),
        "network": configuration.network,
        "local_access": configuration.local_access,
        "desk": {table: dict(keys) for table, keys in configuration.desk.items()},
    }


def image_spec(configuration: Configuration) -> ImageSpec:
    """The rich Desktop that CONFIGURATION describes: Desk opening its
    entries in tiles, in order, and offering its offers on the launcher."""

    applets = (
        *(replace(APPLETS[name], tile=True) for name in configuration.entries),
        *(replace(APPLETS[name], tile=False) for name in configuration.offers),
    )
    return ImageSpec(
        roots=desktop_roots(applets, rich=True),
        resources=desktop_resources(applets),
        autoexec=desktop_autoexec(applets, rich=True),
        linked=True,
        cold_source_codec=COLD_SOURCE_CODEC_STORED,
        total_sectors=DESKTOP_TOTAL_SECTORS,
        minimum_free_bytes=DESKTOP_MINIMUM_FREE_BYTES,
        settings_files=(DESK_SYSTEM_SETTINGS,),
        rich_terminal=DESKTOP_APT1_RICH_TERMINAL,
        rich_boot_progress=True,
        default_ext_mem_mib=configuration.memory_mib,
        general_xmem_reserve_bytes=DESKTOP_APT1_XMEM_RESERVE_BYTES,
        session_entry=DESKTOP_SESSION_ENTRY,
        full_cores=configuration.cores,
    )


def documents(configuration: Configuration) -> dict[str, bytes]:
    """The files a new user volume's documents place starts with: each
    regular file of the documents folder, by name."""

    if configuration.documents is None:
        return {}
    folder = configuration.documents
    found = {}
    for path in sorted(folder.iterdir()):
        if path.is_dir():
            raise ConfigurationError(
                f"{configuration.path}: volumes.user.documents holds a folder, "
                f"which the documents place does not take: {path.name}"
            )
        if path.is_file():
            found[path.name] = path.read_bytes()
    return found


def settings_values(configuration: Configuration) -> dict[str, dict[str, dict[str, object]]]:
    """The values CONFIGURATION gives Desk's system settings, local access
    among them, by settings file and table."""

    tables = {f"desk.{table}": dict(keys) for table, keys in configuration.desk.items()}
    tables["desk.network"] = {"local-access": configuration.local_access}
    return {DESK_SYSTEM_SETTINGS: tables}


def _digest(files: Mapping[str, bytes]) -> str:
    identity = hashlib.sha256()
    for name in sorted(files):
        identity.update(f"{name}\0{hashlib.sha256(files[name]).hexdigest()}\n".encode())
    return identity.hexdigest()


def host() -> dict[str, object]:
    """What a build needs from this computer, as a build finds it: the
    e2fsprogs tools that make the ext4 volumes, each with its path and the
    version it reports.  Tools that are missing, older than the profile's
    minimum or not linked to their own library raise ConfigurationError
    saying so."""

    try:
        _manifest, _environment, tools = image_build._system_volume_toolchain()
    except RuntimeError as error:
        raise ConfigurationError(str(error)) from None
    return {
        "e2fsprogs": {
            name: {"path": found["path"], "version": found["version"]}
            for name, found in tools.items()
        }
    }


def build(
    configuration: Configuration,
    target: Path,
    *,
    fresh_user_volume: bool = False,
    built_from: Mapping[str, object] | None = None,
) -> Path:
    """Build CONFIGURATION's volumes, the boot image at TARGET and the
    others beside it, in the shipping form, with its session manifest.  A
    user volume that is there is kept unless FRESH_USER_VOLUME asks for a
    new one.  BUILT_FROM, what the caller built from, such as its
    components' commits, goes into the manifest with the configuration's
    own digests."""

    files = documents(configuration)
    return image_build.build(
        image_spec(configuration),
        target,
        name=configuration.title,
        backend="simulator",
        samples_for=lambda spec, modules, with_documents: (files, frozenset()),
        settings_values=settings_values(configuration),
        system_volume=True,
        token_modules=True,
        keep_module_source=configuration.keep_source,
        user_volume=True,
        user_volume_mib=configuration.user_mib,
        fresh_user_volume=fresh_user_volume,
        session_manifest=True,
        built_from={
            **(built_from or {}),
            "configuration": {
                "path": str(configuration.path),
                "sha256": configuration.sha256,
                "documents_sha256": _digest(files),
            },
        },
        session_facts={
            "title": configuration.title,
            "description": configuration.description,
            "viewer": {
                "cols": configuration.viewer["cols"],
                "rows": configuration.viewer["rows"],
                "font_size": configuration.viewer["font-size"],
            },
            "network": {
                "enabled": configuration.network,
                "local_access": configuration.local_access,
            },
        },
    )
