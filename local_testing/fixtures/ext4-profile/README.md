# Ext4 profile-v1 qualification fixtures

This directory ratifies the host-side input contract consumed by the Akashic
ext4 binding. It does not contain the driver and is not runtime data, startup
data, or a fallback filesystem; runtime mount evidence belongs to
`local_testing/test_vfs_ext4.py`. The normative human contract is
[`docs/utils/fs/ext4-compatibility-profile.md`](../../../docs/utils/fs/ext4-compatibility-profile.md).

`manifest.json` pins Linux v6.18 and the complete upstream e2fsprogs v1.47.4
suite.  The repository-owned `mke2fs.conf`, explicit `-O none,...` feature
list, geometry arguments, fixed UUIDs/hash seeds, fixed clock, and disabled
lazy initialization keep host defaults out of the profile.  The generator
uses absolute tool paths and rejects the mixed Android/Ubuntu tools currently
visible through this workspace's `PATH`.

Build all four tools from the official v1.47.4 source archive into one staged
prefix. `DESTDIR` keeps the upstream install targets out of the host system:

```sh
ext4_tool_work=$(mktemp -d)
curl -L -o "$ext4_tool_work/e2fsprogs-1.47.4.tar.xz" \
  https://www.kernel.org/pub/linux/kernel/people/tytso/e2fsprogs/v1.47.4/e2fsprogs-1.47.4.tar.xz
printf '%s  %s\n' \
  fd5bf388cbdbe006a3d3b318d983b2948382440acc85a87f1e7d108653e8db0b \
  "$ext4_tool_work/e2fsprogs-1.47.4.tar.xz" | sha256sum -c -
tar -xf "$ext4_tool_work/e2fsprogs-1.47.4.tar.xz" -C "$ext4_tool_work"
mkdir "$ext4_tool_work/build" "$ext4_tool_work/stage"
cd "$ext4_tool_work/build"
../e2fsprogs-1.47.4/configure --prefix=/usr --disable-nls --disable-uuidd
make -j2
make DESTDIR="$ext4_tool_work/stage" install
```

Then generate and independently check the real images from the nested Akashic
repository root using `$ext4_tool_work/stage/usr/sbin` as the tool directory:

```sh
python3 local_testing/generate_ext4_profile_fixtures.py \
  --tool-dir /path/to/e2fsprogs-1.47.4-prefix/sbin \
  --output-dir local_testing/out/ext4-profile

AKASHIC_E2FSPROGS_TOOL_DIR=/path/to/e2fsprogs-1.47.4-prefix/sbin \
  python3 -m pytest -q local_testing/test_ext4_profile.py
```

The generated images and `qualification.json` stay under the ignored
`local_testing/out/` tree.  Every image is created only by pinned `mke2fs`,
populated only through pinned `debugfs`, decoded independently by the Python
superblock oracle, and required to pass pinned `e2fsck -f -n` with exit status
zero.  No in-repository code constructs ext4 metadata.
