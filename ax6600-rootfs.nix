# eMMC image: the kernel and the rootfs are two separate artifacts written
# into two existing GPT partitions, instead of one self-contained fullSystem
# image:
#
#   outputs.uimage  (kernel + dtb, cmdline embedded)  -> partition 0:HLOS
#   outputs.rootfs  (squashfs)                        -> partition rootfs
#
# Two things follow from the kernel no longer embedding a rootdir:
#
#   * modules are loaded by an ordinary pkgs/kmodloader service instead of
#     by preinit - which is only possible here, because a kmodloader needs
#     kernel.modulesupport and a fullSystem image would put that same kernel
#     inside the rootdir it embeds (see pkgs/liminix-tools/modules);
#   * modules/firewall is usable for the same reason, so NAT and the default
#     gateway ruleset come from there instead of from the hand-written nft
#     rule ax6600-nss-ram.nix has to use.
#
# The AHB radio is here too: devices/jdcloud-ax6600/wireless brings in the
# drivers and the hostapd tooling, and its ./rootfs-firmware.nix module puts
# the blobs under /lib/firmware (the fullSystem images import its
# ./preload-firmware.nix instead, because preinit runs before activate has
# created that directory). The radios are not started at boot - BRINGUP N5
# asks for wlan-2g / wlan-5g to be run by hand.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.liminix.services) oneshot;
  inherit (pkgs.pseudofile) dir symlink;

  # Built against the real kernel: nothing embeds a rootdir here, so there
  # is no cycle and no need for the initramfs-less twin.
  nss = import ./devices/jdcloud-ax6600/nss {
    inherit pkgs;
    kernel = config.system.outputs.kernel;
    inherit (config.kernel) version;
  };
in
{
  imports = [
    ./ax6600-lan.nix
    ./modules/early
    ./modules/firewall
    ./devices/jdcloud-ax6600/wireless
    ./devices/jdcloud-ax6600/wireless/rootfs-firmware.nix
  ];

  # The image's only module tree: `all` is `wired ++ wireless` (see
  # targets.nix), and the nft set comes from modules/firewall's own list
  # rather than from a second kmodloader, which would insmod the same
  # nf_conntrack/nf_nat (see firewall.kernelModules below) and put a second
  # copy of the kernel's modules in the image.
  services.modules = pkgs.kmodloader.override {
    inherit (config.system.outputs) kernel;
    modules = [
      nss.qca-ssdk
      nss.qca-nss-dp
      nss.qca-nss-drv
      nss.nss-clients
      nss.qca-nss-ecm
    ];
    targets = (import ./devices/jdcloud-ax6600/nss/targets.nix).all ++ config.firewall.kernelModuleTargets;
  };

  # ... so the firewall depends on that tree instead of building one.
  firewall.kernelModules = config.services.modules;

  # nss-drv asks for this while it probes, so it has to be on disk before
  # services.modules insmods it: an ordinary /lib/firmware file, not the
  # embedded one a fullSystem image needs.
  filesystem = dir {
    lib = dir {
      firmware = dir {
        "qca-nss0.bin" = symlink "${nss.nss-firmware}";
      };
    };
  };

  # The conntrack sysctls ECM assumes. They cannot go through early.sysctl
  # here the way ax6600-nss-ram.nix does: rc.init runs /etc/sysctl.sh before
  # s6 starts, and nf_conntrack is now a module that services.modules loads
  # afterwards - the write would hit a missing file.
  services.netfilter-sysctls = oneshot {
    name = "netfilter-sysctls";
    dependencies = [ config.services.modules ];
    up = ''
      echo 1 > /proc/sys/net/netfilter/nf_conntrack_tcp_no_window_check
      echo 65535 > /proc/sys/net/netfilter/nf_conntrack_max
      echo 1 > /proc/sys/net/netfilter/nf_conntrack_events
    '';
  };

  # masquerade on @wan plus the module's default gateway ruleset.
  services.firewall = config.system.service.firewall.build {
    zones = {
      lan = [ config.services.int ];
      wan = [ config.services.wan ];
    };
  };

  hardware.rootDevice = "PARTLABEL=rootfs";
  rootfsType = "squashfs";

  # root= and init= are spelled out because this force-overrides the list
  # modules/base.nix builds them into - an initramfs image does not need
  # them, a rootfs image does. root= reads hardware.rootDevice rather than
  # repeating the partition name, so a composition that points the same
  # image at other media (ax6600-usb.nix) only has to override that option.
  boot = {
    imageFormat = "fit";
    commandLine = lib.mkForce [
      "panic=10 oops=panic loglevel=8"
      "console=ttyMSM0,115200n8"
      "fw_devlink=off"
      "nokaslr"
      "root=${config.hardware.rootDevice}"
      "rootfstype=squashfs"
      "rootwait"
      "init=/bin/init"
    ];
  };

  kernel.config = {
    CMDLINE = lib.mkForce "\"${lib.concatStringsSep " " config.boot.commandLine}\"";
    CMDLINE_FROM_BOOTLOADER = lib.mkForce "n";
    CMDLINE_FORCE = "y";
    DEVTMPFS_MOUNT = lib.mkForce "n";
  };
}
