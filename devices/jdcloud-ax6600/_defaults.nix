# AX6600 各站点配置的共同部分。
#
# 本文件不是站点配置，不能直接 `-c`：它求值出来是个函数，不是 attrset。
#
# 站点文件这样写：
#
#   import ./_defaults.nix {
#     hostname = "home-ax6600";
#     lan = { address = "10.10.0.1"; dhcpRange = "..."; dhcpHosts = { ... }; };
#     wan = { vlan = 41; pppoe = { username = "..."; password = "..."; }; };
#     wifi.bands = { "24g" = { ssid = "..."; password = "..."; }; ... };
#   }
#
# 覆盖项与这里按 attrset 深度合并：嵌套的 attrset 逐键合并，列表和标量
# 整体替换。站点因此只需写出与这里不同的部分。
#
# 站点必须自己给出 hostname、lan.address、lan.dhcpRange、wan.pppoe 和各
# band 的 ssid/password —— 这些刻意不设默认值，缺了就是构建报错，而不是
# 悄悄沿用别的站点的值。
overrides:
let
  defaults = {
    hardware = {
      rootDevice = "PARTLABEL=rootfs";
      usbRootDevice = "PARTLABEL=liminix-root";
    };

    # 构建期开关：把 s6 日志流也写进 pstore pmsg，重启后仍可读。
    # 改它需要重建镜像，不是改配置能生效的。
    persistentLogging = true;

    lan = {
      prefixLength = 24;

      # dhcpHosts / dnsHosts 不在这里给默认值：它们是站点的事实（主机地址
      # 跟网段走），深度合并只会覆盖同名键，放了条目就会被别的站点继承
      # 成不属于自己网段的地址。站点要用时自行给出整张表。
    };

    wan = {
      # 上联口；其余四个有线口都是 LAN
      interface = "wan";

      # 构建期开关：上联口同时作 WAN/LAN VLAN trunk，PPPoE 落在 int.<vlan>
      singleLine = {
        enable = false;
      };

      # 上联口需要的 802.1Q tag；null 即不带 tag
      vlan = null;

      # 光猫管理地址在未打标一侧，ppp0 到不了它，路由器在该子网取一个地址
      ont = {
        address = "192.168.1.2";
        prefixLength = 24;
      };

      # 同一条 PPPoE 上跑 DHCPv6-PD，再把前缀用 SLAAC 发给 LAN
      ipv6 = {
        enable = true;
      };

      # 额外的上游解析器
      extraResolvers = [
        "223.5.5.5"
        "119.29.29.29"
      ];
    };

    wifi = {
      countryCode = "CN";

      # 构建期开关：false 则开机不启 AP，留给手工
      autostart = true;

      # band 按 AHB pdev 划分。ssid 与 password 每站点不同，密文模式
      # （wpa2 | wpa2-wpa3 | open，构建期确定）和射频参数三站点一致。
      bands = {
        "24g" = {
          hw_mode = "g";
          channel = "6";
          security = "wpa2";
        };
        "58g" = {
          hw_mode = "a";
          channel = "149";
          ieee80211ac = 1;
          ieee80211ax = 1;
          ht_capab = "[HT40+][SHORT-GI-20][SHORT-GI-40]";
          vht_oper_chwidth = 1;
          vht_oper_centr_freq_seg0_idx = 155;
          he_oper_chwidth = 1;
          he_oper_centr_freq_seg0_idx = 155;
          security = "wpa2";
        };
      };
    };
  };

  merge =
    a: b:
    if builtins.isAttrs a && builtins.isAttrs b then
      a
      // builtins.mapAttrs (k: v: if builtins.hasAttr k a then merge a.${k} v else v) b
    else
      b;
in
merge defaults overrides
