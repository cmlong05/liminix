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

  # cfg80211 is built into this kernel and the signed-regdb check defaults
  # on, so it asks for "regulatory.db" *and* the detached "regulatory.db.p7s"
  # (signed by wens, whose cert the kernel carries in net/wireless/certs).
  # The request comes from cfg80211's own late_initcall, before activate
  # creates /lib/firmware, so both files ride in the image. Plain, not .zst:
  # this kernel has FW_LOADER_COMPRESS_XZ but not _ZSTD.
  regdb = name: pkgs.pkgsBuildBuild.runCommand name { } ''
    install -m 0644 ${pkgs.pkgsBuildBuild.wireless-regdb}/lib/firmware/${name} $out
  '';

  # The one module tree the image carries: conntrack (from the kernel's own
  # modulesupport) first, then SSDK, nss-dp, nss-drv, qca-nss-pppoe and ecm.
  # One tree because `pkgs/liminix-tools/modules` derives the load order
  # from `depmod` across all the roots at once; splitting it would mean
  # guessing an order by hand.
  #
  # `load-order` comes from `targets` (closed over their dependencies) and
  # is what preinit loads. The roots only decide what is available and what
  # gets shipped, and the initramfs carries more than the load-order - see
  # BRINGUP D.11.
  moduleTree = pkgs.liminix.modules.build pkgs {
    roots = [
      config.kernel.modulesKernel.modulesupport
      nss.qca-ssdk
      nss.qca-nss-dp
      nss.qca-nss-drv
      nss.nss-clients
      nss.qca-nss-ecm
    ];
    targets = [
      "nf_conntrack"
      "nf_defrag_ipv4"
      "nf_defrag_ipv6"
      "nf_nat"
      # ECM's classifier reads the conntrack DSCPREMARK extension, the
      # kernel's xt_DSCP target writes it. Without these two targets they
      # ship but never load, so the extension stays zero and those
      # connections are never offloaded.
      "xt_DSCP"
      "xt_dscp"
      "qca-ssdk"
      "qca-nss-dp"
      "qca-nss-drv"
      "qca-nss-pppoe"
      "ecm"
    ];
  };
in
{
  imports = [
    ./ax6600-lan.nix
    ./modules/early
    ./modules/outputs/initramfs.nix
  ];

  boot = {
    initramfs = {
      enable = true;
      fullSystem = true;
      preloadModules = moduleTree;
      # nss-drv asks the kernel for "qca-nss0.bin" while preinit is still
      # loading modules, which is before activate creates /lib/firmware,
      # so the blob is embedded in the image rather than put in the
      # filesystem (see boot.initramfs.preloadFirmware).
      preloadFirmware = {
        "qca-nss0.bin" = nss.nss-firmware;
        "regulatory.db" = regdb "regulatory.db";
        "regulatory.db.p7s" = regdb "regulatory.db.p7s";
      };
    };
    commandLine = lib.mkForce [
      "panic=10 oops=panic loglevel=8"
      "console=ttyMSM0,115200n8"
      "fw_devlink=off"
      # nr_cpus=1 was a bring-up workaround and has been stale since N2. It
      # also has to go for N4 to be measurable: on one core the software
      # path is core-bound, and NSS IRQ affinity needs the CPUs. If the
      # board stops reaching userspace, putting it back is the first thing
      # to try.
      "nokaslr"
      # nokaslr stays: second line of defence behind RANDOMIZE_BASE=n, and
      # free at runtime.
    ];
    imageFormat = "fit";
  };

  hardware.defaultOutput = "uimage";

  # (N4) ECM's sysctls: modules/early writes them into /etc/sysctl.sh, which
  # rc.init runs once /proc is mounted. nf_conntrack_tcp_no_window_check is
  # added by 0600-1, ECM assumes it, and its default is 0; the other two are
  # OpenWrt's tuning.
  early.sysctl.net.netfilter = {
    nf_conntrack_tcp_no_window_check = 1;
    nf_conntrack_max = 65535;
    nf_conntrack_events = 1;
  };
}
