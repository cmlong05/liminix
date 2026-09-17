#!/bin/sh
# Print size + md5 for every flashable Liminix artifact for the JDCloud
# AX6600 on this (wired-only) branch. Usage:
#   sh md5_result.sh
#
# Ported from the `ax6600` branch's result-md5.sh (commit f1e65ed),
# with the artifact list adjusted: this branch has no wifi configs
# (result-wifi / result-wifi-ram / result-ram) and no TFTP/boot.scr path
# (result / result-lan). The only image it covers:
#
#   result-lan-ram  - `ax6600-lan-ram.nix -A outputs.uimage` (single
#                     full-system FIT ram image)
#
# Record the md5 before uploading to the U-Boot web uploader, and verify
# it again after boot.
set -u
cd "$(dirname "$0")"
for r in result-lan-ram; do
    if [ -e "$r" ]; then
        real=$(readlink -f "$r")
        printf '%-16s -> %s\n' "$r" "$real"
        if [ -f "$real" ]; then
            printf '  size %s bytes\n' "$(stat -c%s "$real")"
            printf '  md5 %s\n' "$(md5sum < "$real" | cut -d' ' -f1)"
        else
            for f in boot.scr dtb image rootfs; do
                p=$(readlink -f "$r/$f")
                printf '  %-9s size %s  md5 %s\n' "$f" \
                    "$(stat -c%s "$p")" "$(md5sum < "$p" | cut -d' ' -f1)"
            done
        fi
    else
        printf '%-16s (not built)\n' "$r"
    fi
done
