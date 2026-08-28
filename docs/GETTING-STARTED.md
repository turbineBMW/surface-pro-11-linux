# Getting started: Surface Pro 11 Linux beta

This is a beta for people who are comfortable with a terminal, backups, and
recovering a machine that does not boot. The whole flow is:

1. write the ISO to a USB stick;
2. run one script in Windows to copy the firmware Linux needs onto the stick;
3. boot the stick and try everything;
4. (optional) install alongside Windows or wipe the disk.

Everything below has been done on a Surface Pro 11 OLED / Snapdragon X Elite
(device tree `microsoft,denali`). Other Surface variants are untested.

## 0. Before you start

- **Back up** anything on the tablet you care about.
- You need a USB stick of at least 4 GB (16 GB+ recommended if you want
  to keep logs on it) and a way to plug it in (USB-C).
- Keep a Windows recovery USB or the Surface recovery image handy.
- Disable **Secure Boot**: *Settings → Update & Security → Recovery →
  Advanced startup*, then *UEFI Firmware Settings → Security → Secure Boot →
  None* (or hold Volume-Up while powering on to reach UEFI). The installer
  never touches Microsoft's Secure Boot keys; it only needs Secure Boot off.
- If you want dual boot: in Windows **Disk Management**, shrink `C:` and
  leave at least **33 GiB unallocated**. Do not create or format a partition
  there. Also turn off Fast Startup (*Power Options → Choose what the power
  buttons do*) so Windows does not leave its disk hibernated.

## 1. Write the ISO

Download `sp11-linux-beta-<date>-aarch64.iso` and `SHA256SUMS` from the
release. If the release is split into `*.part-aa`, `*.part-ab`, … join them:

```sh
cat sp11-linux-beta-*-aarch64.iso.part-* > sp11-linux-beta-aarch64.iso
sha256sum -c SHA256SUMS
```

Write it to the **whole** stick (this erases the stick):

- Linux/macOS: `sudo dd if=sp11-linux-beta-aarch64.iso of=/dev/sdX bs=4M status=progress conv=fsync`
- Windows: Rufus in *DD image* mode, or `balenaEtcher`.

The stick now has three partitions. Windows only understands one of them,
**SP11FW** (FAT32). When Windows offers to format the other two, say **no**.

## 2. Copy the firmware (in Windows)

Five Qualcomm/Microsoft firmware files (audio DSP, compute DSP, GPU zap
shader) cannot be shipped with the ISO. They are copied from your own
Windows installation:

1. Boot Windows, plug in the stick, open the **SP11FW** drive.
2. Double-click **`RUN-IN-WINDOWS.cmd`**.
3. It scans `C:\Windows\System32\DriverStore`, picks the newest complete
   driver package for each component, shows what it picked, and writes the
   files plus `SP11-FIRMWARE-MANIFEST.tsv` and a report onto SP11FW.
4. "Safely remove" the stick.

If it fails it writes `SP11-FIRMWARE-COLLECTOR-REPORT.tsv` next to it listing
everything it found; include that file when asking for help. Alternatives
(BitLocker, no Windows, etc.) are in [FIRMWARE.md](FIRMWARE.md).

Without this step the live system still boots, but has **no sound, no
microphones, and no GPU acceleration**.

## 3. Boot the live system

1. Shut Windows down completely.
2. Hold **Volume-Down** and press **Power**; release Volume-Down when the
   Surface logo appears. The tablet boots from USB.
3. In the GRUB menu, take the first entry. GRUB says whether it found your
   firmware on SP11FW. The live root is copied into RAM (a few seconds).
4. GNOME logs in automatically as user `live` (sudo without password).

Try: touch, pen (Rnote is installed), keyboard/touchpad, Wi-Fi, Bluetooth,
speakers, microphones (Sound Recorder), cameras (Snapshot), suspend/resume
(short power-button press), brightness, and rotation.

Useful commands in a terminal (Console):

```sh
sp11-firmware status          # did the firmware get imported? DSP/sound state
bash /run/media/live/SP11FW/sp11-live-firstboot-capture.sh   # save a diagnostics report onto SP11FW
```

The diagnostics report contains device identifiers; review it before
sharing.

## 4. Install (optional)

Open the app grid and start **Install SP11 Linux** (a terminal wizard).

- It lists the internal disk and its partitions, refuses USB/removable
  targets, and offers **dual boot** (uses only the unallocated space you
  made in Windows; keeps Windows, its EFI partition and recovery) or
  **wipe** (erases the whole internal disk, including Windows recovery).
- You must type two exact confirmation phrases; nothing is written before
  the second one.
- It asks for a user name, password, and timezone.
- It formats the new partitions, unpacks a pre-built root filesystem
  (identical package set to the live system), installs your firmware,
  writes GRUB (with a *Windows Boot Manager* entry for dual boot), creates a
  UEFI boot entry, and verifies the result twice.

Then shut down, remove the stick, and boot. GRUB shows *SP11 Linux* and
*Windows Boot Manager*. First boot takes a little longer (machine-id, keys).

If you skipped the firmware step you can add it later on the installed
system, with Windows still on the disk:

```sh
sudo sp11-firmware install --from-windows
```

To remove Linux again, see [UNINSTALL.md](UNINSTALL.md).

## 5. When something goes wrong

- The live system never writes to the internal disk unless you run the
  installer and confirm twice.
- GRUB entry *conservative CPU idle* boots with deeper CPU idle disabled;
  use it if the default entry hangs.
- Collect `sp11-live-firstboot-capture.sh` output (it lands on SP11FW) and
  open an issue at <https://github.com/turbineBMW/surface-pro-11-linux>.
- Read [../KNOWN-ISSUES.md](../KNOWN-ISSUES.md) first; several things (deep
  idle, concurrent cameras, sensors) are known.

## For people with an existing Arch Linux ARM install

If you already run the foundation project's Arch Linux ARM on the tablet,
you do not need the fresh installer: `scripts/install.sh` overlays the
project's kernel, modules, and services onto that system and keeps your
existing boot entries. See [INSTALL.md](INSTALL.md).
