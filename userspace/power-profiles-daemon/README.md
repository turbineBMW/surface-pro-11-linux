# Power Profiles Daemon SP11 build

The tested base is upstream Power Profiles Daemon 0.30, peeled tag commit
`5b4994c8a91290481bef87a5bae95391d0ec677f`.

```sh
git clone --branch 0.30 \
  https://gitlab.freedesktop.org/upower/power-profiles-daemon.git \
  /tmp/ppd-upstream.qgYOjo
git -C /tmp/ppd-upstream.qgYOjo apply \
  /path/to/0001-sp11-use-platform-profile-class.patch
meson setup /tmp/ppd-upstream.qgYOjo/build-sp11 \
  /tmp/ppd-upstream.qgYOjo --prefix=/usr --buildtype=debugoptimized \
  -Dtests=false
ninja -C /tmp/ppd-upstream.qgYOjo/build-sp11 \
  src/power-profiles-daemon
```

The unusual source path is retained because the debug-optimized ELF records
its build directory; using another path changes only `.debug_line_str` and the
derived build ID. The qualified build used GCC 16.1.1, binutils 2.46, Meson
1.11.2, Ninja 1.13.2, systemd 261, GLib 2.88.2, gudev 238, UPower 1.91.3, and
polkit 127.

Install the daemon binary separately as
`/usr/local/libexec/power-profiles-daemon-sp11`; do not overwrite the packaged
binary. The rootfs service drop-in selects the separate build and is therefore
reversible by removing the drop-in.

Qualified binary SHA-256:

```text
9e1d72935f2b916de1c44950e425948e60c7bdf83c69bede2a079e7a79a82252
```

That hash was reproduced byte-for-byte from the command above on 2026-07-28.
An earlier rebuild in a different directory became byte-identical after
removing only debug information and the path-derived GNU build ID.

The independent `sp11-power-profile-cpufreq` companion adds the measurable
power-saver cap. It is not part of Power Profiles Daemon.
