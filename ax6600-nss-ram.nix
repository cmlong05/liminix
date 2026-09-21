# Web-uploadable single-file image for the JDCloud AX6600 with the NSS
# wired path (BRINGUP.md N2).
#
# The ethernet driver stack is QSDK's, not the kernel's: qca-ssdk drives
# the ESS switch and its UNIPHY/PCS instances, qca-nss-dp provides the
# netdevs. Neither is in the kernel tree, so they build as out-of-tree
# modules (devices/jdcloud-ax6600/nss) and `preinit` loads them before it
# starts s6 - see boot.initramfs.preloadModules for why that, and not the
# kmodloader service, is what a fullSystem image can do.
#
# Build with:
#   nix-build --arg device "import ./devices/jdcloud-ax6600" \
#     -I liminix-config=./ax6600-nss-ram.nix -A outputs.uimage -o result-nss-ram
# then upload result-nss-ram via http://192.168.1.1/uimage.html.
#
# Success indicators, in the order they should appear:
#   dmesg | grep -iE 'ssdk|ess-switch|nss-dp|qca8075|qca8081'
#   ip link                 -> lan1..lan4 and wan
#   cat /sys/class/net/wan/speed   -> 2500
#   a PC on lan1 gets a DHCP lease on the deployment's LAN subnet
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

  # Only what N2 needs. The kernel's own modulesupport is deliberately not
  # a root here: these two are self-contained (nss-dp is the only consumer
  # of the symbols qca-ssdk exports), so the initramfs carries 2 modules
  # instead of the whole kernel module set.
  nssTree = pkgs.liminix.modules.build pkgs {
    roots = [
      nss.qca-ssdk
      nss.qca-nss-dp
    ];
    targets = [
      "qca-ssdk"
      "qca-nss-dp"
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
