# The global TLS root set

The machine's global trust anchors are the root certificates NSS, the library
Firefox uses, trusts for TLS server authentication. They live in
`akashic/net/web-roots/`:

- `certdata.txt`, the file NSS builds its root module from, unchanged from
  tag `NSS_3_134_RTM` (commit `72611a02c434`), SHA-256
  `6d177e33ab54b338edfee24dc3868585833636716a320a725137ab4a15927292`. It is
  licensed under the Mozilla Public License 2.0, as its header says, and
  ships beside the bundle made from it so its source travels with it.
- `web-roots.mpta`, an MPTA version 2 bundle of 112 global anchors, 121,286
  bytes, generated from `certdata.txt`.
- `web-roots-pin.f`, generated with it: the bundle's SHA-256, size and record
  count, which `net/tls-trust-registry.f` checks before admitting it.

`local_testing/generate_web_roots.py` makes the bundle. It checks
`certdata.txt` against its pinned SHA-256, then takes every certificate whose
NSS trust object marks server authentication `CKT_NSS_TRUSTED_DELEGATOR`, in
the file's order:

- Mozilla's server distrust-after date, `CKA_NSS_SERVER_DISTRUST_AFTER`,
  becomes the record's distrust-after time: KDOS then refuses chains whose
  leaf was issued later. Four roots carry one.
- The name constraints NSS imposes in code on roots it names by subject
  (`lib/certdb/genname.c`, `builtInNameConstraints`) become the record's
  imposed constraints, so KDOS holds TUBITAK's root to `.tr` as NSS does.
- A root whose key KDOS cannot verify is left out and listed in
  `web-roots-pin.f`: today only `e-Szigno TLS Root CA 2023`, a P-521 root.

`test_web_roots.py` regenerates the bundle and compares it byte for byte, so
the committed files are always the script's output.

## Loading

`net/web-roots.f` provides `WEB-ROOTS-REGISTER ( place -- status )`, which
registers the one contributor that reads `net/web-roots/web-roots.mpta` from a
place when the trust registry composes the machine's bundle. Desk registers it
with its origin, the place over the image's shipped files, just before it
freezes the registry; a Desk without an origin has no shipped files and
registers nothing. `MTRUST-WEB-ROOTS+` then admits the file only if it is
exactly the pinned bundle; a changed file fails the composition, and Desk
does not start without machine trust.

The image tool ships the file with every image whose module closure holds
`net/web-roots.f`, through its data-file map (`MODULE_DATA_FILES` in
`toolchain/image/build.py`). The file stands at its path on the image's
origin: the system volume in the shipping form, the boot volume otherwise. A
boot composition that runs without Desk declares a place over the boot volume
and registers the set itself before it freezes the registry, as the live
Streams and Codex profiles and `test_web_roots.py` do. An image without the
file adds no global anchors, so its public TLS fails closed.

Loading costs about 250 KB while the registry composes: the file's bytes, the
composed bundle and KDOS's copy. KDOS keeps about 155 KB afterwards, its copy
of the bundle and a 304-byte record for each anchor.

## Refreshing

A new NSS release can add, remove or distrust roots. To take one:

1. Fetch `lib/ckfw/builtins/certdata.txt` at the new release tag, and put its
   tag, commit and SHA-256 in `generate_web_roots.py`.
2. Check `lib/certdb/genname.c` at that tag for changes to the imposed name
   constraints, and carry them into the script's table.
3. Run `python local_testing/generate_web_roots.py`, review the roots it
   added, removed or left out, and commit the three files together.
