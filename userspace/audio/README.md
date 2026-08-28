# Surface Pro 11 audio integration

The SP11 AudioReach topology and ALSA UCM routing are project source, not
device firmware. They can be distributed with the project independently of
the external Microsoft/Qualcomm ADSP and CDSP images.

`X1E80100-Microsoft-Surface-Pro-11.m4` is derived from the BSD-3-Clause
AudioReach topology for the Microsoft Surface Pro 12. Build it against exact
upstream commit `d7a5e9d80ad18a7a6844eeb32cacbdeea0e7e677` with:

```sh
scripts/build-audio-topology.sh \
  --audioreach-source /path/to/audioreach-topology \
  --output work/audio-topology-review20
```

The expected binary is
`X1E80100-Microsoft-Surface-Pro-11-tplg.bin`, SHA-256
`89b731f3f98fc2b84699bca39a56e390925a44a26d5aea80382cf617e00c08d8`.

The paired UCM profile is installed from `rootfs/usr/share/alsa/ucm2/`. It
sets a conservative fixed hardware ceiling and leaves ordinary desktop volume
control as software attenuation.
