# Surface Pro 11 camera source review

Date: 2026-07-19

Status: **PROVENANCE-REVIEWED AND HARDWARE-VALIDATED SOURCE CANDIDATE**

This record covers only the fresh `sp11-camera-review` branch. It does not
clear, license, or incorporate the withdrawn Practical8 history or artifacts.
It is an engineering provenance record, not legal advice or a guarantee that
a third party will not make a claim.

## Exact identity

- prerequisite branch: `sp11-sanitized2` at
  `2ace98eb6ef18cbd48074eed9f5b585d19ce398b`;
- camera branch: `sp11-camera-review` at
  `675d89b381d8b730a3f2eff1086875481ee5b515`;
- camera branch tree: `03c278405e6d2fd0ffa1fd4cad860ef45c7adbbc`;
- bundle SHA-256:
  `bacf60dc80463c92da9b62f3f0c5da077c27b67ac6685a28c542b890de5b8e64`;
- patch SHA-256:
  `a6d6f31fd9b3eea7e5b4243ec30300e1bc43718253fd2a2b77c2bdf4cebc3b6c`;
- the incremental bundle contains 13 new commits and requires the
  camera-free tip above.

None of the withdrawn camera commits is an ancestor of this branch. In
particular, withdrawn commits `86a8f8b24`, `bfaf42ff5`, and `3cee4c4e2` are
absent. Do not merge, cherry-pick, or publish those old objects.

## Source boundary

- IMX681 and the Surface-specific OV13858 mode are independently authored
  Linux implementations of runtime I2C observations made on personally owned
  hardware. No Windows binary, configuration file, trace, symbol, dump, or
  extracted payload is included.
- VD55G0 support replaces the experimental reconstruction with the official
  STMicroelectronics GPL driver and patch arrays at commit
  `9134fe572b77f906344f37ba227f375db73dc026`.
- Generic 4 nm C-PHY values remain adapted from Qualcomm's GPL-2.0-only
  `cam_csiphy_2_1_2_hwreg.h`, exact blob
  `347fb4944ccedfead1aa0c5260e6b41a5a038017`.
- The Surface-specific C-PHY initialization, interrupt-clear, shutdown, and
  delay values are independently transcribed facts from runtime WinDbg MMIO
  observations on the maintainer's own hardware. The bounded table is
  documented in-tree; no vendor source, binary, symbol file, decompiled
  output, or raw trace is included.
- Dale Whinham's ath12k `disable-rfkill` commit is present with original
  authorship and `Signed-off-by` history. The matching Denali property and
  binding documentation were added after the first hardware boot exposed the
  missing prerequisite.
- The PM8550 IR-illuminator node follows the upstream Qualcomm flash-LED
  binding. Current sinks 1 and 4 and the conservative 600 mA combined torch
  ceiling are independently measured hardware facts from bounded channel and
  VD55G0 frame tests on the maintainer's Surface. No vendor configuration
  file or copied value is included.
- CAMNOC comparison data, probe scanners, debug module parameters,
  bring-up-only controls, unobserved sensor tables, and Windows-derived
  payloads are excluded.
- The in-tree provenance record is
  `Documentation/driver-api/media/sp11-camera-provenance.rst`.

Primary upstream sources:

- https://git.codelinaro.org/clo/la/platform/vendor/opensource/camera-kernel
- https://github.com/LineageOS/android_kernel_oneplus_sm8550-modules/blob/lineage-23.2/qcom/opensource/camera-kernel/drivers/cam_sensor_module/cam_csiphy/include/cam_csiphy_2_1_2_hwreg.h
- https://github.com/STMicroelectronics/vd55g0-linux-driver/tree/9134fe572b77f906344f37ba227f375db73dc026

## Completed software checks

- [x] every new commit reviewed with `scripts/checkpatch.pl`; no code/style
  findings remain (the expected missing sign-off and generic MAINTAINERS
  prompts remain until maintainer certification);
- [x] `git diff --check` passes;
- [x] SPDX checks pass for every changed file;
- [x] affected devicetree binding schemas pass `dt_binding_check` and
  `yamllint`;
- [x] the three Surface Pro 11 DTBs compile;
- [x] all three DTBs pass validation filtered to the affected camera schemas;
- [x] the review4 OLED DTB passes validation against the upstream
  `qcom,spmi-flash-led` schema;
- [x] affected I2C sensor and Qualcomm CAMSS directories compile with Clang,
  LLVM, and `W=1`;
- [x] local Qualcomm tables match the pinned public GPL source: common 4/4,
  2.5-Gsym/s 36/36, and 3-phase 69/69 entries with zero mismatches;
- [x] all six Surface C-PHY observation batches mechanically match the
  hardware-working WinDbg transcription;
- [x] keyword and path audits find no raw trace, CAMNOC diagnostic, extracted
  payload, host identifier, credential, or withdrawn debug implementation;
- [x] withdrawn Practical8 commits are not ancestors of the branch.

## Remaining engineering and upstream checks

- [x] complete the full `Image modules dtbs` build with LLVM and `W=1`;
  final linking used the kernel-recommended `KALLSYMS_EXTRA_PASS=1` workaround
  after the initial link reported inconsistent kallsyms data;
- [x] boot `7.1.3-sp11-camera-review3` and
  `7.1.3-sp11-camera-review4` on the target Surface Pro 11 OLED;
- [x] verify WCN7850 Wi-Fi association and Bluetooth operation on the rebuilt
  kernel;
- [x] capture three changing RAW frames from front, rear, and IR sequentially;
- [x] confirm the expected formats, resolutions, frame sizes, approximately
  30 fps cadence, receiver routes, and interrupt activity;
- [x] review the post-capture kernel log, media graph, and generated OLED DTB;
- [ ] test concurrent camera use, suspend/resume, and extended repeated
  stream start/stop behavior;
- [x] confirm review3 kernel taint is zero and the post-test log contains no
  BUG, warning, lockdep, oops, or call-trace entry; review4 acquired only the
  expected out-of-tree-module taint after loading the separately built
  `v4l2loopback` test dependency; lockdep is not enabled in this release
  configuration;
- [ ] complete the broader non-camera system regression matrix;
- [ ] before any future upstream submission, have the maintainer personally
  review every patch, certify the Developer Certificate of Origin, add the
  maintainer's own `Signed-off-by`, and disclose material AI assistance using
  the target project's then-current format;
- [x] perform final review from a clean reconstruction of the incremental
  bundle before changing repository visibility or publishing binaries.

## Hardware result

The first clean boot (`camera-review1`) exposed an omitted ath12k rfkill
prerequisite: Bluetooth worked, but no wireless PHY registered. Review2
restored Dale Whinham's attributed fix and Wi-Fi passed. Its rear camera also
passed, but the generic Qualcomm C-PHY sequence delivered no front-camera
frames. Review3 replaced only the Surface C-PHY path with the bounded runtime
observations described above.

On review3, front IMX681 captured three 3840x2640 packed RAW10 frames at
33.328 ms average cadence, rear OV13858 captured three 4224x3136 packed RAW10
frames at 33.389 ms, and IR VD55G0 captured three 644x604 Y10P frames. Each
capture had the exact expected byte count, non-zero data, and distinct frame
hashes. Wi-Fi remained associated throughout, Bluetooth remained unblocked,
and no camera error was added to the kernel log.

The tested review3 artifacts are identified by these SHA-256 values:

- kernel Image:
  `72cb5d50d1afbfefe318c680f0d150ddd91bbf6957c11dc435466a287e169213`;
- OLED DTB:
  `3aefc15bf0f7879238d42c035ebac65a9c78b75b2f0511249a8b15164a5dca66`;
- initramfs:
  `ece1c0b3e5a86484a8ea4befe9b45e17f3c7e7169783fd630ff2b7637915c62f`;
- installed `qcom-camss.ko`:
  `bcf6eae66ab783e4cae1737809a3a7f4e796369beb46496ce6b3fc7df46b8988`.

All 3,758 staged modules reported the exact
`7.1.3-sp11-camera-review3` vermagic.

Review4 enabled only the IR illuminator using the standard PM8550 flash-LED
binding and the bounded hardware facts recorded above. In an initial bounded
automatic-exposure comparison, three dark frames averaged 15.839 while three
illuminated frames averaged 245.512, proving that the selected channels drive
the IR scene; the torch returned to zero after capture. Exposure was then
explicitly placed in manual mode and tuned to 1200, producing an unsaturated
face image.

The local Howdy integration converted Y10P to 644x604 GREY at 30 fps through
`v4l2loopback` 0.15.4. Three loopback frames had exact byte counts and distinct
hashes. A forced `SIGKILL` of the bridge proved that an independent systemd
fail-safe returns the torch from brightness 255 to zero. Howdy recognized the
enrolled model on its first frame in 954 ms with certainty 3.438; PAM was not
invoked. These userspace tools and enrolled biometric data are not included in
this camera source bundle.

The tested review4 artifacts are identified by these SHA-256 values:

- kernel Image:
  `9fcc24f29713663fdc89a16b5c3dfd097cc03fa91b3cf5b1a7e3e29a403a1338`;
- OLED DTB:
  `4caa12c8154470ea484890933f7997ec8e9a95b064927e0c2c8b814f9f658b3a`;
- initramfs:
  `e069c0ec9fc283e8e99ecdabc90e1bea86ceda18222918ff00315a19744a3f7b`;
- installed `qcom-camss.ko`:
  `391e1b7621cbe4c657a0b9043cb2a128fe119e418fd3af83cc19440937f9f29e`;
- separately built `v4l2loopback.ko`:
  `16948f9b1d9f1429b66569902d7d299d2469f9984c0093d5fc37e0273d925fcd`.

All 3,758 in-tree modules and the separately built loopback module reported
the exact `7.1.3-sp11-camera-review4` vermagic. Wi-Fi remained associated,
Bluetooth remained unblocked, and the post-test kernel log contained no camera
error, warning, oops, or call trace.

This qualifies the branch for experimental source publication. It does not
authorize a binary or ISO release, claim upstream readiness, or close the
remaining endurance, suspend, concurrent-use, and broader regression gates.
