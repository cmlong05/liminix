#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
uimage=result-uimage
rootfs=result-rootfs
updater=result-updater

device_dir="$here/devices/jdcloud-ax6600"
config="$device_dir/images/ax6600-rootfs.nix"
deployment="$device_dir/config.nix"
firewall="$device_dir/config_firewall.nix"

with_updater=0
while [ $# -gt 0 ]; do
    case "$1" in
        -u) with_updater=1 ;;
        *)
            echo "usage: $0 [-u]" >&2
            exit 2
            ;;
    esac
    shift
done

set -- \
    --arg device "import $device_dir" \
    -I "liminix-config=$config" \
    -I "liminix-deployment=$deployment" \
    -I "liminix-firewall=$firewall"

if [ "$with_updater" -eq 1 ]; then
    echo "==> updater" >&2
    nix-build -Q "$@" \
        -A outputs.updater \
        -o "$here/$updater"
    exit 0
fi

echo "==> rootfs：完整 ext4 镜像（自带 /bin、/etc、fifo）" >&2
nix-build -Q "$@" \
-A outputs.rootfs \
-o "$here/$rootfs"

echo "==> uimage(kernal)" >&2
nix-build -Q "$@" \
    -A outputs.uimage \
    -o "$here/$uimage"

echo "==> md5" >&2
for r in "$uimage" "$rootfs"; do
    real=$(readlink -f "$here/$r")
    printf '%-24s -> %s\n' "$r" "$real"
    if [ -f "$real" ]; then
        printf '  size %s bytes\n  md5 %s\n' \
            "$(stat -c%s "$real")" "$(md5sum < "$real" | cut -d' ' -f1)"
    else
        for p in "$real"/*; do
            printf '  %-9s size %s  md5 %s\n' "$(basename "$p")" \
                "$(stat -c%s "$p")" "$(md5sum < "$p" | cut -d' ' -f1)"
        done
    fi
done
