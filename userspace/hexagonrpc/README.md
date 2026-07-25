<!-- SPDX-License-Identifier: MIT -->

# Surface Pro 11 sensor-DSP support

The tested base is hexagonrpc 0.4.0 at upstream commit
`dd9ac70c026e1bad93e8cffa3801255b8ceb551e`.

On the Surface Pro 11, the ambient color sensor is managed by Qualcomm's
Sensors Subsystem on the ADSP. The DSP cannot read the host filesystem
directly, so `hexagonrpcd` serves its configuration and persistent registry
through reverse FastRPC calls.

The patch adds only the file operations observed during registry bootstrap:

- bounded write and sync;
- remove and atomic rename;
- QAIC extended-method dispatch for `apps_std_frename`;
- a 64 KiB reverse-RPC input buffer for sensor JSON payloads; and
- a writable mapping for the persistent registry.

Mutation is restricted to flat registry records plus
`sns_reg_version`, `parsed_file_list.csv`, and `fstempfile`. Other virtual
paths remain read-only.

```sh
git clone https://github.com/linux-msm/hexagonrpc.git
cd hexagonrpc
git checkout dd9ac70c026e1bad93e8cffa3801255b8ceb551e
git apply /path/to/0001-apps-std-support-writable-sensor-registry.patch
meson setup build --prefix=/usr --buildtype=debugoptimized
meson compile -C build
meson test -C build --print-errorlogs
```

Install the daemon separately as `/usr/local/libexec/sp11-hexagonrpcd` and its
matching `libhexagonrpc.so.0.4` under `/usr/local/lib/sp11/`.
The public repository does not contain Microsoft/Qualcomm sensor
configuration, calibration, firmware, or a generated registry.
