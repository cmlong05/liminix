#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
updater=result-updater

device_dir="$here/devices/jdcloud-ax6600"

target=emmc
with_updater=0
verbose=0
profile=config
firewall_profile=

# 站点专属文件名的约定：站点名追加在 .nix 之前，stem 本身即默认站点。
#   -c home -> config-home.nix          -f home -> config_firewall-home.nix
pick() {
    case "$2" in
        */* | *.nix) echo "$2" ;;
        "$1") echo "$device_dir/$1.nix" ;;
        *) echo "$device_dir/$1-$2.nix" ;;
    esac
}

available() {
    for f in "$device_dir/$1.nix" "$device_dir/$1"-*.nix; do
        test -f "$f" || continue
        b=$(basename "$f" .nix)
        echo "${b#"$1"-}"
    done | tr '\n' ' '
}

abspath() {
    case "$1" in
        /*) echo "$1" ;;
        *) echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")" ;;
    esac
}

usage() {
    cat >&2 <<EOF
usage: $0 [-e|-u] [-c <profile>] [-f <profile|none>] [-v] [--updater]

  -e             build the eMMC image (default)
  -u             build the USB rootfs image
  -c <profile>   deployment: config-<profile>.nix, or a .nix path
                 (default: config). Available: $(available config)
  -f <profile>   site firewall rules: config_firewall-<profile>.nix, a .nix
                 path, or none to ship no site rules at all. Default: the
                 -c profile's own file if it exists, else config_firewall.nix
  -v             full nix-build output
  --updater, -U  build the updater only
EOF
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        -e) target=emmc ;;
        -u) target=usb ;;
        -v) verbose=1 ;;
        --updater | -U) with_updater=1 ;;
        -c)
            test $# -ge 2 || usage
            profile=$2
            shift
            ;;
        -f)
            test $# -ge 2 || usage
            firewall_profile=$2
            shift
            ;;
        *) usage ;;
    esac
    shift
done

deployment=$(pick config "$profile")
if [ ! -f "$deployment" ]; then
    echo "$0: no deployment profile '$profile'" >&2
    echo "$0: available: $(available config)" >&2
    exit 2
fi
deployment=$(abspath "$deployment")

if [ "$firewall_profile" = none ]; then
    firewall=
elif [ -n "$firewall_profile" ]; then
    firewall=$(pick config_firewall "$firewall_profile")
    if [ ! -f "$firewall" ]; then
        echo "$0: no firewall profile '$firewall_profile'" >&2
        list=$(available config_firewall)
        echo "$0: available: ${list% } none" >&2
        exit 2
    fi
    firewall=$(abspath "$firewall")
else
    # 没给 -f：默认站点用基名文件，其它站点找 config_firewall-<站点>.nix；
    # 都没有就沿用默认文件，并说明这一点，免得把一个站点的放行规则默认
    # 悄悄带进另一个站点
    if [ "$profile" = config ]; then
        firewall="$device_dir/config_firewall.nix"
    else
        firewall=$(pick config_firewall "$profile")
    fi
    if [ ! -f "$firewall" ]; then
        firewall="$device_dir/config_firewall.nix"
        if [ -f "$firewall" ]; then
            echo "$0: no config_firewall-$profile.nix; using config_firewall.nix" >&2
        else
            firewall=
        fi
    fi
    if [ -n "$firewall" ]; then
        firewall=$(abspath "$firewall")
    fi
fi

nix_build() {
    if [ "$verbose" -eq 1 ]; then
        nix-build "$@"
    else
        nix-build -Q "$@"
    fi
}

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
    -I "liminix-deployment=$deployment"

# 不带 -I liminix-firewall 就是"没有站点放行规则"（ax6600-rootfs.nix 的
# siteFirewall 靠它区分"没给"和"给了个空文件"）
if [ -n "$firewall" ]; then
    set -- "$@" -I "liminix-firewall=$firewall"
fi

echo "==> deployment: $profile ($deployment)" >&2
if [ -n "$firewall" ]; then
    echo "==> firewall: $(basename "$firewall")" >&2
else
    echo "==> firewall: none" >&2
fi

if [ "$with_updater" -eq 1 ]; then
    echo "==> updater" >&2
    nix_build "$@" \
        -A outputs.updater \
        -o "$here/$updater"
    exit 0
fi

echo "==> rootfs ($target)：完整 ext4 镜像（自带 /bin、/etc、fifo）" >&2
nix_build "$@" \
-A outputs.rootfs \
-o "$here/$rootfs"

echo "==> uimage (kernel)" >&2
nix_build "$@" \
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
