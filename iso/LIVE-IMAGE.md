> **2026-09-05:** the beta image now ships the Linux 7.3 port kernel
> `7.2.0-sp11-73beta1` (`kernel/port-7.3/`), enables cpufreq boost instead of
> the deep-idle block, and offers a `cpuidle.off=1` menu entry as the
> conservative fallback. The build inputs and invocation are in
> `docs/BUILD-ISO.md`. The sections below describe the review20 engineering
> images and the 2026-08-28 beta and remain as history.

# Corrected held ARM64 UEFI live image

The first corrected non-installing GNOME engineering image was assembled and
statically audited on 2026-07-28. It is retained as historical local evidence,
not a beta release:

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

## Qualified repair3 removable image

The final local repair3 artifact booted from the physical thumb drive on
2026-07-29:

- size: 1,298,143,232 bytes;
- SHA-256:
  `f932fccc3c45f0f3c84c272364ff70c4dfd1a14ac754bce6ceff9a4b52952bda`;
- raw thumb-drive bytes matched the ISO SHA-256;
- GNOME, OLED, touchscreen, pen, Wi-Fi, speakers, microphones, and cameras
  passed; and
- the final first-boot capture reported no failed systemd units or PipeWire
  audio error.

The preceding artifact exposed repeated SquashFS read failures when the USB
hub reset during boot. Repair3 copies the complete SquashFS into tmpfs,
validates its byte count and SHA-256, unmounts the removable source, and boots
from the verified RAM copy. This made the live root independent of later hub
resets.

Repair3 contains locally imported owner firmware and remains permanently
non-redistributable. Its hardware result qualifies the stack, not the public
artifact. The next base image must carry the redistributable topology/UCM and
the exact WCN7850 board record derived from `board-2.bin`, then obtain the five
remaining proprietary DSP/GPU files from an exact `SP11FW` companion volume.

## Blob-free public-base held image

The public-base artifact was rebuilt and audited after separating the
redistributable audio integration from owner firmware:

- filename: `sp11-beta-review20-aarch64-HELD-local.iso`;
- size: 1,351,270,400 bytes;
- SHA-256:
  `2fe5f6050ec32b8d5c8d4497198fc87cb1f5ee7ac51057d4efdb8da9dd641d48`;
- firmware in SquashFS: 11 exact distribution files plus the reproducibly
  built BSD-3-Clause audio topology;
- UCM: two exact project files and two selector symlinks;
- owner firmware: absent, with no local-proprietary import marker; and
- personalization path: a 64 MiB FAT32 GPT partition labeled `SP11FW`,
  seeded only with editable redistributable collector/diagnostic tools and
  instructions, plus initramfs support for the exact all-or-nothing firmware
  import contract.

The full static audit and compatible on-device companion-volume qualification
pass. Both fail-closed companion-volume negatives also pass. This image
remains held because package source closure and install/rollback tests are
still incomplete.

Subsequent provenance work established that the qualified 88,872-byte
`board.bin` in those tests was extracted from the redistributable WCN7850
`board-2.bin` in the locked `linux-firmware-atheros` package. It was not an
owner-only Windows artifact.

## Qualified derived-board, five-file image

The corrected successor was built, statically audited, written to freshly
erased removable media, populated by its bundled Windows collector, and
cold-booted on the target on 2026-07-29:

- size: 1,351,317,504 bytes;
- SHA-256:
  `32af335c8e737799589d0179a3620355402d2b9b06dbf604009c8044800f9741`;
- immutable base: 662 packages, 3,759 modules, 13 firmware files, and four
  project UCM entries;
- base board: the exact 88,872-byte WCN7850 record reproducibly extracted
  from the verified `linux-firmware-atheros` package, SHA-256
  `0ef5f6f3cb124f33c6de52371819ccd7c13763ceb86d476a178fd56e4cdc26a3`;
- SP11FW: exactly five verified owner-supplied DSP/GPU files and no ath12k
  board file; and
- physical result: internal Wi-Fi, OLED, touchscreen, pen, speakers,
  microphones, and cameras passed.

The diagnostic report records zero failed systemd units, the WCN7850 hw2.0
ath12k device connected through NetworkManager, powered Bluetooth, three
libcamera cameras with 1920x1080 Snapshot streams, and the expected PipeWire
speaker and microphone endpoints. Its SHA-256 is
`8935f6228769e6988f8cd918c480cdfad0029926850c50671e876556d8bd7b74`.

SP11FW contained no board data, so the connected internal-Wi-Fi result,
together with the audited immutable-root hash, qualifies the derived
base-image board path. This closes the fresh physical five-file companion
qualification. The image remains held for the independent source-closure and
installation/rollback gates; it is not a release.

## Held installation-preflight successor

The next non-published successor adds only the non-mutating installation gate:

- size: 1,414,481,920 bytes;
- SHA-256:
  `688f08f042c16907afee8730e9827ef4f40ba55df80cb98697422bc798a0bc85`;
- rootfs SHA-256:
  `193a8825e8b64fc8762f51634cf34bf5f7bdae5877f8bec50a3e71e2cc14e472`;
- installer-manifest SHA-256:
  `58d8a8069cc711fb98792677a37ccb5c6634eed5c54570d25d76dd5a13f0e685`;
  and
- held payload archive SHA-256:
  `f48b29ca853198d327405439bd20179250506a88e7f457c7e54e9c666636bba5`.

The embedded module manifest covers all 3,759 qualified modules. The
installer defaults to preflight, requires explicit held-local and mutation
confirmations, verifies the exact hardware and Windows/GRUB boundaries, and
records integrity-protected rollback transactions. The live wrapper exposes
no apply option: it mounts explicit internal root and EFI devices read-only,
runs preflight inside the target, and unmounts its private tree.

Host-side read-only preflight passed with 31 preserved GRUB entries, no
pending one-shot boot, Windows Boot Manager intact, a fresh
`/boot/sp11-beta` namespace, all payload modules verified, and the two known
host-only modules left untouched. The preflight did not change the GRUB
configuration, GRUB environment, Windows loader, or installer namespaces.

The physical live-wrapper preflight then passed from freshly written media.
Its persistent report SHA-256 is
`76d4139c1ce4a5d89e03254e61ad3b6314d7c25627a6493519e2fa968b94afa2`.
An immediate installed-host comparison proved that the root/EFI identities,
Windows loader, GRUB configuration, GRUB environment, EFI entry, and fresh
installer namespaces still matched the saved baseline.

## Customized pen-validation successor

The next held iteration changes only the live desktop/test surface and the
corrected post-install verifier:

- signed native Rnote 0.14.2-2 is added to the package closure;
- the existing exact iptsd 3.1.0 binary and dynamic udev/systemd lifecycle
  remain the qualified pen runtime;
- GNOME defaults to the exact owner-supplied 2880x1920 Tux Surface PNG,
  SHA-256
  `1fdc98d786badbf332460460da51496c3674cbead0d501f0e98708c4bb0bb5ac`,
  in both light and dark modes;
- GNOME's accent default is orange; and
- the wallpaper is copied only from local owner-supplied input into held work
  output and is not tracked in the public source tree.

The package closure is 673 unique signed packages, 663 in the live root, with
596 exact recipe identities. The custom iptsd payload remains outside that
distribution-package count and retains its existing source/provenance
contract.

The first controlled installer apply also completed. Rollback transaction
`20260729T224010Z` is complete and integrity-protected; the kernel, DTB, all
3,759 modules, VideoCC initramfs content, isolated GRUB fragment, Windows
chainloader/file/EFI entry, and armed one-shot selection passed the corrected
independent verifier. The persistent GRUB default remains unchanged.

The exact ISO has passed static audit but has not yet been written or
physically booted. Installation remains unauthorized until its live-wrapper
preflight report returns and is reviewed.

## Qualified offline-rollback successor

The synchronized held successor adds the separately gated offline rollback
wrapper, Rnote, iptsd, the orange GNOME accent, and the local Tux Surface
wallpaper:

- size: 1,436,768,256 bytes;
- SHA-256:
  `0ce77d160aa3f3390f31f685cd87966eee71451c913e73f1ed367bcaa7340d8e`;
- rootfs SHA-256:
  `5dd1ef7a8ff5d3b9bf0947705c37b7ea0ccd430fa9f0216dd8b46aa67ce4ccdb`;
  and
- physical USB read-back: exact.

Fresh Windows firmware extraction and the cold live hardware/branding pass
succeeded. A new controlled install then booted its isolated candidate,
completed deep suspend/resume with Wi-Fi recovery, and retained a fully valid
transaction.

The same live USB validated the explicit internal root and EFI targets
read-only before separately confirmed apply. Offline rollback restored every
saved file and symlink, restored the exact five-service enablement baseline,
removed only recorded created paths, retained the compatible module tree,
regenerated GRUB, and passed its Windows loader, chainloader, EFI entry, and
cleanup checks.

Persistent live reports have SHA-256:

- preflight:
  `a1237e7cc3f0bf9682f175f3570d7e16d8c2b5069a46ec8483859ae1100c3dcf`;
  and
- apply:
  `d71f5974a094870ad9d766e87ac655d697f0fa068d2dcbc6e4135da7de80d4fb`.

The restored persistent review20 entry booted with zero failed units, exact
Windows and EFI state, 31 preserved GRUB menu entries, no candidate namespace
or pending one-shot, and a passing fresh installer preflight. The live-USB
offline rollback workflow is physically qualified and no longer requires the
obsolete installed maintenance kernel.

## Corrected fresh-installer held image

The synchronized 2026-08-01 successor embeds the separately built installed
system artifact and connects the GNOME installer entry to the read-only
planner and identity-bound executor:

- ISO size: 2,396,192,768 bytes;
- ISO SHA-256 after the existing-SP11-layout correction:
  `853a0c5fda8a054c1bc824ba73077f04e3996d4653a669c54f25244224e07919`;
- rootfs SHA-256:
  `a0c07af12c50f47862d1f30d5299ba8820ce4f82c62c4d9a37303e6d1fe2b462`;
- installed-system archive SHA-256:
  `fa04efafd4e48a261765f7b008cdb5c961c954a92f41d1a8be278259147674b8`;
  and
- installed-system manifest: 121,266 entries with SHA-256
  `dfad2bdf4abfade3f9cf726fe4c3f1284732ed321eb4667d8a2cb9b3df280d7c`.

The installed-system archive bytes remain unchanged. Its manifest was later
made extraction-portable by normalizing directory allocation sizes to zero;
directory `st_size` is an ext4 allocation detail that can change when the
same members are recreated in a different insertion order. File sizes and
hashes, symlink targets, types, modes, UID/GID ownership, and the 121,266-entry
set remain exact. A regression requires regular-file and symlink sizes while
excluding directory allocation size from the identity.

The static audit proves the exact UI, planner, executor, firmware manifest,
installed root archive and manifests, 663 live packages, 3,759 modules, ARM64
UEFI/GPT layout, and existing recovery tools. The executor remains fail-closed
to the held live environment and one fixed internal NVMe namespace. This is a
local held engineering artifact; disposable-media and target-hardware fresh
installation qualification remain required before release.

The first physical installer launch correctly refused mutation but exposed an
overly broad EFI classifier: it counted both the Microsoft ESP and the
existing project-owned `SP11EFI` as Windows ESPs. The corrected planner
recognizes only the exact terminal `SP11 Linux EFI` plus `SP11 Linux Root`
pair as reclaimable, preserves the Microsoft ESP/MSR/basic-data partitions,
and refuses ambiguous, mounted, mislabeled, or non-adjacent variants. The
complete disposable-loop apply, population, double verification, removal,
and wipe matrix passed before the corrected ISO was rebuilt.

The corrected image was then used for a physical reinstall over the exact
project-owned Linux ESP/root pair. Disk detection, timezone selection,
branding installation, partition reclaim, installed-root population, target
configuration, and both independent verification passes completed. The final
UEFI NVRAM action failed closed because an entry labeled `SP11 Linux` already
existed from the prior installation. Reformatting the Linux partitions had
changed the ESP GPT identity, so the retained entry was stale and needed
replacement rather than refusal. The otherwise complete installation was
recovered by deleting and recreating only that entry. The new entry points to
partition 4 and `\EFI\BOOT\BOOTAA64.EFI`, is first in BootOrder, and Windows
Boot Manager remains present and unchanged. The installed root and ESP mount
from the expected NVMe partitions, the ARM64 fallback loader and GRUB config
exist, and the installed system reports zero failed units.

The maintained executor now reconciles this state transactionally: it removes
all existing entries with the exact project label, excludes their numbers
from the retained order, creates exactly one new entry, places it before the
retained non-project order, and validates its active bit, ESP identity,
loader, uniqueness, and order. Failure cleanup removes partial project
entries and restores only the retained non-project order, never a deleted
stale boot number. Fresh install, single-stale, duplicate-stale, duplicate
validation, and partial-failure cleanup cases pass in the nine-test executor
suite. Advancing the source fix requires a new build, static audit, exact-media
read-back, and physical reinstall/removal qualification.

The rebuild and static-audit portion is now complete. The held successor is
2,396,196,864 bytes with SHA-256
`d50e4729fcd7654029e3f5e7d8c16dbabf8ce8cc3660f1d550ad06bdfb5b944f`.
Its embedded executor and installed-root manifest generator match maintained
source byte-for-byte. The complete audit passed 663 packages including Rnote,
3,759 modules, 13 redistributable firmware files, the orange accent and exact
wallpaper, four project UCM entries, the fresh installer and recovery kits,
the identity-pinned 121,266-entry installed root, clean initramfs policy, and
the ARM64 UEFI/GPT plus helper-seeded SP11FW layout. The ISO was then written
to development thumb drive serial `0308100000000053`; hashing exactly
2,396,196,864 bytes back from the block device produced the same SHA-256,
closing the removable-media identity gate. The ISO remains held pending
physical reinstall/removal tests.

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

Repair1 removed `-all-root`, preserved the staged numeric owners,
and audits `/home/live` both before compression and after extraction from the
finished SquashFS. The live user is `1000:1000` with mode `0700` at both
gates. Repair3 subsequently qualified Wi-Fi and the rest of the listed live
hardware.

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

scripts/build-audio-topology.sh \
  --audioreach-source /path/to/audioreach-topology \
  --output work/audio-topology-review20

sudo scripts/build-held-live-image.sh \
  --local-staging \
  --audio-topology \
    work/audio-topology-review20/X1E80100-Microsoft-Surface-Pro-11-tplg.bin

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

## SP11FW physical qualification

The compatible one-drive path passed on the qualified Surface Pro 11 OLED/X
Elite unit on 2026-07-29. Early boot imported the six exact owner files,
including board SHA-256
`0ef5f6f3cb124f33c6de52371819ccd7c13763ceb86d476a178fd56e4cdc26a3`.
Wi-Fi, speakers, microphones, cameras, touch, and pen passed. The user-invoked
diagnostic report persisted directly to `SP11FW`, and systemd reported no
failed units. A subsequent reboot repeated the complete hardware pass; its
report is `live-image-firstboot-20260729T124330+0000.txt`, SHA-256
`55b6c5707eb9849ead310ef3b296f3f8e1b00300344589fcbbdad80b872a09e8`.

The final fail-closed artifact, ISO SHA-256
`2fe5f6050ec32b8d5c8d4497198fc87cb1f5ee7ac51057d4efdb8da9dd641d48`,
was then written to the same removable drive. Its immutable regions matched
the audited ISO byte-for-byte, and the personalized partition passed all six
firmware and six helper-file checks. The exact artifact boot repeated the
complete hardware pass with no failed units, SquashFS read errors, or BDF
load failure. Its persistent report is
`live-image-firstboot-20260729T133001+0000.txt`, SHA-256
`ae4bb8295ceccd1320ca7fb9a4066f3f781b2ae1c365873c18bde7b0f6f398b3`.
The bundled Linux collector subsequently repopulated the same physical
partition from a private Linux source root. It found and verified all six
files while preserving every seeded helper and existing report.

The separately tested 88,780-byte board data from Qualcomm Windows driver
1.0.4374.1300 imported but timed out in ath12k with `-110`; it is explicitly
rejected from the reviewed collectors and boot contract.
The device-specific 88,792-byte DPP `WLAN_CLPC.PROVISION` object and a
legacy-envelope derivative of its exact data payload independently produced
the same `-110` timeout. Both are also explicitly rejected.

The final artifact also passed the absent-volume negative boot. With the
companion label unavailable, it reached GNOME without an import marker,
Wi-Fi, or a sound card; systemd reported zero failed units, cameras still
enumerated, and no SquashFS read error occurred. Its persistent report
SHA-256 is
`0acd1ca26fdb156ea73b57323c4550afb94f2b8fb92d31c5a813c7ae8b7c0bd4`.

The deliberately incompatible-file boot also passed. With five exact files
and a wrong-size/wrong-hash `board.bin`, the companion volume was present but
the final artifact created no import marker and reached GNOME with zero failed
units and no SquashFS read error. Wi-Fi and the sound card remained
unavailable. Camera nodes enumerated, but Snapshot could not produce a usable
stream while the all-or-nothing policy withheld the owner GPU/DSP files. The
persistent report SHA-256 is
`7abf91ce4dd3d239e290b42f1543784c25619948346599d4a29fe845035fc516`.

## Remaining hardware test scope

All live-image tests must use removable media and the firmware boot picker and
must not install anything. The compatible path has validated:

1. ARM64 GRUB menu and GNOME automatic login;
2. OLED, touchscreen, pen, keyboard, and touchpad;
3. the `/etc/sp11-external-firmware` success marker, Wi-Fi, then Bluetooth;
4. front/rear camera enumeration and switching;
5. speakers and microphones;
6. power-profile changes and runtime state1 controls;
7. one short guarded suspend/resume and the complete post-resume input/camera
   checks; and
8. shutdown, USB removal, and an unchanged installed-system boot.

The final artifact also passed boots with `SP11FW` absent and with a
deliberately incompatible file. Both cases continued to GNOME and imported
nothing. The Linux collector's physical same-drive path passed as well.

Do not test installation from this artifact: no installer is present. Secure
Boot remains unsupported.
