#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)

# config.json：从源码树的 deployment 生成 —— 与镜像里 /persist 的种子同一份文本
nix-instantiate --eval --strict --raw \
    -I "liminix-deployment=$here/devices/jdcloud-ax6600/config.nix" \
    --expr "(import $here/devices/jdcloud-ax6600/deployment-json.nix { lib = import <nixpkgs/lib>; }).text" \
    > "$here/config.json"

# rootfs：完整 ext4 镜像（自带 /bin、/etc、fifo）
nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-usb-ext4.nix \
    -I liminix-firewall=./devices/jdcloud-ax6600/config_firewall.nix \
    -A outputs.rootfs \
    -o result-usb-ext4-rootfs

# Kernel
nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-usb-ext4.nix \
    -I liminix-firewall=./devices/jdcloud-ax6600/config_firewall.nix \
    -A outputs.uimage \
    -o result-usb-ext4-uimage

# 再跑 md5
sh md5_result.sh
