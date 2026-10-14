# ISP Phase B: the IFE pixel path, host programmed

Date: 2026-10-13
Status: **IN PROGRESS**. Continues `ISP-PHASE-A.md`; plan in `ISP-PLAN.md`
section 5, Phase B.

## 1. Strategy without the Windows capture

The plan's B1 (WinDbg capture of the Windows driver's CDM command buffers)
provides one thing: the register offsets and enable sequence of the IFE's
image processing modules (the "CLC" blocks: demux, demosaic, colour
correction, gamma, colour space transform, scalers, statistics). Those are
programmed through CDM by Qualcomm's userspace and are the only part of
the pipeline absent from the GPL tree.

Everything around them is in the GPL tree, offset by offset:

- the CSID pixel path (IPP): `cam_ife_csid680.h`, register block at 0x300,
  IRQ set at 0xAC/0xB0/0xB4, RUP/AUP mask 0x10001, buffer done on
  composite group 0;
- the IFE bus FULL output: `cam_vfe680.h` and `cam_vfe_bus_ver3.c`, write
  masters 0 (luma) and 1 (chroma), line based, packer format 3
  (`PLAIN_8_LSB_MSB_10`) for NV12, chroma plane at half height;
- the IFE top register names (`cam_vfe_top_ver4`), though `core_cfg_0..3`
  values are CDM programmed.

Modules that are not enabled bypass. So the pixel path can be brought up
end to end first: CSID IPP → IFE (modules at reset) → FULL NV12 write. The
expected first result is an NV12 frame whose luma plane carries the
unprocessed Bayer mosaic. That proves the plumbing (path enable, reg
update, buffer done, bus addressing, format negotiation) independently of
the module programming, and it produces a register trace of our own
stream start to diff against the Windows one later.

## 2. What was built (commit `media: qcom: camss: x1e80100: run the IFE pixel path to NV12 on the PIX line`)

- `camss-csid-680.c`: for the full CSIDs, source stream 3 (the one linked
  to the VFE PIX line) programs the IPP path instead of RDI3. cfg0 carries
  the decode format (10-bit unpacked for RAW10), DT, VC and DT_ID; cfg1
  enables pixel store and frame timestamps, crop and drop stay off; error
  recovery cfg0 = overflow control; ctrl = resume at frame boundary on
  start. Reg-update for stream 3 uses the IPP RUP/AUP bits, the IPP IRQ
  mask enables RUP done, the ISR clears IPP status and reports buffer done
  on composite group 0 as the PIX line.
- `camss-vfe-680.c`: for the PIX line, write masters 0 and 1 are
  configured line based: `image_cfg_0` = height<<16 | width (chroma half
  height), `image_cfg_2` = stride, packer 3, frame increment, bandwidth
  limiter 0xF, MMU prefetch, one IRQ per frame, enable. The chroma plane
  address is the luma address plus stride × height. VFE IRQs stay masked;
  buffer done comes from the CSID. The top block's version, capability
  and `core_cfg_0..3` registers are logged under dynamic debug at start so
  the reset state is recorded.
- `camss-vfe.c`: the x1e80100 PIX line offers `YUYV8_1_5X8` (NV12) on its
  source pad for 10-bit Bayer input, raw passthrough first; a PIX format
  table with NV12 plus the raw entries replaces the RDI alias.

Lite VFEs and CSIDs keep their RDI-only behaviour.

## 3. Test procedure

`lab-private/isp-phase-a/test-pix-path.sh [front|rear]`: resets the media
graph, links sensor → CSIPHY → CSID0 → `msm_vfe0_pix` → `msm_vfe0_video3`,
sets Bayer formats through the chain and `YUYV8_1_5X8` on the PIX source
pad, captures four NV12 frames with `v4l2-ctl`, prints luma and chroma
statistics and a row sample, and saves the register trace of the stream
start. `install-camss-ife.sh` installs the package and rebuilds the UKI
with the right DTB.

## 4. Outcomes to expect and what each means

| Observation | Meaning | Next |
|---|---|---|
| Frames arrive, luma shows a mosaic pattern | Path works, modules bypass as assumed | Program modules: needs the CDM offsets (B1) |
| Frames arrive, luma constant or zero | Bus works, pixel pipeline not passing data: `core_cfg` input mux or a module default blocks | Probe `core_cfg_0` bits from the ver3 layout (`INPUTMUX_PP` bit 5, `INPUT_PP_FMT` bit 14) before B1 |
| No frames, no buffer done | IPP path not started or IFE not consuming | Read CSID IPP status / format measure registers, VFE `ipp_violation_status` 0x64, bus overflow 0xC68 |
| CSID path errors (fifo overflow, pix/line count) | Decode format or path cfg wrong | Compare IPP cfg against the GPL path cfg again |

## 5. Bring-up log

### 2026-10-13 evening: path starts, pipeline deadlocks inside the IFE

Clock sizing fixed first (two commits): the VFE core clock is paced by the
pixel clock, the CAMNOC AXI clock by bytes, for the PIX line as for RDI.

With the IFE modules at reset, the pixel path starts and stalls on the
first frame:

- CSID IPP: one SOF, one EOF, then `RECOVERY_OVERFLOW` in the IPP status
  (0x00091e00); format measure reports the input; the RX keeps receiving.
- IFE top: pixel-path SOF latched (irq1 bit 0), no EOF, diagnostic frame
  counters 0, no violation; bus: no write, no overflow.
- The 17 top debug words (`cam_vfe680.h` names, I/V/R nibbles) show the
  whole main pipe from `preprocess` through `demux`, `channel_gain`,
  `lsc`, `wb_gain`, `demosaic`, `color_correct`, `gtm`, `glut`,
  `color_xform`, `uvg` holding valid data with no ready downstream, the
  VID luma and chroma scalers ready with no data, and the DISP chroma
  branch (`downscale_mn_C_DISP`, `4to1_C_DS4/DS16_DISP`,
  `R2PD_DS16_C_DISP`) holding data. The uAPI comment for the core config
  says R2PD "enables Y and C merging PD output" for the DS4/DS16 outputs:
  a merger waiting for luma while chroma backs up, a fan-out that needs
  every branch ready, so the pipe deadlocks.

What was tried, each as a runtime poke (no relink), none produced frames:

- Draining the unused outputs with write masters in virtual frame mode
  (clients 2 to 9): no change in any module state. The stall is not at
  the bus.
- Every single bit of `core_cfg_0` (0x24): bit 3 idles the whole pipe
  (input mux away from the CSID), bit 2 routes input through `chroma_up`
  (input format = YUV), bit 0 idles the Bayer front end, bit 8 touches
  `hxv_tap0`, bit 14 moves the chroma stream from the DISP branch to the
  VID branch where it stalls at `R2PD_DS16_C_VID` instead. Bits 27 to 30,
  the R2PD positions of the previous generation, do nothing here.
- `core_cfg_1` (0x28) bits 0 to 15 and `core_cfg_2/3` (0x2c, 0x68) in
  all field combinations: no effect on the pipe (0x1f on 0x28 only idles
  the `bayer_argb` packer).

Conclusion: the R2PD merge control and the branch enables are module
registers outside the 16 KiB `vfe0` window the DT maps, programmed by
Qualcomm's userspace through CDM. Next: dump the whole IFE window at stop
to locate them (`pix_dump_window`), and prepare the B1 capture.

### The IFE image processing module map, from a runtime read of the block

With `pix_dump_window=0xf000` the driver reads the whole IFE0 window (the
DT maps 16 KiB; the block is 60 KiB) at stop and logs every nonzero row.
Above the bus clients the layout is one module every 0x200 bytes from
0x3900, each starting with a version word, three LUT-carrying modules
taking 0x500, and the sequence matches the 64-entry
`vfe680_ipp_mod_desc` list in the GPL header exactly. The version words
corroborate the assignment: the three GTM variants share 0x1003000x, the
three companders share 0x20000000 and identical knee tables, every MN
downscaler reads 0x20030000, every 4:1 downscaler 0x10010001, every crop
block 0x10020000. Module configuration starts at +0x60, where upstream's
TFE crop driver also puts its enable, and only the preprocessor is
enabled at reset. The full table, with the nonzero reset values of each
module, is `lab-private/isp-phase-a/ife680-module-map.md`; it is a
hardware observation of reset state, no vendor source involved.

Landmarks: demux 0x3900, PDPC 0x3d00, compander 0x4100, LSC 0x4300, WB
gain 0x4500 (three unity gains, Q17), BPC/ABF 0x4900, Bayer GTM 0x4d00
(256-entry identity LUT), demosaic 0x5600, colour correction 0x5800, GTM
0x5a00, GLUT 0x5f00, colour transform 0x6100, UVG 0x6300, preprocessor
0x6500, output stage from 0x7600 (FD, DISP, DISP DS4/DS16, VID, VID DSX,
VID DS16 downscaler and crop pairs) to 0xae00, statistics engines 0xb000
to 0xc000.

### 2026-10-13 22:30: first frame through the IFE pixel path

With the module map in hand, the output crops were the key. Each
`CROP_RND_CLAMP` block disabled blocks its branch; enabled with a zero
window it discards; enabled with a window it passes. Register layout per
crop block (same as upstream's TFE crop code): +0x60 config with bits 0
and 9 set, +0x68 line window `first << 16 | last`, +0x6c pixel window.
The pokes that produced the first NV12 frame, all applied through
`pix_pokes` before the write masters start:

- all fourteen output crops (FD, DISP, DISP DS4/DS16, VID, VID DSX, VID
  DS16, luma and chroma) config = 0x201;
- VID luma crop (0x9c00): lines 0..2639, pixels 0..3839;
- VID chroma crop (0x9e00): lines 0..1319, pixels 0..1919, so the chroma
  crop counts chroma sample pairs and lines of the half-height plane.

Result: the CSID delivers the whole frame, the IFE top latches SOF, EOF
and both epochs, both FULL write masters write their planes, composite
group 0 raises buffer done, and `v4l2-ctl` returns a 15 206 400-byte NV12
frame on `/dev/video3`. `lab-private/isp-phase-a/first-ife-frame.nv12`
with PNG previews next to it. Luma sits at the sensor black level (about
64 of 255, a dark scene at default exposure) with a 59..90 spread, chroma
is all zero with UVG disabled; so the IFE passes the raw mosaic through
the disabled modules exactly as section 1 predicted. A brighter capture
and a comparison against an RDI raw frame of the same scene come next.

Open: only one frame per stream. After the first frame the IPP path
reports recovery overflow and raises no further CAMIF SOF while the RX
keeps counting packets. Next: run with the IPP error recovery disabled
(`ipp_err_recovery=0`) and look at the second frame.

### 2026-10-13 23:00: one frame per stream, and why

With the IPP error recovery off (`ipp_err_recovery=0`) the CSID pixel
path no longer halts: 60 frames in, 59 out per 2-second window, no
overflow flag. So the recovery mode halted the path on the first
backpressure; with it off the path keeps delivering and the jam is purely
inside the IFE.

After the first frame the IFE output stage jams in a specific way: every
`CROP_RND_CLAMP` block of a branch that has no enabled write master
holds data with its downstream not ready, including crops windowed
entirely outside the frame. The VID crops, whose write masters are
enabled, are clean, and the luma write master sits with the next buffer
in its address FIFO (`addr_status_3`) waiting for a frame. Reading: an
enabled crop forwards the frame boundary downstream even when it passes
no pixels; a write master that is not enabled absorbs one such boundary
and then blocks; the fan-out upstream then stalls the pipe for frame two.
So every output branch needs a consumer, or a way to switch the branch
off that we have not found: `core_cfg_2/3` fields, `core_cfg_1` and
`core_cfg_0` bits were all re-swept on top of the working crop
configuration (67 runs) and none changed the outcome.

Pitfall found on the way: `module_param` string parameters refuse writes
over 1024 bytes, so the first drain experiments ran with no pokes at all.
The parameters are now fixed buffers.

### 2026-10-13 23:10: continuous NV12 streaming through the IFE

The consumer for the unused branches is the bus itself: with every
output branch terminated by a write master in **virtual frame mode**
(client config bits 0 and 1), sized to the branch's crop window, the
pipeline runs frame after frame. The working recipe, still applied as
pokes before the write masters start:

- all fourteen output crops enabled (config 0x201);
- VID luma crop: lines 0..2639, pixels 0..3839; VID chroma crop: lines
  0..1319, pixels 0..1919;
- every other crop: lines 0..0, pixels 0..15 (luma) or 0..7 (chroma);
- write masters 2 to 9 (VID DS4, VID DS16, DISP Y, DISP C, DISP DS4,
  DISP DS16, FD Y, FD C): image 16 x 1, stride 16, packer 3, frame
  increment 16, drop and IRQ subsample patterns 1 / periods 0, MMU
  prefetch on, client config = enable | virtual frame;
- CSID IPP error recovery cfg0 = 0;
- the same pokes re-applied with a reg-update at every CSID frame start.

Result: `v4l2-ctl --stream-count=4` returns four NV12 frames, the luma
write master walks through all four buffer addresses, CSID counts match
the capture. Real-mode drains writing to a scratch area instead raise
image size violations on the drain clients and stop after one frame.

Not yet checked: whether the per-frame re-apply is needed now that the
branches are terminated, and the picture itself under light (the scene
so far was at the sensor black level, exposure and gain made no
difference, so the camera was most likely covered).

### 2026-10-13 23:20: the recipe is driver code

Commit `media: qcom: camss: x1e80100: program the IFE output stage for
the PIX line` replaces the pokes: `vfe_pix_program_output_stage()` writes
the fourteen crops from the negotiated format and the eight drains, and
the CSID IPP error recovery defaults to off. Without any pokes the PIX
line captures 30 of 30 requested frames at 30.0 fps, and it does so with
the per-frame re-arm disabled, so the module registers persist across
frames and are not consumed by the apply. The frame-start re-arm stays
in the tree as a disabled knob.

Current output: NV12 at the sensor resolution with the raw mosaic in the
luma plane and zero chroma. Everything from here is image quality:
demux, demosaic, colour correction, gamma and colour transform need
their register layouts, which the dump gives the bases for and the
sibling CLC blocks in Loic's OPE driver may give the fields for.

### 2026-10-13 23:40: the OPE driver's block layouts fit the IFE

Loic Poulain's OPE driver (v6, `lab-private/isp-phase-a/upstream-mail/
ope-17524497.diff`) programs the same CLC blocks: its crop block layout
(config +0x60 with enable bits 0 and 9, line window +0x68, pixel window
+0x6c, first in bits 29:16 and last in 13:0) is exactly what this bring-up
found on the IFE, so the OPE field definitions transfer: white balance
(gains at +0x68 per channel, 15 bits), demosaic (config enable plus
dynamic clamp bits 14 and 15, lambda at +0x68, classifier at +0x6c/+0x70),
colour correction (3x3 in 12-bit at +0x68..+0x7c, offsets at +0x80..+0x88,
Q factor at +0x8c), gamma through a DMI LUT, and the RGB-to-YUV
"chroma enhancement" block (luma coefficients at +0x68/+0x6c/+0x70,
chroma coefficient pairs at +0x74..+0x80, Cb/Cr offsets at +0x84/+0x88).

Applied to the IFE with the OPE defaults (BT.601 full range): enabling
the colour transform at 0x6100 turns the black-level mosaic (luma 64)
into luma 16, the weighted sum of a 64-level input, and demosaic at
0x5600 holds it there with a slightly different noise pattern. Both
blocks are live. The chroma plane stays zero where the 128 offsets should
appear, so the chroma side of the transform, or the UV generation block
at 0x6300 that subsamples it to 4:2:0, needs a different enable; being
swept now.

The device tree now maps the whole 60 KiB IFE block for both full IFEs
(commit `arm64: dts: qcom: hamoa: describe the whole IFE register
block`), and the driver uses the base mapping when it covers the modules.

### 2026-10-13 23:50: YUV from the colour bars: demosaic, colour transform, chroma scaler

The CSI test pattern generator (`msm_tpg0`, colour bars and the incrementing
ramp) replaced the covered camera as the signal source, and each module's
register semantics came from captures through the pixel path
(`lab-private/isp-phase-a/sweep-tpg*.sh`, `tpg*.txt`, `uvg*.txt`,
`clamp1.txt`, `vgeo1.txt`).

**Demosaic (0x5600).** Config +0x60 bit 0 enables it; bits 14 and 15 are
the OPE's dynamic clamp enables (no visible effect on the test patterns).
+0x68 lambda (G in bits 7:0, RB in 23:16), +0x6c classifier a_k (bits
31:20), +0x70 w_k (bits 9:0), as in the OPE. Output is 14-bit, the 10-bit
raw times 16 with the low bits filled (white reads 0x3fff). On the ramp
pattern the G interpolated at R sites is off by +-64 (10-bit) in the top and
bottom quarters of the range; it is a tuning question for later.

**Colour transform (0x6100).** Three output groups (Y, Cb, Cr), each
0x18 bytes from +0x68: two 13-bit two's complement Q10 coefficients at
bits 12:0 (G input) and 28:16 (B input), one at +0x4 for R, the output
offset at +0x8 (bits 31:17), the input offset at +0xc (same field,
subtracted before the multiply), and the clamp minimum and maximum at
+0x10/+0x14 (bits 31:18). out = clamp(round((cG*G + cB*B + cR*R) >> 10))
+ offset. The input channel order is G, B, R for all three groups (the
OPE's white balance order). The 8-bit planes take round(out / 16), so the
clamp maximum must be 0xff7: 0xfff rounds to 0x100 and wraps to 0, which
is how the white bar first came out black. The clamps default to 0 at
reset, which is why enabling the module alone gives a black frame, and
the reset "+0x2000" that looked like an input bias was only the ramp
pattern starting at 512 on the sampled row.

BT.601 full range needs 14-bit in to 12-bit out, so the coefficients are
the usual matrix over four: Y = (150 G + 29 B + 77 R) >> 10, Cb = (-85 G +
128 B - 43 R) >> 10 + 2048, Cr = (-107 G - 21 B + 128 R) >> 10 + 2048.
Those are exactly the OPE driver's luma constants (0x96, 0x1d, 0x4d). The
colour bars then read, per bar (white yellow cyan green magenta red blue
black): Y 255 226 179 150 106 77 29 0, Cb 128 0 171 43 213 85 255 128, Cr
128 149 0 21 235 255 107 128.

**Chroma geometry.** With the colour transform on, the chroma plane came
out at full horizontal resolution (the left half of the frame, one Cb/Cr
pair per source pixel) and already vertically subsampled 2:1 (chroma row k
holds source row 2k+1). Enabling the UVG module at 0x6300 silences the
chroma whatever its other registers hold, so it stays off. The VID output
chroma M/N downscaler at 0x9a00 has the OPE's downscaler layout (+0x64
scale enables bits 9/10, +0x68 image size (w-1)<<16|(h-1), +0x6c/+0x74
Q21 phase step with the resolution field in bits 31:30, +0x70/+0x78 phase)
and a horizontal 2:1 there yields proper 4:2:0 NV12 chroma.

All three are now programmed by `vfe_pix_program_iq()` in
camss-vfe-680.c at PIX start, before the poke list.

### 2026-10-14 00:20: the front-end modules are clock gated

Pokes into the demux (0x3900) and white balance (0x4500) blocks never
read back and never changed the picture, while the crops, demosaic and
colour transform took every write. The IFE top has clock gating
overrides at 0x18/0x1c (core) and 0x20 (AHB), the GPL Titan top driver's
core_cgc_ovd_0/1 and ahb_cgc_ovd; with all three written to all ones
(0x18 reads back 0xbeffffff, 0x1c 0x1ff, 0x20 0x1) the demux and white
balance registers accept writes. The modules whose clocks gate when they
are disabled drop AHB writes, so the overrides go on before programming.

### 2026-10-14 00:50: Bayer order, white balance, the driver's own bars

With no pokes at all the module now streams the TPG colour bars as
BT.601 NV12 (bar centres Y 255 227 179 150 106 77 29 0). Commit
`media: qcom: camss: x1e80100: program demosaic, colour transform and
chroma scaler`.

**Bayer order.** The front camera (IMX681) is RGGB, which is what the
IFE assumes at reset; the rear OV13858 is GRBG. No single-bit field in
the demux (0x3900, config, +0x68, +0x6c), the demosaic (+0x60 bits
1..20, +0x64) or the top core config (0x24, 0x28) permutes the bar
colours. Top core_cfg_0 bit 2 switches the input to something else
(the bars come out as a 2-bar luma pattern) and bits 0 and 3 stop the
stream; demux routing words 0xc9/0xac stop it too, so the demux is live
but its encoding is still unknown. The GPL Titan top driver keeps the
pattern (`pix_pattern`) without writing it anywhere, so userspace owns
it through the module configs. Fallback for GRBG/GBRG/BGGR sensors: the
CSID pixel path crop (CFG1 bits 12/13, windows at 0x35c/0x360 as
end << 16 | start) can drop one column and/or line so the stream starts
on an R pixel, at the cost of two pixels of width or height.

**White balance (0x4500).** Needs the clock gating overrides. Gains are
Q10 in bits 31:17: +0x6c is B and +0x70 is R (0x200 halves the channel);
+0x80..+0x88 are the per-channel adds (all ones saturates the frame).
With unity gains the green channel comes out wrong until +0x94 (reset
0xa) is written with all ones; +0x8c and +0x90 do not help. After that
+0x68 is the G gain (0x200 halves the green of every bar) and the B gain
still touches only the blue bars, so +0x94 is not a pixel position map.
Its meaning is still unknown.

**Gamma (0x5f00).** The OPE's DMI sequence works unchanged: DMI bank
+0x58, LUT select +0x0c (1 G, 2 B, 3 R), DMI config +0x08 with the
auto-load bit 20, then 256 data words at +0x10; select 0 afterwards,
module bank +0x5c, enable +0x60. An entry is a 12-bit output value in
bits 11:0 indexed by the top 8 bits of the input (constant 0xfff gives a
full channel, 0x1000 gives zero, i << 4 is the identity). Loading only 64
entries leaves the table dark, so the hardware wants the full 256.

**Driver.** `vfe_pix_program_iq()` now also sets the clock gating
overrides, white balance at unity, a gamma 2.2 table for all three
channels, and subtracts `pix_black_level` (10-bit units, module
parameter, default 0) on the colour transform input, which only moves
luma since the chroma coefficients sum to zero.

### 2026-10-14 01:20: both cameras through the whole path; NV12 size bug

With the full chain in the driver (white balance, demosaic, colour
transform with black level 64, gamma, chroma scaler) the front IMX681
and the rear OV13858 both stream NV12 at their native sizes. Both frames
are a uniform dark grey with neutral chroma, so the lenses are in the
dark; the picture itself waits for light and for the rear camera's GRBG
order (its colours will be wrong until the Bayer order is handled).

The rear capture first came out truncated with SMMU context faults
(iova 0xf92ef300, SID 0x820): `__video_try_fmt()` clamps a line-based
plane to bytesperline x 4096, which for NV12 at 4224x3136 (19869696
bytes) cut the buffer to 17301504, and the chroma write master ran off
its end. Fixed by scaling the clamp with the plane's vertical
subsampling (commit `media: qcom: camss: video: size the image clamp for
packed chroma planes`); the second capture is complete and fault free.

Branch `feat/camss-ife` now carries, on top of the Phase A work:
output stage, IFE register block in the DT, demosaic + colour transform +
chroma scaler, white balance + gamma + black level, and the video size
fix. Package `linux-sp11-7.3.0.rc6.camss.ife-2` (built from this state)
is in `/mnt/data/sp11/out/stage/camss-ife-pkg/`; `install-camss-ife.sh`
installs it and rebuilds the UKI with the camss-ife device tree.

Open: Bayer order for non-RGGB sensors (CSID IPP crop fallback), colour
correction (0x5800), the demosaic +-64 artefact on ramps (a_k/w_k
tuning), the UVG module, stats for AE/AWB, the IR camera's mono path,
and the libcamera backend.

**Demosaic dark-end artefact.** On the ramp, the G interpolated at R
sites reads 64 (10-bit) where the true value is 0, and the error fades
to about 6 at three quarters scale and nothing at mid scale; lambda, a_k
and w_k barely move it (54 to 64). It looks like a pedestal in the
interpolation rather than a tuning problem, and real sensors never reach
0 before black level subtraction (the IMX681's pedestal is 64), so it
should not show on camera frames.

### 2026-10-14 05:55: first real picture

Rebooted into the packaged kernel (7.3.0-rc6-camss-ife, DT with the
full IFE window), lit room. The front IMX681 through the whole pixel
path gives a recognisable photo (ceiling light, walls, the user) with
`pix_black_level=64`, exposure 2600, gain 900 and white balance pokes
(R about 1.3, B about 1.4 for the warm room light; unity gives a green
cast, a grey-world estimate over the frame overshoots green because the
scene is warm). The rear OV13858 shows a magenta field with a fine grid:
its GRBG mosaic read as RGGB, as expected until the Bayer order is
handled. Picture: `lab-private/isp-phase-a/first-ife-picture.png`.

### 2026-10-14 08:10: Bayer order, second pass

The CSID pixel path crop was tried as the order converter. The vertical
crop works (CFG1 bit 13, 0x360 = end << 16 | start, one line at each
end): the TPG bars come out 1920x1078 and permuted as a one-line shift
should, so GBRG sensors get RGGB this way. The horizontal crop (bit 12,
0x35c) accepts a full-width no-op window, but any window starting on an
odd pixel yields per-pixel alternating garbage: the crop runs before the
RAW10 unpack, so a 1-pixel shift breaks the 4-pixel groups. GRBG (the
rear OV13858) and BGGR therefore still need the native field.

The native field is not in the top core configs 0x24/0x28/0x2c/0x68
(bits 0..8 and 24..26), the demux config or its first registers, or the
demosaic config, in any of the swept positions; the Titan 480's CAMIF
pixel_pattern (bits 26:24 of its module config) has no 680 equivalent at
those offsets. The GPL top driver stores the pattern and never writes it.

Found on the way: csid_try_format() handled only pad 1 as a source pad,
so pads 2..4 (the pixel path is pad 4) never got source-side processing;
fixed. And the VFE's PIX crop rounds the width down to a multiple of 16
("wm writes multiple of 16"); the 680 streams 1916 wide fine when that is
relaxed to 4, so the rule is inherited rather than measured, but it is
left in place since nothing needs odd widths yet.

### 2026-10-14 08:10: controls

The PIX line subdev (`msm_vfe0_pix`) now has V4L2 controls: red_balance,
blue_balance and gain (the IFE white balance R, B and G gains, Q10, 1024
unity) and black_level (10-bit units, the colour transform input
offset). Set before streaming they shape the first frame; changed while
streaming they land within a few frames (red_balance 1330 to 3000 moved
the Cr mean from 131 to 150 by the tenth frame). The pix_black_level
module parameter is gone. Commit `media: qcom: camss: vfe: white balance
and black level controls on the PIX line`.

### 2026-10-14 08:15: closed-loop AE and AWB

`lab-private/isp-phase-a/aeawb-loop.sh` runs a capture loop on the front
camera: sensor exposure and analogue gain through the IMX681 controls,
then digital gain and grey-world white balance through the PIX line
controls (the three IFE white balance gains). From exposure 1000 / gain
256 / unity balance it converges in six iterations to the target luma
(110) with neutral linear means; in this room the sensor saturates
(2660 lines, gain 960) and the IFE supplies a further 2.2x. The frame
(`aeawb-20261014T080955/final.nv12.rgb.png`) is a usable picture of the
room. The remaining haze in the blacks is the next thing to look at
(black level at high gain, lens shading).

### 2026-10-14 08:20: the haze was the black level in the wrong place

A raw capture at the loop's final sensor settings (exposure 2660, gain
960) reads p1 59, median 84, p95 148: the room is dim for this sensor, a
pedestal of about 59 under a small signal. Through the pixel path at
unity gain the output matched the raw exactly with black level 0, but
black level 64 took off only 26..45 and more at the bright end: the
colour transform comes after the gamma LUT, so its input offset
subtracts in the gamma domain. The white balance module's subtract
fields (+0x74 G, +0x78 B, +0x7c R, bits 31:20) are the OPE's: 12-bit
units (field 0x100 removes 64 from a 10-bit frame), applied before the
gains and before the LUT. The BLS module at 0x4b00 blanks the frame when
enabled and is left alone. With the black level moved there the loop's
frame spans luma 22..179 instead of 74..139, with the sensor pinned at
its ceiling and the IFE adding 4x.

### 2026-10-14 08:30: live viewfinder

`lab-private/isp-phase-a/viewfinder.py [front|rear] [seconds]` shows the
PIX line's NV12 on screen through GStreamer (v4l2src, tee, waylandsink)
and feeds a 240x164 copy to the same AE/AWB loop at 4 Hz, which steers
the sensor and the PIX line controls on their subdevs while the stream
runs. Twenty seconds: 593 frames, converged within about 40 frames, then
steady. Package linux-sp11-7.3.0.rc6.camss.ife-2 rebuilt from the
current branch and installed again.

### 2026-10-14 08:40: the cold-boot dark start

Reported: after a fresh boot the front camera starts nearly black and
takes 10 to 15 seconds to come up; later opens are fine. Cause: the
IMX681 controls reset to 1x analogue gain and a 1600-line exposure, and
libcamera's software ISP auto gain (`src/ipa/soft/algorithms/agc.cpp`)
steps multiplicatively and damped from whatever the controls hold,
exposure first and gain second, so a room that needs 16x takes a long
climb. The IPA initialises its state from the sensor's current controls,
which persist in the driver until reboot, so only the first run suffers.
Fix in the driver: default to the full frame of exposure (2660 lines)
and 4x gain (code 768), two doublings from either a dim or a bright
room. Commit `media: i2c: imx681: start with a full frame of exposure
and 4x gain`; verified live after reloading the module, reboot to see
the cold start itself.

### 2026-10-14 09:30: ABF probing, and a hard lock

The ABF (0x4900) answers a readback probe with about two dozen live
registers (+0x68 3 bits, +0x6c 1 bit, +0x80/+0x84 31 bits, +0x88 two
7-bit, +0xa0..+0xbc mixed 4/6/7/10/14-bit pairs, +0xc8/+0xcc 12-bit
pairs, +0xd0..+0xe8 wide, +0x1f8 reset 0xf1). Enabling it with every
register saturated, or with its DMI tables (selects 1..3) filled with
0xffff, 0x400, 0x1000 or a ramp, changes the measured noise by nothing
outside the run-to-run spread (temporal 6.9, spatial 6.2 on a static
ceiling region at the loop's settings). Either the module is bypassed
upstream or its enable needs something not yet found.

**The lock, corrected.** It was not the DMI write. The journal of that
boot shows the GPU's management unit timing out at 09:03:26 ("Timeout
waiting for GMU OOB set GPU_SET", then the display recover worker naming
Hyprland), hung-task reports from 09:05 for kworkers, gpu-worker and the
SMMU irq thread waiting on dma fences, and wireplumber unkillable from
09:04 on. The camera captures kept working for another thirteen minutes
(the select-4 load was written at 09:16:46, after all of that) until the
desktop collapsed and the machine was reset. A GPU hang of the kind this
platform has shown before; whether the camera work provoked it is not
established. The DMI select rule stays as caution, not as a finding.

Bad pixel correction (0x3d00) enables cleanly on its reset thresholds;
GIC (0x4700) enables but changes brightness, so its reset values are
not a pass-through.

### 2026-10-14 09:35: low light by frame length

With the ABF parked, the other noise lever is the sensor: the IMX681's
vertical_blanking control (48..62895) extends the frame, and the driver
raises the exposure limit with it. The viewfinder's policy is now:
exposure to the full frame, analogue gain to 4x, then a longer frame (up
to 2x, 15 fps), then the rest of the analogue gain, then IFE digital
gain. In this room it settles at 5368 lines, gain 960, 1.3x digital
instead of 2660 lines, gain 960, 4x digital. Measured on the static
ceiling region at the same brightness: temporal noise 6.88 -> 4.66,
spatial 6.16 -> 4.17 (about a third less), at half the frame rate.

### 2026-10-14 10:00: colour correction, and the overrides scoped

**Colour correction (0x5800)** is the OPE's layout: out_G = a0 G + b0 B
+ c0 R + k0 (and B, R rows), 12-bit two's complement coefficients
(+0x68 a0 | a1 << 16, +0x6c a2, +0x70/+0x74 for B, +0x78/+0x7c for R),
offsets in bits 31:21 of +0x80..+0x88, Q selector at +0x8c (0 = Q7 ..
3 = Q10). On the bars: identity in Q10 and in Q7 leave them unchanged,
k0 = 0x100 turns the black bar dark green, and the permutation G<-B,
B<-R, R<-G gives WMYRCBGK, the predicted order. The driver programs it
as identity (commit `program the colour correction matrix`); a measured
matrix is a chart away.

**Clock gating overrides** are now held only around the module
programming, control updates and pokes, and released for the stream
(commit `hold the clock gating overrides only while programming`).
Bars and live control changes verified unchanged.

### 2026-10-14 10:00: Phase C begins: libcamera on the pixel path

Hans de Goede's camss pipeline handler (`upstream/libcamera-camss`,
2026-03-31) builds here (GCC 16 needs werror off) and lists the three
cameras with its software ISP on this kernel. Its ISP abstraction is
memory-to-memory, so an inline mode was added: `CamssIspInline` owns
`msm_vfe%d_pix` and its video node, the handler queues requests to it
and never streams the RDI, and the AE/AWB loop from the viewfinder runs
in the class on statistics from the NV12 frames (an IPA later).

Three things learned on the way: libcamera's `cam` sees NV12 as two
logical planes; the handler completes a request as soon as metadata is
in, so the buffer must be reported first; and the pixel path only runs
between a CSID and the VFE of the same index (csid0->vfe0, csid1->vfe1;
csid2->vfe1, csid0->vfe1 and csid1->vfe0 deliver nothing although the
media graph offers the links). The enumeration now pairs them and gives
the full VFEs to the Bayer sensors, the lite one to the mono IR camera.

Result: `cam -c 3 -C150` captures 150 frames of 3840x2640 NV12 at 30 fps
from the front camera, the loop converging from the sensor defaults to
the room (5368 lines at 15 fps, gain 960, 1.6x digital, R 2308 B 1835)
within sixty frames. Commit `camss: Add an inline ISP backend on the IFE
pixel path` in the libcamera tree.

### 2026-10-14 10:20: the system uses it

`sp11-omarchy/packages/libcamera-sp11/PKGBUILD` builds libcamera,
libcamera-ipa, libcamera-tools and gst-plugin-libcamera (0.7.2-4.1) from
the camss-ife-inline tree, adapted from Arch's recipe without docs,
tests, qcam and the Python bindings. Installed over the distro 0.7.2-4
(those packages are kept in out/stage/libcamera-distro for a rollback).
After restarting pipewire and wireplumber, the system libcamera reports
the front camera on the inline IFE pixel path, the rear camera stays on
the software path (GRBG), and pipewire lists the `imx681 [libcamera]`
node that Snapshot and browsers use. The inline backend is gated to
RGGB and GBRG sensors.

### 2026-10-14 10:30: Snapshot could not start, so the scaler

With the package installed, Snapshot failed with "Could not open camera
stream": its GStreamer camerabin would not start on a camera whose only
mode was NV12 at 3840x2640 (the software path had offered a ladder of
sizes), while a plain pipewiresrc consumer streamed the node fine. The
fix is the IFE's own scaler. The VID output path has M/N downscalers
for luma (0x9800) and chroma (0x9a00) in the OPE's layout; the driver
now programs them from the PIX line's compose (sink pad) and crop
(source pad) rectangles, which the older VFEs' scaler support already
defined: luma from the sensor frame to the compose size, chroma (full
width, half height in) to half of it, crop windows from the crop
rectangle. 3840x2640 comes out at 1920x1320 through the test script and
at 1280x880 through libcamera with the loop converging. The inline
backend offers NV12 from a sixteenth of the sensor size up to full, in
steps of two. Also fixed: the exposure limit is read together with the
sensor's current frame length, since it follows it.

### 2026-10-14 10:45: why Snapshot still failed, and the fix

pipewiresrc reported "no more input formats": with libcamera's own
debug log routed out of the pipewire daemon, the handler was never
asked to validate the requested size. The pipewire libcamera plugin
encodes a libcamera size *range* as a stepped rectangle choice in every
format entry, and that choice does not intersect a client's fixed size;
the software path works because it offers discrete sizes and so plain
rectangles. The inline backend now offers the sensor size and a ladder
of common sizes (widths a multiple of 16), and keeps the sensor's aspect
by scaling to cover with the compose rectangle and cropping the centre
with the source crop rectangle: 1280x720 is the middle of a 1280x880
scale, not a stretch. Verified through cam; packaged as 0.7.2-4.3.

### 2026-10-14 11:00: the camera that was never asked

The stepped-range fix was right but not the cause. The explicit
requests kept failing, and the handler's log stayed silent, because
wireplumber was linking every client to the *back* camera: the front
node existed in the graph but had no session item, so a target naming
it fell through to the default source. The reason was the control map.
The inline backend registered no controls, the pipewire libcamera
plugin answered the node's PropInfo enumeration with nothing, pipewire
turned the empty answer into an error, and wireplumber aborted the
node's activation. The software path never hit this because its IPA
publishes a handful of controls.

The inline backend now publishes AeEnable, ExposureTime, AnalogueGain,
AwbEnable and ColourGains with ranges from the sensor, and honours them
in the request path: a manual exposure, gain or colour gain takes the
matching loop out, an explicit enable in the same request has the last
word, and every frame's metadata carries the AE/AWB state. With that
the front camera is the default video source and explicit NV12 requests
at 640x480, 1280x720 and 1920x1080 negotiate and stream.

The second capture then crashed wireplumber in CamssFrames::create().
The frame bookkeeping returned each completed frame's params and stats
buffers to its free queues without checking they existed; the inline
path has neither, so every frame pushed a null pointer, the next
session's init() read the non-empty queue as "buffers required", and
the first create() dereferenced it. Only buffers the frame had are
recycled now. Five consecutive captures through pipewire, by name and as
the default source, with no core dump. Packaged as 0.7.2-4.5.

### 2026-10-14 12:30: the picture was monochrome, and the chroma scaler

With Snapshot finally streaming, the picture was black and white. Colour
bars on the screen, reflected in a mirror into the front camera, settled
what the eye could not in a grey bathroom: full colour at the native
3840x2640, grey bars at 1920x1080. The chroma plane of the 1080p frame
was the top-left of an *unscaled* plane: horizontally the chroma scaler
had scaled correctly, vertically it had never engaged, and the crop
took the top of what arrived. Sizes with a ratio below two did not
stream at all, the crop waiting for lines that never came.

The cause was the input size the scaler was told. The chroma reaches
the VID path downscaler as the full 4:4:4 frame, not half-height as the
earlier comment assumed. Told the full width it scaled horizontally;
told half the height it ignored the vertical step. The driver now gives
the chroma scaler the full frame size and twice the luma ratio in both
directions, always enabled (2:1 at the native size), so it produces half
of the compose size as NV12 needs. Bars captured at 3840x2640,
2560x1440, 1920x1440, 1920x1080, 1280x720 and 640x480 all come through
in colour and in register with the luma. The lesson for the sweeps:
measure with a coloured target in frame, not with chroma statistics of
a grey scene.

### 2026-10-14 12:40: no cameras after a reboot

After the reboot Snapshot listed no cameras. wireplumber's libcamera
enumerated the camera subsystem's media device 0.17 s before the front
sensor had bound (camss registers its media device at probe, the
sensors join the graph as they bind), found no sensors, and never
looked again: libcamera does not rescan a media graph for subdevices
that arrive later. Restarting wireplumber brought both cameras back.
The durable answer for now is to bind the camera stack at early boot
(/etc/modules-load.d/sp11-camera.conf: i2c_qcom_cci, phy_qcom_mipi_csi2,
qcom_camss, imx681, ov13858, vd55g0), shipped by omarchy-hw-sp11; the
proper fix is for the camss pipeline handler to re-match when the
graph completes.

The module-load list is only a margin of a second or two on this
machine, so the real fix went into the driver: camss registered its
media device at probe, with the sensors joining the graph as they
bound and the subdevice nodes created only when the notifier
completed. It now registers the media device from the notifier's
complete callback, after the sensor links and the device nodes, so
userspace never sees a half-built graph. Verified with a live module
swap: the graph comes up with all three sensors and wireplumber finds
both cameras unaided.

### 2026-10-14 13:00: the flicker was the exposure loop, not the IR flash

A screen recording of Snapshot showed a 12% brightness swing about
every 0.4 s, seen only with a hand near the lens or the tablet in
front of a mirror. The IR flash LED stayed at zero and facelock only
wakes for the lock screen, so it was not the emitter. It was the AE
loop: it reasoned in sensor gain codes as if they were linear (256
standing in for unity), while the IMX681's gain is 1024 / (1024 -
code), so above the 4x knee a few codes are a large step and the loop
overshot. Colour bars in the mirror reproduced it in the metadata:
gain toggling 4.0 to 4.5 every fourth frame at the long frame. The
loop now works in real multipliers and places its regime boundaries
there; the same scene settles at exactly 4.0x with the exposure steady
to 0.2%. Packaged as 0.7.2-4.6.
