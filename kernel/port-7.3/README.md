# Linux 7.3 forward port (evaluation)

`port/sp11-7.3` is the SP11 patch series carried forward from Linux `v7.1.3`
onto the 7.3 merge window. It is the kernel the maintainer's tablet has run as
its daily system since 2026-08-28. It is published as **evaluation source**:
it is not built by `scripts/build-kernel.sh`, has no `BUILDINFO`, and is not
what the beta ISO ships. The review20 kernel (`7.1.3-sp11-suspend-review20`,
see `../README.md`) remains the reproducible, qualified build.

## Identity

| | |
| --- | --- |
| Base | mainline `548e7bcd0c5460ddcbca9600cea603ebeebf4da7` (2026-08-28, 7.3 merge window; no `v7.3-rc1` tag existed yet, so the tree self-reports `7.2.0`) |
| Branch | `port/sp11-7.3` |
| Tip commit | `a2c103f964eb9cc9a6799b567d81357504a62d3a` |
| Tip tree | `01beb3b15595e9be5dc985f73e03cdd01c0cc9e1` |
| Size | 39 commits, 63 files, +9511/-173 against the base |
| Installed as | `7.2.0-sp11-73wip2` (GRUB entry `sp11-linux-73wip2`) |

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

`config` is the running configuration of the installed `73wip2` build
(`/proc/config.gz`). It was produced from `../config` plus
`../camera-review.config.fragment` through `olddefconfig`, so every new 7.3
symbol took its default, and it carries `CONFIG_LOCALVERSION="-sp11-73wip2"`.

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

## Runtime configuration that goes with it

The review20 rootfs assumes deep idle is dangerous. On this kernel it is the
main power win, so the 7.3 GRUB entry differs from the review20 entry by two
command-line additions and one unit:

```text
systemd.mask=sp11-noidle.service cpufreq.default_governor=schedutil
```

- `sp11-noidle.service` is masked on the command line only; the unit is
  unchanged and stays active for the review20 entry, which still needs it.
- `schedutil` replaces the `performance` default governor.
- `rootfs/etc/systemd/system/sp11-cpufreq-boost.service` enables cpufreq
  boost. It is gated by `ConditionKernelVersion=*-sp11-73wip*` and ordered
  before `sp11-power-profile-cpufreq.service` so the per-profile caps are
  computed with the boost frequencies available (the performance profile
  otherwise tops out at 2515200 instead of 3417600 kHz).

The review20 entry keeps its original command line, `performance` default,
boost off and an unmasked `sp11-noidle.service`.

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
  This kernel has now gone through a full working day awake plus the
  overnight suspend without a freeze, but no multi-day awake soak has been
  recorded yet, so the review20 guard is still documented as the qualified
  configuration.
- `NOHZ tick-stop error: local softirq work is pending, handler #280` appears
  a few times after boot once state1 is enabled. Not fatal, not explained.
- Non-fatal resume noise: `qcom-pcie 1c08000.pcie: Timeout waiting for L2
  entry! LTSSM: 0x11`, a `spi_hid_of` `Spontaneous FW reset!` that the driver
  recovers from every time, and `hwmon: PM: parent phy0 should not be
  sleeping`.
- Not a reproducible build: built through `olddefconfig` rather than
  `scripts/build-kernel.sh`, no `BUILDINFO`, no `Module.symvers`. Promoting
  it means pinning a `v7.3` release, re-running the config merge under the
  build helper, and recording the identities the way `../BUILDINFO` does.
