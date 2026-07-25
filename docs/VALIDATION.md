# Experimental source validation record

Date opened: 2026-07-19

## Source reconstruction

- [x] sanitized incremental bundle verifies and requires Linux `v7.1.3`
  commit `199c9959d3a9b53f346c221757fc7ac507fbac50`;
- [x] sanitized bundle restores tip
  `2ace98eb6ef18cbd48074eed9f5b585d19ce398b` and tree
  `3924711c8ab3ee5c0208d214a4433eafc271df42`;
- [x] camera bundle adds 13 commits and restores tip
  `675d89b381d8b730a3f2eff1086875481ee5b515` and tree
  `03c278405e6d2fd0ffa1fd4cad860ef45c7adbbc`;
- [x] touch autoload bundle adds one commit and restores tip
  `86fc94c58a89a56c7ceb57b42c6025b2569da56d` and tree
  `4624d85595964242c26d7042106d068cbbdd9977`;
- [x] tablet-mode resynchronization bundle adds three commits and restores tip
  `940bbc856a120e6f967f9dbaf825d5473bfae664` and tree
  `62edee5183ed3b42ee3a2f9f0c71066c3ab87742`;
- [x] charge-limit reliability bundle adds one commit to the tablet-mode tip
  and restores tip `4d50f4a7a8debb28b5780f80f941f1fcee4036cd` and tree
  `9de653f31534b28a525f86d23c441deb831c0e2f`;
- [x] camera-switch fix bundle adds one commit to the charge-limit tip and
  restores tip `fd1932d6e2a45e665c062b1b1c810f09db46ab4e` and tree
  `c30f01a3d05a28bf8c4a0e809fc8f81a919927af`;
- [x] all patches apply cleanly to their declared prerequisites;
- [x] bundle and patch reconstructions produce identical final trees;
- [x] changed-path, keyword, SPDX, and whitespace audits pass;
- [x] a clean LLVM/Clang `Image modules dtbs` build completes;
- [x] generated Image, OLED DTB, config, and module ABI identities are
  recorded.
- [x] two independent clean builds with the neutral `sp11@reproducible`
  identity produce byte-identical Image, DTB, config, `Module.symvers`, and
  module hashes;
- [x] staged module trees contain no absolute `build`/`source` symlink or other
  local workspace path.

The initial reproducibility check used two empty output directories with the
declared Clang/LLD toolchain. Both review4 builds produced Image SHA-256
`9759248ac951f79a259bbebbfc7910891d940e406e9c8f5aafec17b046fde10e`
and identical hashes for all 3,758 modules. The staged review4 candidate was
scanned after removing the generated absolute `build` symlink; it had zero
remaining symlinks and no local account, hostname, or workspace path marker.

The reproducible review4 candidate booted with the exact expected build identity,
Image, DTB, config, module count, and module-tree properties. That boot also
confirmed a pre-existing touch regression in review4: the touchscreen enumerated
as `spi:g6-touch-digitizer`, while the module advertised only the incompatible
`spi:microsoft,g6-touch-digitizer` alias. An explicit `modprobe spi_hid_of`
immediately restored the physical touchscreen/stylus, started `sp11-iptsd`, and
created both iptsd virtual devices.

After the one-line correction, two new empty-directory review5 builds produced
byte-identical Image SHA-256
`39027932868b113b3068713dffd8b97168187a69547065ee4e77e7a136e79b97`,
DTB, config, `Module.symvers`, `vmlinux`, generated build-identity files, and all
3,758 modules. Their module-manifest SHA-256 is
`337ddc859f8b932d78e316f6935b293e97472afb2d6373333f14058894902c2d`.
The rebuilt module advertises the required `spi:g6-touch-digitizer` alias.
The corrected module tree and unique boot payload pass their pre-boot staging
checks. A one-shot review5 boot then passed the strict automatic checker without
calling `modprobe`: `spi0.0` bound to `spi_hid_of`, the physical touchscreen and
stylus appeared, both IPTSD virtual devices appeared, and `sp11-iptsd` was
active. The maintainer physically confirmed touch, multitouch, pen hover,
strokes, and eraser operation.

Review6 added a delayed Surface Aggregator tablet-mode controller re-query after
resume. Two empty-directory builds produced byte-identical Image SHA-256
`f7ca4995d138d9d03969d5c8cbd65764eb5b5b35c0fa3b201c693a3f62df8dd1`,
OLED DTB, config, `Module.symvers`, and all 3,758 modules. Their normalized
module-manifest SHA-256 is
`a4075bc8d26c2637ad46adb377ee42741eb95f987ad439a1e0a1fbe557534b43`.
The changed driver passes strict `checkpatch.pl`, and a targeted `W=1` module
build completes without a warning in the modified module. Attached and detached
suspend/resume tests passed, but a later physical keyboard reattach exposed a
missed cover-state notification: attached HID endpoints returned while the
cached tablet posture suppressed the touchpad. A controller-backed switch
re-query restored `laptop` state and the touchpad immediately.

Review7 observes the KIP connection event and schedules that same delayed state
query, retaining the controller as the source of truth. Two empty-directory
review7 builds are byte-identical across Image, OLED DTB, config,
`Module.symvers`, `vmlinux`,
generated build identity, and all 3,758 modules. The Image SHA-256 is
`caf4fb1db047807a6ff74f5212de51ba96e777a7820e1f7c58ab8d5c210894eb`,
and the normalized module-manifest SHA-256 is
`1fdf6690301ab8961d69be2e95d5cef928d30c898551a76f38ca9ec088263d1b`.
Its first physical reattach returned transient raw KIP state zero and retained
tablet mode, so review7 is not qualified.

Review8 rejects postures outside the valid 1..6 range and performs a bounded
30-second sequence of two-second queries after a KIP connection change,
stopping on the first valid posture. The live module passed five consecutive
traced detach/reattach cycles and one final-candidate cycle with one-finger
motion restored without rebinding. Two clean full builds are byte-identical:
Image SHA-256
`c14a14d353a61693f4306b2cea1704d8af50374d2e8647afd12ac9d1e66fd625`
and normalized module-manifest SHA-256
`64dd759c407e21a2493e835153b1bc3927a6dea3d51b7d5d2f9d4d16e6ee6084`.
The exact-artifact boot checker passed. Five consecutive detach/reattach cycles,
attached lid-triggered s2idle, and detached power-button s2idle restored the
complete tested hardware set without rebinding, input injection, a logind
restart, a failed unit, kernel oops, or call trace.

Review9 adds the focused Qualcomm battery-manager correction. Two independent
builds are byte-identical across Image, `vmlinux`, OLED DTB, config,
`Module.symvers`, generated identities, and all 3,758 in-tree modules. The
Image SHA-256 is
`2027d41c9d34658d44aba3d6497592f470bb0ffe3abc70712f20fd246afe093d`,
the config SHA-256 is
`ce3235cba604521c4b0bc1ce639278e70d612b0e76fa464aee9fd8592f60106c`,
and the normalized module-manifest SHA-256 is
`837037c94f02312080ce9873cb37aef07478b9bd5200d99d5834c9bf06375cbc`.
Its exact-artifact boot checker and complete practical hardware matrix passed,
including attached and detached suspend, lid-triggered suspend, keyboard
reattach, touch, pen, audio, microphones, ambient light, charge-limit service,
and exact 75–80% readback. Review9 was then promoted to the persistent boot
target with review8 preserved as rollback.

Subsequent maintainer daily-use testing repeatedly exercised the Flex Keyboard
both attached and detached without reproducing keyboard, touchpad, or posture
failures.

Review10 adds a single correction to the rear OV13858 sensor driver. Two
independent clean builds from empty directories are byte-identical across
`Image`, `vmlinux`, OLED DTB, config, `Module.symvers`, the generated
`compile.h` and `utsrelease.h`, and all 3,758 in-tree modules. The Image
SHA-256 is
`4020e445a757830c54ea8ad11352e95b88b8eb05f22b5d4cba684277f57f889a`,
the config SHA-256 is unchanged from review9 at
`ce3235cba604521c4b0bc1ce639278e70d612b0e76fa464aee9fd8592f60106c`,
and the normalized module-manifest SHA-256 is
`443c02ead2526f87fde049d86963ff270204e91db7eb45fc8ea184f87d1f7dc1`.
Because the change touches one driver and no configuration, `Module.symvers` is
byte-identical to review9 and the module ABI is unchanged between the releases.

The exact artifact was booted and validated on target hardware. The rear camera
previously failed to start streaming on roughly a third of opens whenever
another camera on the same SoC had run shortly beforehand; a 60-cycle
front/rear soak at zero interval now records **0 capture failures in 60 rear
opens**, against 24 of 60 measured on review9 in a back-to-back control. The
underlying CCI queue timeout still occurs and is still logged — 38 of the 60
opens hit it — but the driver recovers and every session returned its frames.
Cost is about 137 ms on an affected open. The bounded IR bridge was also
exercised on the exact artifact: it started, ran its session, exited cleanly,
and returned the illuminator to zero.

A 27-second s2idle suspend/resume cycle was then performed on the exact
artifact, followed immediately by repeated rapid front/rear switching. All
three internal cameras and the external USB camera still enumerated, 41 CCI
transients were logged and recovered, and no sensor reported a start failure.
The Howdy IR preview produced a live image and matched the enrolled face
through the bounded bridge and the locally built v4l2loopback sink. No kernel
oops, call trace, or failed systemd unit was present, and the illuminator
returned to zero.

Review10's practical hardware coverage is deliberately narrower than review9's:
the camera path, suspend/resume, and the Howdy/IR path were re-verified on the
exact artifact, while touch, pen, audio, microphones, ambient light, and the
charge-limit readback were not re-run. Review10 changes one camera driver and
no configuration, and every module except `ov13858.ko` is byte-identical to
review9, so review9's matrix is expected to carry over — but it was not
re-measured and `validation_status` does not claim it.

## Ambient color sensor validation

Validation opened 2026-07-24:

- [x] Qualcomm SSC service discovery works through QRTR/QMI once hexagonrpcd
  serves the sensor configuration;
- [x] the firmware exposes a Microsoft `surface color sensor` with data type
  `color`, continuous stream mode, and 1 Hz sample rate;
- [x] the standard `ambient_light` endpoint remains static at zero on the
  qualified OLED unit;
- [x] color-report element zero responds as illuminance, moving from roughly
  0.65 lux while covered to 1,438-3,866 lux under a flashlight;
- [x] accelerometer sampling remains valid through the same SSC transport;
- [x] a clean DSP registry bootstrap writes 305 persistent files, including
  the TCS3430 and Surface color records, after adding write, sync, remove,
  rename, extended-method, and large-message support to hexagonrpcd;
- [x] hexagonrpc's clean patched build passes both upstream tests, including
  new write/sync/rename/remove coverage;
- [x] clean pinned hexagonrpc and libssc source trees accept the published
  patches and build successfully;
- [x] installed systemd services run with the private matching
  `libhexagonrpc.so.0.4` and patched `libssc.so.2`;
- [x] the first full host reboot exposed and reproduced a systemd ordering
  race: iio-sensor-proxy exited before `/dev/fastrpc-adsp` appeared, while the
  sensor daemon recovered on its restart policy;
- [x] after adding the FastRPC device dependency and proxy retry policy,
  low-level SSC sampling moved from zero to 1,520 lux under a flashlight;
- [x] iio-sensor-proxy advertised `HasAmbientLight=true`, and
  `monitor-sensor --light` reported live changes from 110 to 5,787 lux;
- [x] a second full host reboot started both services without manual
  intervention, produced raw readings of 0.16-1.26 lux in the dark, and
  reported a desktop-facing peak of 80,089 lux under direct flashlight.

Manual ADSP stop/start testing produced long firmware-client acknowledgement
timeouts and one automatic ADSP recovery. That path is not treated as a valid
cold-boot test because the ADSP is shared with audio and other firmware clients
and its power sequence is not equivalent to a host reboot.

## Bounded target-hardware validation

- [x] review4 boots from a one-shot GRUB entry;
- [x] review4's automatic touch and pen initialization failure is traced to the
  SPI module-alias mismatch, and review5 proves automatic loading after reboot;
- [x] explicit review4 module loading restores the physical touchscreen/stylus
  and iptsd virtual devices;
- [x] review5 automatically restores the complete physical and IPTSD touch/pen
  path, with touch, multitouch, pen hover, strokes, and eraser confirmed;
- [x] review8 preserves correct laptop, detached, and folded-back posture across
  repeated suspend/resume and five consecutive Flex Keyboard detach/reattach
  cycles; folded-back input is suppressed and returns in typing position;
- [x] review9 preserves the complete review8 posture and hardware matrix while
  adding verified charge-limit reliability;
- [x] keyboard, touchpad, volume rocker, audio, and microphones work on the
  tested unit;
- [x] Wi-Fi associates and Bluetooth remains unblocked;
- [x] an imported Windows bond connects the Surface Pro Flex Keyboard over
  Bluetooth while detached when Linux uses the bonded Windows controller
  identity;
- [x] front IMX681, rear OV13858, and IR VD55G0 produce changing frames
  sequentially;
- [x] the IR illuminator produces a measurable scene change and returns to
  zero after bounded capture;
- [x] a local Howdy proof of concept succeeds through a separately built
  v4l2loopback test module;
- [x] the post-test kernel log contains no camera warning, oops, or call trace;
- [x] a lid-triggered suspend with logind's opt-in watchdog override remains in
  genuine suspend-to-idle for more than four minutes and wakes on lid open
  without restarting logind;
- [x] the same override loads persistently after reboot and a second
  lid-triggered cycle again passes the former three-minute failure boundary;
- [x] a short power-button press requests genuine suspend-to-idle rather than
  shutdown or reboot, and a second short press wakes the machine; logind, the
  compositor, one-finger touchpad movement, Wi-Fi, Bluetooth, and iptsd remain
  healthy after resume;
- [x] the Qualcomm charge-control interface stops charging above the requested
  80% end threshold;
- [x] the boot/resume helper applies exact 75–80% readback on target hardware,
  and its fake-sysfs validation covers success and invalid/missing inputs;
- [x] review9 containing the battery-manager reconnect correction completed an
  exact-artifact boot and became the persistent target after the complete
  practical hardware matrix passed;
- [x] one controlled charger protection-domain restart request was attempted,
  but retail firmware rejected it as disabled with QMI error `0x45` /
  `-EOPNOTSUPP` before any state transition; forcing a shared-ADSP failure is
  excluded because audio and sensors depend on it;
- [ ] concurrent cameras, repeated stream cycling, camera suspend/resume, and
  extended endurance remain unqualified;
- [x] the Flex Keyboard controller-identity override survives a fresh boot;
  BlueZ restores the bond and detached keyboard input after login;
- [x] a detached Flex Keyboard reconnects and restores keyboard, mouse, and
  HID interfaces immediately after Bluetooth returns from s2idle;
- [x] the bounded attached/detached non-camera regression matrix passes on the
  tested unit.

Details and exact artifact hashes are in `CAMERA-REVIEW.md`. Howdy itself,
v4l2loopback binaries, biometric data, and captures are not distributed.

## Howdy/IR source review

- [x] generic camera compliance/regression tooling remains outside the focused
  Howdy integration;
- [x] no machine-specific home path, automatic package/AUR install, PAM edit,
  biometric model, image/raw output mode, or capture is present;
- [x] the bridge uses argument-vector subprocess calls rather than shell command
  construction and fails closed on platform, kernel, media graph, sink, LED,
  and brightness-scale mismatches;
- [x] the bridge limits itself to 14 seconds; systemd independently limits the
  service to 15 seconds and runs a separate IR-off helper before and after it;
- [x] hardware-independent Y10P conversion and LED fail-closed tests pass;
- [x] Python/shell syntax, ShellCheck, `reuse lint`, `git diff --check`, and the
  static source-publication audit pass;
- [x] the maintainer selected MIT for the new public integration and the frozen
  legacy files without explicit licenses remain excluded;
- [x] a focused public-tree target-hardware run confirmed the media graph,
  first-frame readiness, exact loopback format, changing frames, bounded
  timeout, normal stop cleanup, forced-kill cleanup, and post-test kernel log;
- [ ] Howdy packaging, model inputs, permissions, and current security posture
  remain unreviewed; PAM integration remains explicitly out of scope.

The 2026-07-19 target run used the exact reviewed kernel and v4l2loopback 0.15.4.
An eight-second direct run delivered 12 loopback frames with 12 distinct frame
hashes without saving frame data. Normal timeout and SIGTERM both returned the
IR brightness to zero. The first hardened `Type=notify` run exposed a readiness
bug: a capability-free child `systemd-notify` process could not notify under
the default `NotifyAccess=main`. The bridge now sends `READY=1` directly from
its main process. A no-light hardened run then reached readiness and exited
normally; a subsequent SIGKILL run recorded main status 9 while `ExecStopPost`
exited 0 and returned brightness from 255 to zero. No residual process,
temporary staging, capture, new camera warning, oops, or call trace remained.

On 2026-07-20, the same bridge with its kernel-release gate retargeted to the
integrated review5 kernel completed two bounded previews using a separately
built review5 v4l2loopback 0.15.4 module. Both reached readiness, returned
brightness to zero, left no bridge/FFmpeg/media-graph process behind, and added
no kernel warning. The maintainer also confirmed the normal visual preview.
Neither the external module nor Howdy is distributed here.

## Three-tier power-profile qualification

The cpufreq companion now maps Power Profiles Daemon `power-saver` and the
kernel `low-power` profile to a qualified 1,920,000 kHz ceiling, maps balanced
profiles to the former 2,515,200 kHz ceiling, and restores the
3,417,600 kHz hardware maximum for performance on the tested unit.

- [x] seven hardware-independent tests cover all profile names, both proposed
  power-saver candidates, supported-frequency rounding, missing frequency
  tables, unknown-profile rejection, preflight without partial writes, and
  restoration;
- [x] all three live SCMI policies apply 1,920,000 kHz for power-saver,
  2,515,200 kHz for balanced, and 3,417,600 kHz for performance;
- [x] stopping the companion restores every policy to hardware maximum and
  starting it reapplies the active profile;
- [x] live profile transitions leave `schedutil` and the 710,400 kHz policy
  minimum unchanged;
- [x] repeated battery-only ABBAAB comparisons selected 1,920,000 over
  1,670,400 kHz: all-core and single-core fixed work completed about 15.5%
  faster while sampled energy per job fell 7.45% and 12.69%, respectively;
- [x] two 90-second idle windows per ceiling differed by 0.96% in sampled
  system power, below the useful precision of the bounded platform-level test;
  mean peak temperature increased only 2.13 C for all-core work and 0.67 C for
  single-core work, and the fan returned to 0 RPM;
- [x] restarting the companion applied 1,920,000 kHz to all policies, and
  restarting Power Profiles Daemon after deliberately applying 1,670,400 kHz
  caused the owner-change handler to restore the selected mapping;
- [x] a real review9 s2idle cycle restored 1,920,000 kHz with `schedutil` and
  the 710,400 kHz minimum unchanged; input, posture, networking, audio, sensor,
  charge-limit, and power-profile health checks passed with no failed unit,
  kernel warning, oops, call trace, panic, lockup, or hung-task match.

## Source-only publication validation

- [x] `reuse lint` passes for the reviewed working tree;
- [x] no prebuilt executable, kernel, module, firmware, initramfs, payload,
  disk image, ISO, biometric model, or private capture is tracked;
- [x] a binary-release guard remains active;
- [x] a fresh single-root repository contains only the allowlisted source tree;
- [x] every object and embedded Git bundle in that fresh repository passes the
  withdrawn-content, privacy, and secret audit;
- [x] a `git archive` from the fresh root passes the path and content audit;
- [x] the GitHub repository is created from that fresh history and has
  no inherited repository network containing the withdrawn history.

## Future binary/ISO validation

- [ ] exact complete corresponding source is staged for every GPL/LGPL binary;
- [ ] all binary/source archives pass absolute-path, traversal, firmware,
  privacy, credential, and diagnostic-log checks;
- [ ] installer syntax, ShellCheck, hash verification, and collision refusal
  pass against the new payload;
- [ ] clean installation and rollback are tested on target hardware;
- [ ] final review is performed from a clean clone of the published source and
  exact binary release candidate.

Open engineering checks do not invalidate publication of clearly labelled
experimental source. They continue to block a prebuilt payload or ISO.
