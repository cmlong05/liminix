# Wired-LAN configuration for JDCloud AX6600 (RE-CS-02) exercising the
# phase-E ethernet: the four DSA LAN ports lan1..lan4 (QCA8075 via the
# in-tree ESS/PPE/EDMA stack) bridged into "int" at the address and
# with the DHCP pool given by devices/jdcloud-ax6600/config.nix, and the
# 2.5G "wan" port as a PPPoE client uplink (the account comes from the
# same deployment file).
#
# WIRED-ONLY / NO-WIFI build: there is no wireless interface, no ath11k
# module and no radio in the device tree. The only network transport is
# this wired bridge plus the WAN uplink, which is all this variant
# needs. (The ax6600 branch carries the radio bring-up image.)
#
# These services are built through ax6600-lan-ram.nix, which wraps them
# in the single-file full-system ram image:
#   nix-build --arg device "import ./devices/jdcloud-ax6600" \
#     -I liminix-config=./ax6600-lan-ram.nix -A outputs.uimage -o result-lan-ram
#
# Success indicators: dmesg shows the ppe/edma/uniphy probes and
# "lan1..lan4, wan" netdevs; "ip link" lists them; plugging a PC into
# lan1 gets a DHCP lease on the deployment's LAN subnet.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  svc = config.system.service;
  nifs = config.hardware.networkInterfaces;
  inherit (pkgs.liminix.services) oneshot;
  inherit (pkgs.pseudofile) dir symlink;

  # Which network this image serves. The values are plain data in
  # ./devices/jdcloud-ax6600/config.nix. By default we build for the
  # network the board is currently deployed on; to build the same system
  # for a different one, choose its file with the same -I idiom already
  # used for the configuration:
  #
  #   -I liminix-deployment=./devices/jdcloud-ax6600/config-lab.nix
  #
  # An unset -I is not an error (the angle-bracket lookup is what
  # fails), but a values file that exists and does not evaluate must
  # not fall back silently to the default network: hence the two steps -
  # tryEval only survives the missing -I, pathExists decides, and the
  # file itself is then imported without any error suppression.
  deployment =
    let
      lookup = builtins.tryEval <liminix-deployment>;
    in
    if lookup.success && builtins.pathExists (toString lookup.value) then
      import lookup.value
    else
      import ./devices/jdcloud-ax6600/config.nix;
in
{
  imports = [
    ./ax6600-dev.nix
    ./modules/network
    ./modules/dnsmasq
    ./modules/bridge
    ./modules/ppp
    ./modules/ssh
  ];

  hostname = lib.mkDefault deployment.hostname;

  services.int = svc.bridge.primary.build {
    ifname = "int";
  };

  services.bridge = svc.bridge.members.build {
    primary = config.services.int;
    members = [
      nifs.lan1
      nifs.lan2
      nifs.lan3
      nifs.lan4
    ];
  };

  services.int-address = svc.network.address.build {
    interface = config.services.int;
    family = "inet";
    inherit (deployment.lan) address prefixLength;
  };

  # LAN clients' resolver, and the router's own. Both read /run/resolv.conf:
  # the file is written by services.resolvconf below from the resolvers the
  # ISP hands back over IPCP, so changing ISP needs no configuration here.
  # dnsmasq is given the path rather than the service on purpose - see
  # resolvFile in modules/dnsmasq/default.nix for why a service's output
  # directory cannot be used.
  services.dhcpv4 = svc.dnsmasq.build {
    interface = config.services.int;
    domain = "lan";
    ranges = lib.optional (deployment.lan.dhcpRange != null) deployment.lan.dhcpRange;
    resolvFile = "/run/resolv.conf";
  };

  # 2.5G WAN as a PPPoE client. The service creates its own interface
  # (the "wan" netdev is only the ethernet port the session runs over),
  # and exposes address / peer-address / ns1 / ns2 / ipv6-* as outputs,
  # so the default route is taken `via` the negotiated local address
  # rather than from a DHCP lease. If the uplink never gets carrier the
  # session just sits there retrying; `debug = true` here (and
  # `ppp-options = [ ... ]`) is what to reach for when diagnosing it.
  services.wan = svc.pppoe.build {
    interface = nifs.wan;
    username = deployment.wan.pppoe.username;
    password = deployment.wan.pppoe.password;
  };
  services.defaultroute4 = svc.network.route.build {
    via = "$(output ${config.services.wan} address)";
    target = "default";
    dependencies = [ config.services.wan ];
  };

  # The ISP's resolvers arrive as the wan service's ns1/ns2 outputs. They are
  # written to a fixed /run path rather than to this service's own output
  # directory because dnsmasq requires the *directory* of its --resolv-file
  # to exist when it starts, and this service only runs once PPPoE is up.
  services.resolvconf = oneshot {
    dependencies = [ config.services.wan ];
    name = "resolvconf";
    up = ''
      ( echo "nameserver $(output ${config.services.wan} ns1)"
        echo "nameserver $(output ${config.services.wan} ns2)"
      ) > /run/resolv.conf
      chmod 0444 /run/resolv.conf
    '';
  };

  filesystem = dir {
    etc = dir {
      "resolv.conf" = symlink "/run/resolv.conf";
    };
  };

  # Without this a client that has a lease still cannot be routed: the
  # kernel's forwarding switch is off by default.
  services.packet_forwarding = svc.network.forward.build {
    enableIPv4 = true;
    enableIPv6 = false;
  };

  # Source NAT for LAN traffic leaving the PPPoE session.
  #
  # This is hand-written because modules/firewall cannot be used in a
  # fullSystem image: its build always depends on a kmodloader service, and
  # a kmodloader service cannot exist there (pkgs/liminix-tools/modules).
  # The nftables modules it needs are loaded by preinit from
  # ax6600-nss-ram.nix's moduleTree instead.
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

  services.sshd = svc.ssh.build { };

  # NB: the ax6600 branch pulls in `iw` here for radio diagnostics.
  # This is a wired-only build with no wireless stack at all, so no
  # wifi tooling is installed.
  defaultProfile.packages = with pkgs; [ iperf3 ];
}
