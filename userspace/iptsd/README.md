# iptsd source and SP11 integration

The tested daemon is an unmodified upstream iptsd v3.1.0 checkout:

```text
repository: https://github.com/linux-surface/iptsd.git
commit:     a83bc1232f7096f8b33b50fdbda249cd640de670
tree:       06c6e812873e117930eca60b8a32cec40fd13281
```

Reconstruct it with:

```sh
git clone https://github.com/linux-surface/iptsd.git /tmp/sp11-iptsd-source
git -C /tmp/sp11-iptsd-source checkout \
  a83bc1232f7096f8b33b50fdbda249cd640de670
meson setup /tmp/sp11-iptsd-build /tmp/sp11-iptsd-source \
  --buildtype=release -Doptimization=3 -Dwerror=false -Db_lto=false \
  --force-fallback-for=fmt
ninja -C /tmp/sp11-iptsd-build src/iptsd src/iptsd-check-device
```

The source and build directory names are part of the byte-reproducible
identity because retained `__FILE__` strings contain paths relative to
`/tmp/sp11-iptsd-build`. The qualified build used GCC 16.1.1, binutils 2.46,
Meson 1.11.2, Ninja 1.13.2, system `libinih` 62-2, and the Meson wrap sources
CLI11 2.6.1, Eigen 5.0.1, fmt 12.0.0, Microsoft GSL 4.2.0, and spdlog 1.15.3.
The fmt fallback, disabled LTO, and disabled warnings-as-errors are required;
allowing Meson to select system fmt 12.2 or default LTO produces a different
binary.

Qualified binary hashes:

```text
iptsd               45ce0fcabdda04a9fcf3ce30f7f0c64ba7098fd2351127ef0e54cf0ac0b3f083
iptsd-check-device  54fcdaef90b0bd4239df670865cf8b258c3ae6e3988e42b0b9a3b58aaa4b08f5
```

Both hashes were reproduced byte-for-byte from the command above on
2026-07-28.

The SP11-specific work is lifecycle integration in `rootfs/`: a guarded udev
eligibility rule, dynamically instantiated service, and suspend hook that stops
iptsd before sleep and re-discovers/restarts it after the SPI-HID device returns.
That integration is required for reliable touch and stylus operation after
resume on the qualified kernel.
