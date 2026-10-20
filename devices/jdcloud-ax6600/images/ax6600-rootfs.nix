# JDCloud AX6600 (RE-CS-02): network and services on the eMMC image.
#
# eMMC image:
#   outputs.uimage  (kernel + dtb, cmdline embedded)  -> partition 0:HLOS
#   outputs.rootfs  (ext4, writable, kernel-mounted)  -> partition rootfs
#

{
  config,
  lib,
  modulesPath,
  pkgs,
  ...
}:
let
  svc = config.system.service;
  nifs = config.hardware.networkInterfaces;

  # 桥的成员口，同时用作防火墙 @lan zone。nft 的 iifname 匹配报文到达的
  # 物理口，oifname 匹配桥设备本身，所以 @lan 里这两类名字都要有，否则
  # LAN 入向流量（DHCP/DNS/新连接）会被拒。
  lanMembers = with nifs; [
    lan1
    lan2
    lan3
    lan4
    wlan24g
    wlan58g
  ];

  inherit (pkgs.liminix.services) bundle oneshot;
  inherit (pkgs.liminix) outputRef;
  inherit (pkgs.pseudofile) dir symlink;

  # Which network this image serves
  deploymentJson = import ../deployment-json.nix { inherit lib; };
  inherit (deploymentJson) deployment;

  runtime = config.services.runtime-config;
  runtimeConfigSeed = pkgs.writeText "runtime-config.json" deploymentJson.text;

  # A deployment config may turn IPv6 off; otherwise it is on
  ipv6Enable = deployment.wan.ipv6.enable or true;

  # What the WAN link can carry, to clamp the MSS of what the LAN sends it.
  # PPPoE costs the ethernet frame 8 bytes of header (6 ethernet + 2 PPPoE
  # protocol), an 802.1Q tag another 4, so these are payload bytes: what pppd
  # may advertise as MTU/MRU on the link we picked, and what the firewall may
  # assume a LAN host can send.
  wanMtu = {
    tagged = 1500 - 4 - 8;
    plain = 1500 - 8;
  };

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

  nss = import ../nss {
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
    (import ../nss/targets.nix).all ++ config.firewall.kernelModuleTargets;

  # The same tree pkgs/kmodloader builds for the service, asked for here as
  # well so the init phase can load it (see etc/rc-init.d/modules below).
  moduleTree = pkgs.liminix.modules.build pkgs {
    roots = [ config.system.outputs.kernel.modulesupport ] ++ moduleFiles;
    targets = moduleTargets;
  };
in
{
  imports = [
    "${modulesPath}/early"
    "${modulesPath}/network"
    "${modulesPath}/dhcp6c"
    "${modulesPath}/dnsmasq"
    "${modulesPath}/bridge"
    "${modulesPath}/ntp"
    "${modulesPath}/ppp"
    "${modulesPath}/ssh"
    "${modulesPath}/tailscale"
    "${modulesPath}/firewall"
    "${modulesPath}/outputs/ext4fs.nix"
    ../wireless
    ../wireless/rootfs-firmware.nix
    ../art.nix
  ];

  # 无串口的判断依据：内核先按 default-state 点亮红灯，本 oneshot 起来后
  # 熄红点绿，绿灯亮即代表 s6 与 userland 已经可用。
  services.led-userland = oneshot {
    name = "led-userland";
    up = ''
      for l in blue:status green:status red:status; do
        test -e /sys/class/leds/$l/brightness || continue
        echo 0 > /sys/class/leds/$l/brightness 2>/dev/null
      done
      echo 255 > /sys/class/leds/green:status/brightness 2>/dev/null || true
    '';
  };

  users.root = {
    # Use mkpasswd -m sha512crypt to create
    # your own hashed password string.
    passwd = "$6$uqFC7Xu7q2uWTquh$axLjr8YpuQE.dqHlgQTXaeglki/FLsaLMX6RyKHWbYUL2VA4FRFmd2N/MNrqdGaKfzDrdbFJUxnPrfmjIciP80";
  };

  # 现场运维工具
  defaultProfile.packages = with pkgs; [
    e2fsprogs
    gptfdisk
    util-linux
    iperf3
    vim
    curl
    nftables
    libubootenv
  ];

  # minimal busybox 默认关掉 ash 的 $((...))，dhcp6c/route 等服务脚本会语法错误退出
  programs.busybox.applets = [
    "mountpoint"
    "nslookup"
    "scp"
  ];
  programs.busybox.options = {
    FEATURE_SH_MATH = "y";
    FEATURE_FANCY_PING = "y";
  };
  
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
    path = "${runtimeConfigSeed}";
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

  # Build-time: mirrored into the s6 logger and the device tree by
  # devices/jdcloud-ax6600/default.nix.
  logging.persistent.enable = lib.mkDefault (deployment.persistentLogging or false);

  services.int = svc.bridge.primary.build {
    ifname = "int";
  };

  # 成员列表与防火墙 @lan zone 共用 lanMembers
  services.bridge = svc.bridge.members.build {
    primary = config.services.int;
    members = lanMembers;
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

  # Static leases come from the deployment, so this renders dnsmasq's host
  # file from the runtime-config output tree.
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

  # Local DNS records come from the deployment and are rendered into
  # dnsmasq's additional hosts file.
  services.dns-hosts =
    let
      generator = oneshot {
        name = "dns-hosts";
        dependencies = [ runtime ];
        up = ''
          ( in_outputs dns-hosts
            : > hosts
            dns=$(output_path ${runtime} lan/dnsHosts 2>/dev/null)
            test -d "$dns" || exit 0
            for f in $dns/* ; do
              test -f "$f" || continue
              ip=$(cat "$f" 2>/dev/null)
              test -n "$ip" || continue
              echo "$ip $(basename $f)"
            done >> hosts
            chmod 0644 hosts
          )
        '';
        down = "true";
      };
    in
    svc.secrets.subscriber.build {
      service = generator;
      watch = [ (outputRef runtime "lan/dnsHosts") ];
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
      addnHosts = [ "$(output_path ${config.services.dns-hosts} hosts)" ];
      dependencies = [
        runtime
        config.services.dhcp-hosts
        config.services.dns-hosts
      ];
    };
    watch = [
      (outputRef config.services.dhcp-hosts "hosts")
      (outputRef config.services.dns-hosts "hosts")
    ];
    action = "restart-all";
  };

  # 无线 beacon 排在桥上的地址与 DHCP 就绪之后：SSID 早于它们可见，
  wireless.apReadyDependencies = [
    config.services.int-address
    config.services.dhcpv4
  ];

  # 2.5G WAN as a PPPoE client. Whether the session has to sit inside an
  # 802.1Q tag is a per-network fact, so the interface it runs on is a
  # service too.
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
  # wan-if 给出的接口上加一个同网段地址，路由器才有通往光猫的路由。
  # 光猫管理地址若在 wan/vlan 的 tag 内，这里加的就是那个子接口，无需改动。
  # LAN 发出的包由下面 firewall 的 @wan masquerade 送上这条路。
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
      wait-for = "$(output_path ${config.services.wan} ipv6-up)";
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
          wait-for = "$(output_path ${config.services.wan} ipv6-up)";
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

  services.resolvconf = oneshot {
    dependencies = [
      config.services.wan
      runtime
    ];
    name = "resolvconf";
    up = ''
      (
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
      # ISP 的解析器只做兜底：一个自定义解析器都没有时留着，免得 dnsmasq 没上游。
      if ! test -s /run/resolv.conf ; then
        echo "nameserver $(output ${config.services.wan} ns1)" > /run/resolv.conf
        echo "nameserver $(output ${config.services.wan} ns2)" >> /run/resolv.conf
      fi
      chmod 0444 /run/resolv.conf
    '';
  };

  services.packet_forwarding = svc.network.forward.build {
    enableIPv4 = true;
    enableIPv6 = ipv6Enable;
  };

  services.sshd = svc.ssh.build { };

  # No auth key: tailscaled comes up at boot, and the first `tailscale up`
  # is run over ssh (it prints a URL to open elsewhere). What keeps that
  # login across reboots is the node state under /var/lib/tailscale.
  services.tailscale = svc.tailscale.build {
    dependencies = [ config.services.wan ];
  };

  # 关机时不卸载模块。kmodloader 默认的 down 会跑 unload.sh，而卸载
  # qca-ssdk/qca-nss-* 会在内核里挂住，加上 s6-rc 的 oneshot down 没有
  # 超时（liminix 默认 timeout-down=0），reboot 就永久停在关机阶段。
  # 重启时内核自己会重置，不需要卸载。
  services.modules = oneshot {
    name = "kmodloader-${lib.concatStringsSep "-" moduleTargets}";
    # 模块已经由 rc-init.d 的 modules 加载（见下面的 filesystem.etc），这里
    # 只是 firewall 的依赖锚点。load.sh 用的是 insmod，重复插入会以 EEXIST
    # 失败并让 s6-rc 判服务 failed，所以先看 load-order 的最后一个模块在不在。
    up = ''
      last=$(basename "$(tail -n 1 ${moduleTree}/load-order)" .ko | tr '-' '_')
      test -d "/sys/module/$last" || O=${moduleTree}/lib/modules sh ${moduleTree}/load.sh
    '';
    down = "true";
  };

  firewall.kernelModules = config.services.modules;

  # 站点策略的第二个注入点：追加到规则集里已有的链末尾。tailscale 模块
  # 也用这个选项，attrsOf (listOf str) 按键合并，互不干扰。
  firewall.appendRules = siteFirewall.appendRules or { };

  # 同上，但插到链的 log 规则之前，避免被放行的包先打一条 DENIED 日志。
  firewall.appendRulesBeforeLog = siteFirewall.appendRulesBeforeLog or { };

  # A LAN host sizes its TCP segments from the 1500-byte bridge, but the
  # PPPoE link carries less, so a server's full-size reply is dropped on
  # the way in.  IPv4 recovers from the resulting ICMP frag-needed, IPv6
  # does not, and the connection hangs in the TLS handshake: clamping the
  # MSS in flight stops the servers sending what the WAN cannot carry.
  services.firewall = config.system.service.firewall.build {
    zones = {
      # int 是出向（oifname）看到的桥设备，成员口是入向（iifname）看到的
      # 物理口：@lan 两者都要。
      lan = [ config.services.int ] ++ lanMembers;
      # wan-if 给出实际承载 PPPoE 的链路接口（untagged 时是物理口，带 VLAN
      # 时是 wan.<vid>）：光猫管理地址加在它上面，@wan 必须包含它，masquerade
      # 与 mss 才会作用于 LAN→光猫的出口。物理口本身也保留。
      wan = [
        config.services.wan
        nifs.wan
        config.services.wan-if
      ];
    };
    # PPPoE 的接口名要等拨号成功才有：规则集先不等它（@wan 里暂时少一个
    # ppp0），ip-up 写出 ifname 后由 watch 触发的重载把它补进集合。
    dontWait = [ config.services.wan ];
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

  services.netfilter-sysctls = oneshot {
    name = "netfilter-sysctls";
    dependencies = [ config.services.modules ];
    up = ''
      echo 1 > /proc/sys/net/netfilter/nf_conntrack_tcp_no_window_check
      # ECM offload desyncs conntrack, so a retransmitted closing packet
      # (FIN) is judged invalid and dropped by input-ip4/6 instead of
      # matching established,related: accept out-of-window packets.
      echo 1 > /proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal
      echo 65535 > /proc/sys/net/netfilter/nf_conntrack_max
      echo 1 > /proc/sys/net/netfilter/nf_conntrack_events
    '';
  };

  filesystem = dir {
    etc = dir {
      "fw_env.config" = symlink "/run/fw_env.config";
      "resolv.conf" = symlink "/run/resolv.conf";
      "rc-init.d" = dir {
        fw-env-config = symlink (
          pkgs.writeAshScript "fw-env-config" { } ''
            export PATH=/bin:/sbin
            part=
            for u in /sys/class/block/*/uevent; do
              if grep -q '^PARTNAME=0:APPSBLENV$' "$u" 2>/dev/null; then
                part=/dev/$(basename "$(dirname "$u")")
                break
              fi
            done
            test -n "$part" || {
              echo "fw-env-config: no APPSBLENV partition" >&2
              exit 0
            }
            echo "$part 0x0 0x40000 0x20000" > /run/fw_env.config
          ''
        );
        # Load the module tree from the init phase as well as from the
        # kmodloader service: that service's output goes to the s6 logger,
        # where a failure is invisible, whereas this runs with the root
        # already mounted and /lib/firmware readable, before s6-rc, and
        # prints to the console.
        modules = symlink (
          pkgs.writeAshScript "load-modules" { } ''
            echo "loading kernel modules from ${moduleTree}"
            O=${moduleTree}/lib/modules sh ${moduleTree}/load.sh
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

  hardware.rootDevice = deployment.hardware.rootDevice;
  rootfsType = "ext4";

  boot = {
    imageFormat = "fit";
    # The kernel mounts the root itself and no initramfs is left to remount
    # it, so this is what leaves the root writable.
    rootfs.mount = "kernel";
    commandLine = lib.mkForce [
      "panic=10 oops=panic loglevel=4"
      "console=ttyMSM0,115200n8"
      "fw_devlink=off"
      "nokaslr"
      "root=${config.hardware.rootDevice}"
      "rootfstype=${config.rootfsType}"
      "rootwait"
      "rw"
      "init=/bin/init"
    ];
  };

  kernel.config = {
    BLK_DEV_LOOP = "y";
    CMDLINE = lib.mkForce "\"${lib.concatStringsSep " " config.boot.commandLine}\"";
    CMDLINE_FROM_BOOTLOADER = lib.mkForce "n";
    CMDLINE_FORCE = "y";
    # s6-linux-init mounts devtmpfs on /dev itself: if the kernel got
    # there first (DEVTMPFS_MOUNT=y) it dies with EBUSY and panics.
    DEVTMPFS_MOUNT = lib.mkForce "n";
  };
}
