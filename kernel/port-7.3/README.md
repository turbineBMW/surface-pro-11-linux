# Linux 7.3 forward port (the beta kernel since 2026-09-05)

`port/sp11-7.3` is the SP11 patch series carried forward from Linux `v7.1.3`
onto the 7.3 merge window. It has been the maintainer's daily kernel since
2026-08-28 and, from the 2026-09-05 beta on, it is the kernel the live ISO
and the installer ship as `7.2.0-sp11-73beta1`, built reproducibly by
`scripts/build-kernel.sh` (profile `port-7.3`, the default) with the
identities in `BUILDINFO`. The review20 kernel of the 2026-08-28 beta
(`7.1.3-sp11-suspend-review20`, see `../README.md`) stays published as
source and as the `review20` build profile.

Two fixes landed on the branch on 2026-09-05 and are also shipped as
standalone patches in `../` for people carrying their own trees:

- `../sp11-imx681-exposure.patch` (Leon Silcott's correction): the front
  camera's `V4L2_CID_EXPOSURE` wrote a 16-bit register the sensor ignores;
  it now writes the 24-bit latch the mode table initialises. Fixed-gain RAW
  measurements confirmed the old control was inert and the new one responds
  monotonically; photos, video, lighting changes and suspend/resume were
  exercised. Automatic exposure tuning is a separate topic.
- `../sp11-surface-hid-shutdown.patch`: `surface_hid` gains a shutdown
  callback that runs the HID client's suspend routine before the Surface
  Aggregator goes down, so the attached Flex Keyboard touchpad is told to
  stop reporting at poweroff exactly as it is at suspend. On its own this
  does **not** reliably stop the keyboard's haptic clicking after a
  battery-powered poweroff; see `KNOWN-ISSUES.md` (Flex Keyboard).

The `BUILDINFO` configuration also differs from the earlier `73wip2` build in
two debugging-related ways: `CONFIG_EFI_VARS_PSTORE=m` (built in, the
efi-pstore backend registered before the Qualcomm UEFI variable service was
ready and silently never attached, so no panic was ever captured) and the
buddy hard-lockup detector with `BOOTPARAM_HARDLOCKUP_PANIC`, so a hard
lockup panics and lands in pstore instead of looking like a freeze.

## Identity

| | |
| --- | --- |
| Base | mainline `548e7bcd0c5460ddcbca9600cea603ebeebf4da7` (2026-08-28, 7.3 merge window; no `v7.3-rc1` tag existed yet, so the tree self-reports `7.2.0`) |
| Branch | `port/sp11-7.3` |
| Tip commit | `1cd9ebdd1584403e14408de1c559883acf064cc6` |
| Tip tree | `1f776364a949e575bfdc72ad1b8c92a7d7f97b30` |
| Size | 41 commits, 64 files, +9524/-173 against the base |
| Release | `7.2.0-sp11-73beta1` (`scripts/build-kernel.sh --profile port-7.3`; identities in `BUILDINFO`) |
| Previous tips | `a2c103f964eb` (`73wip2`/`73wip3`, 2026-08-29 to 2026-09-05) |

```sh
git clone https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git linux
cd linux
git fetch /path/to/surface-pro-11-linux/kernel/port-7.3/sp11-port-7.3.bundle \
  refs/heads/port/sp11-7.3:refs/heads/port/sp11-7.3
git switch port/sp11-7.3
git rev-parse HEAD^{commit} HEAD^{tree}
```

The bundle is incremental and requires the base commit above. For patch
review, `sp11-port-7.3.patch` is the end-state diff against the same base.

`config` is the complete build configuration. It descends from `../config`
plus `../camera-review.config.fragment` through `olddefconfig` (every new 7.3
symbol took its default), with the pstore and hard-lockup changes above and
`CONFIG_LOCALVERSION=""`; the release name comes from the build helper's
`KERNELRELEASE=`. Build it with

```sh
./scripts/build-kernel.sh --profile port-7.3 --source /path/to/linux \
  --output /path/to/build --jobs "$(nproc)"
```

The helper checks the commit, tree, configuration hash, GCC 16.1.1 and the
Python inputs, then prints the Image, DTB, `.config` and `Module.symvers`
hashes to compare with `BUILDINFO`. This profile is built with GCC rather
than the LLVM toolchain of the review20 profile because every 7.3 build the
maintainer has run since 2026-08-28 was a GCC build; the toolchain is a
declared build input, not an accident.

## What changed against the review20 series

Fourteen of the 53 review20 commits were dropped, each verified by
`git patch-id` against mainline and linux-next rather than by subject:

- Eleven merged upstream for 7.3: the PDC series (version restructuring,
  statics into `struct pdc_desc`, direct-SPI vs GPIO-as-SPI, pass-through
  mode), four PDC cleanups, the pinctrl PDC ack, the x1e80100 bypass revert,
  and `arm64: dts: qcom: x1e80100: Add deepest idle state`.
- `irqchip: qcom-pdc: fix secondary set_type kerneldoc` was fixed upstream
  independently (`d307a7e7d939`).
- Two behaviour-neutral diagnostics (`mailbox: qcom-ipcc` suspend-mask switch,
  `soc: qcom: rpmh` cached-vote trace); upstream's rpmh read-back covers the
  latter.

The three review20 `cpuidle` guards were dropped together with the
`CPUIDLE_FLAG_OFF` block in the SP11 platform commit. `drivers/cpuidle/`,
`include/linux/cpuidle.h` and the kernel-parameters documentation are now
byte-identical to upstream and the `sp11_deep_idle=` parameter no longer
exists: deep idle is simply on, as upstream intends.

Still carried, each confirmed absent upstream: the HID-over-SPI series and
SP11 platform support, the camera series, both `drm/msm/dp` DDC fixes, the
ath12k `disable-rfkill` device-tree property, the qcom_battmgr charge-limit
reliability fix, the three tablet-mode resync patches, the OV13858 SCCB
retry, the smp2p inbound reset, camss X1E C-PHY, and the QCE sleep-vote
change. New on this branch (also shipped as standalone patches in `../`,
where they apply cleanly to the exact review20 tip):

- `platform/surface: aggregator_registry: add KIP OOB pairing node for SP11`
  and `Bluetooth: SMP: implement LE legacy out-of-band pairing`
  (`../sp11-flex-bt-oob-pairing.patch`) -- native Flex Keyboard pairing, see
  `docs/BLUETOOTH.md`.
- `drm/msm/dpu: re-program colour-processing blocks on the commit after a
  modeset` (`../sp11-dpu-gc-lut-after-modeset.patch`) -- the half-screen tint
  after resume.
- `platform/surface: retry KIP cover state while settling` gained the
  `system_wq` -> `system_percpu_wq` rename required by 7.3 (the one-commit
  difference between the `73wip1` and `73wip2` builds).
- `media: imx681: write exposure through the 24-bit latch`
  (`../sp11-imx681-exposure.patch`) and `HID: surface-hid: suspend HID
  clients on shutdown` (`../sp11-surface-hid-shutdown.patch`), 2026-09-05.

## Runtime configuration that goes with it

The review20 rootfs assumed deep idle was dangerous. On this kernel it is the
main power win, so the ISO, the installer and `scripts/install.sh` now:

- pass `cpufreq.default_governor=schedutil` (the config still defaults to
  `performance`) and no longer pass `sp11_deep_idle=1` or
  `qcom_ipcc.mask_summary_on_suspend=1`, which do not exist on this kernel;
- enable `sp11-cpufreq-boost.service` instead of `sp11-noidle.service`. The
  boost unit is gated by `ConditionKernelVersion=*-sp11-73*` and ordered
  before `sp11-power-profile-cpufreq.service` so the per-profile caps are
  computed with the boost frequencies available (the performance profile
  otherwise tops out at 2515200 instead of 3417600 kHz);
- keep `sp11-noidle.service` in `rootfs/` for people still booting the
  review20 kernel, where it is still needed.

The live ISO also offers a "CPU idle states off" entry (`cpuidle.off=1`) as
the conservative fallback.

## Measurements (one unit, on battery, 60 s phases)

Deep idle: PSCI OSI mode and `qcom_pdc: PDC pass-through mode selected
through SCM` at boot. With cpuidle state1 enabled the cluster spends 68--84%
of its time in S1 and idle draw falls from 8.95 W to 5.3--6.6 W, about 3.7 W.
Disabling state1 returns residency to exactly 0 ms (the control). Awake idle
after the governor change is 4.4 W; with the display at 60 Hz and a dark
desktop the maintainer observed 3.4 W.

| | deep idle off | deep idle on |
| --- | --- | --- |
| `performance` governor | 8.99 W (n=2) | 6.02 W (n=3) |
| `schedutil` governor | 6.80 W (n=1) | 5.99 W (n=3) |

Deep idle is the reproducible win; the governor matters only when deep idle
is off. The two mechanisms overlap rather than add.

Suspend: `mem_sleep` is `[deep]`, deep idle unrestricted, no guard. A 48 s
cycle, a 6 h 56 m overnight cycle and, on 2026-08-29, a full day of use with
dozens of suspend/resume cycles were all clean: same boot, no panic, pstore
empty, every device back (Wi-Fi, Bluetooth, NVMe Gen4 x4, touch, iptsd,
governor and boost preserved). The overnight cycle drained 3.715 Wh in
6.94 h, **0.535 W in deep suspend**, roughly 90 h of standby -- against the
1.7--1.8 W review20 documents in `KNOWN-ISSUES.md`.

## Open items

- The review20 wedge was a freeze after 16 h 49 m of extended awake use.
  This kernel has been the maintainer's daily system for over a week of
  awake use and suspend/resume without a freeze, but no multi-day awake soak
  has been recorded as a formal measurement. One hard freeze with automatic
  reboot happened on 2026-09-01 during a package upgrade and left no trace,
  which is what the pstore and hard-lockup configuration changes are for.
- `NOHZ tick-stop error: local softirq work is pending, handler #280` appears
  a few times after boot once state1 is enabled. Not fatal, not explained.
- Non-fatal resume noise: `qcom-pcie 1c08000.pcie: Timeout waiting for L2
  entry! LTSSM: 0x11`, a `spi_hid_of` `Spontaneous FW reset!` that the driver
  recovers from every time, and `hwmon: PM: parent phy0 should not be
  sleeping`.
- The base is a merge-window snapshot, not a tagged `v7.3` release (the tree
  self-reports `7.2.0`). Rebasing onto the `v7.3` tag once it exists is the
  next kernel step; it is not expected to change the carried series.
- The attached Flex Keyboard's haptics can stay on after a battery-powered
  poweroff (AC poweroff and suspend are fine). See `KNOWN-ISSUES.md`.
