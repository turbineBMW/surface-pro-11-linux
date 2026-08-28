# Installation

There are two installers. Pick the one that matches your starting point.

## 1. Fresh machine (recommended): the live-USB installer

Boot the beta ISO and start **Install SP11 Linux** from the app grid. It
handles dual boot next to Windows (after you shrink `C:` in Windows Disk
Management) or wiping the internal disk. The walkthrough is in
[GETTING-STARTED.md](GETTING-STARTED.md); removal is in
[UNINSTALL.md](UNINSTALL.md).

How it works, for the curious (`scripts/sp11-install-*.py`):

- `sp11-install-plan.py` runs unprivileged and read-only. It inventories
  whole disks, refuses removable/USB/mounted/serial-less targets, and emits an
  immutable JSON plan: in dual-boot mode exactly two new partitions in the
  single unallocated gap between Windows' data and recovery partitions; in
  wipe mode a fresh GPT.
- `sp11-installer-ui.py` shows the inventory and plan, asks for the two
  confirmation phrases, the account, and the timezone, and warns when no
  owner firmware was imported (you may continue without it and add it later
  with `sudo sp11-firmware install --from-windows`).
- `sp11-install-executor.py` (root, via sudo) re-reads the disk, checks the
  plan still matches the live GPT, checks the exact Surface hardware, RAM-backed
  live root, Secure Boot state, and only then partitions, formats, unpacks the
  pre-built root (`/opt/sp11-fresh-installer/artifact`, identical package set
  to the live system), copies the imported firmware and the `sp11-firmware`
  tool, provisions account/timezone/machine-id/fstab, writes GRUB with a
  *Windows Boot Manager* chainloader, creates the `SP11 Linux` UEFI entry, and
  runs two independent read-only verification passes.
- Every step is journaled under `/run/sp11-installer/` in the live session.

Resulting layout: `SP11EFI` (FAT32, 1 GiB, `/efi`) and `sp11root` (ext4,
`/`), kernel and initramfs in `/boot/sp11/`, GRUB config generated from
`/etc/grub.d/09_sp11_fresh`.

## 2. Existing Arch Linux ARM installation (foundation project): overlay

If the tablet already runs the Arch Linux ARM system from
`dwhinham/linux-surface-pro-11`, `scripts/install.sh` adds the project's
kernel, modules, userspace binaries, and services next to what is there and
never changes the persistent GRUB default:

```sh
# payload: Image, DTB, modules archive, iptsd/PPD binaries + SHA256SUMS
# (built with scripts/assemble-payload.sh or taken from the live ISO at
#  /opt/sp11-beta-installer/payload)
sudo scripts/install.sh --payload /path/to/payload            # read-only preflight
sudo scripts/install.sh --payload /path/to/payload --apply    # install
sudo grub-reboot sp11-beta-review20 && sudo reboot            # one-shot test boot
```

Preflight checks the exact hardware, payload hashes, all 3,759 modules,
root/boot layout, free space, the Windows loader and EFI entry, and that at
least two GRUB entries remain. `--apply` records an integrity-protected
transaction under `/var/lib/sp11-beta/` first; `scripts/rollback.sh` (or
`sp11-rollback-live` from the live USB) restores it. See
[ROLLBACK.md](ROLLBACK.md). The live USB's `sp11-install-preflight` wrapper
runs the same preflight against an internal root/EFI pair read-only.

`--held-local-test` and `--confirm-held-local-install` are still accepted for
compatibility with older notes but are no longer required.

## Firmware on an installed system

```sh
sp11-firmware status                              # what is installed / DSP state
sudo sp11-firmware install --from-windows         # dual boot: read C: directly
sudo sp11-firmware install --pack /path/to/pack   # from a pack made elsewhere
```

See [FIRMWARE.md](FIRMWARE.md).
