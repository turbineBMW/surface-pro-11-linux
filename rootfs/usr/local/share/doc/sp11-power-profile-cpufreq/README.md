# SP11 power-profile CPU-frequency companion

The SP11's SAM platform-profile interface changes real firmware state, but the
qualified short-load test did not show a material CPU-frequency difference.
This companion supplies explicit three-tier userspace limits:

- `low-power` / Power Profiles Daemon `power-saver`: cap all three SCMI cpufreq
  policies at or below 1,920,000 kHz;
- `balanced` and `balanced-performance`: cap them at or below 2,515,200 kHz,
  preserving the former power-saver behavior as the new balanced tier;
- `performance`: restore each policy's `cpuinfo_max_freq` of 3,417,600 kHz on
  the qualified unit.

Repeated battery-only fixed-work tests selected 1,920,000 over 1,670,400 kHz.
It completed both all-core and single-core jobs about 15.5% faster and reduced
sampled energy per job by 7.45% and 12.69%, respectively. Bounded idle power
was effectively tied, thermal increases were small, and the fan returned to
0 RPM. Service restart, Power Profiles Daemon restart, and review9
suspend/resume qualification all restored the selected mapping.

The service watches Power Profiles Daemon's standard D-Bus `ActiveProfile`
notification, independently of the desktop client used to select it. A
system-sleep symlink invokes the same program with `post` so the selected limit
is reapplied after resume. One-shot and resume paths read the authoritative
kernel platform-profile value directly.

The unit is enabled through `graphical.target`, matching the packaged Power
Profiles Daemon lifecycle. Enabling it through `multi-user.target` would create
an ordering cycle because the packaged daemon itself starts after that target.

The targets are configurable with `SP11_POWER_SAVER_MAX_KHZ` and
`SP11_BALANCED_MAX_KHZ`. If an exact value is unavailable, the program uses the
highest advertised hardware frequency below it. It validates every policy
before changing any of them and rejects unknown profile names. It never changes
`scaling_min_freq` or the governor.

Stop and disable the service to restore full frequency range. The unit's stop
path performs the restoration automatically; it can also be requested with:

```sh
sudo /usr/local/libexec/sp11-power-profile-cpufreq --restore
```
