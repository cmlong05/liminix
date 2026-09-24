# Web-uploadable single-file image  with NSS

{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.liminix.services) oneshot;

  # Shared with ax6600-rootfs.nix - see that file for the other half.
  targets = import ./devices/jdcloud-ax6600/nss/targets.nix;

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
    # The masquerade services.nat (below) writes by hand needs these three;
    # the rootfs image gets them from modules/firewall's own kmodloader.
    targets = targets ++ [
      "nft_chain_nat"
      "nft_nat"
      "nft_masq"
    ];
  };
in
{
  imports = [
    ./ax6600-lan.nix
    ./modules/early
    ./modules/outputs/initramfs.nix
    ./devices/jdcloud-ax6600/wireless
  ];

  # Source NAT for LAN traffic leaving the PPPoE session. Hand-written here
  # because modules/firewall cannot be used in a fullSystem image: its build
  # always depends on a kmodloader service, and a kmodloader service cannot
  # exist there (pkgs/liminix-tools/modules) - the nftables modules come
  # from moduleTree above instead. ax6600-rootfs.nix uses the module.
  services.nat = oneshot {
    name = "nat";
    dependencies = [ config.services.wan ];
    up = ''
      wan=$(output ${config.services.wan} ifname)
      ${pkgs.nftables}/bin/nft add table ip nat
      ${pkgs.nftables}/bin/nft add chain ip nat postrouting \
        '{ type nat hook postrouting priority 100 ; }'
      ${pkgs.nftables}/bin/nft add rule ip nat postrouting \
        oifname "$wan" masquerade
    '';
    down = "${pkgs.nftables}/bin/nft delete table ip nat";
  };

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

    imageFormat = "fit";
  };

  hardware.defaultOutput = "uimage";

  kernel.config = {
    NF_TABLES_IPV4 = "y";
    NFT_NAT = "m";
    NFT_MASQ = "m";
  };

  early.sysctl.net.netfilter = {
    nf_conntrack_tcp_no_window_check = 1;
    nf_conntrack_max = 65535;
    nf_conntrack_events = 1;
  };
}
