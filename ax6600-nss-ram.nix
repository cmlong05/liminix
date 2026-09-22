# Web-uploadable single-file image for the JDCloud AX6600 with the NSS
# wired path (BRINGUP.md N2, N3).
#
# The ethernet driver stack is QSDK's, not the kernel's: qca-ssdk drives
# the ESS switch and its UNIPHY/PCS instances, qca-nss-dp provides the
# netdevs, and qca-nss-drv brings the NSS core up. None is in the kernel
# tree, so they build as out-of-tree modules
# (devices/jdcloud-ax6600/nss) and `preinit` loads them before it starts
# s6 - see boot.initramfs.preloadModules for why that, and not the
# kmodloader service, is what a fullSystem image can do. The NSS firmware
# travels in the same image, for the same reason: see
# boot.initramfs.preloadFirmware.
#
# Build with:
#   nix-build --arg device "import ./devices/jdcloud-ax6600" \
#     -I liminix-config=./ax6600-nss-ram.nix -A outputs.uimage -o result-nss-lan-ram
# then upload result-nss-lan-ram via http://192.168.1.1/uimage.html
# (the name md5_result.sh expects; `result-nss-ram` in the BRINGUP plan
# was never the one used, so the plan text was corrected to match).
#
# Success indicators, in the order they should appear:
#   dmesg | grep -iE 'ssdk|ess-switch|nss-dp|nss|qca8075|qca8081'
#   ip link                 -> lan1..lan4 and wan
#   cat /sys/class/net/wan/speed   -> 2500
#   a PC on lan1 gets a DHCP lease on the deployment's LAN subnet
# For N3 also: "NSS fw version: NSS.FW.12.5-210-CP.R" and "NSS core 0
# booted successfully" in dmesg, /proc/sys/dev/nss/ populated, and
# /sys/kernel/debug/qca-nss-drv/ after `mount -t debugfs none
# /sys/kernel/debug` (Liminix does not mount debugfs).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # The module packages are built against the initramfs-less twin of the
  # kernel (config.kernel.modulesKernel), not the real one: this image
  # carries the modules inside the kernel image, and the real kernel's
  # INITRAMFS_SOURCE is this very image, so building them against it would
  # be a cycle. Nothing differs between the two kernels except
  # INITRAMFS_SOURCE, which no exported symbol depends on.
  nss = import ./devices/jdcloud-ax6600/nss {
    inherit pkgs;
    kernel = config.kernel.modulesKernel;
    inherit (config.kernel) version;
  };

  # The NSS stack, in the order it must load: SSDK drives the switch and
  # its PCS instances, nss-dp provides the netdevs on the EDMA rings, and
  # nss-drv brings the NSS core up underneath them. The kernel's own
  # modulesupport is deliberately not a root here: these are self-contained
  # (each one's only unresolved symbols are the previous one's), so the
  # initramfs carries 3 modules instead of the whole kernel module set.
  nssTree = pkgs.liminix.modules.build pkgs {
    roots = [
      nss.qca-ssdk
      nss.qca-nss-dp
      nss.qca-nss-drv
    ];
    targets = [
      "qca-ssdk"
      "qca-nss-dp"
      "qca-nss-drv"
    ];
  };
in
{
  imports = [
    ./ax6600-lan.nix
    ./modules/outputs/initramfs.nix
  ];

  boot = {
    initramfs = {
      enable = true;
      fullSystem = true;
      preloadModules = nssTree;
      # nss-drv asks the kernel for "qca-nss0.bin" while preinit is still
      # loading modules, which is before activate creates /lib/firmware,
      # so the blob is embedded in the image rather than put in the
      # filesystem (see boot.initramfs.preloadFirmware).
      preloadFirmware = {
        "qca-nss0.bin" = nss.nss-firmware;
      };
    };
    commandLine = lib.mkForce [
      "panic=10 oops=panic loglevel=8"
      "console=ttyMSM0,115200n8"
      "fw_devlink=off"
      "nr_cpus=1"
      "nokaslr"
    ];
    imageFormat = "fit";
  };

  hardware.defaultOutput = "uimage";
}
