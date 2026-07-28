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
- [ ] Build a bootable ARM64 UEFI live environment with usable touch/keyboard
  input and an offline recovery path.
  - [x] Assemble and statically audit the first non-installing held image:
    662 packages, 3,759 review20 modules, 11 allowlisted firmware files,
    volatile SquashFS root, ARM64 GRUB fallback loader, El Torito, GPT, and
    EFI System Partition.
  - [ ] Boot the exact image from removable media and qualify the live
    environment on target hardware.
- [ ] Make installation preflight-only by default, collision-safe,
  hardware-gated, repeatable, and rollback-aware.
- [ ] Test the exact ISO through boot, installation, first one-shot boot,
  promotion, reboot, Linux rollback, Windows GRUB boot, reinstall/repair, and
  removal.
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
The 2026-07-28 resolution contains 672 unique distribution packages: 662 in
the live closure and 129 in the build closure, with overlap. The live package
payload is 678,711,028 compressed bytes and 3,511,202,214 installed bytes
before the custom SP11 payload, firmware allowlist, live-image compression,
and project documentation.

Snapshot identities:

- live direct profile:
  `002d3e19caf039fe22f48bb72598230b093f5a2fccfc34ada48ebc97a427c580`;
- build direct profile:
  `972c0113ddef15714149623c947af54e67196cb091ce57f5c039550451b1c245`;
- complete package lock:
  `469dfdf921d1376757d02c0a9492dec58f560c3e359d85c0ddf9e0f68785257e`;
- repository database lock:
  `9dee549f5f9a867115e318448513cc9355b0bca5ab9a060462ff8792d770fd9a`.
- exact 595-pkgbase recipe lock:
  `1361fe0a28652ddb62003925603186fb0b90df3c10d9d02479e902230895eed5`.

The live closure uses only `core`, `extra`, and the single ARM-specific
`alarm/libpisp` dependency required by distribution libcamera. It contains no
firmware, alternate distribution kernel, AUR/foreign package, Howdy,
v4l2loopback, Quickshell, Niri, container stack, or compiler. The exact lock
and source-retention rules are documented in `iso/README.md`.

The held package snapshot contains exactly 672 packages, 672 detached
signatures, and 2,016 extracted package metadata files. Every package
signature and locked SHA-256 passed. Its `PACKAGE-SNAPSHOT.tsv` SHA-256 is
`cb336c6fa1dfab9644f304e89a797ab70d2e1131c6192484a5d043559c7221fe`.
The snapshot remains ignored local engineering output; it is not published.
The signed `.BUILDINFO` files also pin 595 distinct PKGBUILD SHA-256 values.
Those values are the acceptance criterion for the matching source snapshot;
a moving packaging branch is not sufficient.

The first held ISO and its complete static audit are documented in
`iso/LIVE-IMAGE.md`. Its SHA-256 is
`a8fd72ebe52a817634681b1ee827328b9cfdf24d6c6627957d736243f8e5c465`.
It contains no installer and remains local-only pending hardware boot,
distribution source closure, and all publication gates.

## Firmware allowlist

The firmware manifest selects 11 exact files: official WCN7850 Wi-Fi and
Bluetooth firmware, Adreno GPU firmware, X1E80100 QUPv3 firmware, and the
signed wireless regulatory database. Each path is locked by package/version,
size, SHA-256, upstream source identity, and required license/notice material.
The audit rejects any extra firmware or tracked blob.

Six Surface-specific ADSP/CDSP/audio files and one machine-local ath12k
`board.bin` on the qualified host are unowned and absent from upstream
linux-firmware. They are explicitly denied. A pristine beta live boot must
report audio and ADSP/CDSP-backed sensors unavailable; an installer may offer
only an explicit local import from operator-supplied files. Wi-Fi must be
qualified with the denied `board.bin` absent before the ISO claims support.

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
