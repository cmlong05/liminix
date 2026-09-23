# Web-uploadable single-file image for the JDCloud AX6600 with the NSS
# wired path (BRINGUP.md).
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
      # N5: the AHB radio. The WCSS remoteproc must be registered before
      # ath11k_ahb probes (the wifi node's qcom,rproc phandle resolves
      # then); depmod sorts that out from the order of these two. The
      # driver is the secure-PIL one, not mainline's qcom_q6v5_wcss.
      "qcom_q6v5_wcss_sec"
      "ath11k_ahb"
    ];
  };
in
{
  imports = [
    ./ax6600-lan.nix
    ./modules/early
    ./modules/outputs/initramfs.nix
    # N5: the IPQ6010's own radio. Inside the image, not a service: this
    # builds a fullSystem image, and its modules are loaded by preinit
    # (boot.initramfs.preloadModules), which is also why the firmware the
    # Q6 asks for is embedded rather than left in /lib/firmware.
    ./devices/jdcloud-ax6600/wireless
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
