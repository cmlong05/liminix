# Wired-LAN configuration base for JDCloud AX6600 (RE-CS-02)
#
# WIRED-ONLY / NO-WIFI build: there is no wireless interface, no ath11k
# module and no radio in the device tree. The only network transport is
# this wired bridge plus the WAN uplink, which is all this variant
# needs. (The ax6600 branch carries the radio bring-up image.)

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

  # Which network this image serves
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

  # 2.5G WAN as a PPPoE client
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

  # The ISP's resolvers arrive as the wan service's ns1/ns2 outputs, and
  # deployment.wan.extraResolvers is appended to them
  services.resolvconf = oneshot {
    dependencies = [ config.services.wan ];
    name = "resolvconf";
    up = ''
      (
        echo "nameserver $(output ${config.services.wan} ns1)"
        echo "nameserver $(output ${config.services.wan} ns2)"
        ${lib.concatMapStringsSep "\n" (r: "echo \"nameserver ${r}\"") (
          deployment.wan.extraResolvers or [ ]
        )}
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

  services.sshd = svc.ssh.build { };

}
