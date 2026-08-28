#!/bin/bash

set -euo pipefail

expected_source_commit="d7a5e9d80ad18a7a6844eeb32cacbdeea0e7e677"
expected_conf="df8455f922a254d762b4ebe04dfa9f492f918074e960f1454db0cadfcb18a000"
expected_binary="89b731f3f98fc2b84699bca39a56e390925a44a26d5aea80382cf617e00c08d8"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
input="$repo_root/userspace/audio/X1E80100-Microsoft-Surface-Pro-11.m4"
source_dir=""
output_dir=""

usage() {
	cat <<EOF
Usage: $0 --audioreach-source DIRECTORY --output NEW-DIRECTORY

Build the redistributable SP11 AudioReach topology from the exact pinned
BSD-3-Clause upstream source. Nothing is installed on the host.
EOF
}

while (($#)); do
	case "$1" in
	--audioreach-source)
		source_dir="$2"
		shift 2
		;;
	--output)
		output_dir="$2"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		usage >&2
		exit 2
		;;
	esac
done

[[ -n "$source_dir" && -n "$output_dir" ]] || {
	usage >&2
	exit 2
}
source_dir="$(realpath -e -- "$source_dir")"
output_dir="$(realpath -m -- "$output_dir")"
[[ ! -e "$output_dir" ]] || {
	printf 'Refusing to replace existing output: %s\n' "$output_dir" >&2
	exit 1
}
for command_name in alsatplg git m4 realpath sha256sum; do
	command -v "$command_name" >/dev/null || {
		printf 'Missing required command: %s\n' "$command_name" >&2
		exit 1
	}
done
[[ "$(git -C "$source_dir" rev-parse HEAD)" == "$expected_source_commit" ]] || {
	printf 'Unexpected AudioReach source commit.\n' >&2
	exit 1
}
[[ -z "$(git -C "$source_dir" status --short)" ]] || {
	printf 'AudioReach source worktree is not clean.\n' >&2
	exit 1
}

mkdir -p -- "$output_dir"
conf="$output_dir/X1E80100-Microsoft-Surface-Pro-11.conf"
binary="$output_dir/X1E80100-Microsoft-Surface-Pro-11-tplg.bin"
m4 -I "$source_dir" "$input" >"$conf"
alsatplg -c "$conf" -o "$binary"

[[ "$(sha256sum "$conf" | awk '{print $1}')" == "$expected_conf" ]] || {
	printf 'Generated topology source identity mismatch.\n' >&2
	exit 1
}
[[ "$(sha256sum "$binary" | awk '{print $1}')" == "$expected_binary" ]] || {
	printf 'Generated topology binary identity mismatch.\n' >&2
	exit 1
}
printf 'Built reproducible SP11 audio topology:\n'
sha256sum "$conf" "$binary"
