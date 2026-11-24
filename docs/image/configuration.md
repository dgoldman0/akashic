# Configurations

A configuration says what a machine runs: the applets Desk opens and offers,
the Agent's provider, the machine's memory and cores, its volumes, the
viewer's size, its network, and values for Desk's system settings. It is one
TOML file. The image tool reads it and builds the machine's volumes and the
session manifest a server runs them from:

```
python3 -m toolchain.image check CONFIGURATION
python3 -m toolchain.image build CONFIGURATION IMAGE [--fresh-user-volume] [--built-from FILE]
python3 -m toolchain.image host
```

Run it from Akashic's root, with `MEGAPAD_ROOT` naming MegaPad when it is not
beside Akashic. `check` prints what the file says as JSON, or what is wrong
with it. `build` writes the boot image at `IMAGE` and, beside it, the
settings, system and user volumes (`-settings`, `-system` and `-user` added
to the image's name) and the session manifest (`-session.json`). The volumes
are the shipping form: the modules as token forms on the ext4 system volume,
and the user volume with Desk's places. Every file is readable by the user's
own account alone. A user volume that is already there is kept, documents
and all, unless `--fresh-user-volume` asks for a new one. `--built-from`
names a JSON object, such as the components' commits, that the manifest
records beside the configuration's own digests.

`host` says whether this computer has what a build needs from it: the
e2fsprogs tools that make the ext4 volumes, from 1.47.0 on, each linked to
its own library. It prints the tools a build would use, with their paths and
versions, as JSON, or what is missing or too old. A build takes the tools
from the folder `AKASHIC_E2FSPROGS_TOOL_DIR` names, which must hold the
tests' pinned 1.47.4, and otherwise from the first folder on the `PATH`, or
`/usr/sbin` or `/sbin`, that holds them all.

The Desktop that fantasy-engine ships, `configurations/desktop/configuration.toml`
there, reads:

```toml
[configuration]
format = 1
title = "Desktop"
description = "Desk with Pad, File Explorer, Daybook, Grid and the Agent, and Streams on the launcher."

[practice]
offer = ["streams"]

[[practice.entry]]
applet = "pad"

[[practice.entry]]
applet = "file-explorer"

[[practice.entry]]
applet = "daybook"

[[practice.entry]]
applet = "grid"

[[practice.entry]]
applet = "agent"

[agent]
provider = "scripted"

[machine]
memory-mib = 384
cores = 1

[volumes.user]
size-mib = 64
documents = "akashic:assets/samples/desktop"

[volumes.system]
keep-source = false

[viewer]
cols = 160
rows = 48
font-size = 16

[network]
enabled = false

[desk.rich-terminal]
safe-mode = false
full-refresh-quiet-ms = 1000
full-refresh-interval-ms = 5000
```

It builds the same boot, settings, system and user volumes as the harness's
`desktop-apt1` profile.

## The tables

The reader refuses a table or key it does not know, and names it, since a
misspelt key would otherwise be ignored without a word. It also refuses a
value of the wrong kind: a whole number where a boolean belongs, or the
reverse.

`[configuration]` names the format, `format = 1`, which every file states,
and its `title`. A `description` may follow. The manifest carries both, for
whoever lists configurations.

`[practice]` says what Desk opens. Each `[[practice.entry]]` names an applet
Desk opens in a tile, in order, and `offer` lists applets Desk offers on its
launcher without opening them. At least one entry is needed, and no applet is
named twice. The applets are `pad`, `file-explorer`, `daybook`, `grid`,
`agent`, `streams`, `soundlab`, `observatory`, `worlds` and `folio`. Until
Practices declare what they open, the tool composes the list into Desk's boot
script, as the harness does; that declaration will also give a Practice its
own title.

`[agent]` names the Agent's `provider`, which a configuration that opens or
offers the Agent needs. The scripted provider, which answers without a
network as the Desktop's journey needs, is the only one so far. A
configuration without the Agent has no `[agent]` table.

`[machine]` gives MegaPad's external memory, `memory-mib` (384 when left
out), and its full cores, `cores`, one to four (one when left out).

`[volumes.user]` sizes the user volume, `size-mib` (64 when left out, at
least 16), and may name a `documents` folder whose files the volume's
documents place starts with. The folder is copied when the volume is made,
and never again. Its files must sit directly in it. A plain path is relative
to the configuration file; `akashic:` and `megapad:` paths resolve inside
that component. `[volumes.system]` `keep-source` writes each module's source
beside its token form on the system volume, as the Workshop needs.

`[viewer]` sets the viewer's terminal size, `cols` and `rows`, and its
`font-size`: 160, 48 and 16 when left out. The images do not depend on them;
the manifest carries them for whoever opens the viewer.

`[network]` turns on the machine's network with `enabled`. `local-access`,
which needs `enabled`, lets the machine reach the host computer and its local
network, which the network refuses otherwise. The manifest carries both for
the server, and local access also reaches Desk's system settings as
`[desk.network] local-access`, so that Desk warns at every start that any
program on the machine can then reach services that expect only local
callers.

`[desk.*]` tables set Desk's system settings, which the settings volume
carries as `system.toml`. Each table and key must be one that Akashic's
`tui/applets/desk/system.toml` holds, with a value of the same kind; the tool
writes the file with these values in place of its own and keeps its comments.
`[desk.network]` is set through `[network]` alone.

## The session manifest

The manifest beside the boot image holds what a server needs: each storage
unit's image by file name, the machine's memory and cores, the backend
(`simulator`), the rich terminal's policies, the title and description, the
viewer's size, the network's two switches, and `built_from`: the caller's
facts with the configuration's path, the SHA-256 of its file, and a digest of
its documents' names and contents.
