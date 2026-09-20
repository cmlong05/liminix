# Web-uploadable, single-file "full system in initramfs" image for the
# JDCloud AX6600 (RE-CS-02) with the onboard 2.4GHz AHB radio: the wired
# router from ax6600-lan.nix plus the wifi services from ax6600-wifi.nix, on
# one LAN with the 2.5G port as the PPPoE uplink. The QCN9074 5GHz radio is
# off unless `wifi.qcn9074.enable` is set - see ax6600-wifi-ram-5g.nix and
# devices/jdcloud-ax6600/wifi/README.
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

  # cfg80211 asks for regulatory.db from a late_initcall, i.e. as the kernel
  # execs /init - a fraction of a second before `activate` has materialised
  # config.filesystem, which is where modules/wlan.nix puts the file. On
  # hardware that window is real and the load fails:
  #
  #   [3.797394] Run /init as init process
  #   [3.797506] faux_driver regulatory: Direct firmware load for regulatory.db failed with error -2
  #   [4.113637] firmware-ath11k: reading pre-calibration from /dev/mmcblk0p15 (after 0s)
  #
  # and a wireless stack with no regdb leaves this board's QCN9074
  # (supports_regdb = false in core.c) sitting on the world regdomain. Embed
  # the file in the kernel image instead: when the filesystem lookup misses,
  # the firmware loader falls back to the built-in firmware table, so it does
  # not matter that /lib/firmware does not exist yet - or that
  # services.firmware-ath11k later replaces it with a tmpfs. There is no
  # userspace fallback to wait for (the direct load and the failure are 4ms
  # apart on hardware), so "present by the time cfg80211 registers" is the
  # only thing that works.
  #
  # modules/wlan.nix keeps its /lib/firmware copy for the non-ram images,
  # where cfg80211 is a module loaded long after activate. Signed-regdb
  # verification is off (CFG80211_REQUIRE_SIGNED_REGDB = "n"), so
  # regulatory.db is the only file needed; regulatory.db.p7s is never
  # requested.
  regulatoryDb = pkgs.runCommand "ath11k-regulatory-db" { } ''
    mkdir -p $out
    cp ${pkgs.wireless-regdb}/lib/firmware/regulatory.db $out/
  '';
in
{
  imports = [
    ./ax6600-wifi.nix
    ./modules/outputs/initramfs.nix
  ];

  kernel.config = wifiBuiltin // {
    # See regulatoryDb above. EXTRA_FIRMWARE_DIR has to be a directory that
    # holds the named file at its top level. Both are quoted the way kconfig
    # writes string symbols (same reason modules/outputs/initramfs.nix uses
    # builtins.toJSON for INITRAMFS_SOURCE), so the attrset and the built
    # .config agree and the config-consistency check stays quiet.
    EXTRA_FIRMWARE = builtins.toJSON "regulatory.db";
    EXTRA_FIRMWARE_DIR = builtins.toJSON "${regulatoryDb}";
  };
  kernel.conditionalConfig = lib.mkForce { };

  boot = {
    initramfs = {
      enable = true;
      fullSystem = true;
    };
    # No root= / init=: with fullSystem, preinit detects the missing root
    # device and runs the embedded system.
    #
    # NB: on the web-upload path none of this reaches the kernel. The U-Boot
    # web loader at /uimage.html replaces the FIT's bootargs - confirmed on
    # hardware: /chosen/bootargs in the built dtb carries this whole list,
    # but `cat /proc/cmdline` shows only `console=ttyMSM0,115200n8` (which
    # the kernel derives from /chosen/stdout-path). Consequences:
    #   - pcie_aspm=off never applied; ASPM is turned off in the driver
    #     instead, see local patch 971-ath11k-pci-keep-aspm-disabled.patch;
    #   - panic=10/oops=panic never applied, so a hard hang here ends in the
    #     10s APSS watchdog resetting the SoC (silent: this kernel has no
    #     lockup detector built) rather than in a panic;
    #   - loglevel=8 never applied, so ath11k_dbg() output needs dynamic
    #     debug: echo 'module ath11k +p' > /sys/kernel/debug/dynamic_debug/control
    # The list is kept for boot paths that do honour /chosen/bootargs.
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
