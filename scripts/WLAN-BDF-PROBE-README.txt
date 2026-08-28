SURFACE PRO 11 WINDOWS WLAN BDF PROBE
=====================================

Purpose
-------

This probe determines which Qualcomm WLAN board-data file the current Windows
installation actually opens. It also inventories and hashes every relevant
bdwlan, wlanfw, phy_ucode, and regdb file in the Windows driver store.

The script does not install or replace drivers or firmware. It enables one
Process Monitor boot trace and reads existing files and registry entries.

Instructions
------------

1. Boot Windows with this SP11FW USB connected.
2. Open SP11FW.
3. Double-click RUN-WLAN-BDF-PROBE.cmd and approve the administrator prompt.
4. Wait for "Boot trace armed successfully."
5. Reboot Windows normally. Do not boot Linux yet.
6. Sign in, wait for Wi-Fi to reconnect, and open SP11FW again.
7. Double-click RUN-WLAN-BDF-PROBE.cmd a second time.
8. Wait for "Collection completed successfully."
9. Safely eject SP11FW before returning to Linux.

The first run downloads the current Process Monitor archive directly from:

https://download.sysinternals.com/files/ProcessMonitor.zip

If Windows has no Internet access, download ProcessMonitor.zip from that
official Microsoft Sysinternals URL on another system and put the unchanged
ZIP in the root of SP11FW before the first run.

Output
------

The USB receives directories named:

SP11-WLAN-BDF-ARM-YYYYMMDD-HHMMSS
SP11-WLAN-BDF-RESULT-YYYYMMDD-HHMMSS

Start with RESULT-SUMMARY.txt and procmon-wlan-firmware-access.csv in the
RESULT directory. Candidate board files are copied into BDF-COPIES.

The full Process Monitor PML remains in:

C:\ProgramData\SP11-WLAN-BDF-PROBE

It is intentionally not copied to the 64 MiB SP11FW partition because boot
traces can be large. The result summary records its path, size, and SHA-256.

Privacy
-------

The results remain local. They can include device identifiers, file paths,
computer names, and proprietary firmware copied from this Surface. Review
them before sharing and do not publish the BDF-COPIES directory.
