# 0:ART per-unit data for this board: the wired MACs and the radio
# calibration live in one eMMC GPT partition (0:ART) that the build cannot
# know, so they are read at boot.
#
#   * art-extract runs from rc-init.d, before the module loader, so ath11k
#     finds its cal file in /lib/firmware when it probes; it also publishes
#     this unit's MACs under /run/art.
#   * art-apply runs as an s6 oneshot after that: it puts the wired MACs on
#     lan1..4/wan and renames the two AHB netdevs to fixed names by the MAC
#     ath11k took out of the cal data.
#
# Offsets are structural, never a MAC value. Everything is best-effort: a missing 0:ART leaves the built-in
# firmware and default names in place rather than failing the boot.
{ pkgs, ... }:
let
  inherit (pkgs.pseudofile) dir symlink;
  inherit (pkgs.liminix.services) oneshot;

  extract = pkgs.writeAshScript "art-extract" { } ''
    set -u
    export PATH=/bin:/sbin

    part=
    for u in /sys/class/block/*/uevent; do
      if grep -q '^PARTNAME=0:ART$' "$u" 2>/dev/null; then
        part=/dev/$(basename "$(dirname "$u")")
        break
      fi
    done
    if test -z "$part" ; then
      echo "art-extract: no 0:ART partition; radios keep the built-in firmware" >&2
      exit 0
    fi

    # /lib/firmware/ath11k is a symlink into the read-only store, so it has
    # to become a real directory before anything can be written under it.
    if test -L /lib/firmware/ath11k ; then
      tmp=/lib/firmware/.ath11k.new
      rm -rf "$tmp"
      mkdir -p "$tmp"
      cp -a -L /lib/firmware/ath11k/. "$tmp"/ || true
      rm -f /lib/firmware/ath11k
      mv "$tmp" /lib/firmware/ath11k || true
    fi

    fw=/lib/firmware/ath11k/IPQ6018/hw1.0
    mkdir -p "$fw"
    # AHB calibration, shared by the 2.4 and 5.8 GHz pdevs (one cal per AHB
    # device): offset 0x1000, length 0x20000
    dd if="$part" of="$fw/cal-ahb-c000000.wifi.bin" \
       bs=1 skip=$((0x1000)) count=$((0x20000)) 2>/dev/null

    # this unit's MACs, by role: wired in the 0:ART header, radios embedded
    # in the cal blobs (ath11k takes the radio MACs from the cal file itself)
    mkdir -p /run/art
    mac() {
      dd if="$part" bs=1 skip="$1" count=6 2>/dev/null \
        | od -An -tx1 | tr -d ' \n' | sed 's/../&:/g;s/:$//'
    }
    echo "$(mac $((0x0)))"    > /run/art/mac.lan1
    echo "$(mac $((0x6)))"    > /run/art/mac.lan2
    echo "$(mac $((0xc)))"    > /run/art/mac.lan3
    echo "$(mac $((0x12)))"   > /run/art/mac.lan4
    echo "$(mac $((0x18)))"   > /run/art/mac.wan
    echo "$(mac $((0x100e)))" > /run/art/mac.58g
    echo "$(mac $((0x1014)))" > /run/art/mac.24g
    echo "$(mac $((0x26810)))" > /run/art/mac.52g
    echo "art-extract: calibration and MACs read from $part"
  '';

  apply = pkgs.writeAshScript "art-apply" { } ''
    set -u
    export PATH=/bin:/sbin

    set_mac() {   # device, role
      mac=$(cat "/run/art/mac.$2" 2>/dev/null) || return 0
      test -n "$mac" || return 0
      i=0
      while ! ip link show "$1" >/dev/null 2>&1 ; do
        i=$((i + 1))
        test "$i" -ge 60 && { echo "art-apply: $1 never appeared" >&2; return 0; }
        sleep 1
      done
      ip link set dev "$1" address "$mac" 2>/dev/null || true
    }

    set_mac lan1 lan1
    set_mac lan2 lan2
    set_mac lan3 lan3
    set_mac lan4 lan4
    set_mac wan  wan

    rename_wlan() {   # role, fixed name
      wmac=$(cat "/run/art/mac.$1" 2>/dev/null) || return 0
      test -n "$wmac" || return 0
      i=0
      while test "$i" -lt 60 ; do
        for d in /sys/class/net/* ; do
          cur=$(basename "$d")
          test "$cur" = "$2" && return 0
          case "$cur" in wlan*) ;; *) continue ;; esac
          test -r "$d/address" || continue
          test "$(cat "$d/address")" = "$wmac" || continue
          ip link set dev "$cur" down 2>/dev/null || true
          if ip link set dev "$cur" name "$2" ; then
            echo "art-apply: renamed $cur -> $2"
            return 0
          fi
          echo "art-apply: rename $cur -> $2 failed" >&2
          return 0
        done
        i=$((i + 1))
        sleep 1
      done
      echo "art-apply: no netdev with MAC $wmac for $2" >&2
    }

    rename_wlan 24g wlan24g
    rename_wlan 58g wlan58g
  '';
in
{
  filesystem = dir {
    etc = dir {
      "rc-init.d" = dir {
        # sorts before "modules" (0 < m), so the cal file is in place
        # before the module loader - and ath11k - runs
        "05-art" = symlink extract;
      };
    };
  };

  services.art-apply = oneshot {
    name = "art-apply";
    up = ''${apply}'';
  };
}
