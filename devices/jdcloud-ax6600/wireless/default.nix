# N5 phase 1: the IPQ6010's own (AHB) radio - the 2.4 GHz and 5.8 GHz
# pdevs of wifi@c000000 - driven by ath11k.
#
# This is not the PCIe QCN9024; that is the separate 5.2 GHz radio N5
# phase 2 starts. What is here:
#
#   * the WCSS remoteproc, driven by the fork's own secure-PIL driver
#     (qcom_q6v5_wcss_sec): the Q6 is authenticated and released through
#     the SCM as PAS id 6, with the split q6+m3 firmware whose names come
#     from the device tree. Mainline's qcom_q6v5_wcss is not involved -
#     see ./SOURCES.nix for why that route is the one to take;
#   * the AHB half of ath11k, plus the AHB fixes this bring-up needed;
#   * the firmware the Q6 and ath11k request, embedded in the initramfs:
#     a fullSystem image loads its modules from preinit, before activate
#     has created /lib/firmware;
#   * two hostapd configurations and two scripts that start them.
#
# Nothing here autostarts the APs - BRINGUP N5 asks for the radios to be
# brought up by hand. The modules are in preloadModules, so the radio
# and its netdevs are up once the system is, and `wlan-2g` / `wlan-5g`
# do the rest. Which wlanN each pdev gets is registration order, which
# is why the scripts look the interface up by band, not by name.
#
# `qcom,ath11k-fw-memory-mode = <1>`, which the fork's board dts sets on
# both wifi nodes, IS read here: patch 903 is applied (see ./SOURCES.nix),
# so the AHB radio runs mode 1 - 8 vdevs / 128 peers - and the QCN9074
# will run mode 1 too. That is the reference implementation's own
# combination, and it is what the 2026-09-23 board run used; BRINGUP's N5
# review 1 claimed the property was inert, which dmesg's "FW memory mode:
# 1" disproves. There is therefore no override of it anywhere.
{ pkgs, lib, config, ... }:
let
  # --- firmware -----------------------------------------------------
  #
  # The Q6 image, the m3 and the board data are the set ./SOURCES.nix
  # pins, not linux-firmware's IPQ6018 tree: that build's q6 image takes a
  # firmware exception the moment the 5.8 GHz AP's peer is created, so
  # phy0 never comes up (see the note there). The names are exactly what
  # is requested:
  #
  #   IPQ6018/q6_fw.mdt, IPQ6018/m3_fw.mdt and their .bXX segments
  #       by the wcss remoteproc (qcom_q6v5_wcss_sec) for the Q6 and the m3
  #   ath11k/IPQ6018/hw1.0/board-2.bin
  #       ath11k's board data, from the fw.dir in the ipq6018 hw params
  #   ath11k/IPQ6018/hw1.0/cal-ahb-c000000.wifi.bin
  #       this unit's calibration. ath11k builds that name from the bus
  #       and the device name ("cal-%s-%s.bin") and only falls back to
  #       board-2.bin when it is missing, so without it the radio will
  #       not associate.
  #
  # The calibration data is per-unit and comes from a dump of this board's
  # 0:ART partition, kept (git-ignored, so absent from a fresh clone) in
  # ../art/: offset 0x1000 + length 0x20000, as OpenWrt's
  # 11-ath11k-caldata uses for ipq60xx. Embedding it is a RAM-image measure
  # only - preinit insmods before activate creates /lib/firmware - and it
  # makes the image valid for this unit alone. N7 moves this, with the MAC,
  # to a boot-time read of 0:ART; see ../BRINGUP.md.
  sources = import ./SOURCES.nix;
  fetchFirmware =
    p:
    pkgs.pkgsBuildBuild.fetchurl {
      name = p.path;
      inherit (p) url sha256;
    };
  firmwarePkg = pkgs.runCommand "ath11k-ipq6018-firmware" { } ''
    mkdir -p $out/IPQ6018 $out/ath11k/IPQ6018/hw1.0
    ${lib.concatMapStringsSep "\n" (
      p: "install -m 0644 ${fetchFirmware p} $out/IPQ6018/${p.path}"
    ) sources.q6Firmware}
    install -m 0644 ${fetchFirmware (builtins.head sources.boardData)} \
      $out/ath11k/IPQ6018/hw1.0/board-2.bin
    dd if=${../art/mmc_0-ART.bin} \
       of=$out/ath11k/IPQ6018/hw1.0/cal-ahb-c000000.wifi.bin \
       bs=1 skip=4096 count=131072 status=none
  '';

  # Both deliveries at the bottom of this file hand the kernel an attrsOf
  # package keyed by the name it asks for, so each file has to be a derivation
  # of its own rather than a path inside firmwarePkg.
  firmwareFile =
    name:
    pkgs.runCommand "firmware-${baseNameOf name}" { } ''
      install -D -m 0644 ${firmwarePkg}/${name} $out
    '';

  # The names the drivers ask for, exactly as they ask: the Q6 and m3 images
  # from the wcss remoteproc, board-2 from ath11k's board data lookup, and the
  # per-unit calibration ath11k builds out of the bus and device name. Both
  # delivery modules (./preload-firmware.nix, ./rootfs-firmware.nix) index
  # firmwarePkg with this list, so a name that is not in the tree fails their
  # build instead of shipping a dangling file.
  firmwareNames = [
    "IPQ6018/q6_fw.mdt"
    "IPQ6018/q6_fw.b00"
    "IPQ6018/q6_fw.b01"
    "IPQ6018/q6_fw.b02"
    "IPQ6018/q6_fw.b03"
    "IPQ6018/q6_fw.b04"
    "IPQ6018/q6_fw.b05"
    "IPQ6018/q6_fw.b07"
    "IPQ6018/q6_fw.b08"
    "IPQ6018/m3_fw.mdt"
    "IPQ6018/m3_fw.b00"
    "IPQ6018/m3_fw.b01"
    "IPQ6018/m3_fw.b02"
    "ath11k/IPQ6018/hw1.0/board-2.bin"
    "ath11k/IPQ6018/hw1.0/cal-ahb-c000000.wifi.bin"
  ];

  # --- hostapd ------------------------------------------------------
  #
  # SSIDs and channels per BRINGUP N5: CHEN on 2.4 GHz, CHEN_5g on
  # 5.8 GHz. ch6 is the conventional 2.4 GHz channel; ch149 is
  # DFS-free and inside what the AHB 5G pdev tunes to.
  password = "88888888";
  conf = name: params: pkgs.writeText "hostapd-${name}.conf" ''
    driver=nl80211
    logger_syslog=-1
    logger_syslog_level=1
    ctrl_interface=/run/hostapd-${name}
    ctrl_interface_group=0
    ssid=${params.ssid}
    wpa_passphrase=${password}
    country_code=CN
    hw_mode=${params.hw_mode}
    channel=${params.channel}
    wmm_enabled=1
    ieee80211n=1
    auth_algs=1
    wpa=2
    wpa_key_mgmt=WPA-PSK
    wpa_pairwise=CCMP
    rsn_pairwise=CCMP
  '';

  # The 2.4 and 5 GHz pdevs of the one AHB phy are separate netdevs whose
  # names follow registration order, so the interface is found by the
  # band it supports: `iw phy` prints frequencies as "2412.0 MHz", and
  # each band's first channel is enough to tell the two apart.
  #
  # Usage: wlan-2g [start|stop|status]. No argument starts it, in the
  # background with a pidfile under /run - hostapd's own -B, so nothing
  # here has to keep running. It is a writeShellScriptBin rather than a
  # writeShellScript because defaultProfile.packages puts these on the
  # login PATH as <package>/bin: a bare writeShellScript is one file at
  # the store root, so PATH points at a directory that does not exist and
  # `wlan-2g` is simply not found.
  #
  # `start` reports the state hostapd ends in: -B daemonises while the
  # interface is still in COUNTRY_UPDATE, and this build has no log sink
  # after the fork, so the console shows the same two lines whether the AP
  # came up or died. The comment in the `start` branch has the details.
  #
  # Each AP joins the LAN bridge once hostapd has its netdev in AP mode.
  # dnsmasq is bound to that bridge only, so an AP left outside it gives
  # an associated client no lease. The name is read from the service
  # (`ax6600-lan.nix` builds it) instead of repeating the literal here.
  bridge = "${config.services.int}/.outputs/ifname";
  ap = name: band: params: pkgs.writeShellScriptBin "wlan-${name}" ''
    set -eu

    dev=
    set +e
    for phy in /sys/class/ieee80211/phy*; do
      [ -e "$phy/device" ] || continue
      [ "$(basename "$(readlink "$phy/device")")" = c000000.wifi ] || continue
      ${pkgs.iw}/bin/iw phy "$(basename "$phy")" info 2>/dev/null | grep -q ${band} || continue
      for w in /sys/class/net/*/phy80211; do
        [ -e "$w" ] || continue
        [ "$(basename "$(readlink "$w")")" = "$(basename "$phy")" ] || continue
        dev=$(basename "$(dirname "$w")")
        break 2
      done
    done
    set -e
    [ -n "$dev" ] || {
      echo "no AHB ${band} netdev; is the Q6 up? try: dmesg | grep -iE 'wcss|ath11k'" >&2
      exit 1
    }

    case "''${1:-start}" in
      start)
        mkdir -p /run/hostapd-${name}
        # Starting on top of a running hostapd is not harmless (BRINGUP N5):
        # the second one is refused by NL80211_CMD_SET_INTERFACE with
        # -EALREADY and dies on the way out - and the poll below would then
        # read the first one's ENABLED and call that a success. Refuse here
        # instead, which also makes `start` idempotent.
        if [ -f /run/hostapd-${name}.pid ] &&
          kill -0 "$(cat /run/hostapd-${name}.pid)" 2>/dev/null; then
          echo "wlan-${name}: already running, pid $(cat /run/hostapd-${name}.pid)"
          exit 0
        fi
        ${pkgs.hostapd}/bin/hostapd -B -P /run/hostapd-${name}.pid \
          -S -i "$dev" ${conf name params}

        # country_code makes hostapd wait up to 5s for the channel list update, and -B
        # daemonises there, dropping stdout - so poll the control interface for post-fork state
        state=
        for _ in 1 2 3 4 5 6 7 8 9 10; do
          state=$(${pkgs.hostapd}/bin/hostapd_cli -p /run/hostapd-${name} \
            status 2>/dev/null | sed -n 's/^state=//p' || true)
          if [ "$state" = ENABLED ]; then
            break
          fi
          sleep 1
        done
        echo "wlan-${name}: state=''${state:-none}"
        if [ "$state" = ENABLED ]; then
          ip link set dev "$dev" master "$(cat ${bridge})"
          echo "wlan-${name}: joined $(cat ${bridge})"
        fi
        [ "$state" = ENABLED ]
        ;;
      stop)
        ip link set dev "$dev" nomaster 2>/dev/null || true
        kill "$(cat /run/hostapd-${name}.pid)"
        ;;
      status)
        ${pkgs.iw}/bin/iw dev "$dev" info
        ${pkgs.hostapd}/bin/hostapd_cli -p /run/hostapd-${name} status \
          || echo "wlan-${name}: no hostapd on this radio"
        ;;
    esac
  '';

  bands = {
    "2g" = {
      band = "2412";
      params = {
        ssid = "CHEN";
        hw_mode = "g";
        channel = "6";
      };
    };
    "5g" = {
      band = "5745";
      params = {
        ssid = "CHEN_5g";
        hw_mode = "a";
        channel = "149";
      };
    };
  };
in
{
  imports = [ ../../../modules/wlan.nix ];

  # The blobs, one package per name. How they reach the kernel depends on the
  # image form, which is not this module's business: ./preload-firmware.nix
  # embeds them in a fullSystem image, where preinit loads these drivers
  # before activate has created /lib/firmware, and ./rootfs-firmware.nix puts
  # them under /lib/firmware for a mounted root.
  #
  # regulatory.db is in neither list: modules/wlan.nix installs it under
  # /lib/firmware as an ordinary file. cfg80211 asks for it at late_initcall
  # though, before activate has made that file, so a fullSystem image keeps
  # its own copy in boot.initramfs.preloadFirmware (ax6600-nss-ram.nix).
  options.wireless.firmwareFiles = lib.mkOption {
    type = lib.types.attrsOf lib.types.package;
    internal = true;
    description = ''
      The radio's firmware, one package per name the kernel asks for,
      relative to /lib/firmware.
    '';
  };

  config = {
    kernel.config = {
      # The AHB half of ath11k needs the remoteproc framework; the wcss
      # driver itself comes from the kernel patches.
      REMOTEPROC = "y";
      # wlan.nix builds cfg80211 as a module; this device has wanted it
      # built-in since N4, when the only reason to have it at all was ECM's
      # VAP test reading net_device->ieee80211_ptr (that field exists for
      # With CRDA and signature checks off, regulatory.db is cfg80211's only source of country rules,
      # needed at late_initcall inside initramfs—so CFG80211 must be built-in (=y).
      CFG80211 = lib.mkForce "y";

      # ath11k_peer_rx_frag_setup() allocates a "michael_mic" shash for every
      # peer it adds (dp_rx.c:3189), unconditionally and before the key
      # handling, so without this no station can be added at all:
      #   ath11k: failed to allocate michael_mic shash: -2
      #   ath11k: failed to setup dp for peer <mac> on vdev 0 (-2)
      #   ath11k: Failed to add station: <mac> for VDEV: 0
      # Mainline leaves the symbol at m, and a fullSystem image has no
      # kmodloader: preinit loads exactly the module tree's load-order and
      # request_module() has no /sbin/modprobe to fall back on, so `=m`
      # never loads even though the .ko is carried in the image.
      CRYPTO_MICHAEL_MIC = "y";

      # hostapd opens /dev/rfkill in rfkill_init() and logs "rfkill: Cannot
      # open RFKILL control device" when it is missing. This board has no
      # rfkill switch, so the option is here only to create the device node.
      RFKILL = "y";
    };

    # WLAN gates these: kernel.config is merged first and conditionalConfig
    # only when its key is enabled (modules/kernel/modules-kernel.nix).
    # WLAN itself comes from wlan.nix.
    kernel.conditionalConfig.WLAN = {
      WLAN_VENDOR_ATH = "y";
      ATH_COMMON = "m";
      ATH11K = "m";
      ATH11K_AHB = "m";
      MAC80211 = "m";
      # The brcmfmac/ath10k style conditionals are off, so this is the only
      # wireless driver in the image; debug is on because bringing a Q6 up
      # is what the logs are for.
      ATH11K_DEBUG = "y";

      # ath11k talks to the Q6 over QMI/QRTR, and on IPQ6018 that runs on
      # the SMEM glink edge the WCSS remoteproc declares (channel "IPCRTR"):
      # net/qrtr/smd.c is what bridges that rpmsg device into QRTR. Without
      # either, the Q6 boots and no QMI server ever appears, so ath11k
      # waits forever.
      #
      # The remoteproc itself is QCOM_Q6V5_WCSS_SEC, not mainline's
      # QCOM_Q6V5_WCSS: the Q6 is booted through secure PIL, which is what
      # wireless/SOURCES.nix adds a driver for. The module name that
      # preloadModules asks for follows from this.
      QCOM_Q6V5_WCSS_SEC = "m";
      RPMSG = "y";
      RPMSG_QCOM_GLINK = "y";
      RPMSG_QCOM_GLINK_SMEM = "y";
      QRTR = "y";
      QRTR_SMD = "y";

      # smp2p carries the Q6 start/stop handshake, apcs_glb is the mailbox
      # it signals through, and the tcsr mutex backs SMEM.
      QCOM_SMEM = "y";
      QCOM_SMP2P = "y";
      QCOM_APCS_IPC = "y";
      MAILBOX = "y";
      HWSPINLOCK = "y";
      HWSPINLOCK_QCOM = "y";

      # Secure PIL (qcom_scm_pas_auth_and_reset, PAS id 6) is what the
      # ipq6018 driver data in the wcss patches is configured for.
      QCOM_SCM = "y";
    };

    wireless.firmwareFiles = lib.genAttrs firmwareNames firmwareFile;

    # hostapd is started by hand, so it is a tool here, not a service.
    defaultProfile.packages = [
      pkgs.iw
      pkgs.hostapd
    ]
    ++ lib.mapAttrsToList (name: b: ap name b.band b.params) bands;
  };
}