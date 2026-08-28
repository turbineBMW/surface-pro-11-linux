SP11 READ-ONLY WINDOWS DPP WLAN EXTRACTOR

Run this from the SP11FW USB partition while booted into the Surface's
current Windows installation:

    RUN-DPP-WLAN-BDF-EXTRACT.cmd

Accept the Administrator prompt. The tool creates:

    SP11-DPP-WLAN-BDF-RESULT-YYYYMMDD-HHMMSS

Bring that directory back to Linux. The main file will be:

    WLAN_CLPC.PROVISION.bin

If the payload is an ELF, an identical .elf copy is also created. The tool
also attempts to read the optional WLAN_CTL.PROVISION object.

Compatibility note:

The extracted files are diagnostic evidence, not automatically compatible
Linux firmware. On the tested Surface, both the direct WLAN_CLPC.PROVISION ELF
and its exact payload placed in the previously qualified legacy ELF envelope
timed out in ath12k with -110. Do not rename either result to board.bin or add
its hash to a firmware manifest without a separate cold-boot qualification.

Safety properties:

* Resolves QcSOCPartition.sys and qcwlanhmt8380.sys from their registered
  service ImagePath values (including modern DriverStore locations), then
  verifies the exact SHA256 hashes observed on this Surface before sending
  any request.
* Opens \\.\QcSOCPartitionDevice with no requested file access, falling back
  only to GENERIC_READ. It never requests GENERIC_WRITE.
* Contains and permits only the QcSOCPartition DPP size and read IOCTLs:
    0xECAF32C6  item-size query
    0xECAF32C2  item read
* Enforces a 16 MiB maximum result and validates all returned lengths.
* Does not stop Wi-Fi, change test/factory mode, install a driver, edit the
  registry, or issue a partition/DPP write request.

If either installed driver differs, the tool stops before opening the device
and writes ERROR.txt in the result directory.
