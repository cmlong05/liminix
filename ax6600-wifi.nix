# WiFi services for the JDCloud AX6600 (RE-CS-02).
#
# The services side of the radio port: staging the firmware and the board's
# calibration, bringing the two ath11k radios up at the right moment, and
# putting one access point per band on the wired LAN bridge. The driver
# patches and the kernel configuration are the device's (its default.nix
# reads ./devices/jdcloud-ax6600/wifi/SOURCES.nix).
#
# Built through ax6600-wifi-ram.nix:
#   nix-build --arg device "import ./devices/jdcloud-ax6600" \
#     -I liminix-config=./ax6600-wifi-ram.nix -A outputs.uimage -o result-wifi
#
# This is ImmortalWrt's ordering, in Liminix terms. There, /lib/firmware comes
# from packages, the 11-ath11k-caldata hotplug hook cuts the per-unit
# calibration out of the eMMC ART partition as soon as the firmware is
# requested, and the ath11k modules are loaded about 28 seconds in - after
# that hook has run. Here services.firmware-ath11k does the first two jobs and
# services.ath11k-probe binds the (built-in) drivers afterwards, which is why
# the driver patch 999-...-skip-early-probe-until-userspace.patch exists: a
# built-in ath11k would otherwise probe during kernel init, before any of this
# has happened.
#
# The board has two ath11k instances:
#   - QCN9074 5GHz 4x4 on PCIe0 (0000:01:00.0), "wlan5g1" here.
#   - IPQ6018 AHB (device c000000.wifi), whose 2.4G pdev becomes "wlan24".
#     Its second pdev (5GHz) is left alone rather than given a mis-banded AP.
#
# Interface names are not stable: the two instances register in probe order,
# so both are found by phy/device and renamed before anything else touches
# them. That is also why the device's hardware.networkInterfaces has no wlan
# entry.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  net = config.system.service.network;
  nifs = config.hardware.networkInterfaces;

  sources = import ./devices/jdcloud-ax6600/SOURCES.nix;
  wifi = sources.wifi;
  fw = wifi.firmware;

  # "0x26800" -> 157696. The ART offsets stay written the way upstream writes
  # them in its caldata table, and are converted here.
  hex = s: lib.fromHexString s;

  # Board data for the QCN9074: the file immortalwrt's ipq-wifi package
  # installs, keyed by the device tree's calibration variant JDC-RE-CS-02.
  qcn9074Board = pkgs.fetchurl {
    name = "board-jdcloud_re-cs-02.qcn9074";
    url = "${wifi.pins.qcaWireless.rawBase}/${fw.qcn9074Board.path}";
    hash = fw.qcn9074Board.sha256;
  };

  # The IPQ6018 Q6 firmware, from the CodeLinaro tree ImmortalWrt's
  # ath11k-firmware-ipq6018 package installs. The driver asks for these by
  # name under /lib/firmware/IPQ6018/.
  ipq6018Firmware = map (f: pkgs.fetchurl {
    name = f.name;
    url = "${wifi.pins.cloAth11k.rawBase}/${f.name}";
    hash = f.sha256;
  }) fw.ipq6018Firmware.files;

  # The static half of /lib/firmware: everything ath11k will ask for that can
  # be fetched. The per-unit calibration is not here - it is read out of the
  # board's own ART partition at boot, by services.firmware-ath11k below.
  staticFirmware = pkgs.runCommand "ath11k-firmware" { } ''
    root=$out/lib/firmware
    mkdir -p $root/ath11k/QCN9074/hw1.0 $root/ath11k/IPQ6018/hw1.0 $root/IPQ6018

    # --- QCN9074 (PCIe 5GHz): driver firmware from linux-firmware, which is
    # what ImmortalWrt's ath11k-firmware-qcn9074 installs. See the manifest
    # for the alternative firmware with hardware evidence on this unit.
    cp ${pkgs.linux-firmware}/lib/firmware/ath11k/QCN9074/hw1.0/amss.bin \
      $root/ath11k/QCN9074/hw1.0/
    cp ${pkgs.linux-firmware}/lib/firmware/ath11k/QCN9074/hw1.0/m3.bin \
      $root/ath11k/QCN9074/hw1.0/
    cp ${qcn9074Board} $root/ath11k/QCN9074/hw1.0/board-2.bin

    # --- IPQ6018 (onboard AHB): Q6 firmware from CodeLinaro, board data from
    # linux-firmware.
    ${lib.concatMapStrings (f: ''
      cp ${f} $root/IPQ6018/${f.name}
    '') ipq6018Firmware}
    cp ${pkgs.linux-firmware}/lib/firmware/ath11k/IPQ6018/hw1.0/board-2.bin \
      $root/ath11k/IPQ6018/hw1.0/

    # --- regulatory.db: modules/wlan.nix puts the same file in the image's
    # filesystem tree, but cfg80211 wants it while it registers, and this
    # service replaces /lib/firmware with a tmpfs anyway.
    cp ${pkgs.wireless-regdb}/lib/firmware/regulatory.db $root/
  '';

  # The calibration slices as "file|offset|size" records, straight out of the
  # manifest's `firmware.caldata` table (which is ImmortalWrt's for
  # jdcloud,re-cs-02); the service loops over them. Each record is emitted
  # *quoted*: an unquoted "|" in a word list is a pipe to the shell, and the
  # file name itself contains a colon, which is why the separator is "|" and
  # not ":". Only the shell around the table is ours.
  caldataTable = lib.concatMapStringsSep " " (
    e: ''"${e.firmware}|${toString (hex e.offset)}|${toString (hex e.size)}"''
  ) fw.caldata.entries;
in
{
  imports = [
    # The wired half: lan1..lan4, the "int" bridge, the LAN address and
    # dnsmasq from ./devices/jdcloud-ax6600/config.nix, the 2.5G PPPoE uplink
    # and sshd. This file adds the radios to that system.
    ./ax6600-lan.nix
    ./modules/wlan.nix
    ./modules/hostapd
  ];

  # ── Firmware and calibration ─────────────────────────────────────────
  #
  # Everything request_firmware() will look for must be in place before
  # ath11k-probe binds the drivers, and the calibration can only come from
  # the board itself, so this runs first and is a hard dependency below.
  services.firmware-ath11k = pkgs.liminix.services.oneshot {
    name = "firmware-ath11k";
    up = ''
      # /lib/firmware belongs to the root filesystem, which may be read-only,
      # and the calibration has to be written into it: put a tmpfs over the
      # whole directory and copy the static firmware back in on top.
      mountpoint -q /lib/firmware || {
        mkdir -p /lib/firmware
        mount -t tmpfs -o mode=0755 none /lib/firmware
      }
      # `cp -r` from the store brings the store's read-only directory modes
      # with it, and the calibration files are written into those directories
      # below: make them writable first (the copy is on a tmpfs, so this is
      # free).
      cp -r ${staticFirmware}/lib/firmware/. /lib/firmware/
      chmod -R u+w /lib/firmware

      # Find this board's ART GPT partition. ImmortalWrt asks for "0:ART",
      # and find_mmc_part() matches that string against PARTNAME exactly - so
      # the partition's GPT name really is "0:ART" (the CAL-* partitions next
      # to it are named the same way). "ART" is accepted too, because a
      # partition relabelled by hand or by a different flashing tool would
      # otherwise be invisible.
      art=""
      for u in /sys/class/block/mmcblk*p*/uevent; do
        [ -e "$u" ] || continue
        case "$(sed -n 's/^PARTNAME=//p' "$u")" in
          0:ART|ART)
            dev=''${u%/uevent}
            art=/dev/''${dev##*/}
            break
            ;;
        esac
      done

      if [ -z "$art" ]; then
        echo "firmware-ath11k: no ART partition on the eMMC - the radios will not come up" > /dev/kmsg
      else
        echo "firmware-ath11k: reading pre-calibration from $art" > /dev/kmsg
        # file|offset|size, byte-relative to the partition device, exactly as
        # caldata_extract_mmc's dd does it.
        for cal in ${caldataTable}; do
          cal_file=''${cal%%|*}
          cal_rest=''${cal#*|}
          cal_offset=''${cal_rest%%|*}
          cal_size=''${cal_rest##*|}
          dd if="$art" of=/lib/firmware/$cal_file bs=1 \
            skip=$cal_offset count=$cal_size 2>/dev/null
          got=$(stat -c%s /lib/firmware/$cal_file 2>/dev/null || echo 0)
          [ "$got" = "$cal_size" ] \
            || echo "firmware-ath11k: $cal_file is $got bytes, wanted $cal_size" > /dev/kmsg
        done
      fi
    '';
    down = "true";
  };

  # ── Bringing the radios up ───────────────────────────────────────────
  #
  # Both drivers are built in and both were told to skip their early probe
  # (patch 999), so this is what actually starts them. Writing a device name
  # to a bus's drivers_probe runs device_attach(), the probe path the driver
  # core itself uses - not a forced sysfs bind.
  services.ath11k-probe = pkgs.liminix.services.oneshot {
    name = "ath11k-probe";
    # 20s settle + up to six PCIe attempts of ~30s + the AHB wait
    timeout-up = 300000;
    dependencies = [ config.services.firmware-ath11k ];
    up = ''
      kmsg() { echo "ath11k-probe: $*" > /dev/kmsg; }

      # The QCN9074 needs a moment after power-on before its MHI firmware boot
      # will take; the reference reaches it about 28s in, from module autoload.
      kmsg "waiting 20s before probing the radios"
      sleep 20

      # --- QCN9074 on PCIe0 -------------------------------------------
      pci_ok=0
      attempt=1
      while [ $attempt -le 6 ]; do
        kmsg "PCI drivers_probe 0000:01:00.0 (attempt $attempt/6)"
        echo 0000:01:00.0 > /sys/bus/pci/drivers_probe 2>/dev/null \
          || kmsg "drivers_probe write failed"
        i=0
        while [ $i -lt 15 ]; do
          if [ -n "$(ls /sys/bus/pci/devices/0000:01:00.0/net/ 2>/dev/null)" ]; then
            pci_ok=1
            break
          fi
          sleep 2
          i=$((i + 1))
        done
        if [ $pci_ok -eq 1 ]; then
          old=$(ls /sys/bus/pci/devices/0000:01:00.0/net/ 2>/dev/null)
          if [ -n "$old" ] && [ "$old" != wlan5g1 ]; then
            ip link set "$old" down 2>/dev/null
            ip link set "$old" name wlan5g1
          fi
          kmsg "QCN9074 up as wlan5g1 (attempt $attempt)"
          break
        fi
        # A probe that failed before registration can leave the device bound
        # but dead; drop the binding (safe since patch 970) so the next
        # drivers_probe is a fresh probe.
        kmsg "no netdev after attempt $attempt; unbinding and retrying"
        echo 0000:01:00.0 > /sys/bus/pci/drivers/ath11k_pci/unbind 2>/dev/null
        attempt=$((attempt + 1))
        sleep 5
      done
      [ $pci_ok -eq 1 ] || kmsg "gave up on the QCN9074 after 6 attempts"

      # --- IPQ6018 AHB (c000000.wifi) ---------------------------------
      # Its 2.4GHz pdev is the one to serve; find it by the channel it
      # supports (iw prints "2412.0 MHz", so "2412" is the match) and give
      # its netdev the stable name before anything else touches it.
      kmsg "platform drivers_probe c000000.wifi"
      echo c000000.wifi > /sys/bus/platform/drivers_probe 2>/dev/null \
        || kmsg "platform drivers_probe write failed"

      i=0
      while [ $i -lt 120 ]; do
        for phy in /sys/class/ieee80211/phy*; do
          [ -e "$phy/device" ] || continue
          # busybox readlink has no -f; /sys links are direct symlinks, so
          # the basename of the plain readlink output is the device name.
          dev=$(readlink "$phy/device")
          [ "''${dev##*/}" = "c000000.wifi" ] || continue
          ${pkgs.iw}/bin/iw phy "''${phy##*/}" info 2>/dev/null | grep -q 2412 || continue
          for w in /sys/class/net/*; do
            p=$(readlink "$w/phy80211")
            [ "''${p##*/}" = "''${phy##*/}" ] || continue
            old="''${w##*/}"
            if [ "$old" != wlan24 ]; then
              ip link set "$old" down 2>/dev/null
              ip link set "$old" name wlan24
            fi
            kmsg "AHB 2.4G: $old -> wlan24"
            exit 0
          done
        done
        sleep 1
        i=$((i + 1))
      done
      # Deliberately loud. The bridge takes both wlan interfaces as members,
      # so a radio that never comes up means no LAN at all - which is the
      # honest outcome for an AP image: the serial console is the way back in,
      # and a half-up router that looks fine over ssh would be worse.
      kmsg "no 2.4GHz interface appeared on c000000.wifi; the bridge will not come up"
      exit 1
    '';
    down = "true";
  };

  services.wlan5g = net.link.build {
    ifname = "wlan5g1";
    dependencies = [ config.services.ath11k-probe ];
  };

  services.wlan2g = net.link.build {
    ifname = "wlan24";
    dependencies = [ config.services.ath11k-probe ];
  };

  # ── One LAN ──────────────────────────────────────────────────────────
  #
  # The wired config bridged lan1..lan4; replacing it here (rather than
  # adding a second definition, which would be a conflict) is the one place
  # the wifi build restates something from ax6600-lan.nix. Keep the two
  # member lists in step if the switch ports ever change.
  services.bridge = lib.mkForce (config.system.service.bridge.members.build {
    primary = config.services.int;
    members = [
      nifs.lan1
      nifs.lan2
      nifs.lan3
      nifs.lan4
      config.services.wlan2g
      config.services.wlan5g
    ];
  });

  # ── Access points ────────────────────────────────────────────────────
  #
  # Credentials are bring-up defaults, not deployment values: this repo has
  # no secrets story for them yet, and the wired build's SSH password is
  # likewise written down in ax6600-dev.nix.
  services.hostapd-2g = config.system.service.hostapd.build {
    interface = config.services.wlan2g;
    params = {
      ssid = "Liminix-AX6600-2G";
      wpa_passphrase = "liminix-wifi";
      country_code = "CN";
      hw_mode = "g";
      channel = 6;
      wmm_enabled = 1;
      ieee80211n = 1;
      auth_algs = 1;
      wpa = 2;
      wpa_key_mgmt = "WPA-PSK";
      wpa_pairwise = "CCMP";
      rsn_pairwise = "CCMP";
    };
  };

  services.hostapd-5g = config.system.service.hostapd.build {
    interface = config.services.wlan5g;
    params = {
      ssid = "Liminix-AX6600";
      wpa_passphrase = "liminix-wifi";
      country_code = "CN";
      hw_mode = "a";
      channel = 36;
      wmm_enabled = 1;
      ieee80211n = 1;
      ht_capab = "[HT40+][SHORT-GI-20][SHORT-GI-40][TX-STBC][RX-STBC1][MAX-AMSDU-7935]";
      ieee80211ac = 1;
      vht_oper_chwidth = 1;
      vht_oper_centr_freq_seg0_idx = 42;
      vht_capab = "[VHT80][SHORT-GI-80][RXLDPC][TX-STBC-2BY1][RX-STBC-1][MAX-MPDU-11454]";
      # 11ax is deliberately off for now: this tree's ath11k was still
      # asserting the firmware on the HE/PEER path under sustained load, and
      # an AC-only AP is the configuration that survived longest. Revisit
      # once a newer driver or the mac80211 patch set is in.
      ieee80211ax = 0;
      auth_algs = 1;
      wpa = 2;
      wpa_key_mgmt = "WPA-PSK";
      wpa_pairwise = "CCMP";
      rsn_pairwise = "CCMP";
    };
  };

  defaultProfile.packages = with pkgs; [
    # iw: used by the probe service above, and the only way to see what the
    # radios actually did.
    iw
  ];
}
