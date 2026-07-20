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
| Kernel candidate | `7.1.3-sp11-camera-review4` |

Any future installer must reject a device whose DMI product or live
device-tree compatible string does not match unless the operator supplies an
explicit unsafe override. No installer is published in the source preview.

## Not qualified

- Surface Pro 11 LCD variants
- Snapdragon X Plus variants
- 5G/mobile-broadband variants
- Other Surface generations
- Other distributions or boot loaders

Reports from other variants are welcome, but similarity is not support. Never
install the included DTB on a machine with a different hardware description
without first reviewing the device-tree differences.
