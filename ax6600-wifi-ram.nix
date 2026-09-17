# Web-uploadable, single-file "full system in initramfs" image for the
# JDCloud AX6600 (RE-CS-02) with both radios: the wired router from
# ax6600-lan.nix plus the wifi services from ax6600-wifi.nix, on one LAN
# with the 2.5G port as the PPPoE uplink.
#
# Build with:
#   nix-build --arg device "import ./devices/jdcloud-ax6600" \
#     -I liminix-config=./ax6600-wifi-ram.nix -A outputs.uimage -o result-wifi
# then upload result-wifi via /uimage.html on http://192.168.1.1.
#
# Why the drivers are built in. ath11k is a module in the reference build, but
# a full-system initramfs image cannot load modules: kmodloader would have to
# load them from config.system.outputs.kernel, which is the very derivation
# this image is being embedded into. So the whole wireless stack is =y here.
#
# That in turn is why ax6600-wifi.nix brings the radios up from userspace:
# with the drivers built in, a probe during kernel init would happen before
# the firmware service has staged the firmware or read this board's
# calibration out of the eMMC ART partition. Driver patch 999 makes both
# probes return early, and services.ath11k-probe attaches the devices after
# services.firmware-ath11k has run - the ordering ImmortalWrt gets from
# loading ath11k as a module about 28 seconds in.
#
# Nothing about the board's calibration is baked into this image; it stays in
# the ART partition and is read at every boot.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  sources = import ./devices/jdcloud-ax6600/SOURCES.nix;
  wifi = sources.wifi;

  # modules/wlan.nix sets the wireless stack to =m. A full-system ram image
  # needs it all built in, so every module-form symbol is forced to "y" and
  # the device's conditional block (which would re-apply the =m values, since
  # WLAN = "y" is what arms it) is disabled.
  wifiBuiltin =
    lib.mapAttrs (_: v: lib.mkForce (if v == "m" then "y" else v))
      (wifi.kconfig.infra // wifi.kconfig.wlan)
    // {
      CFG80211 = lib.mkForce "y";
      MAC80211 = lib.mkForce "y";
    };
in
{
  imports = [
    ./ax6600-wifi.nix
    ./modules/outputs/initramfs.nix
  ];

  kernel.config = wifiBuiltin;
  kernel.conditionalConfig = lib.mkForce { };

  boot = {
    initramfs = {
      enable = true;
      fullSystem = true;
    };
    # No root= / init=: with fullSystem, preinit detects the missing root
    # device and runs the embedded system. pcie_aspm=off because the QCN9074
    # was seen to RDDM intermittently during its QMI handshake, with PCIe
    # ASPM gating the refclk as the suspect.
    #
    # NB: the U-Boot web loader at /uimage.html overwrites the FIT's
    # bootargs with its own, so these may not reach the kernel on a web
    # upload (panic=10 and the loglevel certainly do not matter there).
    commandLine = lib.mkForce [
      "panic=10 oops=panic loglevel=8"
      "console=ttyMSM0,115200n8"
      "pcie_aspm=off"
      "fw_devlink=off"
      "nokaslr"
    ];
    imageFormat = "fit";
  };

  hardware.defaultOutput = "uimage";
}
