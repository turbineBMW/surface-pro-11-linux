# Redistribution and provenance review

Date opened: 2026-07-19

Status: **SOURCE-ONLY PUBLICATION CANDIDATE — BINARY/ISO HOLD ACTIVE**

This document tracks the evidence for publishing a fresh source-only
repository and, separately, for a future binary or ISO. It distinguishes copyrightable source or
firmware from hardware observations, independently written integration code,
and material already offered under an open-source license. Acknowledgement is
required, but acknowledgement alone is not permission to redistribute.

This is an engineering compliance record, not legal advice. Items marked
`LEGAL REVIEW` require permission from the rightsholder, replacement from a
documented redistributable source, removal, or review by qualified counsel.

## Current classification

| Material | Present location | Source | Classification | Required action |
| --- | --- | --- | --- | --- |
| Linux v7.1.3 base | kernel bundle/patch prerequisite | Linux stable | CLEAR, GPL-2.0-only aggregate with per-file exceptions | Preserve upstream licenses and source identity |
| Surface Pro 11 bootstrap | installation documentation | `dwhinham/linux-surface-pro-11` | CLEAR as credited prior art; no image-builder code copied into this repository | Preserve credit and link |
| ath12k rfkill change | fresh `sp11-camera-review` history | Dale Whinham commit `d7e0b837e` | CLEAR, GPL kernel contribution with original author and Signed-off-by preserved | Retain Dale's authorship, trailer, and matching Denali property provenance |
| X1E80100 CAMSS binding changes | fresh `sp11-camera-review` history | adapted with explicit credit to Bryan O'Donoghue commits `f347696c3`, `5d95ac773` | REVIEWED GPL/DT BINDING ADAPTATION | Preserve Bryan/Linaro credit and upstream source identity |
| HID-over-SPI series | sanitized kernel history | upstream v4 series by Jingyuan Liang, Jarrett Schultz, and Angela Czubak, with reviews/sign-offs including Dmitry Antipov | CLEAR, GPL-compatible upstream contribution | Preserve complete author/sign-off/copyright history and link the series |
| SP11 touch/QSPI work | curated kernel history | independently developed from public specifications, Linux source, hardware tests, and WinDbg runtime observations | REVIEWED ORIGINAL WORK | Preserve `docs/TOUCH-QSPI-PROVENANCE.md`; exclude private inputs and descriptor-only diagnostics |
| SP11 suspend, volume, fan, and SAM profile work | curated kernel history | independently developed Linux integration | REVIEWED ORIGINAL WORK | Preserve source history and platform limitations |
| Qualcomm C-PHY tables | fresh `sp11-camera-review` history | Qualcomm `cam_csiphy_2_1_2_hwreg.h`, exact blob `347fb4944ccedfead1aa0c5260e6b41a5a038017` | REVIEWED OPEN-SOURCE ADAPTATION, GPL-2.0-only | Preserve Qualcomm copyright, GPL license, immutable source link, and provenance record |
| Zenbook A14 camera wiring example | withdrawn Practical8 history only | Aleksandrs Vinarskis, patch `2eb7105d803d` | CREDITED PRIOR ART; excluded | Preserve exact source/author and notices if reintroduced |
| IMX681 initialization and mode data | fresh `sp11-camera-review` history | independently authored from runtime I2C observations on owned hardware | REVIEWED ORIGINAL WORK; old history and its inaccurate “verbatim” claim excluded | Preserve provenance record; do not import extracted files, dumps, or old commits |
| OV13858 Surface mode/register changes | fresh `sp11-camera-review` history | independently authored from runtime I2C observations on owned hardware | REVIEWED ORIGINAL WORK extending the upstream GPL driver | Preserve provenance record; do not import extracted files, dumps, or old commits |
| VD55G0 driver, patch firmware, and mode data | fresh `sp11-camera-review` history | official STMicroelectronics GPL driver, commit `9134fe572b77f906344f37ba227f375db73dc026` | REVIEWED OPEN-SOURCE IMPORT, GPL-2.0-only SPDX normalization | Preserve ST copyright, license, source pin, and adaptation record |
| Surface IR illuminator DT description | fresh `sp11-camera-review` history | upstream Qualcomm flash-LED binding plus independently measured channel mapping and conservative torch ceiling | REVIEWED HARDWARE OBSERVATION | Retain the bounded provenance record; do not import the withdrawn Windows-referenced commit or values |
| Surface X1E80100 C-PHY observation sequence | fresh `sp11-camera-review` history | independently transcribed runtime WinDbg MMIO observations on owned hardware | REVIEWED HARDWARE OBSERVATION; no vendor source, binary, symbol file, decompiled output, or raw trace included | Retain the bounded-table provenance and hardware evidence; do not expand it with raw diagnostic material |
| Withdrawn C-PHY replay/debug machinery | withdrawn Practical8 history only | early runtime experiments and diagnostics | EXCLUDED; not part of the reviewed branch | Do not reintroduce module parameters, static-extraction artifacts, or diagnostic-only tables |
| CAMNOC diagnostic values | withdrawn Practical8 history only | runtime MMIO trace | EXCLUDED; not required by the fresh implementation | Do not reintroduce without a new technical and provenance review |
| libcamera IMX681 properties/helper | userspace patches 1-2 | original changes to LGPL-2.1-or-later libcamera files | CLEAR subject to LGPL notices/source | Record LGPL-2.1-or-later and upstream copyrights |
| libcamera IMX681 tuning | userspace patch 3 and rootfs YAML | measured black level; original CC0 file | CLEAR, CC0-1.0 | Retain SPDX and copyright text |
| iptsd v3.1.0 binaries | future binary payload; not included | unmodified `linux-surface/iptsd` commit `a83bc1232` | CLEAR subject to GPL-2.0 source obligations | Include license, exact complete source, and build recipe with any future binary |
| Power Profiles Daemon binary | future binary payload; not included | PPD 0.30 plus local patch | CLEAR subject to GPL-3.0-only source obligations | Include exact complete source, patch, license, and build recipe with any future binary |
| v4l2loopback 0.15.4 | local review4 and review5 Howdy tests only; not included in this repository | Arch package source / upstream GPL project | TEST DEPENDENCY, NOT DISTRIBUTED | If a binary is shipped later, include exact corresponding source, license, and reproducible build identity |
| Bounded SP11 IR bridge | `feature/howdy-ir-review` source only | publication-review rewrite from public APIs, published topology/format facts, and functional lessons from the frozen proof of concept | REVIEWED ORIGINAL WORK, MIT; bounded target hardware and SIGKILL fail-safe tests pass; no biometric output mode or PAM mutation; legacy unlicensed files excluded | Retain safety/privacy documentation; reassess Howdy packaging, model, permissions, and security before any PAM work |
| Howdy 2.6.1 | local review4 direct test and review5 bounded previews only; not included | upstream tag `3c9537a35`, Arch package `2.6.1-3` | MIT TEST DEPENDENCY, NOT DISTRIBUTED; old authentication software with an explicit upstream security warning | Reassess version, model inputs, dependencies, packaging, storage permissions, and PAM threat model before any distribution or authentication integration |
| Original integration scripts and documentation | repository | turbinebmw | CLEAR, MIT | Retain consistent SPDX/REUSE metadata |
| AI-assisted development | source and documentation | Fable 5, ChatGPT 5.6, and later Codex/GPT-5 assistance reported in `docs/AI-ASSISTANCE.md` | DISCLOSED TOOL ASSISTANCE; human upstream certification not claimed | Preserve the disclosure; require human review and DCO certification before any future upstream submission |

## Immediate containment

- [x] Public repository made private by the owner.
- [x] Public promotion of downloadable code and binaries paused.
- [x] Local `provenance-cleanup` branch created.
- [x] Release-assembly script refuses to run while the hold file exists.
- [x] GitHub reports the repository `PRIVATE`; the withdrawn prerelease asset
  and tag have been deleted.
- [x] GitHub reports zero forks. The retained payload asset reported one
  download on 2026-07-19. Independent mirrors cannot be ruled out.

## Source publication strategy

The conservative 12-commit prerequisite contains no camera enablement. A
separate 13-commit `sp11-camera-review` branch adds the reviewed camera source
on top of that exact tip. Both are distributed as source-only incremental Git
bundles and cumulative patches.

The public repository must have a new, single-root Git history. It must not reuse the
Practical8 commit, tree, Image, DTB, module, archive, or checksum values.

## Source-only publication gates

- [x] Build a sanitized kernel history from the declared Linux base without the camera commit range.
- [x] Review every remaining commit message and diff for copied proprietary expression.
- [x] Generate a new incremental bundle and cumulative patch from the sanitized history.
- [x] Add an SPDX/copyright manifest for every release file and pass `reuse lint`.
- [x] Include no kernel, module, userspace binary, firmware, initramfs, payload,
  disk image, ISO, biometric model, or private capture.
- [x] Verify that no firmware, Windows package, trace, private capture, host identifier, or credential is present in every object and archive of the fresh repository.
- [x] Rebuild on a clean tree and record compiler, binutils, source, config, and artifact hashes.
- [x] Remove or replace every camera item previously marked `LEGAL REVIEW` from the fresh source history.
- [x] Revalidate the fresh camera implementation on Surface Pro 11 hardware and record bounded front, rear, IR, Wi-Fi, and Bluetooth results.
- [x] Disclose material AI assistance without representing an AI-generated
  human DCO certification.
- [x] Create a fresh local single-root repository and verify that its complete
  object graph contains no withdrawn Practical8 patch or bundle.
- [x] Create a brand-new GitHub repository from that audited history; do not
  change the existing private repository to public.
- [x] Delete the retained `v0.1.0-alpha` release asset and withdrawn tag, or
  otherwise prove they cannot become public when repository visibility changes.
- [x] Publish corrected release notes that make no unsupported provenance or compatibility claims.

## Future binary and ISO gates

- [ ] Stage complete corresponding source for every shipped GPL/LGPL binary,
  including the exact full kernel, iptsd, Power Profiles Daemon, and any
  modified libcamera sources used by the payload.
- [ ] Include all applicable license texts, copyright notices, source
  identities, build inputs, and machine-readable build instructions alongside
  the binaries.
- [ ] Verify that binary and source archives contain no absolute or
  parent-traversal paths and no external firmware, Windows package, trace,
  private capture, host identifier, credential, or diagnostic log.
- [ ] Run clean install, rollback, boot, input, audio, camera, suspend, and
  profile tests against the exact packaged build.
- [ ] Perform a final clean-clone source/binary correspondence audit and
  deliberately remove `BINARY-RELEASE-HOLD.md`.
- [ ] Obtain qualified legal review if a risk tolerance beyond this
  engineering provenance review is required.

## Primary references

- Linux licensing rules: https://docs.kernel.org/process/license-rules.html
- Linux stable: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
- SP11 base project: https://github.com/dwhinham/linux-surface-pro-11
- HID-over-SPI v4 series: https://patchew.org/linux/20260609-send-upstream-v4-0-b843d5e6ced3%40chromium.org/
- Microsoft HID-over-SPI specification: https://www.microsoft.com/en-us/download/details.aspx?id=103325
- Qualcomm camera-kernel: https://git.codelinaro.org/clo/la/platform/vendor/opensource/camera-kernel
- Reviewed Qualcomm mirror/blob: https://github.com/LineageOS/android_kernel_oneplus_sm8550-modules/blob/lineage-23.2/qcom/opensource/camera-kernel/drivers/cam_sensor_module/cam_csiphy/include/cam_csiphy_2_1_2_hwreg.h
- STMicroelectronics VD55G0 GPL driver: https://github.com/STMicroelectronics/vd55g0-linux-driver/tree/9134fe572b77f906344f37ba227f375db73dc026
- linux-surface iptsd: https://github.com/linux-surface/iptsd
- libcamera: https://git.libcamera.org/libcamera/libcamera.git
- Power Profiles Daemon: https://gitlab.freedesktop.org/upower/power-profiles-daemon
