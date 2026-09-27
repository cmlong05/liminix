# eMMC image: 
#   outputs.uimage  (kernel + dtb, cmdline embedded)  -> partition 0:HLOS
#   outputs.rootfs  (squashfs)                        -> partition rootfs
#

{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.liminix.services) oneshot;
  inherit (pkgs.pseudofile) dir symlink;

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

  firewall.kernelModules = config.services.modules;

  filesystem = dir {
    lib = dir {
      firmware = dir {
        "qca-nss0.bin" = symlink "${nss.nss-firmware}";
      };
    };
  };

  services.netfilter-sysctls = oneshot {
    name = "netfilter-sysctls";
    dependencies = [ config.services.modules ];
    up = ''
      echo 1 > /proc/sys/net/netfilter/nf_conntrack_tcp_no_window_check
      echo 65535 > /proc/sys/net/netfilter/nf_conntrack_max
      echo 1 > /proc/sys/net/netfilter/nf_conntrack_events
    '';
  };

  services.firewall = config.system.service.firewall.build {
    zones = {
      lan = [ config.services.int ];
      wan = [ config.services.wan ];
    };
  };

  hardware.rootDevice = "PARTLABEL=rootfs";
  rootfsType = "squashfs";

  boot = {
    imageFormat = "fit";
    commandLine = lib.mkForce [
      "panic=10 oops=panic loglevel=8"
      "console=ttyMSM0,115200n8"
      "fw_devlink=off"
      "nokaslr"
      "root=${config.hardware.rootDevice}"
      "rootfstype=${config.rootfsType}"
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
