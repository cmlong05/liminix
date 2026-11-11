{ config, pkgs, ... }:
let
  inherit (pkgs.liminix.services) oneshot target;
  svc = config.system.service;
in
rec {
  services.lan4 = svc.network.address.build {
    interface = config.hardware.networkInterfaces.lan;
    family = "inet";
    address = "192.168.19.1";
    prefixLength = 24;
  };

  imports = [
    ../../modules/ppp
    ../../modules/dnsmasq
    ../../modules/network
    ../../modules/firewall
  ];

  services.pppoe = svc.pppoe.build {
    interface = config.hardware.networkInterfaces.wan;
    username = "db123@a.1";
    password = "NotReallyTheSecret";
    timeout-up = 2000;
    redial-interval = 1;
    redial-dependents = [ "pppoe-recovered" ];
  };

  services.pppoe-recovered = oneshot {
    name = "pppoe-recovered";
    dependencies = [ services.pppoe ];
    up = "touch /run/pppoe-recovered";
  };

  services.firewall = svc.firewall.build {
    zones = {
      wan = [ services.pppoe ];
      lan = [ services.lan4 ];
    };
  };

  services.defaultroute4 = svc.network.route.build {
    via = "$(output ${services.pppoe} address)";
    target = "default";
    dependencies = [ services.pppoe ];
  };

  services.packet_forwarding = svc.network.forward.build {
    dependencies = [ services.pppoe ];
  };

  services.dns = svc.dnsmasq.build {
    interface = services.lan4;
    ranges = [ "192.168.19.10,192.168.19.253" ];
    domain = "fake.liminix.org";
  };

  defaultProfile.packages = with pkgs; [
    nftables
    hello
  ];
}
