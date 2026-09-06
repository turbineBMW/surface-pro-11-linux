# Building the live/installer ISO (maintainer notes)

The image is built natively on an aarch64 Arch Linux ARM host (the tablet
itself works) from frozen, signed inputs. Nothing is downloaded during the
build. Inputs:

| Input | Where it comes from |
| --- | --- |
| Package snapshot (664 signed packages, `PACKAGE-SNAPSHOT.tsv`) | `scripts/cache-locked-packages.sh --local-staging --output work/package-snapshot-…` against `iso/packages.lock.tsv`; the 2026-09-05 snapshot is the July one plus `plymouth`, taken from the same frozen `extra.db` |
| Firmware package cache (linux-firmware-atheros/qcom/whence, wireless-regdb 20260622) | `scripts/cache-firmware-packages.sh --local-staging` |
| Kernel payload (`Image`, DTB, `modules-*.tar.zst`, `MODULES.tsv`, iptsd + PPD binaries, `SHA256SUMS`) | `scripts/build-kernel.sh --profile port-7.3`, `modules_install` into a staging root (see `docs/BUILD.md`), then `SP11_KERNEL_STAGE=… scripts/assemble-payload.sh --local-staging` |
| Audio topology `X1E80100-Microsoft-Surface-Pro-11-tplg.bin` (11,320 bytes) | `scripts/build-audio-topology.sh` from the BSD-3 audioreach topology source |
| Wallpaper `Tux Surface.png` (hash-pinned, not in git) | maintainer-local |
| Installed-root artifact (`sp11-installed-rootfs.tar.zst` + manifests) | `scripts/build-installed-rootfs.sh --local-staging …` (hash pinned in `sp11-install-executor.py`) |

On the maintainer's machine the firmware cache, topology and wallpaper are
under `work/firmware-v2-rebuild-inputs/` (unchanged since the 2026-08-28
beta) and the package snapshot is `work/package-snapshot-plymouth-20260905`; the 7.3 kernel payload is
`work/payload-port73-20260905` and the installed-root artifact
`work/installed-rootfs-port73-20260905`. Every builder and audit script pins
the kernel release name and the Image/DTB hashes, and
`scripts/sp11-install-executor.py` pins the installed-root archive and
manifest hashes, so a new kernel means: build the kernel, update
`assemble-payload.sh`, build the payload, update the Image/DTB pins in the
builders/audits/installer, build the installed root, update the executor's
archive/manifest pins, then build the live image.

Build and audit:

```sh
cd public
sudo scripts/build-held-live-image.sh --local-staging \
  --package-snapshot work/package-snapshot-plymouth-20260905 \
  --firmware-cache   work/firmware-v2-rebuild-inputs/firmware-package-cache-20260622 \
  --payload          work/payload-port73-20260905 \
  --audio-topology   work/firmware-v2-rebuild-inputs/X1E80100-Microsoft-Surface-Pro-11-tplg.bin \
  --wallpaper        "work/firmware-v2-rebuild-inputs/Tux Surface.png" \
  --installed-rootfs-artifact work/installed-rootfs-port73-20260905 \
  --output work/live-image-beta-$(date -u +%Y%m%d)
# the builder ends by running scripts/audit-held-live-image.sh on the output
scripts/package-release.sh work/live-image-beta-$(date -u +%Y%m%d)
```

`package-release.sh` writes `work/release-<date>/` with the public ISO
name, `SHA256SUMS`, and split parts when the ISO exceeds GitHub's 2 GiB
asset limit. Attach everything in that directory to the GitHub release.

What the build does (`scripts/build-held-live-image.sh`):

1. verifies every package signature and hash, installs the closure into a
   fresh root with an empty pacman hook directory;
2. applies the live-only overlay (`iso/live-rootfs-files.tsv`, `iso/rootfs/`),
   GNOME defaults, the project UCM audio routing, iptsd/PPD binaries, kernel
   modules, allowlisted firmware, the derived WCN7850 board file, and the
   audio topology;
3. installs `sp11-firmware`, the validator, the documentation, the overlay
   installer kit (`/opt/sp11-beta-installer`), and the fresh installer
   (`/usr/local/libexec/sp11-fresh-installer`, `/opt/sp11-fresh-installer/artifact`);
4. builds the live initramfs with `iso/mkinitcpio/hooks/sp11live` (RAM copy
   of the SquashFS, owner-firmware validation) and staged Python;
5. compresses the root with SquashFS/xz, builds the ARM64 GRUB standalone
   loader (`iso/grub-embedded.cfg` → `iso/grub.cfg`), a 64 MiB EFI partition,
   and the 128 MiB FAT32 `SP11FW` partition seeded with the collectors and
   docs;
6. assembles the hybrid ISO with xorriso (ISO9660 + GPT with the two
   appended partitions) and audits everything.

The words `HELD` / `LOCAL-STAGING` in the build directory are historical
markers used by the audit scripts; the public artefact names come from
`package-release.sh`.

## Testing without a second USB stick

- `grub-script-check iso/grub.cfg`
- `/usr/lib/initcpio/busybox ash -n iso/mkinitcpio/hooks/sp11live`
- `sudo losetup -Pf --show work/…/sp11-beta-port73-aarch64-HELD-local.iso`
  exposes the three partitions; mount `p3` to inspect SP11FW, `p1` for the
  ISO tree.
- `pwsh -File scripts/sp11-collect-firmware.ps1 -WindowsDirectory /mnt/win/Windows -OutputDirectory /tmp/pack`
  exercises the Windows collector against a mounted Windows partition
  (PowerShell from the AUR `powershell-bin` package).
