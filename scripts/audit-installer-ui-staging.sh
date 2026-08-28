#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
project_root=$(cd -- "$script_dir/.." && pwd -P)
ui="$script_dir/sp11-installer-ui.py"
tests="$script_dir/test-installer-ui.py"
staging="$project_root/iso/installer-ui-staging"
desktop="$staging/usr/share/applications/sp11-installer-preview.desktop"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

[[ -x "$ui" ]] || fail "installer preview is missing or not executable"
[[ -x "$tests" ]] || fail "installer preview tests are missing or not executable"
[[ -f "$desktop" ]] || fail "staged desktop entry is missing"

python -m py_compile "$ui" "$tests"
python "$tests"

if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "$desktop"
fi

grep -Fxq \
    'Exec=kgx --wait -- /usr/local/bin/sp11-installer-ui' \
    "$desktop" ||
    fail "desktop entry does not invoke the unprivileged preview exactly"

if grep -Eiq '(^|[[:space:]=])(sudo|pkexec)([[:space:]]|$)' "$desktop"; then
    fail "desktop entry requests privilege"
fi

grep -Fxq 'Name=Install SP11 Linux' "$desktop" ||
    fail "desktop entry is not labeled as the installer"
grep -Fq 'run_executor(' "$ui" || fail "installer UI does not invoke the gated executor"
grep -Fq 'LIVE_EXECUTOR_STATUS = "held-live-internal-only"' "$ui" ||
    fail "installer UI lacks the held internal-only gate"

printf 'PASS: installer UI preserves read-only planning and gated execution\n'
