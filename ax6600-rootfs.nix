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

  # What the WAN link can carry, to clamp the MSS of what the LAN sends it.
  wanMtu = import ./devices/jdcloud-ax6600/wan-mtu.nix;

  # Site firewall policy: rules come from the file named by
  # -I liminix-firewall=<file>, so an image not given one carries no site
  # rules at all. See devices/jdcloud-ax6600/config_firewall.nix.
  # The nixPath lookup is only there to tell "no -I" from "a -I that points
  # nowhere": Nix silently drops a search path entry naming a missing file,
  # so without it a typo would look like a deliberate "no rules". The <...>
  # lookup is what actually resolves a relative entry, the way the search
  # path does.
  siteFirewall =
    let
      entry = lib.findFirst (e: e.prefix == "liminix-firewall") null builtins.nixPath;
      resolved = builtins.tryEval <liminix-firewall>;
    in
    if entry == null then
      { }
    else if !resolved.success then
      throw "liminix-firewall: cannot read ${entry.path}"
    else
      import resolved.value;

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

  # A LAN host sizes its TCP segments from the 1500-byte bridge, but the
  # PPPoE link carries less, so a server's full-size reply is dropped on
  # the way in.  IPv4 recovers from the resulting ICMP frag-needed, IPv6
  # does not, and the connection hangs in the TLS handshake: clamping the
  # MSS in flight stops the servers sending what the WAN cannot carry.
  services.firewall = config.system.service.firewall.build {
    zones = {
      lan = [ config.services.int ];
      wan = [ config.services.wan ];
    };
    extraRules = {
      # The tagged case is the smaller of the two, so clamping to it is
      # right for an untagged WAN as well; MSS is that MTU less the
      # IPv4/TCP (20+20) or IPv6/TCP (40+20) headers.
      mss-ip4 = {
        type = "filter";
        family = "ip";
        hook = "forward";
        priority = "mangle";
        policy = "accept";
        rules = [
          "iifname @lan oifname @wan tcp flags & (syn | rst) == syn tcp option maxseg size set ${toString (wanMtu.tagged - 40)}"
        ];
      };
      mss-ip6 = {
        type = "filter";
        family = "ip6";
        hook = "forward";
        priority = "mangle";
        policy = "accept";
        rules = [
          "iifname @lan oifname @wan tcp flags & (syn | rst) == syn tcp option maxseg size set ${toString (wanMtu.tagged - 60)}"
        ];
      };

      # 默认的 incoming-allowed-ip6 是空链，站点放行规则在这里注入，见
      # siteFirewall：没有 -I liminix-firewall 就是空链。
      incoming-allowed-ip6 = {
        rules = siteFirewall.incomingAllowedIp6 or [ ];
      };
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
