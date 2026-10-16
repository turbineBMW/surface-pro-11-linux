# ISP Phase C: the IPE through the ICP firmware, host programmed

Date: 2026-10-17
Status: **LAB COMPLETE for the noise and colour chain**; next is Windows photo
parity and a snapshot proof of concept. Continues `ISP-PHASE-B.md`; plan in
`ISP-PLAN.md`.

Everything below was measured on the Surface Pro 11 (X1E80100, front camera
imx681) with the Linux camss driver plus a lab-only ICP debug interface
(kernel branch `feat/camss-icp`, debugfs `camss-icp/{cmd,alloc,buf*,fwmem}`).
The lab tree itself (`lab-private/icp-lab`) stays local: it holds the
Windows DLL and tuning binaries, which are proprietary and serve only as an
oracle for register values.

## 1. What runs on the IPE today

A 1920x1080 NV12 frame from the IFE goes through the IPE with the Windows
tuning values for every module Windows uses on this camera:

| Stage | Module | Status | Values from |
|---|---|---|---|
| NPS | ANR 1.0.1 spatial noise reduction, 3 passes (full, DS4, DS16) | works | Chromatix `anr10` region by gain band, through the DLL's NcLib |
| NPS | TF 2.1.1 temporal filter, full + DC4 passes, reference from the previous frame | works | Chromatix `tf21` region by gain band, NcLib |
| NPS | DSX downscaler (DS4 reference output for the next frame) | works | Chromatix `dsx10_ipe_tf_dc4_v2`, NcLib |
| PPS | CST colour space transform, CC colour correction, GLUT gamma, CE chroma enhancement | works | demo numbers (saturation 1.35, S-curve); **not yet the Windows values** |
| PPS | ASF 3.4 sharpening | works | Chromatix `asf34` region, DLL packer |
| PPS | LTM local tone mapping | not started | |

Results (luma high-pass noise, lower is better): raw 2.3 to 3.3; single-pass
ANR 0.33 (wall); three-pass ANR + TF chain 0.24, with the low-frequency
chroma mottle gone. Edge energy is preserved. Frame-to-frame chaining over
16 real frames is stable with no ghost trails.

## 2. Facts a reimplementation needs

Program and buffer plumbing (firmware HFI 2.52, `IpeFrameProcessData`):

- Program arrays are `CDMProgramArray {allocator, numPrograms, CdmProgram[]}`,
  `CdmProgram` = {base | (len-1)<<44, type, uid, hasSingleReg, internal}.
  Frame fields: pre/post LTM at +0x24/+0x28, ANR passes +0x2c..+0x38, TF
  passes +0x3c..+0x48, DSX +0x4c..+0x54. Host PPS register programs are type
  72 (generic REG_CONT); NPS programs are firmware owned: ANR 66, TF 67,
  DSX 68, plus LUT programs 18 (GLUT), 20 (ASF), 23/24 (DSX Y/C LUTs).
  The firmware re-emits NPS registers per stripe as REG_RANDOM pairs, so a
  wrong program is silently dropped rather than rejected.
- Register bases on this chip (Titan 680): PPS CST 0x11068, CE 0x11668,
  ASF 0x11c00 block (DMI cfg 0x11c08), GLUT DMI cfg 0x14e08, CC 0x15768.
  NPS = kona Titan480 + 0x1000: ANR 0x4870.., TF 0x5868/0x59fc, DSX luma
  block 0x8860 (DMI 0x8808), chroma block 0x8a60 (DMI 0x8a08).
- IQ (`IpeIQSettings`) offsets: ANR 0x498 (4 x 0x38), TF 0x578 (4 x 0x198),
  DS4 coefficients 0xbe0 (125/91/144), CST enable 0xc44, CC/GLUT/CE
  0xca4/0xca8/0xcb0, ASF 0xcf0 (asfParameters_680), refinement 0xe20,
  LMC 0xec0, DSX 0xf94 (4 x 0x40). The block at 0x13ec is not ASF and
  stalls the frame.
- The striping output comes from Qualcomm's striping library (in the DLL,
  run natively by `slrun`); it must be recomputed for every IQ change. A
  3-pass stream needs the DS4/DS16 inputs (images 1/2) and allows
  references for the full and DS4 passes only (images 4/5 in, 10/11 out).
  TF on the DC16 pass hangs the IPE; TF on the full pass alone is a no-op
  in 3-pass mode (it waits for DC4 indications).
- PD10 (DS4/DS16 and the DS4 reference): 2x2 block in 64 bits, bytes 0..5 =
  8 MSBs of Y(0,0), Y(1,0), Y(0,1), Y(1,1), Cb, Cr; bits 48..59 = the two
  LSBs of the six samples (sample k at 48+2k); bits 60..63 pad. Stride =
  align(align(ceil(w/2)*8, 192), 256), slice height = align(ceil(h/2), 32).
  Measured from the IPE's own DS4 reference output.
- Tuning regions are gain bands centred on 1.1, 2, 4, 8, 16, 32, 64 (total
  gain = analogue x digital from libcamera metadata).
- ANR 3.4 LUT lanes: activity | softThreshold<<8 | gainNeg<<16 | gainPos<<24.
  The NcLib struct layouts equal kona's prebuilt headers byte for byte
  (`ANR_Chromatix` 0x954, `TF_Chromatix` 0x4e0, `DSX_Chromatix` 0xb0c).

## 3. Plan

**Phase C1, photo parity with Windows.** Replace the demo colour numbers with
the Windows values: CST/CC/GLUT/CE from the Chromatix (`cst12`, `cc13`,
`gamma15`, `ce`) selected by gain and colour temperature; add LTM
(`ltm13`), the one PPS module still off; set the ANR/TF/ASF regions from the
frame's gain each time; compare against a Windows photo of the same scene.

**Phase C2, snapshot proof of concept on this machine.** Precompute, for each
gain band, the register programs, LUT tables, IQ blocks and striping
outputs (seven sets) and store them as data; a small tool then takes a
libcamera frame plus its downscaled copies, picks the band from the
metadata, runs the IPE frame through the lab driver, and writes the photo.
No DLL at run time. Keep the previous frame's references to enable TF for
bursts.

**Phase C3, clean-room rebuild.** With C2 as the answer key, reimplement the
value derivation (the NcLib/ASF/CST maths) and the striping computation,
verifying byte for byte against the stored sets, then move the host side
into the camss driver / libcamera IPA and the inputs onto the IFE's
DS4/DS16 ports.
