# Firmware boundary

> **Current workflow (beta, 2026-08-28):** users collect the five
> non-redistributable files themselves with `RUN-IN-WINDOWS.cmd` or
> `sp11-firmware`; see [`docs/FIRMWARE.md`](../docs/FIRMWARE.md). The exact
> hashes in `external-required.tsv` are the ones exercised on the maintainer's
> unit and are informational only — newer Windows driver packages are accepted
> and validated structurally. The allowlist/denylist policy below still governs
> what the ISO itself may contain.


No firmware blob is tracked in this source repository. This directory defines
the only firmware files that a future beta image assembler may select from
verified distribution packages.

## Allowlist policy

`allowlist.tsv` is fail-closed. Every entry records the exact relative
firmware path, source package/version, uncompressed size, SHA-256, required
license/notice material, and purpose. An image assembler must:

1. acquire the exact signed package in `packages.lock.tsv`;
2. verify the package signature and package SHA-256;
3. extract only paths in `allowlist.tsv`;
4. verify every extracted file's size and SHA-256;
5. include the named license and notice files plus the exact `WHENCE`; and
6. reject any extra firmware file, symlink, special file, or unsafe path.

The Linux firmware source is tag `20260622`, commit
`b2722d241309a1872446c1d00c2e812bad055f89`. Its `WHENCE` explicitly calls
the selected Qualcomm/Atheros files redistributable under the named terms.
The signed wireless regulatory database comes from the separately locked
`wireless-regdb` package.

## Qualified WCN7850 board record

The working 88,872-byte `board.bin` is an unmodified record from the official
WCN7850 `board-2.bin` already selected by `allowlist.tsv`. `derived.tsv`
records the exact source path, board name, output size, and SHA-256. The image
builder extracts that record offline only after verifying the signed
`linux-firmware-atheros` package and the complete `board-2.bin` identity.

The selected record name is:

```text
bus=pci,vendor=17cb,device=1107,subsystem-vendor=17cb,subsystem-device=3378,qmi-chip-id=2,qmi-board-id=255
```

Its extracted SHA-256 is
`0ef5f6f3cb124f33c6de52371819ccd7c13763ceb86d476a178fd56e4cdc26a3`.
It remains byte-identical to the redistributable binary record and is shipped
with the Qualcomm license, WCN7850 notice, and `WHENCE`.

The 88,780-byte `bdwlan.elf` supplied by Qualcomm Windows driver
1.0.4374.1300 is not this record and is known incompatible with the current
beta stack. The device's read-only DPP `WLAN_CLPC.PROVISION` object is also
incompatible: both its original 88,792-byte ELF and its exact 87,040-byte
payload placed in the qualified legacy ELF envelope timed out with `-110`.
Those three rejected identities remain in `denylist.tsv`.

## Surface-specific external prerequisite

The qualified host loads five Surface-specific files that are unowned by any
distribution package: two DSP device trees, two DSP images, and one GPU secure
image. `external-required.tsv` records the first qualified paths, sizes, hashes,
candidate source names, and purposes. The same paths are documented in
`denylist.tsv` so a published ISO fails closed if any is accidentally
embedded. Hashes identify files; they do not grant redistribution rights.

As of upstream linux-firmware commit
`543b8f5f987c4da3f21550cf4827c69276986fbb`, none of those five files is
present in the official tree or `WHENCE`. They must not be copied from this
machine, a Windows partition, a Microsoft driver package, or another
installation into a published image.

The audio topology is different: its reviewed source is tracked under
`userspace/audio/` under `BSD-3-Clause`, and
`scripts/build-audio-topology.sh` reproducibly creates the exact tested binary.
The paired project-authored ALSA UCM routing is tracked under
`rootfs/usr/share/alsa/ucm2/`. Neither is proprietary firmware.

## Low-effort offline SP11FW pack

Wi-Fi is not required to provide the external files. The hybrid beta ISO
contains a 64 MiB FAT32 partition labeled `SP11FW`, preloaded only with
redistributable collector and diagnostic scripts, their exact-hash manifest,
and `START-HERE.txt`. After the ISO is written, an owner opens that ordinary
writable partition and populates it on the same USB drive. The beta initramfs
ignores the helper files, validates all five firmware files before copying any
of them into the volatile live overlay, and continues safely if the firmware
pack is absent or incompatible.

An owner can create the pack in either of these ways:

1. From an existing Linux installation, with the written live USB attached:

   ```sh
   sudo scripts/prepare-external-firmware.sh \
     --source-root / \
     --target-sp11fw
   ```

2. From stock Windows, open the writable `SP11FW` drive and double-click
   `RUN-IN-WINDOWS.cmd`. Alternatively, open PowerShell there and run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\sp11-collect-firmware.ps1 `
     -TargetSP11FW -AllowUnpinnedCandidates
   ```

   It searches the local Windows DriverStore and the known direct System32
   GPU path. A previously qualified identity is preferred when present;
   otherwise research mode selects a coherent package candidate and records
   its actual size, SHA-256, component, source package, and selection reason.
   DSP images and device trees are never mixed across packages.

The live importer recomputes every recorded hash and independently checks the
ELF machine, entry point, program-header layout, and reserved-memory bounds.
Unknown but structurally compatible identities are marked as such by the
collector; passing these checks permits a controlled boot test, not release
qualification. A malformed, incomplete, mixed-package, or modified pack is
rejected atomically and the live system continues without owner firmware.

Both collectors retain `--output`/`-OutputDirectory` standalone-pack modes for
advanced or two-drive workflows. They never download, install, or publish
firmware. USB Ethernet remains an optional way to obtain project tools, but is
not part of the boot dependency chain.

After boot, `sp11-live-firstboot-capture.sh` saves a bounded diagnostic report
directly to `SP11FW` for retrieval after shutdown. It is user-invoked, sends
nothing, and falls back to the volatile live home only when the partition is
unavailable. Reports can contain device identifiers and must be reviewed
before sharing.

There is no need to repack the ISO. The distributed ISO remains free of the
five owner-only files; only the writable `SP11FW` partition on the owner's
thumb drive is personalized. Its contents persist across live boots.
Reflashing the drive replaces the partition, so the collector must then be
run again.

Consequences for beta 1:

- display/GPU, QUPv3 serial devices, Bluetooth, regulatory data, the official
  WCN7850 firmware, and the qualified extracted board record may be included
  from the redistributable manifests;
- audio and ADSP/CDSP-dependent devices require the exact owner-supplied pack
  on the qualified hardware;
- the ISO and source tree contain no external file, and the live overlay is
  volatile; and
- installation may later offer the same explicit hash-verified local import,
  but must not upload, bundle, or publish the files.

The installer must continue without the denied files and clearly report the
resulting hardware limitations. Missing external firmware is never permission
to fetch or redistribute a Windows package automatically.
