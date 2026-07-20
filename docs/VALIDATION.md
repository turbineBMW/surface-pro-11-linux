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
- [x] both cumulative patches apply cleanly to their declared prerequisites;
- [x] bundle and patch reconstructions produce identical final trees;
- [x] changed-path, keyword, SPDX, and whitespace audits pass;
- [x] a clean LLVM/Clang `Image modules dtbs` build completes;
- [x] generated Image, OLED DTB, config, and module ABI identities are
  recorded.

## Bounded target-hardware validation

- [x] review4 boots from a one-shot GRUB entry;
- [x] touch, multitouch, pen hover/strokes, eraser, keyboard, touchpad, volume
  rocker, audio, and microphones work on the tested unit;
- [x] Wi-Fi associates and Bluetooth remains unblocked;
- [x] front IMX681, rear OV13858, and IR VD55G0 produce changing frames
  sequentially;
- [x] the IR illuminator produces a measurable scene change and returns to
  zero after bounded capture;
- [x] a local Howdy proof of concept succeeds through a separately built
  v4l2loopback test module;
- [x] the post-test kernel log contains no camera warning, oops, or call trace;
- [ ] concurrent cameras, repeated stream cycling, camera suspend/resume, and
  extended endurance remain unqualified;
- [ ] the broader non-camera regression matrix remains incomplete.

Details and exact artifact hashes are in `CAMERA-REVIEW.md`. Howdy tools,
v4l2loopback binaries, biometric data, and captures are not distributed.

## Howdy/IR feature-branch source review

- [x] generic camera compliance/regression tooling remains outside the focused
  `feature/howdy-ir-review` branch;
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
- [ ] Howdy packaging, model inputs, permissions, current security posture, and
  PAM integration have been reviewed; PAM remains explicitly out of scope for
  this branch.

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
