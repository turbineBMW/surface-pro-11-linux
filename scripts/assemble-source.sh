#!/bin/bash

# Assemble deterministic complete-source staging for the custom review20
# payload. Distribution-package sources used by a future ISO are tracked
# separately from this custom kernel/iptsd/PPD source set.

set -euo pipefail

release="7.1.3-sp11-suspend-review20"
kernel_commit="18d7951a10dc49e383d16c6af82fc2c07784de3d"
kernel_tree="b820f10abba096e23a28506d7ad591dffdedf1a8"
iptsd_commit="a83bc1232f7096f8b33b50fdbda249cd640de670"
iptsd_tree="06c6e812873e117930eca60b8a32cec40fd13281"
ppd_commit="5b4994c8a91290481bef87a5bae95391d0ec677f"
ppd_tree="8310d18187f51b027004b3fc3e35f2bdd1ef5840"
source_date_epoch=1785076525

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
output_dir="$repo_root/work/source-review20"

usage() {
	cat <<EOF
Usage: $0 [--output DIRECTORY]

Required environment:
  SP11_KERNEL_REPO    Git repository containing the exact review20 commit
  SP11_IPTSD_SOURCE  Clean exact iptsd worktree with downloaded wrap sources
  SP11_PPD_SOURCE    Exact PPD 0.30 worktree with only the published patch

Output is restricted to this repository's ignored work/ directory.
EOF
}

while (($#)); do
	case "$1" in
	--output)
		[[ $# -ge 2 ]] || {
			usage >&2
			exit 2
		}
		output_dir="$2"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		printf 'Unknown argument: %s\n' "$1" >&2
		usage >&2
		exit 2
		;;
	esac
done

for command_name in git install realpath sha256sum tar zstd; do
	command -v "$command_name" >/dev/null || {
		printf 'Missing source-assembly command: %s\n' "$command_name" >&2
		exit 1
	}
done

mkdir -p -- "$repo_root/work"
output_dir="$(realpath -m -- "$output_dir")"
case "$output_dir" in
	"$repo_root/work"/*) ;;
	*)
		printf 'Refusing output outside %s/work: %s\n' \
			"$repo_root" "$output_dir" >&2
		exit 1
		;;
esac
if [[ -e "$output_dir" ]]; then
	printf 'Refusing to replace existing output: %s\n' "$output_dir" >&2
	exit 1
fi

kernel_repo="${SP11_KERNEL_REPO:-}"
iptsd_source="${SP11_IPTSD_SOURCE:-}"
ppd_source="${SP11_PPD_SOURCE:-}"
for variable_name in kernel_repo iptsd_source ppd_source; do
	if [[ -z "${!variable_name}" ]]; then
		printf 'Missing required environment for %s.\n' "$variable_name" >&2
		exit 1
	fi
done
kernel_repo="$(realpath -e -- "$kernel_repo")"
iptsd_source="$(realpath -e -- "$iptsd_source")"
ppd_source="$(realpath -e -- "$ppd_source")"

[[ "$(git -C "$kernel_repo" rev-parse "$kernel_commit^{commit}")" == \
	"$kernel_commit" ]]
[[ "$(git -C "$kernel_repo" rev-parse "$kernel_commit^{tree}")" == \
	"$kernel_tree" ]]

[[ "$(git -C "$iptsd_source" rev-parse "HEAD^{commit}")" == "$iptsd_commit" ]]
[[ "$(git -C "$iptsd_source" rev-parse "HEAD^{tree}")" == "$iptsd_tree" ]]
git -C "$iptsd_source" diff --quiet
git -C "$iptsd_source" diff --cached --quiet

required_iptsd_sources=(
	subprojects/CLI11-2.6.1/LICENSE
	subprojects/eigen-5.0.1/COPYING.MPL2
	subprojects/fmt-12.0.0/LICENSE
	subprojects/GSL-4.2.0/LICENSE
	subprojects/spdlog-1.15.3/LICENSE
)
for relative_path in "${required_iptsd_sources[@]}"; do
	[[ -f "$iptsd_source/$relative_path" ]] || {
		printf 'Missing iptsd fallback source/license: %s\n' \
			"$relative_path" >&2
		exit 1
	}
done

[[ "$(git -C "$ppd_source" rev-parse "HEAD^{commit}")" == "$ppd_commit" ]]
[[ "$(git -C "$ppd_source" rev-parse "HEAD^{tree}")" == "$ppd_tree" ]]
git -C "$ppd_source" diff --cached --quiet
git -C "$ppd_source" diff --check
mapfile -t ppd_changed_paths < <(git -C "$ppd_source" diff --name-only)
[[ "${#ppd_changed_paths[@]}" -eq 1 ]]
[[ "${ppd_changed_paths[0]}" == "src/ppd-driver-platform-profile.c" ]]
git -C "$ppd_source" apply --reverse --check \
	"$repo_root/userspace/power-profiles-daemon/0001-sp11-use-platform-profile-class.patch"

mkdir -p -- "$output_dir/kernel" "$output_dir/iptsd" "$output_dir/ppd"

git -C "$kernel_repo" archive --format=tar \
	--prefix="linux-$release/" "$kernel_commit" |
	zstd -q -10 -T1 -o "$output_dir/kernel/linux-$release.tar.zst"
install -m0644 "$repo_root/kernel/config" "$output_dir/kernel/config"
install -m0644 "$repo_root/kernel/Module.symvers" \
	"$output_dir/kernel/Module.symvers"
install -m0644 "$repo_root/kernel/BUILDINFO" "$output_dir/kernel/BUILDINFO"
install -m0755 "$repo_root/scripts/build-kernel.sh" \
	"$output_dir/kernel/build-kernel.sh"
install -m0644 "$repo_root/kernel/sp11-suspend-review20.patch" \
	"$output_dir/kernel/sp11-suspend-review20.patch"
install -m0644 "$repo_root/kernel/sp11-suspend-review20.bundle" \
	"$output_dir/kernel/sp11-suspend-review20.bundle"

tar --sort=name --mtime="@$source_date_epoch" --owner=0 --group=0 \
	--numeric-owner --format=posix \
	--pax-option=delete=atime,delete=ctime \
	--exclude=.git --transform='s#^\./#iptsd-3.1.0/#' \
	-cf - -C "$iptsd_source" . |
	zstd -q -10 -T1 -o "$output_dir/iptsd/iptsd-3.1.0-source.tar.zst"
install -m0644 "$repo_root/userspace/iptsd/README.md" \
	"$output_dir/iptsd/README.md"
install -m0644 "$repo_root/userspace/iptsd/LICENSE.upstream" \
	"$output_dir/iptsd/LICENSE.upstream"

tar --sort=name --mtime="@$source_date_epoch" --owner=0 --group=0 \
	--numeric-owner --format=posix \
	--pax-option=delete=atime,delete=ctime \
	--exclude=.git --exclude=build-sp11 \
	--transform='s#^\./#power-profiles-daemon-0.30-sp11/#' \
	-cf - -C "$ppd_source" . |
	zstd -q -10 -T1 \
		-o "$output_dir/ppd/power-profiles-daemon-0.30-sp11-source.tar.zst"
install -m0644 \
	"$repo_root/userspace/power-profiles-daemon/0001-sp11-use-platform-profile-class.patch" \
	"$output_dir/ppd/0001-sp11-use-platform-profile-class.patch"
install -m0644 "$repo_root/userspace/power-profiles-daemon/README.md" \
	"$output_dir/ppd/README.md"

cat >"$output_dir/CUSTOM-PAYLOAD-SOURCE-MANIFEST.txt" <<EOF
Custom review20 payload corresponding-source staging

Kernel:
  release: $release
  repository: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
  base tag: v7.1.3
  exact commit: $kernel_commit
  exact tree: $kernel_tree
  config/build identity: kernel/BUILDINFO

iptsd:
  repository: https://github.com/linux-surface/iptsd.git
  exact commit: $iptsd_commit
  exact tree: $iptsd_tree
  qualified binaries:
    sp11-iptsd 45ce0fcabdda04a9fcf3ce30f7f0c64ba7098fd2351127ef0e54cf0ac0b3f083
    sp11-iptsd-check-device 54fcdaef90b0bd4239df670865cf8b258c3ae6e3988e42b0b9a3b58aaa4b08f5
  included fallback sources:
    CLI11 2.6.1
    Eigen 5.0.1
    fmt 12.0.0
    Microsoft GSL 4.2.0
    spdlog 1.15.3
  system dynamic dependency: libinih 62-2

Power Profiles Daemon:
  repository: https://gitlab.freedesktop.org/upower/power-profiles-daemon.git
  exact base commit: $ppd_commit
  exact base tree: $ppd_tree
  applied patch: ppd/0001-sp11-use-platform-profile-class.patch
  qualified binary:
    power-profiles-daemon-sp11 9e1d72935f2b916de1c44950e425948e60c7bdf83c69bede2a079e7a79a82252

This source set covers the custom binaries in the held payload. Distribution
packages and their corresponding source are a separate future ISO manifest.
EOF

(
	cd -- "$output_dir"
	mapfile -t checksum_files < <(
		find . -type f ! -name SHA256SUMS -printf '%P\n' | LC_ALL=C sort
	)
	sha256sum "${checksum_files[@]}" >SHA256SUMS
)

archive="$(dirname -- "$output_dir")/sp11-beta-review20-custom-source.tar.zst"
if [[ -e "$archive" ]]; then
	printf 'Refusing to replace existing archive: %s\n' "$archive" >&2
	exit 1
fi
tar --sort=name --mtime="@$source_date_epoch" --owner=0 --group=0 \
	--numeric-owner --format=posix \
	--pax-option=delete=atime,delete=ctime \
	--zstd -cf "$archive" -C "$output_dir" .

printf 'Source staging: %s\n' "$output_dir"
printf 'Source archive: %s\n' "$archive"
sha256sum "$archive"
