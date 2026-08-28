# Release status: public beta

This project ships a **beta live/installer ISO** for the Microsoft Surface
Pro 11 (Snapdragon X Elite, OLED). It replaces the earlier binary/ISO release
hold: the source-closure, reproducibility, and privacy gates that the hold
was waiting on are recorded in `docs/`, and the remaining gaps are listed here
honestly instead of blocking the release.

## What the beta is

- A live GNOME environment that boots from USB with the project's
  `7.1.3-sp11-suspend-review20` kernel, copied to RAM.
- A dual-boot / wipe installer ("Install SP11 Linux" in the app grid) that
  was qualified on the maintainer's own tablet, which has run the result as
  its daily system since 2026-08-01.
- Tools that pull the five non-redistributable Qualcomm/Surface firmware
  files out of *your own* Windows installation (`RUN-IN-WINDOWS.cmd` on the
  USB stick, or `sp11-firmware` from Linux). The ISO itself contains only
  firmware that upstream `linux-firmware` allows to be redistributed.

## What it is not

- Not a supported product. Expect rough edges and read `KNOWN-ISSUES.md`.
- Not Secure Boot capable. Secure Boot must be disabled in UEFI settings.
- Not tested on the LCD, X Plus, 5G, or Surface Laptop variants.
- Not a replacement for the foundation project
  (`dwhinham/linux-surface-pro-11`) whose Arch Linux ARM bootstrap this
  builds on.

## Known gaps that were previously "hold reasons"

| Gap | Status |
| --- | --- |
| Exact corresponding source for every distribution package | Package recipes are pinned by `.BUILDINFO` checksum (`iso/package-recipes.lock.tsv`); the Arch Linux ARM source endpoint was unreliable, so upstream tarballs are not mirrored here. See `iso/SOURCE-STATUS.md`. Source for the project's own kernel/userspace changes is complete (`kernel/`, `userspace/`). |
| Install/rollback qualification | Fresh dual-boot install, Windows chainload, and removal were exercised physically (Aug 2026). Wipe mode was exercised on loop devices only. |
| Firmware extraction robustness | Rewritten: collectors pick the newest coherent Windows driver package and Linux validates structure at boot; no maintainer-specific hashes are required. |
| Proprietary firmware in the image | None. Users supply their own five files. |

Local engineering artifacts under `work/` still carry `HELD`/`LOCAL-STAGING`
markers from the build scripts; `scripts/package-release.sh` produces the
public file names and checksums.

This document is an engineering status note, not legal advice.
