<!-- SPDX-License-Identifier: MIT -->

# Ambient color sensor

## Architecture

The OLED Surface Pro 11 contains an AMS TCS3430 tristimulus color and ambient
light sensor. It is not attached to the Surface Aggregator HID endpoint and it
does not appear as a direct Linux I2C/IIO device.

The sensor is owned by Qualcomm's Sensors Subsystem on the ADSP:

```text
TCS3430 -> Qualcomm SSC firmware -> QRTR/QMI -> libssc
        -> iio-sensor-proxy -> desktop brightness control
```

`hexagonrpcd` supplies the sensor DSP with its configuration and writable
registry over reverse FastRPC. The standard SSC `ambient_light` endpoint is
present on the tested machine but returns zero. Microsoft firmware publishes
the usable measurement as a composite `color` sensor named
`surface color sensor`; element zero of that report is illuminance in lux.

No kernel patch is required for this path. The existing kernel already boots
the ADSP, exposes `/dev/fastrpc-adsp`, and carries the QRTR transport.

## External private input

The Microsoft/Qualcomm sensor configuration is an external prerequisite. It is
not licensed or redistributed by this repository.

On the qualified machine, the required configuration was prepared from the
official Surface Pro 11 driver pack obtained from Microsoft's
[Surface driver and firmware download](https://www.microsoft.com/en-us/download/details.aspx?id=106119).
The active OLED/CRD configuration directory in that package is
`SurfaceUpdate/prosnscfgcrd`.

Keep extracted packages, JSON/protobuf configuration, calibration blobs, and
generated registry files outside the public repository. A prepared local root
has this shape:

```text
ROOT/
  sensors/
    config/                 # external sensor configuration
    sns_reg.conf            # registry-generator path configuration
    persist/
      registry/             # generated, initially empty or preserved
  socinfo/
    hw_platform             # CRD on the qualified unit
    platform_subtype
    platform_subtype_id
    platform_version
    revision
    soc_id
```

An empty `color_calibration.bin` must not be installed. If no valid calibration
record exists, leave the file absent and allow the sensor service to create it.

## Build

Build the pinned hexagonrpc and libssc trees using the instructions in:

- `userspace/hexagonrpc/README.md`
- `userspace/libssc/README.md`

The hexagonrpc test suite must pass before installation. libssc's mocked tests
also require its optional QRTR test library; the target-hardware check below
tests the actual SSC service.

## Developer installation

Run the sensor-only helper once without `--apply`:

```sh
sudo scripts/install-sensors.sh \
  --hexagonrpcd /path/to/hexagonrpc/build/hexagonrpcd/hexagonrpcd \
  --libhexagonrpc /path/to/hexagonrpc/build/libhexagonrpc/libhexagonrpc.so.0.4 \
  --libssc /path/to/libssc/build/src/libssc.so.2 \
  --sensor-root /path/to/private/prepared/root
```

After reviewing the resolved paths, repeat with `--apply`. The helper:

- installs separate binaries under `/usr/local`, without overwriting packaged
  libssc;
- copies the operator-supplied private sensor root to
  `/var/lib/sp11-sensors/root`;
- starts `sp11-sensors.service`;
- makes only the persistent registry writable to the daemon; and
- points iio-sensor-proxy at the private patched library; and
- unmasks `iio-sensor-proxy.service` if the host had it masked (a masked unit
  is the one failure mode where `sp11-sensors.service` is healthy and nothing
  ever consumes the sensor).

The helper records replaced files under
`/var/lib/sp11-sensor-install/backups/`. A full host reboot is required for the
final cold-path test.

## Validation

After reboot:

```sh
systemctl --no-pager --full status sp11-sensors.service
systemctl --no-pager --full status iio-sensor-proxy.service
busctl get-property net.hadess.SensorProxy \
  /net/hadess/SensorProxy net.hadess.SensorProxy HasAmbientLight
busctl get-property net.hadess.SensorProxy \
  /net/hadess/SensorProxy net.hadess.SensorProxy LightLevel
LD_LIBRARY_PATH=/usr/local/lib/sp11 /usr/bin/ssccli \
  --sensor light --timeout 15
```

Cover the top/front sensor area, then expose it to a flashlight. Lux should
change by orders of magnitude. A static zero does not qualify the setup.

Do not repeatedly stop/start the ADSP remote processor as a substitute for a
host reboot. Other firmware clients share that processor, and peripheral
power state after a manual DSP restart is not equivalent to a cold boot.
