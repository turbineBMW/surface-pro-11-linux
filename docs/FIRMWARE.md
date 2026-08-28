# Firmware: what is needed, where it comes from, how it gets in

## The five files

| Installed path (under `/usr/lib/firmware/`) | Windows source | Used for |
| --- | --- | --- |
| `qcom/x1e80100/microsoft/Denali/qcadsp8380.mbn` | `DriverStore\FileRepository\surfacepro_ext_adsp8380.inf_*\qcadsp8380.mbn` | Audio DSP: speakers, microphones, battery/charger glue, sensors |
| `qcom/x1e80100/microsoft/Denali/adsp_dtb.mbn` | same package, `adsp_dtbs.elf` | ADSP device tree (must come from the same package as the image) |
| `qcom/x1e80100/microsoft/Denali/qccdsp8380.mbn` | `DriverStore\FileRepository\qcnspmcdm_ext_cdsp8380.inf_*` (older Windows: `qcsubsys_ext_cdsp8380.inf_*`) | Compute DSP |
| `qcom/x1e80100/microsoft/Denali/cdsp_dtb.mbn` | same package, `cdsp_dtbs.elf` | CDSP device tree |
| `qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn` | `C:\Windows\System32\qcdxkmsuc8380.mbn` (also in `qcdx8380.inf_*`) | GPU "zap" shader; without it Mesa falls back to software rendering |

Everything else (Wi-Fi, Bluetooth, GPU microcode, QUP firmware, audio
topology, regulatory database) is redistributable and already in the image.
The Wi-Fi board file is extracted from upstream `board-2.bin`; the board
files from the Windows Wi-Fi driver do **not** work with this kernel.

The collectors do not require particular versions or hashes. Windows Update
replaces these packages regularly; the tools pick the **newest complete
driver package** per component (by the INF `DriverVer`, not by file date),
keep image and device tree from the same package, and prefer the copy Windows
actually deploys for the GPU file. Linux then checks each file structurally
(right processor, segments inside the memory the device tree reserves for
it) before using it, and the hardware authenticates the images again when
they load. A file that does not work simply does not start; it cannot damage
the device.

Hashes seen on the maintainer's unit are recorded in the tools as
"known-good" for information only.

## Ways to get the files

### A. From Windows (recommended)

Boot Windows with the live USB plugged in, open the SP11FW drive, run
`RUN-IN-WINDOWS.cmd`. It writes the pack straight onto SP11FW. Both Windows
PowerShell 5.1 and PowerShell 7 work; no admin rights are required.

Manual equivalent:

```powershell
powershell -ExecutionPolicy Bypass -File .\sp11-collect-firmware.ps1 -TargetSP11FW
# or into a folder you copy to SP11FW yourself:
powershell -ExecutionPolicy Bypass -File .\sp11-collect-firmware.ps1 -OutputDirectory D:\SP11-FIRMWARE
```

### B. From Linux, reading the Windows partition

Works from the live USB, from an installed SP11 system (dual boot), or from
any Linux box that can see the tablet's disk. BitLocker-encrypted volumes
cannot be read this way; use A, or disable BitLocker first.

```sh
sudo sp11-firmware collect --to-usb                 # live USB: write onto SP11FW
sudo sp11-firmware install --from-windows           # installed system: install directly
sudo sp11-firmware collect --from-windows /dev/nvme0n1p3 -o ~/SP11-FIRMWARE
```

`sp11-firmware` is `/usr/local/bin/sp11-firmware` on the live and installed
systems and `sp11-firmware.py` on SP11FW / in `scripts/`; it needs only
Python 3.9+.

### C. From a folder

If you already have the files (from an earlier pack, another machine, a
driver `.cab` you extracted yourself), point the tool at the folder:

```sh
sp11-firmware collect --from-dir /path/to/files -o ./SP11-FIRMWARE
```

### D. Downloading Qualcomm reference drivers

The foundation project fetches the same files from the
[WOA-Project Qualcomm reference driver repository](https://github.com/WOA-Project/Qualcomm-Reference-Drivers).
`sp11-firmware collect --download` does the equivalent (needs `cabextract`
and network). This is a convenience, not something the project distributes.

## How the live USB uses the pack

1. GRUB looks for the `SP11FW` partition. If the manifest and all five files
   are there, it passes them to the kernel together with the initramfs
   (`initrd … newc:`), so they are in `/usr/lib/firmware` before any driver
   loads — GPU acceleration and audio are available from the first second.
2. The initramfs validates them. Bad files are removed before drivers load.
3. If GRUB found nothing, the initramfs tries to mount SP11FW itself and
   import the pack (the method that worked in July 2026).
4. If that also failed, `sp11-firmware-import.service` tries once more in
   userspace before the login screen and restarts the DSPs.
5. `/etc/sp11-external-firmware` records what was imported and from where;
   `/etc/sp11-external-firmware-status` is the trail. `sp11-firmware status`
   shows both.

The installer copies the imported files into the new system. On an installed
system, `sudo sp11-firmware install …` replaces the files (keeping the
previous ones as `*.previous`), restarts the ADSP/CDSP so audio comes back
immediately, and GPU acceleration follows at the next login.

## Pack layout

```
SP11-FIRMWARE-MANIFEST.tsv        tab-separated: manifest_version path bytes sha256 component source_package selection candidate_names purpose
SP11-FIRMWARE-REPORT.txt          human-readable: where each file came from
README.txt
usr/lib/firmware/qcom/x1e80100/microsoft/Denali/{adsp_dtb,cdsp_dtb,qcadsp8380,qccdsp8380}.mbn
usr/lib/firmware/qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn
```

`sp11-firmware validate <dir>` checks a pack. Please do not post packs
publicly; they are Microsoft/Qualcomm property.
