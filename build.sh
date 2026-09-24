#!/bin/sh

# NSS（lan1..lan4 桥接 + 2.5G PPPoE + 2.4g + 5.8g）
nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-nss-ram.nix \
    -A outputs.uimage \
    -o result-nss-lan-ram && \
    sh md5_result.sh