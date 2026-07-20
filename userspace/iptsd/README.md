# iptsd source and SP11 integration

The tested daemon is an unmodified upstream iptsd v3.1.0 checkout:

```text
repository: https://github.com/linux-surface/iptsd.git
commit:     a83bc1232f7096f8b33b50fdbda249cd640de670
tree:       06c6e812873e117930eca60b8a32cec40fd13281
```

Reconstruct it with:

```sh
git clone https://github.com/linux-surface/iptsd.git
cd iptsd
git checkout a83bc1232f7096f8b33b50fdbda249cd640de670
meson setup build --buildtype=release -Doptimization=3
ninja -C build iptsd iptsd-check-device
```

Qualified binary hashes:

```text
iptsd               45ce0fcabdda04a9fcf3ce30f7f0c64ba7098fd2351127ef0e54cf0ac0b3f083
iptsd-check-device  54fcdaef90b0bd4239df670865cf8b258c3ae6e3988e42b0b9a3b58aaa4b08f5
```

The SP11-specific work is lifecycle integration in `rootfs/`: a guarded udev
eligibility rule, dynamically instantiated service, and suspend hook that stops
iptsd before sleep and re-discovers/restarts it after the SPI-HID device returns.
That integration is required for reliable touch and stylus operation after
resume on the qualified kernel.
