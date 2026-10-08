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
  deploymentJson = import ./devices/jdcloud-ax6600/deployment-json.nix { inherit lib; };
  inherit (deploymentJson) deployment;

  runtime = config.services.runtime-config;
  runtimeConfigFile = "/persist/config.json";

  # A deployment config may turn IPv6 off; otherwise it is on
  ipv6Enable = deployment.wan.ipv6.enable or true;

  # PPPoE costs the ethernet frame 8 bytes of header (6 ethernet + 2 PPPoE
  # protocol), an 802.1Q tag another 4: what is left is what pppd may
  # advertise as MTU/MRU on the link we picked.
  wanMtu = import ./devices/jdcloud-ax6600/wan-mtu.nix;
in
{
  imports = [
    ./ax6600-dev.nix
    ./modules/network
    ./modules/dhcp6c
    ./modules/dnsmasq
    ./modules/bridge
    ./modules/ntp
    ./modules/ppp
    ./modules/ssh
    ./modules/tailscale
  ];

  # Nothing that speaks TLS works on a 1970 clock: tailscale cannot even
  # fetch its login URL, every certificate being "not yet valid", and the
  # board has no RTC to fall back on.
  #
  # user = "root" is not optional: liminix builds chrony without libcap (see
  # -PRIVDROP in `chronyd --version`), and a chronyd that has dropped to the
  # module's default "ntp" user cannot keep CAP_SYS_TIME - it runs, but
  # silently fails to set the clock.
  services.ntp = svc.ntp.build {
    user = "root";
    dependencies = [ config.services.resolvconf ];
    pools = {
      "ntp.aliyun.com" = [ "iburst" ];
      "cn.pool.ntp.org" = [ "iburst" ];
    };
    makestep = {
      threshold = 1.0;
      limit = -1;
    };
  };

  services.runtime-config = svc.secrets.local.build {
    name = "runtime-config";
    path = runtimeConfigFile;
    seed = pkgs.writeText "runtime-config.json" deploymentJson.text;
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

  # Static leases live in the run-time config, so this service regenerates
  # dnsmasq's host file whenever lan/dhcpHosts changes there.
  services.dhcp-hosts =
    let
      generator = oneshot {
        name = "dhcp-hosts";
        dependencies = [ runtime ];
        up = ''
          ( in_outputs dhcp-hosts
            hosts=$(output_path ${runtime} lan/dhcpHosts)
            : > hosts
            test -d "$hosts" || exit 0
            for d in $hosts/* ; do
              test -d "$d" || continue
              mac=$(cat $d/mac 2>/dev/null)
              ip=$(cat $d/ip 2>/dev/null)
              test -n "$mac" -a -n "$ip" || continue
              leasetime=$(cat $d/leasetime 2>/dev/null)
              echo "$mac,$ip,$(basename $d),''${leasetime:-86400}"
            done >> hosts
            chmod 0644 hosts
          )
        '';
        down = "true";
      };
    in
    svc.secrets.subscriber.build {
      service = generator;
      watch = [ (outputRef runtime "lan/dhcpHosts") ];
      action = "restart-all";
    };

  services.dhcpv4 = svc.secrets.subscriber.build {
    service = svc.dnsmasq.build {
      interface = config.services.int;
      domain = "lan";
      ranges =
        lib.optional (deployment.lan.dhcpRange != null)
          "$(output ${runtime} lan/dhcpRange 2>/dev/null || echo ${lib.escapeShellArg deployment.lan.dhcpRange})"
        ++ lib.optional ipv6Enable "::,constructor:$(output ${config.services.int} ifname),ra-stateless";
      resolvFile = "/run/resolv.conf";
      hostsFile = "$(output_path ${config.services.dhcp-hosts} hosts)";
      dependencies = [
        runtime
        config.services.dhcp-hosts
      ];
    };
    watch = [ (outputRef config.services.dhcp-hosts "hosts") ];
    action = "restart-all";
  };

  # 2.5G WAN as a PPPoE client. Whether the session has to sit inside an
  # 802.1Q tag is a per-network fact, read at run time (wan/vlan in
  # /persist/config.json), so the interface it runs on is a service too.
  services.wan-if = oneshot {
    name = "wan-if";
    dependencies = [
      nifs.wan
      runtime
    ];
    up = ''
      base=$(output ${nifs.wan} ifname)
      vid=$(output ${runtime} wan/vlan 2>/dev/null || true)
      ifname=$base
      mtu=${toString wanMtu.plain}
      if test -n "$vid" ; then
        ifname=$base.$vid
        ip link add link $base name $ifname type vlan id $vid
        mtu=${toString wanMtu.tagged}
        mkdir -p /run/wan-if
        echo $ifname > /run/wan-if/vlan
      fi
      ip link set up dev $ifname
      ( in_outputs wan-if
        echo $ifname > ifname
        echo $mtu > mtu
      )
    '';
    down = ''
      if test -e /run/wan-if/vlan ; then
        ip link del dev $(cat /run/wan-if/vlan)
        rm -f /run/wan-if/vlan
      fi
      true
    '';
  };

  # 光猫的管理地址在 WAN 口的 untagged 侧，拨号用的 ppp0 到不了它：在
  # wan-if 给出的接口上加一个同网段地址，路由器才有通往光猫的路由，防火墙
  # wan zone 里的 masquerade 让 LAN 发出的包也走这条路（ax6600-rootfs.nix）。
  # 光猫管理地址若在 wan/vlan 的 tag 内，这里加的就是那个子接口，无需改动。
  services.wan-ont = oneshot {
    name = "wan-ont";
    dependencies = [
      config.services.wan-if
      runtime
    ];
    up = ''
      address=$(output ${runtime} wan/ont/address 2>/dev/null || true)
      test -n "$address" || exit 0
      prefixLength=$(output ${runtime} wan/ont/prefixLength 2>/dev/null || true)
      # replace 而非 add：wan-if 重启后地址可能还在，重加不能失败。
      ip address replace "$address/''${prefixLength:-24}" dev "$(output ${config.services.wan-if} ifname)"
    '';
    down = "true";
  };

  services.wan = svc.pppoe.build {
    interface = config.services.wan-if;
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
    # pppd's default is 1500, which is more than PPPoE can carry, so the
    # big packets are the ones that get lost: take the MTU/MRU from the
    # interface service, which knows whether it added a VLAN tag.
    ppp-options = [
      "mtu"
      (outputRef config.services.wan-if "mtu")
      "mru"
      (outputRef config.services.wan-if "mtu")
    ];
  };
  # tailscale warns that UDP forwarding over the PPPoE device is left
  # suboptimal by default. The interface is pppN with N picked by pppd, so
  # find it instead of naming it.
  services.wan-gro = oneshot {
    name = "wan-gro";
    dependencies = [ config.services.wan ];
    up = ''
      for d in /sys/class/net/ppp* ; do
        test -e "$d" || continue
        ${pkgs.ethtool}/bin/ethtool -K "$(basename "$d")" \
          rx-udp-gro-forwarding on rx-gro-list off || true
      done
    '';
    down = "true";
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

  # No auth key: tailscaled comes up at boot, and the first `tailscale up`
  # is run over ssh (it prints a URL to open elsewhere). What keeps that
  # login across reboots is the node state under /persist/tailscale.
  services.tailscale = svc.tailscale.build {
    dependencies = [ config.services.wan ];
  };

}
