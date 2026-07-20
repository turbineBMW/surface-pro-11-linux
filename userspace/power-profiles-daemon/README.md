# Power Profiles Daemon SP11 build

The tested base is upstream Power Profiles Daemon 0.30, peeled tag commit
`5b4994c8a91290481bef87a5bae95391d0ec677f`.

```sh
git clone --branch 0.30 \
  https://gitlab.freedesktop.org/upower/power-profiles-daemon.git
cd power-profiles-daemon
git am /path/to/0001-sp11-use-platform-profile-class.patch
meson setup build --prefix=/usr --buildtype=debugoptimized
ninja -C build
```

Install the daemon binary separately as
`/usr/local/libexec/power-profiles-daemon-sp11`; do not overwrite the packaged
binary. The rootfs service drop-in selects the separate build and is therefore
reversible by removing the drop-in.

Qualified binary SHA-256:

```text
9e1d72935f2b916de1c44950e425948e60c7bdf83c69bede2a079e7a79a82252
```

The independent `sp11-power-profile-cpufreq` companion adds the measurable
power-saver cap. It is not part of Power Profiles Daemon.
