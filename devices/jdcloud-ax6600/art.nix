# 0:ART per-unit data for this board: the wired MACs and the radio
# calibration live in one eMMC GPT partition (0:ART) that the build cannot
# know, so they are read at boot.
#
#   * art-extract runs from rc-init.d, before the module loader, so ath11k
#     finds a cal file when it probes: it writes them into its service outputs,
#     and ./rootfs-firmware.nix links ath11k's names for them there. It also
#     publishes this unit's MACs under /run/art.
#   * radios-init runs from rc-init.d after the module loader: once both AHB
#     radios have registered it renames their netdevs to fixed names by the MAC
#     ath11k took out of the cal data. The QCN9074 netdev is renamed by qcn-up.
#   * art-apply runs as an s6 oneshot: it puts the wired MACs on lan1..4/wan.
#
# Offsets are structural, never a MAC value. A missing 0:ART is reported and
# leaves the built-in firmware and the default names in place.
{ lib, pkgs, ... }:
let
  inherit (pkgs.pseudofile) dir symlink;
  inherit (pkgs.liminix.services) oneshot;

  extract = pkgs.writeAshScript "art-extract" { } ''
    set -u
    export PATH=/bin:/sbin
    . ${pkgs.serviceFns}

    part=
    for u in /sys/class/block/*/uevent; do
      if grep -q '^PARTNAME=0:ART$' "$u" 2>/dev/null; then
        part=/dev/$(basename "$(dirname "$u")")
        break
      fi
    done
    if test -z "$part" ; then
      echo "art-extract: no 0:ART partition; the AHB radios cannot start" >&2
      exit 1
    fi

    # AHB calibration, shared by the 2.4 and 5.8 GHz pdevs (one cal per AHB
    # device): offset 0x1000, length 0x20000
    out=$(mkoutputs art-extract)
    dd if="$part" of="$out/cal" bs=4096 skip=1 count=32 2>/dev/null

    # PCI calibration for the QCN9074 (5.2 GHz): offset 0x26800, length
    # 0x20000 (bs=1024: skip=154, count=128)
    dd if="$part" of="$out/cal-pci" bs=1024 skip=154 count=128 2>/dev/null

    # this unit's MACs, by role: wired in the 0:ART header, radios embedded
    # in the cal blobs (ath11k takes the radio MACs from the cal file itself)
    mkdir -p /run/art
    mac() {
      dd if="$part" bs=1 skip="$1" count=6 2>/dev/null | xxd -p \
        | sed 's/../&:/g;s/:$//'
    }
    echo "$(mac $((0x0)))"    > /run/art/mac.lan1
    echo "$(mac $((0x6)))"    > /run/art/mac.lan2
    echo "$(mac $((0xc)))"    > /run/art/mac.lan3
    echo "$(mac $((0x12)))"   > /run/art/mac.lan4
    echo "$(mac $((0x18)))"   > /run/art/mac.wan
    echo "$(mac $((0x100e)))" > /run/art/mac.58g
    echo "$(mac $((0x1014)))" > /run/art/mac.24g
    echo "$(mac $((0x2680e)))" > /run/art/mac.52g
    echo "art-extract: calibration and MACs read from $part"
  '';

  renameRadios = roles: pkgs.writeAshScript "art-rename-radios" { } ''
    set -u
    export PATH=/bin:/sbin

    rename_wlan() {   # role, fixed name
      wmac=$(cat "/run/art/mac.$1" 2>/dev/null) || return 0
      test -n "$wmac" || return 0
      i=0
      # cap the wait: a radio that never probes (e.g. QCN9074 firmware
      # stall) must not stall boot past s6-rc's 30s oneshot timeout.
      while test "$i" -lt 15 ; do
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

    ${lib.concatMapStrings (r: "rename_wlan ${r} wlan${r}\n") roles}
  '';

  renameAhb = renameRadios [ "24g" "58g" ];
  renameQcn = renameRadios [ "52g" ];

  ahbReady = pkgs.writeAshScript "ahb-ready" { } ''
    set -u
    export PATH=/bin:/sbin
    test -d /sys/module/ath11k_ahb || {
      echo "ahb-ready: AHB driver is not loaded" >&2
      exit 1
    }
    i=0
    while test "$i" -lt 30; do
      phys=0
      for d in /sys/class/ieee80211/*; do
        test -e "$d" || continue
        case "$(readlink "$d")" in
          */c000000.wifi/*) phys=$((phys + 1)) ;;
        esac
      done
      test "$phys" -ge 2 && exit 0
      sleep 1
      i=$((i + 1))
    done
    echo "ahb-ready: AHB radios did not initialize" >&2
    exit 1
  '';

  radiosInit = pkgs.writeAshScript "radios-init" { } ''
    set -u
    ${ahbReady} && ${renameAhb}
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
  '';
in
{
  options.wireless.qcnRenameScript = lib.mkOption {
    type = lib.types.package;
    internal = true;
    description = "Script that renames the QCN9074 netdev to wlan52g.";
  };

  options.wireless.ahbReadyScript = lib.mkOption {
    type = lib.types.package;
    internal = true;
    description = "Script that waits for both AHB radios to register.";
  };

  config = {
    wireless.qcnRenameScript = renameQcn;
    wireless.ahbReadyScript = ahbReady;

    # The one firmware name the build cannot fill: rootfs-firmware.nix links it
    # to art-extract's output, which ath11k then opens like any other file.
    wireless.runtimeFirmwareFiles."ath11k/IPQ6018/hw1.0/cal-ahb-c000000.wifi.bin" =
      "/run/services/outputs/art-extract/cal";
    wireless.runtimeFirmwareFiles."ath11k/QCN9074/hw1.0/cal-pci-0000:01:00.0.bin" =
      "/run/services/outputs/art-extract/cal-pci";

    filesystem = dir {
      etc = dir {
        "rc-init.d" = dir {
          # sorts before "modules" (0 < m), so the cal file is in place
          # before the module loader - and ath11k - runs
          "05-art" = symlink extract;
          # sorts after "modules", so the AHB netdevs exist to be renamed
          "zz-radios" = symlink radiosInit;
        };
      };
    };

    services.art-apply = oneshot {
      name = "art-apply";
      up = ''${apply}'';
    };
  };
}
