# Held installer UI staging

These files stage the GNOME application entry consumed by the corrected held
live-image builder. Planning remains unprivileged and read-only. Mutation is
available only after the planner, two exact confirmations, and the privileged
executor independently validate the held live environment and internal NVMe.

Run `scripts/audit-installer-ui-staging.sh` from the public project to verify
the UI tests and desktop entry.

The live-image audit proves the exact UI, planner, executor, manifest helper,
and installed-system artifact embedded in the image.
