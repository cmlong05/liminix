#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)

device_dir="$here/devices/jdcloud-ax6600"
deployment="$device_dir/config.nix"

echo "==> config.json：从 deployment 生成，与镜像 /persist 的种子同一份文本" >&2
nix-instantiate --eval --strict --raw \
    -I "liminix-deployment=$deployment" \
    --expr "(import $device_dir/deployment-json.nix { lib = import <nixpkgs/lib>; }).text" \
    > "$here/config.json"

set -- \
    --arg device "import $device_dir" \
    -I "liminix-config=$here/ax6600-usb-ext4.nix" \
    -I "liminix-deployment=$deployment" \
    -I "liminix-firewall=$device_dir/config_firewall.nix"

echo "==> rootfs：完整 ext4 镜像（自带 /bin、/etc、fifo）" >&2
nix-build -Q "$@" \
    -A outputs.rootfs \
    -o "$here/result-usb-ext4-rootfs"

echo "==> kernel" >&2
nix-build -Q "$@" \
    -A outputs.uimage \
    -o "$here/result-usb-ext4-uimage"

echo "==> md5" >&2
sh "$here/md5_result.sh"