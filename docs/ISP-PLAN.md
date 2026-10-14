# Hardware ISP plan for the Surface Pro 11 (X1E80100)

Date: 2026-10-13
Status: **IN PROGRESS**. Phase A done 2026-10-13 (`ISP-PHASE-A.md`:
C-PHY on the generic PHY path, three cameras raw). Phase B 2026-10-14
(`ISP-PHASE-B.md`): the IFE pixel path streams BT.601 NV12 from Bayer
with demosaic, white balance, gamma and colour transform programmed by
the driver; verified on the CSI test pattern generator's colour bars,
both real cameras stream through it. Companion to `CAMERA-REVIEW.md`.

Both the Surface Pro 11 (X1E80100, "Hamoa"/"Denali") and the Surface Pro 12
(Intel Panther Lake) run their cameras through libcamera's software ISP. This
document records what the upstream Qualcomm camera stack looks like as of
today, why the X1E is the better of the two machines to get a hardware ISP on,
and what we propose to try. The Intel IPU7 side stays on the software ISP and
is tracked in the SP12 repository.

## 1. Where the SP11 is today

- Kernel `port/sp11-7.3` (7.3 merge-window snapshot of 2026-08-28). CAMSS is
  upstream's, plus our Denali camera device tree (`hamoa.dtsi`,
  `x1-microsoft-denali.dtsi`, `qcom,x1e80100-camss`), the generic 4 nm C-PHY
  values from Qualcomm's GPL `cam_csiphy_2_1_2_hwreg.h`, and the
  Surface-specific C-PHY table transcribed from WinDbg MMIO observations
  (`x1e80100-cphy-observed.h`).
- All three sensors (IMX681 front, OV13858 rear, VD55G0 IR) stream raw Bayer
  through the IFE **RDI** (raw dump) paths. No IFE processing is used.
- Userspace is libcamera's simple pipeline handler with the software ISP and
  our IMX681 sensor helper and tuning (`userspace/libcamera/`).
- Cost: CPU demosaic, no hardware noise reduction, no hardware 3A statistics.

## 2. How the Spectra ISP on the X1E is layered

The X1E80100 camera block is the same generation upstream calls CSID/VFE
"gen3" (the SM8550-era Titan 780 family). It has three layers:

| Layer | What it does | Who programs it | Open source? |
|---|---|---|---|
| **IFE** (inline ISP) | Pedestal, linearization, BPC, ABF bayer denoise, LSC, WB, demosaic, CCM, GTM, gamma, CST, crop/downscale, and the AE/AWB/AF statistics engines. Produces YUV from CSI-2 in one pass. | The host, through CDM command buffers (lists of register writes). **No firmware.** | Register map in Qualcomm's GPL `camera-kernel` tree (`cam_vfe780`, `cam_ife_csid_780`). Upstream camss uses only its RDI paths today. |
| **ICP** (Image Control Processor) running IPE and BPS | IPE: temporal denoise (MCTF/TF), ANR, EIS, ICA warp, LTM, upscaling. BPS: offline stills, MFNR, HDR. | Signed firmware (`CAMERA_ICP`), loaded through the MDT loader and PAS, driven over HFI. | The HFI kernel side is GPL (`cam_icp` in camera-kernel). The firmware is a vendor blob. |
| **camx / Chromatix** userspace | Computes the per-frame, per-stripe IPE/BPS configuration payloads and the IFE register programs from tuning data. | Qualcomm's proprietary Android/Windows userspace, including the closed striping library. | **No.** This is the layer nobody has reproduced. |

The takeaway: the IFE alone gives a complete video-quality pipeline and is
register-driven. The ICP adds temporal denoise but is only useful with the
payloads camx generates. "Wrapping the firmware" means rewriting camx; driving
the IFE means writing a register translator, which is tractable.

## 3. Upstream state (checked 2026-10-13)

**Mainline, v7.3-rc7.** Latest camss commits: RDI streaming fixes and a
host-programmed PIX (processed) output for the Spectra 340 on QCM2290. Nothing
processed for gen3 parts.

**Queued for 7.4** (present in media_stage and linux-next 20261013, absent
from mainline): Bryan O'Donoghue's
[x1e80100 CAMSS dt-bindings and PHY series v12](https://ratatoskr.run/linux-devicetree/2026/07/17227938/t).
CSIPHYs move to the generic PHY framework (`legacy_phy` fallback for other
SoCs), IOMMU stream IDs are trimmed to the five S1 HLOS IDs. The dtsi was
split into a separate series, and the upstream Denali device tree
(`x1e80100-microsoft-denali-oled.dts`) still has no camera node. This is
raw-capture plumbing, not ISP processing, but it is the base our C-PHY work
has to be rebased onto.

**ICP boots on x1e80100, as an RFC.**
[media: qcom: camss: icp: Add HFI/ICP v4l m2m driver for x1e80100 BPS/IPE](https://ratatoskr.run/linux-media/2026/07/17211940/t)
(Bryan O'Donoghue, 2026-07-03, 7 patches, branch
`qcom-laptops-v6.18-rc4-camss-icp-bps-ipe-icp-boots+stats-b4` in his
kernel.org tree). It loads `qcom/x1e80100/CAMERA_ICP.mdt` (7 340 032 bytes),
brings up HFI shared memory and queues, and logs
`Firmware ready! version=0x01000100` followed by a successful ping. BPS and
IPE are V4L2 mem2mem nodes (BPS: Bayer 10-bit in, NV12 out; IPE: NV12 to
NV12); the log ends in an HFI ack mismatch on handle destroy. The author
calls it "a very loose RFC": no YAML, no uAPI documentation, `simple-mfd` as
a temporary device model, and an open question whether it belongs in media or
`drivers/accel`. No userspace exists for it.

**A shared params/stats uAPI exists as a dormant RFC.**
[media: uapi: qcom-camss-stats-params](https://ratatoskr.run/lkml/2026/04/3529562)
(Bryan O'Donoghue, 2026-04-26, zero replies). It defines per-block parameter
entries (demosaic, LSC mesh, CCM, gamma/GLUT, etc., marked "IFE, BPS") and
statistics (AWB Bayer grid, BHIST, BAF with up to 180 ROIs) as V4L2 params
and meta-capture buffers, reusing HFI's data representation. It states that
the IFE "can operate on CSI2 sensor data directly producing YUV", that the
layout is not register-level, and that "CDM program composition is left to
the kernel". That kernel translator for gen3 IFE does not exist.

**Maintainer direction.** In
[March 2026](https://lkml.org/lkml/2026/3/24/1986) Bryan argued that on
ICP-capable platforms the IPE/OPE, BPS and CDM complexity should sit behind
HFI in firmware, with direct register access reserved for Agatti (QCM2290),
which has no ICP. That concerns the offline engines. The IFE is inline and
is covered by the uAPI RFC as host-programmed.

**OPE, the Agatti memory-to-memory ISP.**
[CAMSS Offline Processing Engine support v6](https://ratatoskr.run/linux-arm-msm/2026/09/17524489/t)
(Loic Poulain, 2026-09-07, not yet in media_stage). Bayer to NV12 with
debayer, WB, CCM, gamma, downscale at up to 580 MP/s, with a params node
(`V4L2_META_FMT_QCOM_ISP_PARAMS`) and `camss-isp-common` helpers for buffer
queues, job scheduling and parameter parsing. The X1E has no OPE, but the
helpers and the params format are what an IFE path should reuse.

**libcamera.** Hans de Goede's
[camss pipeline handler v2](https://patchwork.libcamera.org/project/libcamera/list/?q=camss&state=*&archive=both)
(2026-07-21, 7 patches, state New; branch
[`camss_pipeline_v2.1`](https://github.com/jwrdegoede/libcamera/commits/camss_pipeline_v2.1))
adds a camss pipeline handler with OPE support, `camss_params.h`, the
`camss-config.h` uAPI copy, and IPA creation by name. This is the userspace
an IFE path plugs into.

**Nobody has posted an IFE processed path for the X1E**, and no community
port (Thinkpad T14s, Slim 7x, Zenbook A14, Galaxy Tab) has one either; they
all run the software ISP.

## 4. What is missing, in order of value

1. A gen3 **IFE inline YUV path** in camss: full-path output port, bus write
   master configuration for NV12, and a translator from uAPI params to IFE
   register programs. Plus IFE stats as a meta-capture node.
2. A libcamera IPA that consumes those stats and emits those params (AE,
   AWB, LSC interpolation, CCM selection), on top of Hans's handler.
3. The upstream Denali camera device tree, rebased onto the v12 PHY model.
4. Later: the ICP for IPE temporal denoise, on top of Bryan's RFC, once the
   firmware boots on a Surface and the HFI frame-process payload is
   understood.

## 5. Proposal

### Phase A: align with upstream (no new hardware work)

- Rebase the camera branch onto media_stage so it carries the v12 PHY
  series. Our Surface C-PHY observations move under the generic PHY model
  (`phy@` child nodes with their own rails).
- Compare our `hamoa.dtsi` camss node with Bryan's pending dtsi and the ICP
  RFC's `icp@ac01000`, `ipe@ac42000`, `bps@ac2c000` children, so our DT is
  ready for both.
- Mail linux-media (Bryan, Loic, Hans, Vladimir) with the SP11 as a test
  platform, asking whether Linaro has gen3 IFE inline work in flight for
  Hamoa, and which base to build on. Draft in section 7. Do this **before**
  writing the translator so we do not duplicate work.

### Phase B: IFE inline YUV, host-programmed

This is the heroic-but-tractable part. The engineering unknowns are the exact
IFE register programming for a working video pipeline on this silicon, and
the bus write-master setup for the full output port. We get them from two
sources the project already uses:

- **B1. Windows runtime capture with WinDbg (KDNET over USB/Ethernet, as for
  the C-PHY table).** Break in the Qualcomm camera driver at CDM command
  buffer submission while the Windows Camera app starts a 1080p30 stream.
  Record the IFE register writes (offset, value) for stream start and for a
  few steady-state frames, and the IFE output port and bus configuration.
  Stay within the provenance rules in `PROVENANCE.md`: runtime MMIO and
  command-buffer observations transcribed into a bounded table, no copied
  binaries, no decompilation, no disassembly-derived pseudocode.
- **B2. Names and semantics from Qualcomm's GPL `camera-kernel`** headers
  for Titan 780 (`cam_vfe780.h`, `cam_ife_csid_780.h`, bus ver4). Already a
  cited source in `CAMERA-REVIEW.md`. These map the observed offsets to IQ
  modules and give the module enable bits, so the table in B1 becomes
  "which registers, in what order" rather than opaque data.
- **B3. Kernel.** Extend `camss-vfe-gen3` with a full-path output producing
  NV12, a minimal static programming for the first bring-up (demux, WB,
  demosaic, CCM, gamma, CST, downscale; everything else bypassed), then IFE
  stats (AWB BG and BHIST first, BAF later) as a meta-capture node. Shape it
  after the stats-params uAPI RFC and the OPE `camss-isp-common` helpers so
  it is upstreamable rather than a Surface fork.
- **B4. Tuning data is ours, not Windows'.** Gamma from the sRGB curve, LSC
  mesh from our own flat-field measurement (we did this for the SP12 and the
  method transfers), CCM from a ColorChecker shot under our own lights. The
  Windows capture supplies register layout and enable sequencing only.
  Windows LUT contents are Windows-derived payloads and stay out of the tree.
- **B5. libcamera.** Build on Hans's camss pipeline handler: add the IFE
  inline configuration (sensor → CSID → IFE full path → video node) and an
  IPA that runs AE on BHIST, AWB on the Bayer grid, and writes params.
  Reuse our IMX681 helper and tuning.

**Acceptance:** NV12 1080p30 from the front camera with the IFE doing
demosaic, WB, CCM, gamma and downscale, software ISP CPU load gone, AE and
AWB driven by hardware statistics. Rear camera the same. Picture quality at
least matching the current software ISP in daylight.

### Phase C: ICP for temporal denoise (only if B leaves low light noisy)

- Take Bryan's ICP RFC branch. Firmware: the Surface Windows install's camera
  package should carry `CAMERA_ICP` (the names `CAMERA_ICP.elf`/`.mbn` show up
  in our lab notes); confirm in the DriverStore, install it as
  `qcom/x1e80100/CAMERA_ICP.mdt` the way `FIRMWARE.md` handles the ADSP and
  CDSP images (user-supplied, listed in `external-required.tsv`, never
  redistributed). First test: does PAS accept it and does the ICP reach
  "Firmware ready" on Denali.
- If it boots, the IPE node gives NV12 in, NV12 out. The unknown is the HFI
  frame-process payload camx normally generates. Scope it strictly: a single
  fixed TF (temporal filter) configuration captured at runtime, nothing per
  frame. If that needs reproducing camx, stop; the IFE path already delivers
  the main win.

## 6. Risks

- **Maintainer appetite.** HFI-first applies to the offline engines; the
  IFE inline path is in the uAPI RFC. Still, confirm in the Phase A mail.
- **Provenance of register programming.** Offsets and sequencing observed at
  runtime are the same class of fact as the C-PHY table. Table contents
  (gamma, LSC, CCM values) are not, and we generate our own (B4).
- **CDM capture mechanics.** The command buffers live in DMA memory at
  submit time; the breakpoint has to land after composition and before the
  CDM consumes them. Fallback: MMIO trace of the IFE register window during
  stream start, which is slower to read but unambiguous.
- **Bus write-master differences.** The gen3 bus register layout for full
  output ports is not in upstream camss; it comes from the GPL header plus
  the capture. Wrong strides or formats show up as garbage frames, which is
  cheap to diagnose.
- **libcamera churn.** Hans's handler is unmerged and OPE-shaped. Expect to
  carry patches until the IFE model settles upstream.

## 7. First steps

1. **Mail linux-media** (Phase A). Draft:

   > Subject: x1e80100 CAMSS: IFE inline YUV path, test platform offer
   >
   > We maintain Linux support for the Surface Pro 11 (x1e80100, Microsoft
   > Denali) and have all three cameras streaming raw through CAMSS RDI with
   > the software ISP. We would like to work on a gen3 IFE inline processed
   > path (full-path NV12 output plus BG/BHIST stats) shaped after the
   > qcom-camss-stats-params RFC and the OPE camss-isp-common helpers, and
   > plug it into the camss libcamera pipeline handler. Before starting: is
   > there Linaro/Qualcomm work in flight for the gen3 IFE inline path, and
   > which base (media_stage after the v12 PHY series, or the ICP RFC branch)
   > should we build on? We can test on Denali and provide register-level
   > observations from the running hardware.

2. **Windows prep** (B1): confirm KDNET works on the SP11 as it did for the
   C-PHY work, identify the Qualcomm camera driver package in the DriverStore
   and its CDM submission path, and record a 1080p30 front-camera stream
   start.
3. **Linux prep** (B2/B3): rebase onto media_stage, pull the Titan 780 IFE
   and bus headers from the cited GPL tree, and add a debug option to camss
   that logs every IFE register write so Linux and Windows sequences can be
   diffed.
4. **Firmware check** (C): list the SP11 DriverStore camera package and
   record the `CAMERA_ICP` file name, size and hash in the lab notes, not in
   the tree.

## Sources

- [ICP/HFI RFC for x1e80100 BPS/IPE](https://ratatoskr.run/linux-media/2026/07/17211940/t)
- [x1e80100 CAMSS PHY series v12](https://ratatoskr.run/linux-devicetree/2026/07/17227938/t)
- [qcom-camss-stats-params uAPI RFC](https://ratatoskr.run/lkml/2026/04/3529562)
- [OPE series v6](https://ratatoskr.run/linux-arm-msm/2026/09/17524489/t) and [v2 cover letter](https://ratatoskr.run/linux-media/2026/04/3531308/t)
- [Bryan O'Donoghue on HFI vs direct register access](https://lkml.org/lkml/2026/3/24/1986)
- [libcamera camss pipeline handler patches](https://patchwork.libcamera.org/project/libcamera/list/?q=camss&state=*&archive=both), [branch camss_pipeline_v2.1](https://github.com/jwrdegoede/libcamera/commits/camss_pipeline_v2.1)
- [meta-qcom-distro note on the camss pipeline handler](https://github.com/qualcomm-linux/meta-qcom-distro/pull/464)
- [Community CAMSS status snapshot, SM8450](https://github.com/aaronsb/sm-x800-linux/issues/27)
- Qualcomm GPL camera-kernel: https://git.codelinaro.org/clo/la/platform/vendor/opensource/camera-kernel
