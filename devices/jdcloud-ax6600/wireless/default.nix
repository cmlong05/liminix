# N5 phase 1: the IPQ6010's own (AHB) radio - the 2.4 GHz and 5.8 GHz
# pdevs of wifi@c000000 - driven by ath11k.
#
## What is here:
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
#   * a hostapd AP per band, an ordinary s6 longrun service: ssid,
#     passphrase and channel come from the deployment and can be changed
#     at run time via /persist/config.json. Encryption is the exception -
#     each band names its own mode, read at build time only through
#     `bandSecurity`, see `securityModes` below.
#
# wlan0 is the 2.4 GHz pdev and wlan1 the 5.8 GHz one; `link` waits for
# each netdev with ifwait, so ath11k registering them asynchronously
# after the Q6 boots is not a problem.
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
  inherit (pkgs.liminix) outputRef;

  svc = config.system.service;

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
  # per-unit calibration ath11k builds out of the bus and device name.
  # ./rootfs-firmware.nix indexes firmwarePkg with this list, so a name that is
  # not in the tree fails its build instead of shipping a dangling file.
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
  ];

  # --- deployment ---------------------------------------------------
  #
  # The AP values are not read here at all: ax6600-lan.nix seeds the
  # deployment into /persist/config.json and publishes it as a service
  # output tree, and the hostapd services below read ssid, passphrase
  # and channel out of that tree. Only the build-time autostart switch
  # is read directly.
  deployment =
    let
      lookup = builtins.tryEval <liminix-deployment>;
    in
    if lookup.success && builtins.pathExists (toString lookup.value) then
      import lookup.value
    else
      import ../config.nix;

  runtime = config.services.runtime-config;
  wifiAutostart = (deployment.wifi or { }).autostart or true;

  # Which AHB pdev serves which band, by the netdev name ath11k gives it:
  # wlan0 is the 2.4 GHz pdev, wlan1 the 5.8 GHz one. Nothing in sysfs
  # tells the two apart - both hang off the one AHB phy - so these names
  # are what the services below are addressed by.
  bands = {
    "24g" = "wlan24g";
    "58g" = "wlan58g";
  };

  # Encryption, build-time only: modules/hostapd turns `params` into a
  # static config file, so there is no way to leave a line out at run time
  # and hence one entry per mode rather than independent knobs.
  # Every band names its own mode; there is no wifi-wide default.
  # wpa2-wpa3 needs hostapd built with CONFIG_SAE.
  securityModes =
    {
      wpa2 = {
        auth_algs = 1;
        wpa = 2;
        wpa_key_mgmt = "WPA-PSK";
        wpa_pairwise = "CCMP";
        rsn_pairwise = "CCMP";
      };
      wpa2-wpa3 = {
        auth_algs = 1;
        wpa = 2;
        wpa_key_mgmt = "WPA-PSK SAE";
        wpa_pairwise = "CCMP";
        rsn_pairwise = "CCMP";
        # PMF optional: WPA3 stations use it, WPA2-only ones still associate
        ieee80211w = 1;
      };
      open = {
        auth_algs = 1;
      };
    };
  bandConf = name: (deployment.wifi.bands or { }).${name} or { };
  bandSecurity =
    name:
    if (bandConf name) ? security then
      (bandConf name).security
    else
      throw "wifi.bands.${name}.security: every band needs its own encryption mode";
  securityFor =
    name:
    securityModes.${bandSecurity name}
    or (throw "wifi.bands.${name}.security: expected wpa2, wpa2-wpa3 or open, got ${bandSecurity name}");

  # There is no wifi-wide passphrase either: each band names its own, and
  # this fails at build time rather than leaving hostapd to read an empty
  # file. The value itself is still read at run time, from the path below.
  bandPasswordPath =
    name:
    if (bandConf name) ? password then
      "wifi/bands/${name}/password"
    else
      throw "wifi.bands.${name}.password: every band needs its own passphrase";
in
{
  imports = [
    ../../../modules/wlan.nix
    ../../../modules/hostapd
  ];

  # The blobs, one package per name. How they reach the kernel is
  # ./rootfs-firmware.nix's business: it puts them under /lib/firmware for a
  # mounted root.
  #
  # regulatory.db is not here: modules/wlan.nix installs it under /lib/firmware
  # as an ordinary file.
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
      # A module, not built-in: the mounted-root shapes load it from the
      # kmodloader once /lib/firmware is on disk, where modules/wlan.nix puts
      # regulatory.db. Built-in it asks for that file at late_initcall, before
      # the kernel mounts the root, and the failure sticks.
      CFG80211 = lib.mkForce "m";

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

    # The AHB netdevs
    # These are the names art-apply renames the AHB radios 
    hardware.networkInterfaces = {
      wlan24g = svc.network.link.build {
        ifname = "wlan24g";
        dependencies = [ config.services.art-apply ];
      };
      wlan58g = svc.network.link.build {
        ifname = "wlan58g";
        dependencies = [ config.services.art-apply ];
      };
    };

    # Unless wifi.autostart is false, one hostapd per band: a longrun
    # service s6 starts at boot. ssid/passphrase/channel come from the
    # runtime-config tree; modules/hostapd's secrets subscriber makes
    # that service a dependency and restarts hostapd when it changes.
    # Encryption comes from the per-band `securityFor` instead, see above.
    services = lib.optionalAttrs wifiAutostart (lib.mapAttrs' (
      name: netif:
      lib.nameValuePair "hostap-${name}" (svc.hostapd.build {
        interface = config.hardware.networkInterfaces.${netif};
        params =
          {
            ssid = outputRef runtime "wifi/bands/${name}/ssid";
            country_code = outputRef runtime "wifi/countryCode";
            hw_mode = outputRef runtime "wifi/bands/${name}/hw_mode";
            channel = outputRef runtime "wifi/bands/${name}/channel";
            wmm_enabled = 1;
            ieee80211n = 1;
          }
          // securityFor name
          // lib.optionalAttrs (bandSecurity name != "open") {
            wpa_passphrase = outputRef runtime (bandPasswordPath name);
          };
      })
    ) bands);

    # iw/hostapd stay on the login PATH for debugging.
    defaultProfile.packages = [
      pkgs.iw
      pkgs.hostapd
    ];
  };
}