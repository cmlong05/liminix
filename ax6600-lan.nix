# Wired-LAN configuration base for JDCloud AX6600 (RE-CS-02)
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  svc = config.system.service;
  nifs = config.hardware.networkInterfaces;
  inherit (pkgs.liminix.services) bundle longrun oneshot;
  inherit (pkgs.liminix) outputRef;
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

  runtime = config.services.runtime-config;
  runtimeConfigFile = "/persist/config.json";

  # A deployment config may turn IPv6 off; otherwise it is on
  ipv6Enable = deployment.wan.ipv6.enable or true;

  seedValue =
    v:
    if builtins.isAttrs v then
      lib.filterAttrs (_: x: x != null) (lib.mapAttrs (_: seedValue) v)
    else if builtins.isList v then
      map seedValue v
    else if v == null then
      null
    else
      toString v;

  # builtins.toJSON writes the whole tree on one line; this indents it so
  # the file dropped in /persist stays readable and hand-editable.
  prettyJson =
    let
      pad = n: lib.concatStringsSep "" (lib.genList (_: "  ") n);
      go =
        depth: v:
        if builtins.isAttrs v then
          if v == { } then
            "{}"
          else
            "{\n"
            + lib.concatStringsSep ",\n" (
              lib.mapAttrsToList (
                k: x: "${pad (depth + 1)}${builtins.toJSON k}: ${go (depth + 1) x}"
              ) v
            )
            + "\n${pad depth}}"
        else if builtins.isList v then
          if v == [ ] then
            "[]"
          else
            "[\n"
            + lib.concatStringsSep ",\n" (map (x: "${pad (depth + 1)}${go (depth + 1) x}") v)
            + "\n${pad depth}]"
        else
          builtins.toJSON v;
    in
    go 0;
in
{
  imports = [
    ./ax6600-dev.nix
    ./modules/network
    ./modules/dhcp6c
    ./modules/dnsmasq
    ./modules/bridge
    ./modules/ppp
    ./modules/ssh
  ];

  services.runtime-config = svc.secrets.local.build {
    name = "runtime-config";
    path = runtimeConfigFile;
    seed = pkgs.writeText "runtime-config.json" (prettyJson (seedValue deployment) + "\n");
  };

  services.hostname = lib.mkForce (
    oneshot {
      name = "hostname";
      dependencies = [ runtime ];
      up = ''
        h=$(output ${runtime} hostname)
        test -n "$h" || h=${lib.escapeShellArg deployment.hostname}
        echo "$h" > /proc/sys/kernel/hostname
      '';
      down = "true";
    }
  );

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
      nifs.wlan24g
      nifs.wlan58g
    ];
  };

  services.int-address = oneshot {
    name = "int-address";
    dependencies = [
      config.services.int
      runtime
    ];
    up = ''
      dev=$(output ${config.services.int} ifname)
      address=$(output ${runtime} lan/address)
      prefixLength=$(output ${runtime} lan/prefixLength)
      test -n "$address" || address=${lib.escapeShellArg deployment.lan.address}
      test -n "$prefixLength" || prefixLength=${toString deployment.lan.prefixLength}
      ip address add $address/$prefixLength dev $dev
      (in_outputs int-address
       echo $address > address
       echo $prefixLength > prefix-length
       echo inet > family
       echo $dev > ifname
      )
    '';
    down = "true";
  };

  services.dhcpv4 = svc.dnsmasq.build {
    interface = config.services.int;
    domain = "lan";
    ranges =
      lib.optional (deployment.lan.dhcpRange != null)
        "$(output ${runtime} lan/dhcpRange 2>/dev/null || echo ${lib.escapeShellArg deployment.lan.dhcpRange})"
      ++ lib.optional ipv6Enable "::,constructor:$(output ${config.services.int} ifname),ra-stateless";
    resolvFile = "/run/resolv.conf";
    dependencies = [ runtime ];
  };

  # 2.5G WAN as a PPPoE client
  services.wan = svc.pppoe.build {
    interface = nifs.wan;
    username =
      if deployment.wan.pppoe.username == null then
        null
      else
        outputRef runtime "wan/pppoe/username";
    password =
      if deployment.wan.pppoe.password == null then
        null
      else
        outputRef runtime "wan/pppoe/password";
  };
  services.defaultroute4 = svc.network.route.build {
    via = "$(output ${config.services.wan} address)";
    target = "default";
    dependencies = [ config.services.wan ];
  };

  services.defaultroute6 = lib.mkIf ipv6Enable (
    svc.network.route.build {
      via = "$(output ${config.services.wan} ipv6-peer-address)";
      target = "default";
      interface = config.services.wan;
      dependencies = [ config.services.wan ];
    }
  );

  # One DHCPv6 client on the WAN link, asking for both a lease and a
  # delegated prefix: the prefix service puts <prefix>::1 on the LAN
  # bridge, and dnsmasq advertises that prefix to the LAN by SLAAC.
  services.dhcp6c =
    lib.mkIf ipv6Enable (
      let
        client = svc.dhcp6c.client.build {
          interface = config.services.wan;
        };
      in
      bundle {
        name = "dhcp6c";
        contents = [
          (svc.dhcp6c.prefix.build {
            inherit client;
            interface = config.services.int;
          })
          (svc.dhcp6c.address.build {
            inherit client;
            interface = config.services.wan;
          })
        ];
      }
    );

  services.wan-redial = longrun {
    name = "wan-redial";
    run = ''
      until test -d /run/service/${config.services.wan.name}/supervise ; do
        sleep 1
      done
      while : ; do
        ${pkgs.s6}/bin/s6-svwait -d /run/service/${config.services.wan.name}
        ${pkgs.s6-rc}/bin/s6-rc -b -u change ${config.services.wan.name} || true
        sleep 30
      done
    '';
  };

  services.resolvconf = oneshot {
    dependencies = [
      config.services.wan
      runtime
    ];
    name = "resolvconf";
    up = ''
      (
        echo "nameserver $(output ${config.services.wan} ns1)"
        echo "nameserver $(output ${config.services.wan} ns2)"
        found=
        for f in $(output_path ${runtime} wan/extraResolvers)/* ; do
            test -f "$f" || continue
            echo "nameserver $(cat $f)"
            found=1
        done
        if test -z "$found" ; then
          ${lib.concatMapStringsSep "\n" (r: "echo \"nameserver ${r}\"") (
            deployment.wan.extraResolvers or [ ]
          )}
          :
        fi
      ) > /run/resolv.conf
      chmod 0444 /run/resolv.conf
    '';
  };

  filesystem = dir {
    etc = dir {
      "resolv.conf" = symlink "/run/resolv.conf";
    };
  };
  services.packet_forwarding = svc.network.forward.build {
    enableIPv4 = true;
    enableIPv6 = ipv6Enable;
  };

  services.sshd = svc.ssh.build { };

}
