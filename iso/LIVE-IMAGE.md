# Corrected held ARM64 UEFI live image

The corrected non-installing GNOME engineering image was assembled and
statically audited on 2026-07-28. It is a local test artifact, not a beta
release:

- filename: `sp11-beta-review20-aarch64-HELD-local.iso`;
- size: 1,284,163,584 bytes;
- SHA-256:
  `4aae21a7183e0a7eb0a5ce2cbfbae798fd481f0d9b3f5e67380e5b82b5ef19ba`;
- package root: 662 exact signed Arch Linux ARM packages;
- custom kernel: `7.1.3-sp11-suspend-review20`, 3,759 modules;
- firmware: exactly the 11 files in `firmware/allowlist.tsv`;
- boot: protective MBR, GPT, appended 64 MiB EFI System Partition, El Torito
  UEFI entry, and fallback `EFI/BOOT/BOOTAA64.EFI`;
- root: read-only SquashFS with a volatile tmpfs overlay; and
- desktop: automatic login as the non-persistent `live` user.

The ignored local artifact is under
`work/live-image-review20-held-20260728/`. `ARTIFACTS.tsv` records the exact
rootfs, initramfs, GRUB EFI, ESP, and ISO identities.

## Rejected first boot

The initial statically audited image, SHA-256
`a8fd72ebe52a817634681b1ee827328b9cfdf24d6c6627957d736243f8e5c465`,
is rejected. Both its normal and conservative entries reached the kernel's
early EFI framebuffer but never reached the systemd boot display.

The root cause was deterministic: its SquashFS used Zstandard compression
while the qualified review20 kernel has `CONFIG_SQUASHFS_ZSTD` disabled. The
kernel could not mount `rootfs.sfs` and entered the initramfs emergency path.
The first initramfs also lacked the Surface keyboard stack, so TTY switching
and Ctrl+Alt+Delete could not expose or leave that shell.

The corrected image:

- uses gzip SquashFS with the kernel's `CONFIG_SQUASHFS_ZLIB=y`;
- identifies the real live medium with `root=LABEL=SP11BETA` instead of the
  nonexistent `/dev/ram0`;
- explicitly early-loads ISO9660, MSM display/panel, and Surface
  keyboard/aggregator modules; and
- audits the SquashFS codec against the exact kernel configuration and checks
  the early module and root-device contract.

## First desktop boot and rejected ownership build

The codec-corrected image, SHA-256
`f6cae0d7a4fdd8691122288ff4d909607e84e5072c5442b89e6138df8d1a6cbf`,
successfully completed the ARM64 UEFI, GRUB, kernel, live-root, systemd, and
GNOME automatic-login path. The OLED and touchscreen worked.

That image is nevertheless rejected. GNOME Console could not start because
it could not enter `/home/live`. The rootfs staging tree correctly created
that directory as `1000:1000` with mode `0700`, but the SquashFS builder's
`-all-root` option rewrote all filesystem owners to `0:0`. This also risked
breaking other service-owned state.

The current image removes `-all-root`, preserves the staged numeric owners,
and audits `/home/live` both before compression and after extraction from the
finished SquashFS. The live user must be `1000:1000` with mode `0700` at both
gates. Wi-Fi was unavailable during the rejected desktop boot; its exact
live-side driver/firmware state still needs capture after Console works.

## Build and audit

The builder requires native AArch64 and explicit root access only to create
root-owned files below the new `work/` directory. It does not install a host
package, modify a boot entry, write an EFI variable, partition a disk, or
include an installer.

```sh
scripts/cache-locked-packages.sh \
  --local-staging \
  --output work/package-snapshot-469dfdf921d1-20260728

scripts/cache-firmware-packages.sh --local-staging

sudo scripts/build-held-live-image.sh --local-staging

sudo scripts/audit-held-live-image.sh \
  work/live-image-review20-held-20260728
```

The builder uses an empty pacman hook directory so machine-local package hooks
cannot enter the live root. Its dedicated initramfs excludes the generic
`modconf` hook after a member-level audit caught and rejected a local IR
loopback policy during development.

The final audit verifies:

- package, module, custom binary, kernel, DTB, and firmware identities;
- required runtime link dependencies and custom systemd units;
- exact firmware allowlist membership and exclusion of the denied files;
- disabled sensor/IR units and absence of Howdy, v4l2loopback, installer,
  network profiles, Bluetooth state, and machine ID;
- required live-mount, USB-storage, SquashFS, overlay, and VideoCC initramfs
  members, plus the early ISO, MSM display/panel, and Surface input stack, with
  no host modprobe policy;
- gzip SquashFS compatibility with the exact kernel configuration and the
  live-medium root-device contract;
- preservation of required file capabilities through SquashFS;
- preservation of the live user's private home ownership and mode through
  SquashFS;
- ARM64 PE/COFF fallback loader, EFI FAT contents, El Torito UEFI boot entry,
  GPT, and EFI System Partition; and
- every SHA-256 and byte count in `ARTIFACTS.tsv`.

## Hardware test scope

The first boot test must use removable media and the firmware boot picker. It
must not install anything. Validate, in order:

1. ARM64 GRUB menu and GNOME automatic login;
2. OLED, touchscreen, pen, keyboard, and touchpad;
3. Wi-Fi with only official `board-2.bin`, then Bluetooth;
4. front/rear camera enumeration and switching;
5. expected absence of audio and ADSP/CDSP-backed sensors;
6. power-profile changes and runtime state1 controls;
7. one short guarded suspend/resume and the complete post-resume input/camera
   checks; and
8. shutdown, USB removal, and an unchanged installed-system boot.

Do not test installation from this artifact: no installer is present. Secure
Boot remains unsupported.
