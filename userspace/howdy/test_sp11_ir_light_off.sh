#!/bin/sh
# SPDX-FileCopyrightText: 2026 turbinebmw
# SPDX-License-Identifier: MIT

set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd -P)
helper=$repo_root/rootfs/usr/local/libexec/sp11-ir-light-off
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT HUP INT TERM

mkdir "$test_root/ir:flash"
printf '1' >"$test_root/ir:flash/flash_strobe"
printf '255' >"$test_root/ir:flash/brightness"

SP11_LED_ROOT=$test_root "$helper" --require-led
[ "$(cat "$test_root/ir:flash/flash_strobe")" = 0 ]
[ "$(cat "$test_root/ir:flash/brightness")" = 0 ]

mkdir "$test_root/ir:flash-1"
printf '255' >"$test_root/ir:flash-1/brightness"
if SP11_LED_ROOT=$test_root "$helper" --require-led 2>/dev/null; then
	printf 'multiple LEDs unexpectedly passed the reviewed-LED check\n' >&2
	exit 1
fi

rm -rf -- "$test_root/ir:flash" "$test_root/ir:flash-1"
if SP11_LED_ROOT=$test_root "$helper" --require-led 2>/dev/null; then
	printf 'missing LED unexpectedly passed the reviewed-LED check\n' >&2
	exit 1
fi

printf 'sp11-ir-light-off tests passed\n'
