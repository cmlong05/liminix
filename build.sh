#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
updater=result-updater

device_dir="$here/devices/jdcloud-ax6600"
deployment="$device_dir/config.nix"
firewall="$device_dir/config_firewall.nix"

target=emmc
with_updater=0
while [ $# -gt 0 ]; do
    case "$1" in
        -e | e) target=emmc ;;
        -u | u) target=usb ;;
        --updater | -U) with_updater=1 ;;
        *)
            echo "usage: $0 [-e|-u] [--updater]" >&2
            exit 2
            ;;
    esac
    shift
done

case "$target" in
    emmc)
        config="$device_dir/images/ax6600-rootfs.nix"
        uimage=result-uimage
        rootfs=result-rootfs
        ;;
    usb)
        config="$device_dir/images/ax6600-usb-ext4.nix"
        uimage=result-usb-ext4-uimage
        rootfs=result-usb-ext4-rootfs
        ;;
esac

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

echo "==> rootfs ($target)：完整 ext4 镜像（自带 /bin、/etc、fifo）" >&2
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
