# Supported hardware

## Candidate hardware target

The reviewed source was tested on one physical unit:

| Property | Qualified value |
| --- | --- |
| Product | Microsoft Surface Pro, 11th Edition |
| Device tree | `microsoft,denali` |
| Display | OLED |
| SoC | Qualcomm Snapdragon X Elite / X1E80100 |
| Boot environment | UEFI + GRUB |
| Distribution | Arch Linux ARM bootstrap from the base project |
| Hardware-validated kernel | `7.1.3-sp11-suspend-review20` |
| Preserved safe kernel | `7.1.3-sp11-camera-review12` |
| Ambient color sensor | AMS TCS3430 through Qualcomm SSC |

The installer rejects a device whose DMI product or live device-tree
compatible string does not match.

## Not supported

This project supports **only** the Surface Pro 11 OLED with Snapdragon X
Elite. The following are **not supported** — do not flash the image on them
and do not open support issues for them:

- Surface Pro 11 **LCD** variants
- Snapdragon **X Plus** variants
- 5G/mobile-broadband variants
- Surface Laptop 7 and other Surface generations
- Other distributions or boot loaders

They use different device trees, panels, and firmware; the included DTB and
kernel configuration would be wrong for them. Porting to another variant is a
separate development effort, not a configuration change.
