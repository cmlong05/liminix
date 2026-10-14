#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
uimage=result-usb-ext4-uimage
rootfs=result-usb-ext4-rootfs

device_dir="$here/devices/jdcloud-ax6600"
deployment="$device_dir/config.nix"
firewall="$device_dir/config_firewall.nix"

echo "==> config.json：从 deployment 生成，与镜像 /persist 的种子同一份文本" >&2
nix-instantiate --eval --strict --raw \
    -I "liminix-deployment=$deployment" \
    --expr "(import $device_dir/deployment-json.nix { lib = import <nixpkgs/lib>; }).text" \
    > "$here/config.json"

set -- \
    --arg device "import $device_dir" \
    -I "liminix-config=$here/devices/jdcloud-ax6600/images/ax6600-usb-ext4.nix" \
    -I "liminix-deployment=$deployment" \
    -I "liminix-firewall=$firewall"
    
echo "==> rootfs：完整 ext4 镜像（自带 /bin、/etc、fifo）" >&2
nix-build -Q "$@" \
    -A outputs.rootfs \
    -o "$here/$rootfs"

echo "==> kernel" >&2
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