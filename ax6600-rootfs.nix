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

  moduleFiles = [
    nss.qca-ssdk
    nss.qca-nss-dp
    nss.qca-nss-drv
    nss.nss-clients
    nss.qca-nss-ecm
  ];

  moduleTargets =
    (import ./devices/jdcloud-ax6600/nss/targets.nix).all ++ config.firewall.kernelModuleTargets;

  # The same tree pkgs/kmodloader builds for the service, asked for here as
  # well so the init phase can load it (see etc/rc-init.d/modules below).
  moduleTree = pkgs.liminix.modules.build pkgs {
    roots = [ config.system.outputs.kernel.modulesupport ] ++ moduleFiles;
    targets = moduleTargets;
  };
in
{
  imports = [
    ./ax6600-lan.nix
    ./modules/early
    ./modules/firewall
    ./devices/jdcloud-ax6600/wireless
    ./devices/jdcloud-ax6600/wireless/rootfs-firmware.nix
    ./devices/jdcloud-ax6600/art.nix
  ];

  services.modules = pkgs.kmodloader.override {
    inherit (config.system.outputs) kernel;
    modules = moduleFiles;
    targets = moduleTargets;
  };

  firewall.kernelModules = config.services.modules;

  filesystem = dir {
    etc = dir {
      "rc-init.d" = dir {
        # Load the module tree from the init phase as well as from the
        # kmodloader service: that service's output goes to the s6 logger,
        # where a failure is invisible, whereas this runs with the root
        # already mounted and /lib/firmware readable, before s6-rc, and
        # prints to the console.
        modules = symlink (
          pkgs.writeAshScript "load-modules" { } ''
            echo "loading kernel modules from ${moduleTree}"
            O=${moduleTree}/lib/modules sh ${moduleTree}/lib/modules/load.sh
          ''
        );
      };
    };
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
    commandLine = lib.mkForce (
      [
        "panic=10 oops=panic loglevel=8"
        "console=ttyMSM0,115200n8"
        "fw_devlink=off"
        "nokaslr"
        "root=${config.hardware.rootDevice}"
        "rootfstype=${config.rootfsType}"
        "rootwait"
        "init=/bin/init"
      ]
      # With the root mounted by the kernel there is no initramfs, so
      # nothing remounts it: without this the root stays read-only.
      ++ lib.optional (config.rootfsType == "ext4") "rw"
    );
  };

  kernel.config = {
    CMDLINE = lib.mkForce "\"${lib.concatStringsSep " " config.boot.commandLine}\"";
    CMDLINE_FROM_BOOTLOADER = lib.mkForce "n";
    CMDLINE_FORCE = "y";
    # s6-linux-init mounts devtmpfs on /dev itself: if the kernel got
    # there first (DEVTMPFS_MOUNT=y) it dies with EBUSY and panics.
    DEVTMPFS_MOUNT = lib.mkForce "n";
  };
}
