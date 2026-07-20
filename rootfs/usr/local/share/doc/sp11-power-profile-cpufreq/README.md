# SP11 power-profile CPU-frequency companion

The SP11's SAM platform-profile interface changes real firmware state, but the
qualified short-load test did not show a material CPU-frequency difference.
This companion supplies a deliberately modest userspace limit:

- `low-power`: cap all three SCMI cpufreq policies at the supported
  2,515,200 kHz level (about 74% of the qualified 3,417,600 kHz maximum);
- `balanced`, `balanced-performance`, and `performance`: restore each policy's
  `cpuinfo_max_freq`.

The service watches Power Profiles Daemon's standard D-Bus `ActiveProfile`
notification, independently of the desktop client used to select it. A
system-sleep symlink invokes the same program with `post` so the selected limit
is reapplied after resume. One-shot and resume paths read the authoritative
kernel platform-profile value directly.

The unit is enabled through `graphical.target`, matching the packaged Power
Profiles Daemon lifecycle. Enabling it through `multi-user.target` would create
an ordering cycle because the packaged daemon itself starts after that target.

The target is configurable with the service environment variable
`SP11_POWER_SAVER_MAX_KHZ`. If the exact value is unavailable, the program uses
the highest advertised hardware frequency below it. It never changes
`scaling_min_freq` or the governor.

Stop and disable the service to restore full frequency range. The unit's stop
path performs the restoration automatically; it can also be requested with:

```sh
sudo /usr/local/libexec/sp11-power-profile-cpufreq --restore
```
