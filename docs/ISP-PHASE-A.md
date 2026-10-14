# ISP Phase A: upstream alignment findings

Date: 2026-10-13
Status: **IN PROGRESS**. Companion to `ISP-PLAN.md` section 5, Phase A.

This records what was verified against the actual upstream trees on
2026-10-13, where the plan's assumptions held, where they did not, and the
branch that now carries the alignment work.

## 1. Where the work lives

- Kernel branch: `feat/camss-ife`, worktree
  `kernel/worktrees/camss-ife`, built in `out/build/camss-ife`.
- Base: `sp11/v7.3` (v7.3-rc6 plus the 50 SP11 commits), not
  `port/sp11-7.3` as `ISP-PLAN.md` section 1 says. `sp11/v7.3` is the
  branch with the current camera stack and the v7.3-rc6 fixes.
- Reference checkouts under `upstream/`:
  `camera-kernel` (Qualcomm GPL tree, branch `camera-kernel.lnx.6.0.r7-rel`,
  which carries `cam_vfe680.h`, `cam_vfe780.h`, `cam_vfe_top_ver4.h`,
  `cam_vfe_bus_ver3.h` and the CSID 680/780 headers) and `libcamera-camss` (Hans de Goede's
  `camss_pipeline_v2.1`).
- Remotes added to `kernel/linux.git`: `media_stage`
  (git.linuxtv.org) and `bod` (Bryan O'Donoghue's kernel.org tree, branch
  `icp-b4` = `qcom-laptops-v6.18-rc4-camss-icp-bps-ipe-icp-boots+stats-b4`).

## 2. What media_stage actually carries

`media_stage/master` on 2026-10-13 is `v7.2-16863-gd7e7bca71698`, branched
at v7.3-rc1, so it is *older* than our base for everything outside media.
Rebasing `sp11/v7.3` onto it would lose rc2 to rc6. Instead the camss delta
was cherry-picked onto `sp11/v7.3`: 19 commits, all applied, one dropped.

Picked (in order):

- `fwnode_graph_for_each_endpoint_scoped()` (device property helper the
  camss simplification needs; came through media_stage from another tree);
- camss: fwnode endpoint loop simplification;
- phy core: `phy_get_by_of_node()` and `devm_phy_get_by_of_node()`. The
  first conflicted with v7.3-rc6's locking in `_of_phy_get()`; resolved by
  keeping rc6's mutex placement and calling the new
  `_of_phy_get_with_args()` helper under it;
- camss vfe-17x write master fixes, VFE reset fix, 8775p clock fix;
- camss PM clock support and runtime PM integration, QCM2290 clock rework;
- camss hardware version via media controller;
- x1e80100 binding: iommu entry descriptions (empty on our tree, our
  "correct resources" commit already carried them, skipped), vdd-csiphy
  supplies optional;
- Glymur compatible;
- **`phy: qcom-mipi-csi2: Add a CSI2 MIPI DPHY driver`**, the new generic
  PHY provider (`drivers/phy/qualcomm/phy-qcom-mipi-csi2-*.c`, compatible
  `qcom,x1e80100-csi2-phy`, binding
  `Documentation/devicetree/bindings/phy/qcom,x1e80100-csi2-phy.yaml`);
- camss PHY API support with `legacy_phy` fallback, data-lanes from 1 for
  the new mode, two 8300 resource table drops.

Dropped: `media: v4l2-subdev: Add struct v4l2_subdev_client_info pointer
to pad ops`, a 254-file API change that conflicts with rc6 sensor drivers.
It only touches camss pad-op prototypes; the later camss picks applied
without it. Patches sent upstream will need the new prototype, which is
mechanical.

Result: `drivers/media/platform/qcom/camss/` and `drivers/phy/qualcomm/`
build clean with `W=1` (GCC 16.1.1, the running Omarchy n1x config plus
`CONFIG_PHY_QCOM_MIPI_CSI2=m`). The Denali OLED DTB builds. Our device tree
still describes the PHYs the legacy way, so `camss_detect_legacy_phy()`
selects the existing code path and nothing changes at runtime.

## 3. The finding that changes Phase A: no C-PHY in the PHY API path

The plan assumed our Surface C-PHY observations "move under the generic
PHY model". They cannot yet:

- `phy_qcom_mipi_csi2_set_mode()` rejects anything but
  `PHY_MODE_MIPI_DPHY`.
- `csiphy_stream_on()` in camss computes a D-PHY configuration with
  `phy_mipi_dphy_get_default_config_for_hsclk()` and nothing else.
- `include/linux/phy/phy.h` has no C-PHY mode and no C-PHY configure
  options.
- The binding text says the PHY "supports both C-PHY and D-PHY modes" and
  accepts `bus-type = <MEDIA_BUS_TYPE_CSI2_CPHY>`, so the gap is in the
  drivers, not the DT model.

The front camera (IMX681, one C-PHY trio on CSIPHY2) is the camera the IFE
work targets first. So Phase A gains a concrete upstream deliverable that
is independent of the IFE: **C-PHY support in the generic PHY path**, which
means a `PHY_MODE_MIPI_CPHY` (or submode) in the PHY core, a C-PHY branch
in `csiphy_stream_on()`, and the 3-phase lane programming in the provider
driver. Our bounded observation table in `x1e80100-cphy-observed.h` is the
Surface-specific part; the generic 4 nm values come from the same GPL header
the provider driver already cites.

**Prototype on `feat/camss-ife` (2026-10-13 evening).** Five commits on
top of the alignment work:

- `phy: core: add PHY_MODE_MIPI_CPHY`
- `phy: qcom-mipi-csi2: support C-PHY links on x1e80100`: the endpoint
  parser accepts `bus-type` C-PHY with `data-lanes` naming trios,
  `set_mode()` accepts the new mode, `configure()` reuses the D-PHY option
  block for C-PHY with `lanes` = trios and `hs_clk_rate` = link frequency
  and skips the D-PHY timing validation, and `lanes_enable()` /
  `lanes_disable()` replay the Surface observation tables (reset, toggle,
  common, config; shutdown). The tables are a copy of
  `x1e80100-cphy-observed.h` without the interrupt-clear sequence, since
  the generic driver does not service the PHY interrupt. First trio only.
- `media: qcom: camss: configure C-PHY links through the PHY API`: the
  C-PHY branch in `csiphy_stream_on()`.
- `arm64: dts: qcom: hamoa: add CSI2 PHY nodes`: CSIPHY0/1/2/4 as
  `phy@` nodes with a shared OPP table scaling MMCX and MXC.
- `arm64: dts: qcom: denali: connect the cameras through the CSI2 PHY
  nodes`: all three cameras on the new model, lanes numbered from 1,
  analog rails on the PHY nodes.

**Hardware result, 2026-10-13 20:38, kernel `7.3.0-rc6-camss-ife`.**
Booted first time. `phy-qcom-mipi-csi2` bound `ace4000.phy`,
`ace6000.phy` and `ace8000.phy`; camss came up in PHY API mode with
`msm_csiphy0..2` (no csiphy4, its node stays disabled). libcamera's simple
pipeline captured five distinct frames from each camera with the
`cam` tool: rear OV13858 4224x3136 RAW10 at 30.0 fps, front IMX681
3840x2640 RAW10 at 30.0 fps **over the C-PHY trio through the new PHY
path**, IR VD55G0 in its 320x240 8-bit mode at 58.7 fps. Kernel taint 0.
Run directory: `lab-private/isp-phase-a/run-20261013T203843/`.

One kernel warning, pre-existing upstream and not caused by this work:
UBSAN out-of-bounds in `vfe_buf_done()` at stream stop, where the line
pointer is computed before the "unmapped write master" check. Fixed on
the branch (`media: qcom: camss: vfe: look up the line only after
validating the write master`), to be sent upstream.

The register trace of the three stream starts (356 writes: 282 CSID, 3
CSID wrapper, 71 VFE) shows the VFE writing bus client registers at
0x2600 to 0x2664, which is client 24: the Titan 680 RDI0 index, not the
780 one (23). That settles section 6.

Open points for upstream: whether C-PHY deserves its own configure option
struct instead of borrowing the D-PHY one; the PHY interrupt (the binding
requires it, the driver never requests it); and that the binding example
sizes the first three PHY windows at 4 KiB while the 3-phase common
control block lives 4 KiB into the window, so 8 KiB is needed. The rear
(OV13858, D-PHY) and IR (VD55G0, D-PHY) cameras could move to `phy@` nodes
now; mixing models on one camss instance is not supported, since
`legacy_phy` is a per-device flag derived from the first endpoint.

## 4. Device tree model under the new binding

The media_stage binding puts each PHY in its own node with two ports:

- `phy@ace4000 { compatible = "qcom,x1e80100-csi2-phy"; ... }` with
  clocks `core`, `timer`, `ahb`; power domains `top`, `mmcx`, `mx`;
  `operating-points-v2`; `vdda-0p9-supply`, `vdda-1p2-supply`.
- `port@0`: sensor input, `data-lanes` numbered from 1, `bus-type` 1 or 4.
- `port@1`: output to the camss CSID.
- The camss node's `port@N` endpoints then point at the PHY's `port@1`.
  Detection keys on the remote node being named `phy`.

Bryan's older ICP branch (v6.19-rc4 base) has a different, superseded PHY
node shape (four clocks, `#phy-cells`, `opp-table-names`). Ignore it; the
media_stage binding is the one being merged. The ICP branch's
`icp@ac01000` node, `camera_icp_mem` reserved region and
`qcom,x1e80100-camss` as `simple-mfd` are still the only reference for
Phase C.

## 5. Status of the other upstream pieces

| Piece | Verified state |
|---|---|
| OPE series v6 (Loic Poulain) | Not in media_stage, not in linux-next (`v7.3-rc6-17228`). No `camss-isp-common` or `V4L2_META_FMT_QCOM_ISP_PARAMS` anywhere in a tree yet. Only the mailing list copy exists. |
| stats-params uAPI RFC | Present as the last commit of Bryan's ICP branch (`include/uapi/linux/media/qcom/camss/camss-stats-params.h`, 2022 lines). Defines params for BLS, linearisation, demux, bincorrect, ABF, WB, LSC, demosaic, CCM, CST, GLUT, GTM, UVG, LTM and stats for BG, BHIST, HDR BHIST, IHIST, RS, BAF. |
| ICP RFC | Seven patches on `bod/icp-b4`. DT, ICP/HFI driver, BPS and IPE m2m nodes. |
| libcamera camss handler | `camss_pipeline_v2.1`: 2917 lines, `CamssIsp` virtual base with `CamssIspOpe` and `CamssIspSoft` implementations. An IFE implementation slots in as a third subclass. |

## 6. Which Titan generation the x1e80100 really is, and the Phase B facts

`ISP-PLAN.md` calls the X1E "the SM8550-era Titan 780 family". Upstream
camss disagrees in a way that matters for the code: `vfe_res_x1e80100`
and `csid_res_x1e80100` use `vfe_ops_680` / `csid_ops_680`
(`camss-vfe-680.c`, `camss-csid-680.c`), the SM8450 Titan 680 code, with
`line_num = 4` (three RDI lines plus a PIX line that already appears as
`msm_vfe0_pix` / `/dev/video3` on the running kernel). `camss-vfe-gen3.c`
serves SM8550, SM8650 and SA8775P. The matching GPL header is therefore
`cam_vfe680.h` (also `cam_vfe_lite68x.h`, `cam_ife_csid680.h`), not the
780 one; the two are close but not identical (RDI0 is write master 24 on
680 and 23 on 780, the FULL output MIDs differ, and 680 has `core_cfg_3`).
The runtime `CAMSS HW Version` print will settle it on the first boot of
the new kernel.

From `cam_vfe680.h`, names and offsets only:

- Bus write masters (full IFE): `VIDEO_FULL_Y` = 0, `VIDEO_FULL_C` = 1,
  `VIDEO_DS_4:1` = 2, `VIDEO_DS_16:1` = 3, `DISPLAY_FULL_Y/C` = 4/5,
  `DISPLAY_DS_4:1/16:1` = 6/7, `FD_Y/C` = 8/9, `PIXEL_RAW` = 10,
  `STATS_BE0` = 11, `STATS_BHIST0` = 12, `STATS_TINTLESS_BG` = 13,
  `STATS_AWB_BG` = 14, `STATS_AWB_BFW` = 15, `STATS_BAF` = 16,
  `STATS_BHIST` = 17, `STATS_RS` = 18, `STATS_IHIST` = 19,
  `SPARSE_PD` = 20, `PDAF` = 21/22, `LCR` = 23, `RDI0..2` = 24..26,
  `LTM_STATS` = 27.
- Bus client register block for client n is at `0xC00 + 0x200 + n * 0x100`
  (`cfg` 0xE00 for FULL_Y, 0xF00 for FULL_C; `image_addr` +4,
  `frame_incr` +8, `image_cfg_0/1/2` +0xC/+0x10/+0x14, `packer_cfg`
  +0x18). Bus common: `hw_version` 0xC00, `cgc_ovd` 0xC08,
  `global_irq_cmd` 0xC30, `test_bus_ctrl` 0xCDC. The FULL output is a
  two-WM NV12 pair, max 4096 x 4096.
- Top: `core_cfg_0..3` at 0x24/0x28/0x2C/0x68, `global_reset_cmd` 0x30,
  `diag_config` 0x50, `ipp_violation_status` 0x64, `core_cgc_ovd_0/1`
  0x18/0x1C, `stats_throttle_cfg_0..2` 0x70..0x78, `period_cfg` 0x8C.
- IPP module order (CLC blocks): DEMUX, CHANNEL_GAIN, BPC_PDPC,
  BINCORRECT, COMPDECOMP, LSC, WB_GAIN, GIC, BPC_ABF, BLS, BAYER_GTM,
  BAYER_LTM, LCAC, DEMOSAIC, COLOR_CORRECT, GTM, GLUT, COLOR_TRANSFORM,
  UVG, PREPROCESSOR, CHROMA_UP, SPARSE_PD_EXT, LCR, then the crop and
  downscale chains for FD, DISP and VID outputs, then the stats engines
  (AEC_BE, AEC_BHIST, BHIST, TINTLESS_BG, AWB_BG, BFW, BAF, RS, IHIST).
  The first static program enables DEMUX, WB_GAIN, DEMOSAIC,
  COLOR_CORRECT, GLUT, COLOR_TRANSFORM and the VID downscale chain and
  bypasses the rest.
- The per-module register offsets live in `cam_vfe680.h` too and will be
  transcribed when the first program is written.

## 7. Register trace for the Windows diff

Commit `media: qcom: camss: log CSID and VFE register writes under
dynamic debug` on `feat/camss-ife` routes every CSID and VFE write in the
680 and gen3 files through `csid_reg_write()`, `csid_wrapper_write()` and
`vfe_reg_write()`. The x1e80100 runs the 680 files.
Enable at runtime:

```sh
echo 'func vfe_reg_write +p'  > /sys/kernel/debug/dynamic_debug/control
echo 'func csid_reg_write +p' > /sys/kernel/debug/dynamic_debug/control
echo 'func csid_wrapper_write +p' > /sys/kernel/debug/dynamic_debug/control
```

The CSIPHY writes are not included; that sequence is already the bounded
table in `x1e80100-cphy-observed.h`.

## 8. Windows side, what already exists

- `lab-private/sensor/msi/SurfaceUpdate/qccamisp/qccamisp8380.inf`: the
  ISP driver package. Driver `qccamisp8380.sys`, ACPI id `QCOM0C25`,
  firmware files `CAMERA_ICP_AAAAAA.elf` and `CAMERA_ICP.mbn`. This is the
  driver the B1 breakpoint goes in and the package Phase C's firmware comes
  from. Hash and size still to be recorded in the lab notes.
- `lab-private/windows-trace-20260906/kit/`: the KDNET-over-USB-EEM kit
  (host attach script, kdnet.exe for ARM64, first-command blocks) from the
  Bluetooth shutdown investigation. The transport and host setup transfer
  unchanged; only the breakpoints differ.

## 9. Revised first steps

1. **Mail linux-media.** Revised draft below; it now leads with the C-PHY
   gap, which is a concrete question the maintainers can answer.
2. **C-PHY in the PHY API path** (new): prototyped and proven on
   hardware (section 3). Next is turning it into a series for
   linux-phy and linux-media: a C-PHY configure option struct, trio
   position handling, the PHY interrupt, and the provenance text for the
   observed tables.
3. **Boot test `feat/camss-ife`.** Done, passed, see section 3. Built as `linux-sp11`
   7.3.0.rc6.camss.ife-2 (release `7.3.0-rc6-camss-ife`, the running
   Omarchy n1x config plus `PHY_QCOM_MIPI_CSI2=m`); it installs next to the
   n1x kernel and `pacman -R linux-sp11` removes it again. The
   limine-mkinitcpio hook builds the UKI, but `/etc/kernel/uki.conf`
   hardwires the n1x kernel's DTB, so the UKI was rebuilt with `ukify`
   around the hook's initramfs and command line with the camss-ife DTB
   (`.dtb` 226353 bytes) and registered with
   `limine-entry-tool --add-uki`; recipe in `lab-private/isp-phase-a/uki/`.
   The post-boot check is `lab-private/isp-phase-a/test-camss-ife.sh`:
   PHY API mode detected, raw capture on all three cameras, and a
   register trace of one stream start. This boot carries the new PHY
   model directly; if the C-PHY front camera fails, retest with the DT
   reverted to the legacy description to separate the two changes.
4. **Windows prep** (B1) as in `ISP-PLAN.md`, using the September kit.
5. **IFE full-path bring-up** (B3) once 1 and 3 are done.

### Draft mail

> Subject: x1e80100 CAMSS: C-PHY in the PHY API path, and an IFE inline
> YUV path for Hamoa
>
> We maintain Linux support for the Surface Pro 11 (x1e80100, Microsoft
> Denali). All three cameras stream raw through CAMSS RDI into libcamera's
> software ISP: a Sony IMX681 on one C-PHY trio (CSIPHY2), an OV13858 on
> four D-PHY lanes (CSIPHY1) and an ST VD55G0 on one D-PHY lane (CSIPHY0).
> The C-PHY link runs on a bounded register table transcribed from runtime
> observation of the hardware, on top of the generic 4 nm values from the
> GPL camera-kernel tree.
>
> Two questions before we start on code we would like to send upstream:
>
> 1. The qcom-mipi-csi2 PHY driver and the camss PHY API path in
>    media_stage are D-PHY only (set_mode rejects anything else, and
>    csiphy_stream_on only builds a D-PHY config), while the binding
>    accepts bus-type CPHY. We have a small prototype that adds a
>    PHY_MODE_MIPI_CPHY, a C-PHY branch in csiphy_stream_on and the
>    3-phase lane programming in the provider, reusing the D-PHY configure
>    options with lanes = trios. Is C-PHY in that path planned on your
>    side, and would you want it as its own configure option struct
>    rather than borrowing the D-PHY one?
>
> 2. We would like to work on a gen3 IFE inline processed path: full-path
>    NV12 output plus AWB BG and BHIST stats, shaped after the
>    qcom-camss-stats-params RFC and the OPE camss-isp-common helpers, and
>    plug it into the camss libcamera pipeline handler as an ISP backend
>    next to OPE. Is there Linaro or Qualcomm work in flight for the gen3
>    IFE inline path, and which base should we build on: media_stage after
>    the PHY series, or the ICP branch?
>
> We can test on Denali and provide register-level observations from the
> running hardware.
