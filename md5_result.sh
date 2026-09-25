#!/bin/sh
# Print size + md5 for the flashable Liminix artifacts for the JDCloud
# AX6600 on this branch. Usage:
#   sh md5_result.sh                       # the artifacts below, then any
#                                          # other result* link here
#   sh md5_result.sh result-usb-uimage …   # or exactly the ones named
#
# Ported from the `ax6600` branch's result-md5.sh (commit f1e65ed), with the
# artifact list adjusted twice: this branch has no TFTP/boot.scr path
# (`outputs.tftpboot` and its `result` are gone), and each disk image is two
# artifacts - a uimage and a squashfs - which are built with an `-o` of their
# own so the name says which is which:
#
#   result-lan-ram     - ax6600-lan-ram.nix   outputs.uimage   (wired, RAM)
#   result-nss-lan-ram - ax6600-nss-ram.nix   outputs.uimage   (wired + radio, RAM)
#   result-uimage      - ax6600-rootfs.nix    outputs.uimage   (eMMC: kernel FIT + dtb)
#   result-rootfs      - ax6600-rootfs.nix    outputs.rootfs   (eMMC: squashfs root)
#   result-usb-uimage  - ax6600-usb.nix       outputs.uimage   (USB root: kernel FIT + dtb)
#   result-usb-rootfs  - ax6600-usb.nix       outputs.rootfs   (USB root: squashfs root)
#
# Each name above is the `-o` of its own nix-build. A single invocation with
# both `-A outputs.uimage -A outputs.rootfs` and one `-o` leaves the second
# artifact under a `-2` name instead; the extra-links loop below picks up
# either spelling.
#
# Record the md5 before uploading/flashing, and verify it again after boot.
set -u
cd "$(dirname "$0")"

known="result-lan-ram result-nss-lan-ram result-uimage result-rootfs result-usb-uimage result-usb-rootfs"

if [ "$#" -gt 0 ]; then
    results="$*"
else
    # The known names first, absent ones included so a forgotten artifact is
    # visible, then whatever else here looks like a result link (`result`
    # only exists if something still produces a bare `result` output).
    results="$known"
    for f in result result-*; do
        [ -e "$f" ] || continue
        case " $results " in
            *" $f "*) ;;
            *) results="$results $f" ;;
        esac
    done
fi

for r in $results; do
    if [ ! -e "$r" ]; then
        printf '%-20s (not built)\n' "$r"
        continue
    fi
    real=$(readlink -f "$r")
    printf '%-20s -> %s\n' "$r" "$real"
    if [ -f "$real" ]; then
        printf '  size %s bytes\n' "$(stat -c%s "$real")"
        printf '  md5 %s\n' "$(md5sum < "$real" | cut -d' ' -f1)"
    else
        # A multi-artifact output directory: report whatever files it holds.
        for p in "$real"/*; do
            [ -f "$p" ] || continue
            printf '  %-9s size %s  md5 %s\n' "$(basename "$p")" \
                "$(stat -c%s "$p")" "$(md5sum < "$p" | cut -d' ' -f1)"
        done
    fi
done
