#!/bin/sh
# Print size + md5 for the flashable Liminix artifacts
# Usage:
#   sh md5_result.sh                       # the artifacts below, then any
#                                          # other result* link here
#   sh md5_result.sh result-usb-uimage …   # or exactly the ones named
#
set -u
cd "$(dirname "$0")"

known="result-uimage result-rootfs result-usb-uimage result-usb-rootfs"

if [ "$#" -gt 0 ]; then
    results="$*"
else
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
        for p in "$real"/*; do
            [ -f "$p" ] || continue
            printf '  %-9s size %s  md5 %s\n' "$(basename "$p")" \
                "$(stat -c%s "$p")" "$(md5sum < "$p" | cut -d' ' -f1)"
        done
    fi
done
