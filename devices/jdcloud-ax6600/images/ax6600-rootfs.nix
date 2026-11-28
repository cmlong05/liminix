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
  buildCommit,
  buildCommitDate,
  buildDate,
  buildProfile,
  ...
}:
let
  svc = config.system.service;
  nifs = config.hardware.networkInterfaces;
  dropbear = pkgs.dropbear.override {
    enableSCP = true;
  };

  inherit (pkgs.liminix.services) bundle longrun oneshot;
  inherit (pkgs.liminix) outputRef;
  inherit (pkgs.pseudofile) dir symlink;

  stateRoot = "/var/lib/liminix";

  # Which network this image serves
  deploymentJson = import ../deployment-json.nix { inherit lib; };
  inherit (deploymentJson) deployment;

  # 校验 wan.interface，并从五个有线口中选出唯一的 WAN 上联口。
  wiredPortNames = [
    "wan"
    "lan1"
    "lan2"
    "lan3"
    "lan4"
  ];
  wanPortName =
    let
      name = deployment.wan.interface or "wan";
    in
    if builtins.elem name wiredPortNames then
      name
    else
      throw "wan.interface must be one of ${lib.concatStringsSep ", " wiredPortNames}";
  wanPort = nifs.${wanPortName};

  # 是否配置了单线复用
  singleLineEnable = (deployment.wan.singleLine or { }).enable or false;

  # VLAN 是构建期参数，single-line 与 wan-if 必须使用同一值。
  wanVlan =
    if (deployment.wan.vlan or null) == null then
      ""
    else
      toString deployment.wan.vlan;
  singleLineVlan =
    if wanVlan == "" then
      throw "wan.vlan must be set when wan.singleLine.enable is true"
    else
      wanVlan;

  # WAN 上联口不放入普通 access ports；单线模式下由 trunk 服务在 VLAN filtering 后加入。
  lanBridgePorts =
    map (name: nifs.${name}) (lib.remove wanPortName wiredPortNames)
    ++ [
      nifs.wlan24g
      nifs.wlan58g
    ];
  qcnWlan52g = nifs.wlan52g;
  lanZonePorts = lanBridgePorts ++ [ qcnWlan52g ] ++ lib.optional singleLineEnable wanPort;

  # 仅单线模式让 PPPoE 终止在桥上的 VLAN 子接口。
  wanBase = if singleLineEnable then config.services.int else wanPort;

  runtime = config.services.runtime-config;
  runtimeConfigSeed = pkgs.writeText "runtime-config.json" deploymentJson.text;
  buildMarker = "liminix-build/${buildCommit}/${buildDate}";
  buildMeta = {
    marker = buildMarker;
    commit = buildCommit;
    commitDate = buildCommitDate;
    builtAt = buildDate;
    profile = buildProfile;
    hostname = config.hostname;
  };
  buildMetaJson = pkgs.writeText "liminix-build.json" (builtins.toJSON buildMeta);

  singleLine = svc.singleLine.build {
    name = "single-line";
    bridge = config.services.int;
    uplink = wanPort;
    vlan = singleLineVlan;
    dependencies = [ config.services.bridge ];
  };

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

  nssTargets = import ../nss/targets.nix;
  moduleTargets = nssTargets.all ++ config.firewall.kernelModuleTargets;
  ath11kArgs = "nss_offload=1 frame_mode=2";

  # rc-init.d/modules loads this tree before s6-rc (see below), and
  # services.modules keeps a oneshot as firewall's dependency anchor.
  moduleTree = pkgs.liminix.modules.build pkgs {
    roots = [ config.system.outputs.kernel.modulesupport ] ++ moduleFiles;
    targets = moduleTargets;
    moduleArgs.ath11k = ath11kArgs;
  };

  qcnModuleTree = pkgs.liminix.modules.build pkgs {
    roots = [ config.system.outputs.kernel.modulesupport ] ++ moduleFiles;
    targets = nssTargets.qcn;
    moduleArgs.ath11k = ath11kArgs;
  };

  loadModule = pkgs.writeAshScript "load-module" { } ''
    set -u
    O=$1
    rel=$2
    module=''${rel##*/}
    module=''${module%.ko}
    module=$(printf '%s' "$module" | tr '-' '_')
    test -d "/sys/module/$module" && exit 0
    args=
    case "$module" in
      ath11k) args=${lib.escapeShellArg ath11kArgs} ;;
    esac
    cmdline_args=
    for arg in $(cat /proc/cmdline); do
      case "$arg" in
        "$module".*=*) cmdline_args="$cmdline_args ''${arg#*.}" ;;
      esac
    done
    insmod "$O/$rel" $args $cmdline_args
  '';

  qcnLoad = pkgs.writeAshScript "qcn-up" { } ''
    set -u
    export PATH=/bin:/sbin
    ${config.wireless.ahbReadyScript} || {
      echo "qcn-up: QCN left unloaded" >&2
      exit 1
    }

    O=${qcnModuleTree}/lib/modules
    while read -r rel; do
      ${loadModule} "$O" "$rel"
    done < ${qcnModuleTree}/load-order
    ${config.wireless.qcnRenameScript}
    test -d /sys/class/net/wlan52g || {
      echo "qcn-up: wlan52g did not appear; QCN load failed" >&2
      exit 1
    }
  '';

  # qcn-up's down runs after s6-rc has brought down hostap-52g and
  # wlan52g.link (reverse dependency order), so nothing still holds the
  # netdev. Unload the PCI half so the QCN9074 powers off with 5.2G;
  # ath11k itself stays loaded because the AHB radio shares it.
  qcnUnload = pkgs.writeAshScript "qcn-down" { } ''
    set -u
    export PATH=/bin:/sbin
    for m in ath11k_pci qrtr_mhi; do
      test -d "/sys/module/$m" || continue
      rmmod "$m" 2>/dev/null || true
    done
    i=0
    while test -e /sys/class/net/wlan52g && test "$i" -lt 20; do
      sleep 1
      i=$((i + 1))
    done
  '';

  # 长按 WPS 键 3 秒开关 5.2G WiFi（QCN9074）。
  # 开启：拉起 qcn-bridge，它按序带起 qcn-up、wlan52g.link、hostap-52g，
  # 最后把 wlan52g 接入 int。关闭：down qcn-up，s6-rc 先停 hostapd 和
  # wlan52g.link，再由 qcn-up 的 down 卸载 ath11k_pci/qrtr_mhi。
  # 开启中蓝灯闪、成功后蓝灯常亮；关闭中绿灯闪、成功后绿灯常亮。
  wifi52gToggle = pkgs.writeAshScript "wifi-52g-toggle" { } ''
    set -u
    export PATH=${pkgs.s6-rc}/bin:${pkgs.s6}/bin:/bin:/sbin

    led() { echo "$2" > "/sys/class/leds/$1:status/brightness" 2>/dev/null || true; }

    blink() {
      while :; do
        led "$1" 255
        ${pkgs.coreutils}/bin/sleep 0.2
        led "$1" 0
        ${pkgs.coreutils}/bin/sleep 0.2
      done
    }

    # 状态转换期间后台闪烁；结束后先停闪烁再写最终状态，避免闪到一半停住。
    if s6-rc -a list 2>/dev/null | grep -qx qcn-up; then
      echo "wifi-52g-toggle: stopping 5.2G"
      led blue 0
      led green 0
      blink green &
      pid=$!
      if s6-rc -b -d change qcn-up; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        led blue 0
        led red 0
        led green 255
      else
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        led green 0
        led blue 255
      fi
    else
      echo "wifi-52g-toggle: starting 5.2G"
      led green 0
      led blue 0
      blink blue &
      pid=$!
      if s6-rc -b -u change qcn-bridge; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        led green 0
        led red 0
        led blue 255
      else
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        led blue 0
        led green 255
      fi
    fi
  '';

  # The NSS WiFi data path keeps its packet buffers in the NSS N2H pool.
  # With the driver defaults (wifi pool 0, extra pbuf 0, high water 8704)
  # nss_offload on ath11k has nowhere to put WiFi traffic, so the data path
  # never actually leaves the CPU even though the radio is "on NSS". The
  # fork's qca-nss-pbuf init sets the same knobs before wifi binds; these
  # are its RAM-size profile values.
  #
  # It must run after nss-drv has booted the core and before ath11k creates
  # its NSS interfaces (extra_pbuf_core0 can only be set while still 0), so
  # the rc-init module loader calls this once it sees the core booted, which
  # is before it insmods ath11k.
  nssPbuf = pkgs.writeAshScript "nss-pbuf" { } ''
    set -u
    i=0
    while test "$i" -lt 10; do
      test -w /proc/sys/dev/nss/n2hcfg/n2h_wifi_pool_buf && break
      sleep 1
      i=$((i + 1))
    done
    test -w /proc/sys/dev/nss/n2hcfg/n2h_wifi_pool_buf || {
      echo "nss-pbuf: n2hcfg sysctls never appeared" >&2
      exit 1
    }

    echo 0 > /proc/sys/dev/nss/clock/auto_scale 2>/dev/null || true
    echo 2048 > /proc/sys/dev/nss/n2hcfg/n2h_queue_limit_core0 2>/dev/null || true

    memtotal=$(grep '^MemTotal' /proc/meminfo | tr -cd '0-9')
    : "''${memtotal:=0}"
    if test "$memtotal" -le 256000; then
      extra=4000000; high=16384; wifi=8192
    elif test "$memtotal" -le 512000; then
      extra=8000000; high=32768; wifi=16384
    else
      extra=10000000; high=65536; wifi=32768
    fi

    current=$(cat /proc/sys/dev/nss/n2hcfg/extra_pbuf_core0 2>/dev/null || echo 0)
    if test "''${current:-0}" = 0; then
      echo "$extra" > /proc/sys/dev/nss/n2hcfg/extra_pbuf_core0 2>/dev/null || true
    fi
    echo "$high" > /proc/sys/dev/nss/n2hcfg/n2h_high_water_core0 2>/dev/null || true
    echo "$wifi" > /proc/sys/dev/nss/n2hcfg/n2h_wifi_pool_buf 2>/dev/null || true

    cpus=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || true)
    : "''${cpus:=1}"
    echo $(( (1 << cpus) - 1 )) > /proc/sys/dev/nss/rps/hash_bitmap 2>/dev/null || true
  '';

  nssWifiCheck = pkgs.callPackage ../nss-wifi/check-built.nix {
    inherit pkgs moduleTree qcnModuleTree;
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
    "${modulesPath}/gpio-button"
    "${modulesPath}/outputs/ext4fs.nix"
    "${modulesPath}/usb.nix"
    ../locale.nix
    ../sing-box.nix
    ../wireless
    ../wireless/rootfs-firmware.nix
    ../network
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

  services.debugfs = oneshot {
    name = "debugfs";
    up = "mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug";
    down = "umount /sys/kernel/debug";
  };

  users.root = {
    # Use mkpasswd -m sha512crypt to create
    # your own hashed password string.
    passwd = "$6$uqFC7Xu7q2uWTquh$axLjr8YpuQE.dqHlgQTXaeglki/FLsaLMX6RyKHWbYUL2VA4FRFmd2N/MNrqdGaKfzDrdbFJUxnPrfmjIciP80";
  };

  # 现场运维工具
  defaultProfile.packages = with pkgs; [
    dropbear
    e2fsprogs
    gptfdisk
    htop
    iproute2
    libubootenv
    min-collect-garbage
    nftables
    util-linux
    iperf3
    vim
    curl
  ];

  # minimal busybox 默认关掉 ash 的 $((...))，dhcp6c/route 等服务脚本会语法错误退出
  programs.busybox.applets = [
    "mountpoint"
    "nslookup"
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

  # 长按 reset 键 5 秒重启：直接读 GPIO，不经过 input 层。
  services.reset-button = svc.gpio-button.build {
    name = "reset-button";
    gpio = 71;
    holdSeconds = 5;
  };

  # 长按 WPS 键（GPIO 72）3 秒开关 5.2G WiFi。
  services.wifi-button = svc.gpio-button.build {
    name = "wifi-button";
    gpio = 72;
    holdSeconds = 3;
    command = "${wifi52gToggle}";
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

  # 普通 LAN 口加入桥；lanZonePorts 同时作为防火墙 @lan。
  services.bridge = svc.bridge.members.build {
    primary = config.services.int;
    members = lanBridgePorts;
  };

  # Controlled: QCN9074 is never loaded at boot. `s6-rc -u change qcn-bridge`
  # loads it and attaches wlan52g to int.
  services.qcn-up = oneshot {
    name = "qcn-up";
    dependencies = [ config.services.modules ];
    controller = longrun {
      name = "control-qcn-up";
      run = "while sleep 86400; do true; done";
    };
    up = ''${qcnLoad}'';
    down = ''${qcnUnload}'';
  };

  services.qcn-bridge = oneshot {
    name = "qcn-bridge";
    dependencies = [
      config.services.int
      config.services.qcn-up
      qcnWlan52g
      # Hostapd puts wlan52g in AP mode before it joins the bridge.
      config.services."hostap-52g"
    ];
    up = ''
      ifname=$(output ${qcnWlan52g} ifname)
      # cfg80211 sets IFF_DONT_BRIDGE while the netdev is STATION and clears
      # it only once hostapd switches it to AP. The longrun dependency is up
      # before the AP is announced, so wait for carrier (AP started).
      i=0
      while test "$i" -lt 30; do
        test "$(cat /sys/class/net/$ifname/carrier 2>/dev/null)" = 1 && break
        sleep 1
        i=$((i + 1))
      done
      test "$i" -lt 30 || {
        echo "qcn-bridge: $ifname never became an AP" >&2
        exit 1
      }
      ip link set dev "$ifname" master "$(output ${config.services.int} ifname)"
    '';
    down = ''
      ip link set dev "$(output ${qcnWlan52g} ifname)" nomaster
    '';
  };

  services.single-line = lib.mkIf singleLineEnable singleLine;

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
      hostsFile = "${config.services.dhcp-hosts}/.outputs/hosts";
      addnHosts = [ "${config.services.dns-hosts}/.outputs/hosts" ];
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

  # The selected WAN uplink carries PPPoE in wan/vlan.
  services.wan-if = oneshot {
    name = "wan-if";
    dependencies = [ wanPort ]
    ++ lib.optional singleLineEnable singleLine;
    up = ''
      set -e
      base=$(output ${wanBase} ifname)
      vid=${lib.escapeShellArg wanVlan}
      ifname=$base
      mtu=${toString wanMtu.plain}
      if test -n "$vid" ; then
        ifname=$base.$vid
        link=$(ip -d link show dev "$ifname" 2>/dev/null || true)
        if test -n "$link" ; then
          case "$link" in
            *"$ifname@$base:"*"vlan protocol 802.1Q id $vid "*) ;;
            *)
              echo "wan-if: $ifname has unexpected VLAN configuration" >&2
              exit 1
              ;;
          esac
        else
          ip link add link "$base" name "$ifname" type vlan id "$vid"
        fi
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

  # 光猫的管理地址位于 wan/vlan 给定的子接口，ppp0 到不了它。
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
      "defaultroute"
      "defaultroute-metric"
      "100"
      "defaultroute6"
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
  # is run over ssh (it prints a URL to open elsewhere).
  services.tailscale = svc.tailscale.build {
    stateDir = "${stateRoot}/tailscale";
    dependencies = [
      config.services.wan
      config.services.firewall
    ];
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

  services.nss-tuning = oneshot {
    name = "nss-tuning";
    dependencies = [ config.services.modules ];
    up = ''
      # rc-init sets these before ath11k loads; repeat them so a boot that
      # fell back to this oneshot's load.sh still gets the WiFi pools.
      ${nssPbuf} || echo "nss-tuning: NSS pbuf setup failed" >&2
      if test -w /proc/sys/dev/nss/general/redirect; then
        echo 1 > /proc/sys/dev/nss/general/redirect
      fi
      if test -w /sys/kernel/debug/ecm/ecm_classifier_default/accel_delay_pkts; then
        echo 1 > /sys/kernel/debug/ecm/ecm_classifier_default/accel_delay_pkts
      fi
    '';
    down = "true";
  };

  firewall.kernelModules = config.services.modules;

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
      # 入向看到物理口，出向看到桥设备，@lan 两套名字都要有。
      lan = [ config.services.int ] ++ lanZonePorts;
      # 单线模式下上联物理口属于 LAN；否则它属于 WAN。
      wan = [
        config.services.wan
        config.services.wan-if
      ]
      ++ lib.optional (!singleLineEnable) wanPort;
    };
    # PPPoE 的接口名要等拨号成功才有：规则集先不等它（@wan 里暂时少一个
    # ppp0），ip-up 写出 ifname 后由 watch 触发的重载把它补进集合。
    # wlan52g 同理：52g 固件起不来时 link 等不到接口，防火墙不等它，
    # 52g 恢复后由 watch 触发重载补进 @lan。
    dontWait = [ config.services.wan nifs.wlan52g ];
    # 全量重载会清掉 auto_redirect 的 nft 表。
    restartAfterReload = lib.optional config.jdcloudAx6600.singBox.enable config.services.sing-box;
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
      "localtime" = symlink "${pkgs.tzdata}/share/zoneinfo/Asia/Shanghai";
      "resolv.conf" = symlink "/run/resolv.conf";
      "terminfo" = symlink "${pkgs.ncurses}/share/terminfo";
      "liminix-nss-wifi.check" = symlink "${nssWifiCheck}";
      liminix = dir {
        "build.json" = symlink "${buildMetaJson}";
      };
      "rc-init.d" = dir {
        state-dir = symlink (
          pkgs.writeAshScript "state-dir" { } ''
            state=${stateRoot}
            mkdir -m 0751 -p "$state"
            echo "$state" > /run/state-mountpoint
          ''
        );
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
            O=${moduleTree}/lib/modules
            nss_ready=unknown
            while read -r rel; do
              module=''${rel##*/}
              module=''${module%.ko}
              module=$(printf '%s' "$module" | tr '-' '_')
              case "$module" in
                ath11k|ath11k_ahb)
                  if test "$nss_ready" != yes; then
                    echo "load-modules: skipping $module; NSS core is not ready" >&2
                    continue
                  fi
                  ;;
              esac
              ${loadModule} "$O" "$rel"
              test "$module" = qca_nss_drv || continue
              i=0
              while test "$i" -lt 30; do
                if dmesg | grep -i 'nss core 0 booted successfully' >/dev/null; then
                  nss_ready=yes
                  break
                fi
                sleep 1
                i=$((i + 1))
              done
              test "$nss_ready" = yes || echo "load-modules: NSS core did not boot" >&2
              if test "$nss_ready" = yes; then
                ${nssPbuf} || echo "load-modules: NSS WiFi pbuf setup failed" >&2
              fi
            done < ${moduleTree}/load-order
            if test "$nss_ready" = yes && test -w /proc/sys/dev/nss/general/redirect; then
              echo 1 > /proc/sys/dev/nss/general/redirect
            fi
          ''
        );
      };
    };
    var = dir {
      lib = dir {
        liminix = dir { };
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
      "ath11k.nss_offload=1"
      "ath11k.frame_mode=2"
    ];
    # Recorded in the FIT's device tree at image assembly time, not in
    # CONFIG_CMDLINE, so a new commit/date does not force a kernel rebuild.
    buildMarker = buildMarker;
  };

  kernel.config = {
    BLK_DEV_LOOP = "y";
    CMDLINE = lib.mkForce "\"${lib.concatStringsSep " " config.boot.commandLine}\"";
    CMDLINE_FROM_BOOTLOADER = lib.mkForce "n";
    CMDLINE_FORCE = "y";
    FAT_FS = "y";
    VFAT_FS = "y";
    EXFAT_FS = "y";
    NTFS3_FS = "y";
    # s6-linux-init mounts devtmpfs on /dev itself: if the kernel got
    # there first (DEVTMPFS_MOUNT=y) it dies with EBUSY and panics.
    DEVTMPFS_MOUNT = lib.mkForce "n";
  };
}
