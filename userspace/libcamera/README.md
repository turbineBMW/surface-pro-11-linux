# IMX681 libcamera patch series

> **Source-preview note:** no binary payload is published. The daily-driver
> machine now uses the distribution's
> libcamera 0.7.2-3 packages plus the exact IMX681 tuning file. The bundle and
> patches are retained as the camera-qualified source history and for developers
> working on the remaining metadata/tuning changes.

These three patches apply to upstream libcamera v0.7.1 in order:

1. `0001-libcamera-camera_sensor_properties-Add-IMX681.patch`
   adds the measured 1000 nm unit cell and two-frame sensor-control delays.
2. `0002-libipa-camera_sensor_helper-Add-IMX681.patch`
   adds the Sony reciprocal analogue-gain mapping and measured 10-bit black
   pedestal of 64 (4096 on libcamera's 16-bit scale).
3. `0003-ipa-simple-Add-initial-IMX681-tuning-data.patch`
   adds a conservative simple-IPA tuning file with that measured black level.
   It deliberately leaves CCM calibration for controlled chart measurements.

Apply them for review or rebasing:

```sh
git checkout v0.7.1
git am /path/to/surface-pro-11-linux-camera/libcamera-patches/*.patch
```

The resulting tree must be
`d27c3bd9f4ce87d2cdf87f52ffd9d63bacf744b1`. Use
`libcamera-history/sp11-imx681.bundle` when the original commit IDs are
required.
