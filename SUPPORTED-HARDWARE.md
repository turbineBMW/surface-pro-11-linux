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

Any future installer must reject a device whose DMI product or live
device-tree compatible string does not match unless the operator supplies an
explicit unsafe override. The beta installer remains held for qualification.

## Not qualified

- Surface Pro 11 LCD variants
- Snapdragon X Plus variants
- 5G/mobile-broadband variants
- Other Surface generations
- Other distributions or boot loaders

Reports from other variants are welcome, but similarity is not support. Never
install the included DTB on a machine with a different hardware description
without first reviewing the device-tree differences.
