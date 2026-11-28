#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)

target=emmc
while [ $# -gt 0 ]; do
    case "$1" in
        -u) target=usb ;;
        *) echo "usage: $0 [-u]" >&2; exit 2 ;;
    esac
    shift
done

case "$target" in
    emmc)
        uimage="$here/result-uimage"
        rootfs="$here/result-rootfs"
        ;;
    usb)
        uimage="$here/result-usb-ext4-uimage"
        rootfs="$here/result-usb-ext4-rootfs"
        ;;
esac

tool_path() {
    if command -v "$1" >/dev/null 2>&1; then
        command -v "$1"
        return
    fi
    for path in /nix/store/*/bin/$1; do
        if [ -x "$path" ]; then
            echo "$path"
            return
        fi
    done
    return 1
}

strings_bin=$(tool_path strings) || { echo "verify-build.sh: strings not found" >&2; exit 1; }
debugfs_bin=$(tool_path debugfs) || { echo "verify-build.sh: debugfs not found" >&2; exit 1; }
for file in "$uimage" "$rootfs"; do
    test -e "$file" || { echo "verify-build.sh: $file not built" >&2; exit 1; }
done

uimage=$(readlink -f "$uimage")
rootfs=$(readlink -f "$rootfs")
kernel_marker=$("$strings_bin" "$uimage" | sed -n 's/.*\(liminix-build\/[^ ]*\).*/\1/p' | tail -n 1)
rootfs_json=$("$debugfs_bin" -R "cat /etc/liminix/build.json" "$rootfs" 2>/dev/null)
rootfs_marker=$(printf '%s\n' "$rootfs_json" | sed -n 's/.*"marker":"\([^"]*\)".*/\1/p')

test -n "$kernel_marker" || { echo "verify-build.sh: no build marker in $uimage" >&2; exit 1; }
test -n "$rootfs_marker" || { echo "verify-build.sh: no build marker in $rootfs" >&2; exit 1; }

printf '%s\n' "$rootfs_json"
printf 'kernel: %s\nrootfs: %s\n' "$kernel_marker" "$rootfs_marker"
if [ "$kernel_marker" = "$rootfs_marker" ]; then
    echo "match: yes"
    exit 0
fi

echo "match: no" >&2
exit 1
