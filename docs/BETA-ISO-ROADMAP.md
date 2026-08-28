# Surface Pro 11 beta ISO roadmap

## Release scope

The first beta targets only the tested Microsoft Surface Pro, 11th Edition
with the X1E80100/X Elite SoC, OLED panel, and `microsoft,denali` device tree.
The installer must reject LCD, X Plus, 5G, and other Surface variants unless
the operator explicitly accepts an unsafe development override.

Hardware-enablement has reached the threshold for ISO work. The tested tablet
has been used as a primary system for more than ten days; input, audio,
cameras, wireless, charging, display, and repeated suspend/resume have remained
stable. The first overnight guarded suspend completed 7 h 48 m with a clean
lid-open resume and all hardware passing afterward.

The remaining approximately 1.7--1.8 W suspend floor is a documented beta
limitation. Both Linux and Windows fail to reach the platform's final
AOSS/DDR collapse on the tested firmware. It does not block ISO development.

## Frozen functional baseline

The beta candidate must first reproduce the exact behavior of the qualified
local review20 configuration:

- Linux release `7.1.3-sp11-suspend-review20`;
- source commit `18d7951a10dc49e383d16c6af82fc2c07784de3d`;
- source tree `b820f10abba096e23a28506d7ad591dffdedf1a8`;
- promoted reproducible Image SHA-256
  `918ed2560654355555535290fd0d9657e1afc7022b3e46cc8396155d3575f256`;
- OLED DTB SHA-256
  `5e9009f5bd96a760a33086d1a8842e3228e3d28c413f96d70aca4914f7e397ed`;
- runtime PSCI state1 enabled by `sp11_deep_idle=1`;
- fail-closed state1 quiescence around every system suspend;
- `mem_sleep_default=deep`;
- `qcom_ipcc.mask_summary_on_suspend=1`;
- USB runtime autosuspend and MSM PSR experiments absent;
- both DWC3/xHCI paths left at their safe default runtime policy.

The release branch may clean up commit organization or remove unused
diagnostic interfaces only after a rebuilt candidate repeats the complete
qualification. Until then, the exact review20 tree is the behavioral
reference.

## Boot contract

The ISO must preserve every existing firmware boot entry and must not replace
or delete Windows Boot Manager. The tested GRUB chainloader entry is
functional:

```grub
chainloader /EFI/Microsoft/Boot/bootmgfw.efi
```

Windows USB/kernel debugging is enabled on the development machine and causes
an unusually long blank transition during Windows startup. That delay was
previously mistaken for a GRUB failure; it is not a chainloading defect.

Installation must:

1. retain the pre-existing Linux and Windows boot paths;
2. install the beta kernel, DTB, modules, and initramfs under unique names;
3. retain a known-good Linux rollback entry;
4. use a one-shot first beta boot;
5. promote the beta default only after an explicit successful validation;
6. provide recovery-media instructions for restoring the old default.

Secure Boot may remain unsupported for the first beta, but the requirement to
disable it must be stated before installation.

## Safety defaults

- Never enable runtime PSCI state1 unless the reviewed suspend guard is
  installed and effective.
- If the guard cannot prove all 12 state1 controls disabled and quiescent, it
  must prevent suspend.
- A boot without the `sp11_deep_idle` opt-in must retain the conservative
  state1-disabled behavior.
- Do not ship the rejected USB runtime-autosuspend or PSR experiments.
- Preserve the systemd-logind suspend-watchdog workaround used by the
  qualified host, or requalify long lid suspend without it.
- Warn that suspend consumes about 3.7 battery percentage points per hour on
  the tested firmware and is not suitable for multi-day bag storage.

## Binary and ISO gates

- [x] Publish reviewed source for the complete review20-derived kernel stack,
  including attribution and provenance for the PDC series and local changes.
- [x] Produce two clean, byte-identical kernel builds and record the complete
  build identity.
- [x] Qualify the corrected reproducible Image on target hardware through an
  exact-identity one-shot boot, active runtime state1, VideoCC binding, deep
  suspend/resume, and the complete post-resume hardware matrix.
- [x] Package and test the runtime-idle suspend guard and its conservative
  no-opt-in fallback.
- [x] Replace the obsolete `sp11-sanitized2` identities in the payload,
  installer, verifier, rollback tool, build helper, and documentation.
- [x] Assemble the promoted kernel payload twice from the audited module stage
  under the release hold; confirm byte-identical archives, safe paths, exact
  module count, and exclusion of host-only modules.
- [x] Stage deterministic complete corresponding source for every custom
  binary in the held payload: kernel/modules, iptsd/checker, and patched Power
  Profiles Daemon; reproduce all three userspace binary identities.
- [ ] Define the eventual live ISO package manifest and stage or offer the
  matching distribution-package source, including libcamera/IPA components
  and v4l2loopback only if the ISO actually includes it.
  - [x] Freeze the recommended GNOME AArch64 direct profiles, complete
    transitive dependency lock, repository database identities, package
    hashes, source-retrieval contract, and hard exclusion audit.
  - [x] Cache and verify every exact signed binary package and extract its
    `.BUILDINFO`, `.PKGINFO`, and `.MTREE` under the release hold.
  - [ ] Stage every matching package recipe, upstream source input, and
    applicable license in a durable source snapshot or offer.
    - [x] Prove that the canonical Arch recipe is not sufficient evidence for
      at least one signed ARM package and document the authoritative-source
      recovery hold in `iso/SOURCE-STATUS.md`.
- [ ] Include every applicable license, notice, source identity, patch, and
  machine-readable build recipe.
- [x] Define a firmware manifest containing only redistributable firmware.
  Never include Windows drivers, private traces, machine-specific Bluetooth
  identity/key material, sensor calibration, or generated proprietary
  registry data.
- [x] Build a bootable ARM64 UEFI live environment with usable touch/keyboard
  input and a fully target-qualified offline recovery path.
  - [x] Assemble and statically audit the first non-installing held image:
    662 packages, 3,759 review20 modules, 11 allowlisted firmware files,
    volatile SquashFS root, ARM64 GRUB fallback loader, El Torito, GPT, and
    EFI System Partition.
  - [x] Reject the first physical-boot artifact after proving its Zstandard
    SquashFS was incompatible with the exact kernel; rebuild with supported
    gzip compression, real live-medium root resolution, early display/input
    modules, and a codec/configuration audit gate.
  - [x] Reach GNOME with working OLED/touch, reject the image after
    `-all-root` made the mode-0700 live home inaccessible, preserve staged
    numeric owners, and audit home ownership in the finished SquashFS.
  - [x] Boot the exact repair3 image from removable media and qualify the live
    environment on target hardware. OLED, touchscreen, pen, Wi-Fi, speakers,
    microphones, and cameras passed; the initramfs RAM-copy eliminated the
    USB-hub-reset/SquashFS read failure seen on the earlier artifact.
  - [x] Define and statically validate an offline `SP11FW` companion-volume
    contract plus exact-hash Linux and Windows collectors. Wi-Fi is not a
    prerequisite: the owner can prepare the pack from an installed Linux
    system or the stock Windows driver store.
  - [x] Execute the PowerShell collector on stock Windows and compare the
    resulting six-file manifest to the Linux-created pack. Five identities
    match the original pins; Qualcomm driver 1.0.4374.1300 supplies a newer,
    Microsoft-signed 88,780-byte `bdwlan.elf` candidate.
  - [x] Boot with the exact new `bdwlan.elf` candidate hash. The all-or-nothing
    pack imported and restored audio, but ath12k timed out loading the BDF with
    `-110`; reject this candidate from the collector and boot allowlist.
  - [x] Read the device-specific `WLAN_CLPC.PROVISION` object through the
    installed Qualcomm DPP driver's read-only interface. Its 88,792-byte ELF
    and a controlled legacy-envelope derivative of the exact payload both
    timed out loading the BDF with `-110`; reject both identities.
  - [x] Trace the qualified 88,872-byte `board.bin` back to the
    `linux-firmware-atheros` WCN7850 `board-2.bin` package transaction. It is
    the unmodified record named by `firmware/derived.tsv`, and deterministic
    extraction reproduces SHA-256
    `0ef5f6f3cb124f33c6de52371819ccd7c13763ceb86d476a178fd56e4cdc26a3`.
    Move it into the redistributable base-image workflow and reduce SP11FW to
    the five proprietary DSP/GPU files.
  - [x] Prove a one-drive hybrid layout with a 64 MiB FAT32 `SP11FW`
    partition appended after the EFI partition. Seed it only with editable
    redistributable Windows/Linux collectors, a user-invoked diagnostic
    capture, their manifest, and a quick-start document. The resulting image
    is about 1.351 GB and retains a blob-free ISO/rootfs.
  - [x] Qualify Windows in-place population of that same-drive partition on
    physical removable media. The collector and FAT32 persistence work; the
    newer Windows board-data identity is separately rejected as incompatible.
  - [x] Qualify Linux in-place population of that same-drive partition on
    physical removable media. The bundled collector located all six exact
    files from a private Linux source root, populated the physical removable
    partition, and preserved the seeded helpers and existing reports; all
    resulting sizes and hashes verified.
  - [x] Build and audit the blob-free public-base held image with the
    redistributable topology/UCM and no local-proprietary marker. The audit
    proves 662 packages, 3,759 modules, 12 allowlisted/project firmware files,
    four project UCM entries, the SP11FW-aware initramfs, and ARM64 UEFI/GPT.
  - [x] Boot the blob-free base ISO with the qualified exact `SP11FW` pack and
    prove all six files are imported before device initialization. Wi-Fi,
    speakers, microphones, cameras, touch, and pen passed; the diagnostic
    report persisted directly to the same partition. A subsequent reboot
    repeated the complete hardware pass and produced report SHA-256
    `55b6c5707eb9849ead310ef3b296f3f8e1b00300344589fcbbdad80b872a09e8`.
  - [x] Write and boot the final fail-closed ISO, SHA-256
    `2fe5f6050ec32b8d5c8d4497198fc87cb1f5ee7ac51057d4efdb8da9dd641d48`.
    Its immutable regions matched the audited artifact byte-for-byte; all six
    qualified firmware files and six seeded helper files verified after
    personalization. The exact artifact repeated the full hardware pass with
    no failed units, SquashFS read errors, or BDF load failure. Persistent
    report SHA-256:
    `ae4bb8295ceccd1320ca7fb9a4066f3f781b2ae1c365873c18bde7b0f6f398b3`.
  - [x] Repeat with `SP11FW` absent. The final artifact reached GNOME with no
    import marker, no Wi-Fi or sound card, zero failed units, and no SquashFS
    read errors; cameras still enumerated and no partial owner-firmware
    activation occurred. Persistent report SHA-256:
    `0acd1ca26fdb156ea73b57323c4550afb94f2b8fb92d31c5a813c7ae8b7c0bd4`.
  - [x] Repeat with one deliberately incompatible file. With five exact files
    and a wrong-size/wrong-hash `board.bin`, the final artifact reached GNOME
    with the companion volume present but no import marker, Wi-Fi, sound card,
    or partial owner-firmware activation. It reported zero failed units and no
    SquashFS read errors. Camera nodes enumerated, but Snapshot could not
    produce a usable stream while the owner GPU/DSP files were withheld.
    Persistent report SHA-256:
    `7abf91ce4dd3d239e290b42f1543784c25619948346599d4a29fe845035fc516`.
  - [x] Rebuild, audit, write, populate, and cold-boot the corrected image
    whose base root contains the derived board record and whose SP11FW
    contract contains five files. The exact ISO, SHA-256
    `32af335c8e737799589d0179a3620355402d2b9b06dbf604009c8044800f9741`,
    passed its full static audit and whole-ISO thumb-drive read-back. Its
    bundled Windows collector produced exactly five verified files and no
    board data. Internal Wi-Fi, OLED, touchscreen, pen, speakers,
    microphones, and cameras passed the cold boot; Bluetooth was powered and
    zero systemd units failed. Persistent report SHA-256:
    `8935f6228769e6988f8cd918c480cdfad0029926850c50671e876556d8bd7b74`.
- [x] Make installation preflight-only by default, collision-safe,
  hardware-gated, repeatable, and rollback-aware.
  - [x] Add explicit held-local gating, a second confirmation for mutation,
    exact DMI/device-tree validation, Windows ESP/EFI/GRUB preservation
    checks, fresh/repair boot-state classification, a 3,759-entry module
    identity manifest, compatible-tree reuse, transaction integrity, and
    rollback path validation.
  - [x] Capture the installed tablet's preflight baseline and pass host-side
    read-only preflight. All 3,759 payload modules matched; two host-only
    modules remained outside the payload, and the documented exact VideoCC
    promotion relocation was accepted. The GRUB config, GRUB environment,
    Windows loader, and installer namespaces remained unchanged.
  - [x] Build and audit a held install-preflight ISO containing the exact
    installer kit and a live wrapper with read-only target mounts and no apply
    path. The synchronized final artifact is 1,414,481,920 bytes with SHA-256
    `688f08f042c16907afee8730e9827ef4f40ba55df80cb98697422bc798a0bc85`.
  - [x] Write and cold-boot that exact ISO, run its live wrapper against the
    internal root and ESP, and return the persistent preflight report without
    modifying the target. The report SHA-256 is
    `76d4139c1ce4a5d89e03254e61ad3b6314d7c25627a6493519e2fa968b94afa2`.
    The immediate host-side comparison confirmed the Windows loader, GRUB
    config, GRUB environment, EFI entry, and empty installer namespaces were
    unchanged.
- [ ] Test the exact ISO through boot, installation, first one-shot boot,
  promotion, reboot, Linux rollback, Windows GRUB boot, reinstall/repair, and
  removal.
  - [x] Complete the first controlled apply. Transaction
    `20260729T224010Z` passed rollback-integrity, isolated boot payload, all
    3,759 module identities, initramfs VideoCC, Windows chainloader/file/EFI,
    and one-shot-entry verification. The persistent default was unchanged.
  - [x] Boot and validate the armed one-shot target. The one-shot was consumed,
    the exact isolated installed payload booted, the full installed hardware
    and service matrix passed, Windows and BootOrder remained unchanged, and
    the persistent default was not modified.
  - [x] Cold-boot the exact customized live image after fresh Windows firmware
    extraction. Firmware import, Wi-Fi, Bluetooth, both visible cameras,
    audio, desktop defaults, touch, and full Rnote pen behavior passed.
  - [x] Boot a preserved base kernel, dry-run/apply rollback, and validate the
    restored system and Windows boot.
    The first physical apply exposed an `ETXTBSY` restore failure because the
    power-profiles daemon still executed its wrapper. The transaction remained
    intact; stopping that daemon before restoration allowed an idempotent retry
    to complete, and all restored files, GRUB, modules, Windows, and EFI
    identities passed independent verification. The post-rollback base-kernel
    reboot also passed; its only failed unit reflects that obsolete kernel's
    known missing/unsupported modules. Windows chainload reached the desktop,
    and the next boot returned through the unchanged persistent qualified
    review20 default with zero failed units and exact GRUB/Windows/EFI
    identities.
  - [x] Replace the installed-obsolete-kernel rollback dependency with a
    separately gated live-USB rollback path and qualify it.
    The synchronized replacement ISO passed static audit and exact physical
    read-back. A fresh Windows extraction/live hardware pass, new install,
    candidate boot, deep suspend/resume, read-only live rollback preflight,
    confirmed apply, and restored-default boot all passed. The live reports
    have SHA-256
    `a1237e7cc3f0bf9682f175f3570d7e16d8c2b5069a46ec8483859ae1100c3dcf`
    and
    `d71f5974a094870ad9d766e87ac655d697f0fa068d2dcbc6e4135da7de80d4fb`.
    All saved files/symlinks, service states, 31 GRUB entries, reused modules,
    Windows loader, EFI entry, BootOrder, and empty one-shot state passed
    independent post-boot verification.
  - [ ] Exercise explicit repair and final removal from a promoted installation,
    then remove the
    obsolete development fallback from the supported workflow.
- [ ] Build and qualify a separate fresh-machine installer; do not repurpose
  the existing installed-system overlay transaction.
  - [x] Define the fail-closed dual-boot/wipe contract, immutable-plan boundary,
    dedicated Linux ESP/root layout, installed-rootfs artifact boundary,
    partition-aware removal model, and optional Secure Boot qualification path
    in `docs/FRESH-INSTALLER-DESIGN.md`.
  - [x] Implement the first read-only disk inventory/planning component. It has
    no partitioning or formatting code, marks fixture-derived plans
    non-executable, refuses mounted/removable/hot-plug/USB/serial-less targets,
    accepts dual boot only in a >=33 GiB Windows-created extent immediately
    before Windows Recovery, and emits an identity-bound JSON plan. Eight
    synthetic regression cases pass; the installed development host is
    correctly refused because its target filesystems are mounted.
  - [ ] Create and independently verify two disconnected pre-recovery archives
    of the complete active workspace, frozen legacy lab, qualified inputs,
    working firmware, and host audit state. The 2026-07-30 inventory is
    245,670,223,872 bytes before compression and requires
    257,953,735,065 free bytes on each destination after the enforced 5%
    headroom; `SP11FW` is not a valid backup target.
  - [x] Test planning against a real disposable sparse GPT/loop device in
    addition to the synthetic JSON models. The Windows EFI, reserved,
    basic-data, 34 GiB free extent, and recovery geometry produced the exact
    dual-boot plan; the independent wipe plan required the physical serial and
    remained non-executable because its inventory was captured as a fixture.
  - [x] Build and audit the first dedicated installed-system rootfs artifact
    directly from the frozen 663-package closure; never copy the live root.
    It contains 121,262 manifested entries, 3,759 exact modules, only
    redistributable base firmware, no human account, a locked root account, no
    machine ID, NVMe host identity, `fstab`, generated Java/font/loader caches,
    or live/autologin/installer/owner-firmware state. Its 953,559,601-byte
    archive has SHA-256
    `37466c74b4640b300c9f31e242050b42d75bb5163e3a02cf2228562285631993`.
  - [x] Repeat the complete installed-root package build from a new directory
    and require byte-identical root manifest and archive identities. Both
    independent builds passed the strengthened audit and matched exactly:
    root manifest
    `aea2358bb9d7b326fbf486e0e013936b2cbeb3984e5ce0bce4a6bad83ac67be1`,
    boot manifest
    `e4ba2e046cc5e230df8222bf16a3e1cc1bf94240086dd49ad3a121aac3ad5f38`,
    and archive
    `37466c74b4640b300c9f31e242050b42d75bb5163e3a02cf2228562285631993`.
  - [x] Implement and qualify the first identity-rechecking partition executor
    and transaction-aware dual-boot removal path, restricted in code to a
    fixed-serial `/dev/loopN` backed by the same private directory as an exact
    disposable marker. Wrong confirmations and mounted targets make no
    changes; dual apply/removal restores the original GPT table byte-for-byte;
    wipe apply works and explicitly refuses a false Windows-recovery claim.
  - [x] Extend the held loop executor with installed-root extraction, exact
    five-file owner-firmware import, target `fstab` and machine/NVMe identity,
    password-backed account creation, review20 initramfs, ARM64 GRUB on the
    dedicated ESP, explicit Windows chainloader, and an independent
    block-level read-only installed-system verifier. Two consecutive verifier
    passes reproduce the complete target manifest and validate all 3,759
    modules plus VideoCC initramfs content before exact dual removal.
  - [x] Stage an unprivileged interactive terminal planning preview and valid
    GNOME application entry without connecting either to the held live-image
    build. Three regression cases prove that it saves only non-executable
    plans, requires exact `SAVE`, and never replaces an existing plan; the
    staging audit also rejects privilege, mutation commands, or a live-builder
    consumer.
  - [x] Connect the planning preview to the separately gated install action
    after the planner, disposable-loop executor, root-population, double
    verification, removal, and wipe qualifications passed. The held ISO
    exposes the resulting GNOME installer entry and exact second-confirmation
    boundary.
  - [x] Exercise the corrected dual-boot reclaim path in a physical reinstall.
    The installer preserved the Microsoft ESP, MSR, and BitLocker partition;
    reclaimed only the exact project-owned Linux ESP/root pair; populated and
    configured the installed system; and completed both verification passes.
    The final NVRAM step then refused the stale `SP11 Linux` entry retained
    from the prior installation. Manual entry replacement recovered the
    populated system without repartitioning; Linux booted from the new ESP,
    Windows Boot Manager remained intact, and systemd reported zero failed
    units.
  - [x] Fix the physical reinstall NVRAM failure in maintained source. The
    executor now removes all stale/duplicate entries labeled `SP11 Linux`,
    preserves the relative order of every non-SP11 entry, creates and
    validates exactly one active entry for the new ESP and ARM64 fallback
    loader, and leaves a deterministic non-SP11 BootOrder if replacement
    fails. Nine executor unit tests cover fresh creation, one stale entry,
    duplicate stale entries, exact final validation, and partial-failure
    cleanup without deleting Windows Boot Manager.
  - [x] Rebuild and statically audit the held ISO with the UEFI reconciliation
    fix and extraction-portable installed-root manifest. The embedded executor
    and manifest generator match maintained source byte-for-byte. The artifact
    is 2,396,196,864 bytes with SHA-256
    `d50e4729fcd7654029e3f5e7d8c16dbabf8ce8cc3660f1d550ad06bdfb5b944f`;
    its complete 663-package, 3,759-module, firmware, branding, installer,
    installed-root, initramfs, UEFI/GPT, and artifact-identity audit passed.
  - [x] Write that exact successor to development thumb drive serial
    `0308100000000053` and verify an exact 2,396,196,864-byte device read-back.
    The read-back SHA-256 is
    `d50e4729fcd7654029e3f5e7d8c16dbabf8ce8cc3660f1d550ad06bdfb5b944f`,
    identical to the source ISO. Physical reinstall/removal remains required.
  - [ ] Qualify dual boot, removal, and wipe mode on disposable physical media,
    then repeat the complete workflow after official Surface recovery restores
    the tablet to its default Windows layout.
  - [ ] Qualify an optional signed ARM64 unified-kernel-image and manual Surface
    UEFI certificate-enrollment path without replacing Microsoft keys.
- [ ] Test touchscreen, pen, keyboard, both touchpads, Wi-Fi, Bluetooth, audio,
  cameras, charging, power profiles, lid suspend, power-button suspend, and
  resume against the exact packaged build.
- [ ] Scan every ISO/archive member and symlink for unsafe paths, private host
  data, credentials, diagnostic captures, and withdrawn artifacts.
- [ ] Run a final clean-clone source/binary correspondence and REUSE audit.
- [ ] Remove `BINARY-RELEASE-HOLD.md` only after every required gate passes.

## GNOME package snapshot

The first live profile is defined by `iso/packages-live.aarch64.tsv`; the
native image-builder profile is separate in `iso/packages-build.aarch64.tsv`.
The 2026-07-29 resolution contains 673 unique distribution packages: 663 in
the live closure and 129 in the build closure, with overlap. The live package
payload is 690,962,764 compressed bytes and 3,546,544,912 installed bytes
before the custom SP11 payload, firmware allowlist, live-image compression,
and project documentation.

Snapshot identities:

- live direct profile:
  `22af984674e8d525190d06d954d72f42bfe6c2f222882e0aa02a780f4d2414e5`;
- build direct profile:
  `972c0113ddef15714149623c947af54e67196cb091ce57f5c039550451b1c245`;
- complete package lock:
  `98d417e0c48c03a8a2249b901241132bbf81d857cfddfc5fc41ecc05e36b682a`;
- repository database lock:
  `9dee549f5f9a867115e318448513cc9355b0bca5ab9a060462ff8792d770fd9a`.
- exact 596-pkgbase recipe lock:
  `ee489a2f3931d0a424b56a4e5d6d004e8593805d4db56cc0f147bc9984879847`.

The live closure uses only `core`, `extra`, and the single ARM-specific
`alarm/libpisp` dependency required by distribution libcamera. It contains no
firmware, alternate distribution kernel, AUR/foreign package, Howdy,
v4l2loopback, Quickshell, Niri, container stack, or compiler. The exact lock
and source-retention rules are documented in `iso/README.md`.

The held package snapshot contains exactly 673 packages, 673 detached
signatures, and 2,019 extracted package metadata files. Every package
signature and locked SHA-256 passed. Its `PACKAGE-SNAPSHOT.tsv` SHA-256 is
`60a1d33fd546985a9a73ce286fb34b1cbd9fb153436f6639a12fa55901e3cf14`.
The snapshot remains ignored local engineering output; it is not published.
The signed `.BUILDINFO` files also pin 596 distinct PKGBUILD SHA-256 values.
Those values are the acceptance criterion for the matching source snapshot;
a moving packaging branch is not sufficient.

The held-image history, repair3 target result, and current blob-free
public-base artifact are documented in `iso/LIVE-IMAGE.md`. The held image
contains a fail-closed installer kit and a live wrapper with no mutation path;
it is not a supported installer. Publication still requires distribution
source closure, install/rollback testing, and the remaining release gates.

## Firmware allowlist

The firmware allowlist selects 11 exact files: official WCN7850 Wi-Fi and
Bluetooth firmware, Adreno GPU firmware, X1E80100 QUPv3 firmware, and the
signed wireless regulatory database. Each path is locked by package/version,
size, SHA-256, upstream source identity, and required license/notice material.
`firmware/derived.tsv` additionally selects one unmodified WCN7850 board
record from the exact allowlisted `board-2.bin`; the builder verifies its
88,872-byte output and SHA-256 before installation. The audit rejects any
extra firmware or tracked blob.

Five owner-supplied files on the qualified host—two DSP device trees, two DSP
images, and one GPU secure image—are unowned and absent from upstream
linux-firmware. They remain explicitly denied from published artifacts.

The audio topology and UCM profile are not part of that restricted set. The
BSD-3-Clause topology source now reproduces the exact tested binary, and the
project-authored UCM routing is tracked under MIT. The blob-free ISO can
therefore carry both.

For beta 1, the hybrid ISO includes a 64 MiB FAT32 partition labeled
`SP11FW`, seeded only with editable redistributable Linux/Windows collectors,
a user-invoked persistent diagnostic capture, their manifest, and quick-start
instructions. Those collectors populate the same writable partition on the
already written live USB. Early boot validates all five files into RAM before
importing any into the volatile live root. An absent or incompatible firmware
payload leaves the ISO bootable with documented hardware limitations. This
avoids a Wi-Fi bootstrap problem and a second USB, does not download firmware,
and keeps the published ISO redistributable.

## Accepted beta limitations

The following do not block a narrowly scoped and clearly labeled beta:

- high suspend drain caused by missing AOSS/CX/DDR collapse;
- USB runtime autosuspend remaining disabled;
- no native Linux pairing for the detached Flex Keyboard;
- proprietary ambient-color configuration not being redistributed;
- conservative speaker volume;
- incomplete desktop integration for external-monitor brightness;
- no support for untested SP11 hardware variants;
- no Secure Boot support.

These limitations must be prominent in the release notes and installer
preflight rather than hidden in development history.
