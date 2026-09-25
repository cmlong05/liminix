#!/bin/sh

# 构建 rootfs
nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-usb.nix \
    -A outputs.rootfs \
    -o result-usb-rootfs

# 构建内核
nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-usb.nix \
    -A outputs.uimage \
    -o result-usb-uimage

# 再跑 md5
sh md5_result.sh