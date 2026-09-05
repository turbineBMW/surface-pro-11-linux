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

Every application submits its requested ceiling even if the current readback
already matches. Readback is the kernel's aggregate QoS limit: a positive value
below the request is valid when thermal, boost, or another constraint imposes
a lower ceiling. The helper writes once and polls while the effective ceiling
is still above its request. Kernel thermal constraints remain in force.

Before application it snapshots all effective maxima. A write or verification
failure triggers reverse-order rollback of every attempted policy, including
the failing policy. Rollback continues after an individual failure and reports
any policy it could not restore. Sysfs does not expose the separate user QoS
request, so rollback restores the observed effective ceilings conservatively;
an existing lower constraint may remain as a user cap until the next successful
profile application. This is best-effort rollback, not an atomic kernel update.

Failed startup and service failure cleanup preserve those rollback limits.
Intentional service stops restore the full user-requested range. Install the
updated helper and service unit together: the unit uses `--restore-after-stop`
and systemd's `SERVICE_RESULT` to distinguish normal stops from failures.

Stop and disable the service to restore full frequency range. The unit's stop
path performs the restoration automatically; it can also be requested with:

```sh
sudo /usr/local/libexec/sp11-power-profile-cpufreq --restore
```
